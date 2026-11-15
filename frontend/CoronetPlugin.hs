{-# LANGUAGE BangPatterns #-}
module CoronetPlugin (plugin) where

import GHC.Plugins
import GHC.Core
import GHC.Core.Utils
import Data.List (isPrefixOf, intercalate)
import System.IO
import Control.Monad.IO.Class (liftIO)

plugin :: Plugin
plugin = defaultPlugin
  { installCoreToDos = install
  , pluginRecompile  = purePlugin
  }

install :: [CommandLineOption] -> [CoreToDo] -> CoreM [CoreToDo]
install opts todos = do
  -- Run Coronet Core extraction after GHC simplifier
  let pass = CoreDoPluginPass "CoronetDump" (coronetPass opts)
  return (todos ++ [pass])

coronetPass :: [CommandLineOption] -> ModGuts -> CoreM ModGuts
coronetPass opts guts = do
  let rawBinds = mg_binds guts
  let coreLiteText = dumpCoreProgram rawBinds
  liftIO $ do
    case parseOutPath opts of
      Just outPath -> writeFile outPath coreLiteText
      Nothing -> do
        putStrLn "==================== Coronet CoreLite ===================="
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

dumpCoreProgram :: CoreProgram -> String
dumpCoreProgram binds =
  let filtered = filter (not . isMetadataBind) binds
      hasResult = any hasResultBind filtered
      pruned = if hasResult then filter (not . isIoMainBind) filtered else filtered
      rendered = map renderBind pruned
      finalBinds = if hasResult then rendered ++ ["main = result\n"] else rendered
  in intercalate "\n" finalBinds

isMetadataBind :: CoreBind -> Bool
isMetadataBind (NonRec b _) = isMetaName (bndrName b)
isMetadataBind (Rec pairs)  = all (\(b, _) -> isMetaName (bndrName b)) pairs

isMetaName :: String -> Bool
isMetaName name =
  "$trModule" `isPrefixOf` name ||
  "$tc" `isPrefixOf` name ||
  "$krep" `isPrefixOf` name

hasResultBind :: CoreBind -> Bool
hasResultBind (NonRec b _) = bndrName b == "result"
hasResultBind (Rec pairs)  = any (\(b, _) -> bndrName b == "result") pairs

isIoMainBind :: CoreBind -> Bool
isIoMainBind (NonRec b _) =
  let n = bndrName b in n == "main" || "main" `isPrefixOf` n
isIoMainBind (Rec pairs)  =
  any (\(b, _) -> "main" `isPrefixOf` bndrName b) pairs

bndrName :: CoreBndr -> String
bndrName b = occNameString (getOccName b)

renderBind :: CoreBind -> String
renderBind (NonRec b expr) =
  bndrName b ++ "\n  = " ++ renderExpr expr ++ "\n"
renderBind (Rec pairs) =
  "Rec {\n" ++
  concatMap (\(b, expr) -> bndrName b ++ "\n  = " ++ renderExpr expr ++ ";\n") pairs ++
  "end Rec }\n"

renderExpr :: CoreExpr -> String
renderExpr expr = case expr of
  Var v -> normalizeVarName (bndrName v)
  Lit l -> renderLiteral l
  Cast e _ -> renderExpr e
  Tick _ e -> renderExpr e
  Type _ -> "*"
  Coercion _ -> "*"
  App f (Type _) -> renderExpr f
  App f (Coercion _) -> renderExpr f
  App _ _ ->
    let (headFn, args) = collectArgs expr
        cleanArgs = filter (not . isTypeOrCoercion) args
    in if null cleanArgs
       then renderExpr headFn
       else renderExpr headFn ++ " " ++ unwords (map renderAtom cleanArgs)
  Lam _ _ ->
    let (bndrs, body) = collectBinders expr
        termBndrs = filter isId bndrs
    in if null termBndrs
       then renderExpr body
       else "\\ " ++ unwords (map bndrName termBndrs) ++ " ->\n      " ++ renderExpr body
  Let bind body ->
    "let " ++ renderInlineBind bind ++ " in " ++ renderExpr body
  Case scrut bndr _ alts ->
    let bndrStr = let n = bndrName bndr in if isWild n then "" else " " ++ n
    in "case " ++ renderExpr scrut ++ " of" ++ bndrStr ++ " {\n" ++
       intercalate ";\n" (map renderAlt alts) ++ "\n      }"

isTypeOrCoercion :: CoreExpr -> Bool
isTypeOrCoercion (Type _)     = True
isTypeOrCoercion (Coercion _) = True
isTypeOrCoercion _            = False

isWild :: String -> Bool
isWild n = "wild" `isPrefixOf` n || "ds" `isPrefixOf` n || n == "_"

renderInlineBind :: CoreBind -> String
renderInlineBind (NonRec b e) = bndrName b ++ " = " ++ renderExpr e
renderInlineBind (Rec pairs) =
  "Rec { " ++ intercalate "; " (map (\(b, e) -> bndrName b ++ " = " ++ renderExpr e) pairs) ++ " end Rec }"

renderAtom :: CoreExpr -> String
renderAtom expr = case expr of
  Var v -> normalizeVarName (bndrName v)
  Lit l -> renderLiteral l
  App f (Type _) -> renderAtom f
  App f (Coercion _) -> renderAtom f
  Cast e _ -> renderAtom e
  Tick _ e -> renderAtom e
  _ -> "(" ++ renderExpr expr ++ ")"

renderLiteral :: Literal -> String
renderLiteral lit = case lit of
  LitNumber _ n -> show n ++ "#"
  LitString bs  -> show bs
  LitChar c     -> show c
  _             -> "0#"

normalizeVarName :: String -> String
normalizeVarName name
  | name == "$fNumInt_$c+" = "+"
  | name == "$fNumInt_$c-" = "-"
  | name == "$fNumInt_$c*" = "*"
  | otherwise              = name

renderAlt :: CoreAlt -> String
renderAlt (Alt con bndrs e) =
  let patStr = case con of
        DEFAULT -> "__DEFAULT"
        LitAlt l -> renderLiteral l
        DataAlt dc ->
          let cname = occNameString (getOccName dc)
              termArgs = [bndrName v | v <- bndrs, isId v]
          in if null termArgs then cname else cname ++ " " ++ unwords termArgs
  in "        " ++ patStr ++ " -> " ++ renderExpr e
