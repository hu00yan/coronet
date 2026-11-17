{-# LANGUAGE BangPatterns #-}
module CoronetPlugin (plugin) where

import GHC.Plugins
import GHC.Core
import GHC.Core.Utils
import GHC.Types.ForeignCall (ForeignCall(..), CCallSpec(..), CCallTarget(..))
import GHC.Types.Id.Info (IdDetails(..))
import Data.Char (isAlphaNum, ord)
import Data.List (isPrefixOf, isSuffixOf, isInfixOf, intercalate, nub)
import System.IO
import System.Directory (doesFileExist, createDirectoryIfMissing)
import Control.Monad.IO.Class (liftIO)

plugin :: Plugin
plugin = defaultPlugin
  { installCoreToDos = install
  , pluginRecompile  = purePlugin
  }

install :: [CommandLineOption] -> [CoreToDo] -> CoreM [CoreToDo]
install opts todos = do
  let pass = CoreDoPluginPass "CoronetDump" (coronetPass opts)
  return (todos ++ [pass])

coronetPass :: [CommandLineOption] -> ModGuts -> CoreM ModGuts
coronetPass opts guts = do
  let currentMod = mg_module guts
  let mName = moduleNameString (moduleName currentMod)
  let safeMName = sanitizeModName mName
  let rawBinds = mg_binds guts

  let (coreLiteText, exportedNames, isMainMod) = dumpCoreProgram currentMod rawBinds

  liftIO $ do
    case parseDirOpt opts of
      Just dirPath -> do
        createDirectoryIfMissing True dirPath
        let outCorePath = dirPath ++ "/" ++ safeMName ++ ".core"
        writeFile outCorePath coreLiteText
        let manifestPath = dirPath ++ "/manifest.json"
        updateManifest manifestPath mName (safeMName ++ ".core") exportedNames isMainMod
      Nothing ->
        case parseOutPath opts of
          Just outPath -> writeFile outPath coreLiteText
          Nothing -> do
            putStrLn ("==================== Coronet CoreLite: " ++ mName ++ " ====================")
            putStr coreLiteText
            putStrLn "=========================================================="
  return guts

parseOutPath :: [CommandLineOption] -> Maybe FilePath
parseOutPath [] = Nothing
parseOutPath (opt:opts)
  | "out=" `isPrefixOf` opt    = Just (drop 4 opt)
  | "output=" `isPrefixOf` opt = Just (drop 7 opt)
  | "-o=" `isPrefixOf` opt     = Just (drop 3 opt)
  | otherwise                  = parseOutPath opts

parseDirOpt :: [CommandLineOption] -> Maybe FilePath
parseDirOpt [] = Nothing
parseDirOpt (opt:opts)
  | "dir=" `isPrefixOf` opt    = Just (drop 4 opt)
  | "-dir=" `isPrefixOf` opt   = Just (drop 5 opt)
  | otherwise                  = parseDirOpt opts

sanitizeModName :: String -> String
sanitizeModName = map (\c -> if c == '.' then '_' else c)

isUserModule :: String -> Bool
isUserModule mName =
  not ("GHC." `isPrefixOf` mName ||
       "System." `isPrefixOf` mName ||
       "Control." `isPrefixOf` mName ||
       "Data.Tuple" `isPrefixOf` mName)

dumpCoreProgram :: Module -> CoreProgram -> (String, [String], Bool)
dumpCoreProgram currentMod binds =
  let mName = moduleNameString (moduleName currentMod)
      safeMName = sanitizeModName mName
      isMain = mName == "Main"

      filtered = filter (not . isMetadataBind) binds
      hasResult = any hasResultBind filtered
      pruned = if hasResult then filter (not . isIoMainBind) filtered else filtered

      exportedNames = nub [ qualifyTopBinder currentMod b | b <- collectTopBinders pruned, not (isMetadataName (bndrName b)) ]

      rendered = map (renderBind currentMod) pruned
      finalBinds = if hasResult then rendered ++ ["main = result\n"] else rendered
  in (intercalate "\n" finalBinds, exportedNames, isMain)

collectTopBinders :: [CoreBind] -> [CoreBndr]
collectTopBinders [] = []
collectTopBinders (NonRec b _ : rest) = b : collectTopBinders rest
collectTopBinders (Rec pairs : rest) = map fst pairs ++ collectTopBinders rest

isMetadataBind :: CoreBind -> Bool
isMetadataBind (NonRec b _) = isMetadataName (bndrName b)
isMetadataBind (Rec pairs)  = all (\(b, _) -> isMetadataName (bndrName b)) pairs

isMetadataName :: String -> Bool
isMetadataName name =
  "$trModule" `isPrefixOf` name ||
  "$tc" `isPrefixOf` name ||
  "$krep" `isPrefixOf` name

hasResultBind :: CoreBind -> Bool
hasResultBind (NonRec b _) = bndrName b == "result"
hasResultBind (Rec pairs)  = any (\(b, _) -> bndrName b == "result") pairs

isIoMainBind :: CoreBind -> Bool
isIoMainBind (NonRec b expr) =
  let n = bndrName b in n == "main" || "main" `isPrefixOf` n || mentionsIo expr
isIoMainBind (Rec pairs)  =
  any (\(b, expr) -> "main" `isPrefixOf` bndrName b || mentionsIo expr) pairs

mentionsIo :: CoreExpr -> Bool
mentionsIo expr = case expr of
  Var v ->
    let occ = occNameString (getOccName v)
    in occ `elem` ["itos", "$witos", "hPutStr2", "stdout", "runMainIO1", "putStrLn"]
  App f a -> mentionsIo f || mentionsIo a
  Lam _ body -> mentionsIo body
  Let bind body ->
    (case bind of
       NonRec _ e -> mentionsIo e
       Rec ps -> any (mentionsIo . snd) ps) || mentionsIo body
  Case scrut _ _ alts ->
    mentionsIo scrut || any (\(Alt _ _ e) -> mentionsIo e) alts
  Cast e _ -> mentionsIo e
  Tick _ e -> mentionsIo e
  _ -> False

isStandAloneOperator :: String -> Bool
isStandAloneOperator s =
  s `elem`
    [ "+", "-", "*", "/", "==", "/=", "<", "<=", ">", ">="
    , "+#", "-#", "*#", "*H#", "==#", "/=#", "<#", "<=#", ">#", ">=#"
    ]

sanitizeIdent :: String -> String
sanitizeIdent raw
  | isStandAloneOperator raw = raw
  | isUnboxedTupleOcc raw || isUnboxedSumOcc raw = raw
  | otherwise =
      let rep [] = []
          rep ('/':'=':xs) = '_' : 'n' : 'e' : '_' : rep xs
          rep ('=':'=':xs) = '_' : 'e' : 'q' : '_' : rep xs
          rep ('<':'=':xs) = '_' : 'l' : 'e' : '_' : rep xs
          rep ('>':'=':xs) = '_' : 'g' : 'e' : '_' : rep xs
          rep ('<':xs)     = '_' : 'l' : 't' : '_' : rep xs
          rep ('>':xs)     = '_' : 'g' : 't' : '_' : rep xs
          rep ('/':xs)     = '_' : 'd' : 'i' : 'v' : '_' : rep xs
          rep ('+':xs)     = '_' : 'p' : 'l' : 'u' : 's' : '_' : rep xs
          rep ('-':xs)     = '_' : 'm' : 'i' : 'n' : 'u' : 's' : '_' : rep xs
          -- Operators a real package can name: Data.Map.(!?), Data.Set.(\\),
          -- the (.) method selector `$c.`. CoreLite has no syntax for these,
          -- so they get a readable escape instead of breaking the parse.
          rep ('!':xs)     = '_' : 'b' : 'a' : 'n' : 'g' : '_' : rep xs
          rep ('?':xs)     = '_' : 'q' : 'u' : 'e' : 's' : '_' : rep xs
          rep ('\\':xs)    = '_' : 'b' : 's' : 'l' : '_' : rep xs
          rep ('.':xs)     = '_' : 'd' : 'o' : 't' : '_' : rep xs
          rep ('=':xs)     = '_' : 'e' : 'q' : '_' : rep xs
          -- Anything else a symbol operator can contain (`=<<`, `>>>`, `<$!>`)
          -- Characters CoreLite can lex as part of an operator name stay
          -- literal (this keeps `[]`, `(:)`, `(,)`, `C:Show`, `&&` readable and
          -- lets the core-lite side keep its constructor table keys).
          rep (c:xs)
            | isAlphaNum c || c `elem` "_$#'()[]&|:," = c : rep xs
            | otherwise = '_' : 'u' : (show (ord c) ++ ('_' : rep xs))
      in rep raw

extractFfiName :: CoreBndr -> Maybe String
extractFfiName b =
  case idDetails b of
    FCallId (CCall (CCallSpec (StaticTarget _ fs _ _) _ _)) ->
      Just ("ccall_" ++ unpackFS fs)
    FCallId (CCall (CCallSpec DynamicTarget _ _)) ->
      Just "ccall_dynamic"
    _ ->
      let raw = showSDocUnsafe (ppr b)
      in if "__ffi_" `isInfixOf` raw
         then
           let clean = takeWhile (\c -> c /= ' ' && c /= ':' && c /= '}' && c /= '\n')
                         (dropWhile (== ' ')
                           (dropWhile (/= ' ')
                             (dropWhile (/= '_') raw)))
           in if null clean then Just "ccall_unknown" else Just ("ccall_" ++ clean)
         else Nothing

bndrName :: CoreBndr -> String
bndrName b =
  case extractFfiName b of
    Just ffiName -> ffiName
    Nothing ->
      let name = varName b
          occ = occNameString (getOccName b)
          raw = if isExternalName name || occ == "main" || occ == "result"
                then occ
                else showSDocUnsafe (ppr b)
      in sanitizeIdent raw

qualifyTopBinder :: Module -> CoreBndr -> String
qualifyTopBinder currentMod b =
  let mName = moduleNameString (moduleName currentMod)
      occ = bndrName b
  in if mName == "Main" || occ == "main" || occ == "result"
     then occ
     else sanitizeModName mName ++ "_" ++ occ

qualifyVarUse :: Module -> CoreBndr -> String
qualifyVarUse currentMod v
  | isLocalId v = normalizeVarName (bndrName v)
  | isDataConWorkId v || isDataConWrapId v = normalizeVarName (bndrName v)
  | otherwise =
      let occ = bndrName v
          curMName = moduleNameString (moduleName currentMod)
      in if isPrimitiveName occ
         then normalizeVarName occ
         else case nameModule_maybe (idName v) of
           Just m ->
             let vMod = moduleNameString (moduleName m)
             in if isUserModule vMod
                then if vMod == curMName
                     then if curMName == "Main" then occ else sanitizeModName curMName ++ "_" ++ occ
                     else sanitizeModName vMod ++ "_" ++ occ
                else normalizeVarName occ
           Nothing ->
             if curMName /= "Main"
             then sanitizeModName curMName ++ "_" ++ occ
             else normalizeVarName occ

isUnboxedTupleOcc :: String -> Bool
isUnboxedTupleOcc s =
  "(#" `isPrefixOf` s && "#)" `isSuffixOf` s &&
  let inner = take (length s - 4) (drop 2 s)
  in all (\c -> c == ',' || c == ' ') inner

isUnboxedSumOcc :: String -> Bool
isUnboxedSumOcc s =
  "(#" `isPrefixOf` s && "#)" `isSuffixOf` s && '|' `elem` s

isPrimitiveName :: String -> Bool
isPrimitiveName occ =
  occ `elem`
    [ "I#", "W#", "W8#", "W16#", "W32#", "W64#", "I8#", "I16#", "I32#", "I64#", "C#"
    , "True", "False", "+", "-", "*"
    , "+#", "-#", "*#", "*H#", "negateInt#"
    , "quotInt#", "remInt#", "quotRemInt#"
    , "==#", "/=#", "<#", "<=#", ">#", ">=#"
    , "and#", "or#", "xor#", "not#"
    , "andI#", "orI#", "xorI#", "notI#"
    , "uncheckedShiftL#", "uncheckedShiftRL#"
    , "uncheckedIShiftL#", "uncheckedIShiftRL#", "uncheckedIShiftRA#"
    , "plusWord#", "minusWord#", "timesWord#", "quotWord#", "remWord#"
    , "eqWord#", "neWord#", "ltWord#", "leWord#", "gtWord#", "geWord#"
    , "andWord#", "orWord#", "xorWord#", "notWord#"
    , "int2Word#", "word2Int#"
    , "narrow8Int#", "narrow16Int#", "narrow32Int#"
    , "narrow8Word#", "narrow16Word#", "narrow32Word#"
    , "chr#", "ord#"
    , "unpackCString#", "unpackCStringUtf8#", "Addr#"
    , "newByteArray#", "sizeofByteArray#", "sizeofMutableByteArray#"
    , "indexWord8Array#", "readWord8Array#", "writeWord8Array#"
    , "indexIntArray#", "readIntArray#", "writeIntArray#"
    , "copyByteArray#", "readByteArray#", "writeByteArray#", "setByteArray#"
    , "newMutVar#", "readMutVar#", "writeMutVar#"
    , "runRW#", "realWorld#", "State#", "RealWorld", "MutVar#"
    , "raise#", "raiseIO#", "patError#", "divZeroError", "overflowError"
    ]
    || isUnboxedTupleOcc occ
    || isUnboxedSumOcc occ
    || ("ccall_" `isPrefixOf` occ)
    || ("#" `isSuffixOf` occ && not ("$" `isPrefixOf` occ))

renderBind :: Module -> CoreBind -> String
renderBind currentMod (NonRec b expr) =
  let qName = qualifyTopBinder currentMod b
      bodyStr = renderExpr currentMod expr
      aliasStr =
        let orig = bndrName b
        in if qName /= orig && not (isMetadataName orig)
           then "\n" ++ orig ++ " = " ++ qName ++ "\n"
           else ""
  in qName ++ "\n  = " ++ bodyStr ++ "\n" ++ aliasStr
renderBind currentMod (Rec pairs) =
  let recBody = "Rec {\n" ++
        concatMap (\(b, expr) -> qualifyTopBinder currentMod b ++ "\n  = " ++ renderExpr currentMod expr ++ ";\n") pairs ++
        "end Rec }\n"
      aliases = concatMap (\(b, _) ->
        let q = qualifyTopBinder currentMod b
            orig = bndrName b
        in if q /= orig && not (isMetadataName orig)
           then orig ++ " = " ++ q ++ "\n"
           else ""
        ) pairs
  in recBody ++ (if null aliases then "" else "\n" ++ aliases)

renderExpr :: Module -> CoreExpr -> String
renderExpr currentMod expr = case expr of
  Var v -> qualifyVarUse currentMod v
  Lit l -> renderLiteral l
  Cast e _ -> renderExpr currentMod e
  Tick _ e -> renderExpr currentMod e
  Type _ -> "*"
  Coercion _ -> "*"
  App f (Type _) -> renderExpr currentMod f
  App f (Coercion _) -> renderExpr currentMod f
  App _ _ ->
    let (headFn, args) = collectArgs expr
        cleanArgs = filter (not . isTypeOrCoercion) args
    in if null cleanArgs
       then renderExpr currentMod headFn
       else
         case headFn of
           Var v | isUnboxedTupleOcc (occNameString (getOccName v)) ->
             "(# " ++ intercalate ", " (map (renderExpr currentMod) cleanArgs) ++ " #)"
           Var v | isUnboxedSumOcc (occNameString (getOccName v)) ->
             "(# | " ++ unwords (map (renderExpr currentMod) cleanArgs) ++ " #)"
           _ ->
             renderExpr currentMod headFn ++ " " ++ unwords (map (renderAtom currentMod) cleanArgs)
  Lam _ _ ->
    let (bndrs, body) = collectBinders expr
        termBndrs = filter isId bndrs
    in if null termBndrs
       then renderExpr currentMod body
       else "\\ " ++ unwords (map bndrName termBndrs) ++ " ->\n      " ++ renderExpr currentMod body
  Let bind body ->
    "let " ++ renderInlineBind currentMod bind ++ " in " ++ renderExpr currentMod body
  Case scrut bndr _ alts ->
    let bndrStr = let n = bndrName bndr in if n == "_" then "" else " " ++ n
    -- The scrutinee has to be an atom: a nested case (`case case f x of ...`)
    -- or a lambda there is not readable back by Coronet's own parser.
    in "case " ++ renderAtom currentMod scrut ++ " of" ++ bndrStr ++ " {\n" ++
       intercalate ";\n" (map (renderAlt currentMod) alts) ++ "\n      }"

isTypeOrCoercion :: CoreExpr -> Bool
isTypeOrCoercion (Type _)     = True
isTypeOrCoercion (Coercion _) = True
isTypeOrCoercion _            = False

renderInlineBind :: Module -> CoreBind -> String
renderInlineBind currentMod (NonRec b e) =
  bndrName b ++ " = " ++ renderExpr currentMod e
renderInlineBind currentMod (Rec pairs) =
  "Rec { " ++ intercalate "; " (map (\(b, e) -> bndrName b ++ " = " ++ renderExpr currentMod e) pairs) ++ " end Rec }"

renderAtom :: Module -> CoreExpr -> String
renderAtom currentMod expr = case expr of
  Var v -> qualifyVarUse currentMod v
  Lit l -> renderLiteral l
  App f (Type _) -> renderAtom currentMod f
  App f (Coercion _) -> renderAtom currentMod f
  Cast e _ -> renderAtom currentMod e
  Tick _ e -> renderAtom currentMod e
  App _ _ ->
    let (headFn, args) = collectArgs expr
        cleanArgs = filter (not . isTypeOrCoercion) args
    in case headFn of
         Var v | isUnboxedTupleOcc (occNameString (getOccName v)) ->
           "(# " ++ intercalate ", " (map (renderExpr currentMod) cleanArgs) ++ " #)"
         Var v | isUnboxedSumOcc (occNameString (getOccName v)) ->
           "(# | " ++ unwords (map (renderExpr currentMod) cleanArgs) ++ " #)"
         _ -> "(" ++ renderExpr currentMod expr ++ ")"
  _ -> "(" ++ renderExpr currentMod expr ++ ")"

renderLiteral :: Literal -> String
renderLiteral lit = case lit of
  LitNumber _ n -> show n ++ "#"
  LitString bs  -> show bs ++ "#"
  LitChar c     -> show c
  LitNullAddr   -> "0#"
  _             -> "0#"

normalizeVarName :: String -> String
normalizeVarName name
  | name == "$fNumInt_$c+" = "+"
  | name == "$fNumInt_$c-" = "-"
  | name == "$fNumInt_$c*" = "*"
  | otherwise              = name

renderAlt :: Module -> CoreAlt -> String
renderAlt currentMod (Alt con bndrs e) =
  let patStr = case con of
        DEFAULT -> "__DEFAULT"
        LitAlt l -> renderLiteral l
        DataAlt dc ->
          let cname = occNameString (getOccName dc)
              termArgs = [bndrName v | v <- bndrs, isId v]
          in if isUnboxedTupleOcc cname
             then "(# " ++ intercalate ", " termArgs ++ " #)"
             else if isUnboxedSumOcc cname
                  then "(# | " ++ unwords termArgs ++ " #)"
                  else if null termArgs then cname else cname ++ " " ++ unwords termArgs
  in "        " ++ patStr ++ " -> " ++ renderExpr currentMod e

-- Manifest JSON generation and updating
data ModEntry = ModEntry
  { entryModName :: String
  , entryCoreFile :: String
  , entryExports :: [String]
  , entryIsMain :: Bool
  } deriving (Show, Eq)

updateManifest :: FilePath -> String -> String -> [String] -> Bool -> IO ()
updateManifest manifestPath mName coreFileName exps isMain = do
  exists <- doesFileExist manifestPath
  prevEntries <- if exists
                 then do
                   content <- withFile manifestPath ReadMode $ \h -> do
                     c <- hGetContents h
                     length c `seq` return c
                   return (parseManifest content)
                 else return []
  let newEntry = ModEntry mName coreFileName exps isMain
  let merged = filter (\e -> entryModName e /= mName) prevEntries ++ [newEntry]
  writeFile manifestPath (renderManifest merged)

renderManifest :: [ModEntry] -> String
renderManifest entries =
  "{\n  \"modules\": [\n" ++
  intercalate ",\n" (map renderEntry entries) ++
  "\n  ]\n}\n"
  where
    renderEntry e =
      "    {\n" ++
      "      \"name\": \"" ++ entryModName e ++ "\",\n" ++
      "      \"file\": \"" ++ entryCoreFile e ++ "\",\n" ++
      "      \"exports\": [" ++ intercalate ", " (map (\x -> "\"" ++ x ++ "\"") (entryExports e)) ++ "]" ++
      (if entryIsMain e then ",\n      \"entrypoint\": \"main\"" else "") ++
      "\n    }"

parseManifest :: String -> [ModEntry]
parseManifest content =
  let chunks = splitOnObject content
  in [e | Just e <- map parseEntry chunks]

splitOnObject :: String -> [String]
splitOnObject s =
  case break (== '{') s of
    (_, "") -> []
    (_, rest) ->
      case break (== '}') (drop 1 rest) of
        (chunk, after) -> chunk : splitOnObject after

parseEntry :: String -> Maybe ModEntry
parseEntry chunk =
  case (extractField "name" chunk, extractField "file" chunk) of
    (Just m, Just f) ->
      let exts = extractList "exports" chunk
          hasEntry = extractField "entrypoint" chunk == Just "main"
      in Just (ModEntry m f exts hasEntry)
    _ -> Nothing

extractField :: String -> String -> Maybe String
extractField key chunk =
  let needle = "\"" ++ key ++ "\":"
  in case findSub needle chunk of
    Just rest ->
      let trimmed = dropWhile (\c -> c == ' ' || c == '\t' || c == '\n') rest
      in case trimmed of
        '"':afterQuote -> Just (takeWhile (/= '"') afterQuote)
        _ -> Nothing
    Nothing -> Nothing

extractList :: String -> String -> [String]
extractList key chunk =
  let needle = "\"" ++ key ++ "\":"
  in case findSub needle chunk of
    Just rest ->
      case dropWhile (/= '[') rest of
        '[':inside ->
          let content = takeWhile (/= ']') inside
              tokens = words (map (\c -> if c == ',' then ' ' else c) content)
          in [stripQuotes t | t <- tokens, not (null (stripQuotes t))]
        _ -> []
    Nothing -> []

stripQuotes :: String -> String
stripQuotes s = filter (/= '"') s

findSub :: String -> String -> Maybe String
findSub [] ys = Just ys
findSub _ [] = Nothing
findSub xs (y:ys) =
  if take (length xs) (y:ys) == xs
  then Just (drop (length xs) (y:ys))
  else findSub xs ys
