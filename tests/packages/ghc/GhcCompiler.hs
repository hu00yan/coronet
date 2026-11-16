{-# LANGUAGE BangPatterns #-}
module Main where

-- =========================================================================
-- 1. Core AST Representation (GHC Core Subset)
-- =========================================================================

type Var = String

data Literal
  = LitInt !Int
  | LitBool !Bool
  deriving (Show, Eq)

data AltCon
  = CDataAlt String
  | CLitAlt Literal
  | CDEFAULT
  deriving (Show, Eq)

data CoreAlt
  = CAlt AltCon [Var] CoreExpr
  deriving (Show, Eq)

data CoreBind
  = CNonRec Var CoreExpr
  | CRec [(Var, CoreExpr)]
  deriving (Show, Eq)

data CoreExpr
  = CVar Var
  | CLit Literal
  | CApp CoreExpr CoreExpr
  | CLam Var CoreExpr
  | CLet CoreBind CoreExpr
  | CCase CoreExpr Var [CoreAlt]
  deriving (Show, Eq)

-- =========================================================================
-- 2. Free Variables & Substitution
-- =========================================================================

freeVars :: CoreExpr -> [Var]
freeVars expr = case expr of
  CVar v -> [v]
  CLit _ -> []
  CApp f a -> freeVars f ++ freeVars a
  CLam x b -> filter (/= x) (freeVars b)
  CLet (CNonRec x e) b -> freeVars e ++ filter (/= x) (freeVars b)
  CLet (CRec bs) b ->
    let bndrs = map fst bs
        allFVs = concatMap (freeVars . snd) bs ++ freeVars b
    in filter (`notElem` bndrs) allFVs
  CCase s b alts ->
    freeVars s ++ concatMap (\(CAlt _ vars e) -> filter (`notElem` (b : vars)) (freeVars e)) alts

subst :: Var -> CoreExpr -> CoreExpr -> CoreExpr
subst x s expr = case expr of
  CVar v -> if v == x then s else CVar v
  CLit l -> CLit l
  CApp f a -> CApp (subst x s f) (subst x s a)
  CLam v b ->
    if v == x then CLam v b
    else CLam v (subst x s b)
  CLet (CNonRec v e) b ->
    let e' = subst x s e
    in if v == x then CLet (CNonRec v e') b
       else CLet (CNonRec v e') (subst x s b)
  CLet (CRec bs) b ->
    let bndrs = map fst bs
    in if x `elem` bndrs
       then CLet (CRec (map (\(k, v) -> (k, subst x s v)) bs)) b
       else CLet (CRec (map (\(k, v) -> (k, subst x s v)) bs)) (subst x s b)
  CCase scrut b alts ->
    let scrut' = subst x s scrut
    in if b == x
       then CCase scrut' b alts
       else CCase scrut' b (map substAlt alts)
    where
      substAlt (CAlt con vars e) =
        if x `elem` vars
        then CAlt con vars e
        else CAlt con vars (subst x s e)

-- =========================================================================
-- 3. GHC Core Optimizer Pipeline
-- =========================================================================

-- 3.1 Constant Folding (constFold)
constFold :: CoreExpr -> CoreExpr
constFold expr = case expr of
  CApp (CApp (CVar "+") (CLit (LitInt a))) (CLit (LitInt b)) -> CLit (LitInt (a + b))
  CApp (CApp (CVar "-") (CLit (LitInt a))) (CLit (LitInt b)) -> CLit (LitInt (a - b))
  CApp (CApp (CVar "*") (CLit (LitInt a))) (CLit (LitInt b)) -> CLit (LitInt (a * b))
  CApp (CApp (CVar "==") (CLit (LitInt a))) (CLit (LitInt b)) -> CLit (LitBool (a == b))
  CApp (CApp (CVar "<") (CLit (LitInt a))) (CLit (LitInt b)) -> CLit (LitBool (a < b))
  CApp (CApp (CVar ">") (CLit (LitInt a))) (CLit (LitInt b)) -> CLit (LitBool (a > b))
  CCase (CLit (LitBool True)) _ alts ->
    findAlt (CDataAlt "True") alts
  CCase (CLit (LitBool False)) _ alts ->
    findAlt (CDataAlt "False") alts
  CCase (CLit (LitInt n)) _ alts ->
    findLitAlt (LitInt n) alts
  CApp f a -> CApp (constFold f) (constFold a)
  CLam x b -> CLam x (constFold b)
  CLet (CNonRec x e) b -> CLet (CNonRec x (constFold e)) (constFold b)
  CLet (CRec bs) b -> CLet (CRec (map (\(k, v) -> (k, constFold v)) bs)) (constFold b)
  CCase s b alts ->
    CCase (constFold s) b (map (\(CAlt c vs e) -> CAlt c vs (constFold e)) alts)
  other -> other
  where
    findAlt _ [] = CLit (LitInt 0)
    findAlt con (CAlt c _ e : rest)
      | c == con = constFold e
      | c == CDEFAULT = constFold e
      | otherwise = findAlt con rest
    findLitAlt _ [] = CLit (LitInt 0)
    findLitAlt l (CAlt (CLitAlt l') _ e : rest)
      | l == l' = constFold e
      | otherwise = findLitAlt l rest
    findLitAlt _ (CAlt CDEFAULT _ e : _) = constFold e

-- 3.2 Beta Reduction (betaReduce)
betaReduce :: CoreExpr -> CoreExpr
betaReduce expr = case expr of
  CApp (CLam x body) arg ->
    betaReduce (subst x (betaReduce arg) body)
  CApp f a ->
    let f' = betaReduce f
        a' = betaReduce a
    in case f' of
      CLam x body -> betaReduce (subst x a' body)
      _ -> CApp f' a'
  CLam x b -> CLam x (betaReduce b)
  CLet (CNonRec x e) b -> CLet (CNonRec x (betaReduce e)) (betaReduce b)
  CLet (CRec bs) b -> CLet (CRec (map (\(k, v) -> (k, betaReduce v)) bs)) (betaReduce b)
  CCase s b alts -> CCase (betaReduce s) b (map (\(CAlt c vs e) -> CAlt c vs (betaReduce e)) alts)
  other -> other

-- 3.3 Inlining of Simple Binders (inlineBndr)
inlineBndr :: CoreExpr -> CoreExpr
inlineBndr expr = case expr of
  CLet (CNonRec x (CVar v)) b ->
    inlineBndr (subst x (CVar v) b)
  CLet (CNonRec x (CLit l)) b ->
    inlineBndr (subst x (CLit l) b)
  CLet (CNonRec x e) b ->
    CLet (CNonRec x (inlineBndr e)) (inlineBndr b)
  CLet (CRec bs) b ->
    CLet (CRec (map (\(k, v) -> (k, inlineBndr v)) bs)) (inlineBndr b)
  CApp f a -> CApp (inlineBndr f) (inlineBndr a)
  CLam x b -> CLam x (inlineBndr b)
  CCase s b alts -> CCase (inlineBndr s) b (map (\(CAlt c vs e) -> CAlt c vs (inlineBndr e)) alts)
  other -> other

-- 3.4 Dead Code Elimination (dce)
dce :: CoreExpr -> CoreExpr
dce expr = case expr of
  CLet (CNonRec x e) b ->
    let b' = dce b
    in if x `elem` freeVars b'
       then CLet (CNonRec x (dce e)) b'
       else b'
  CLet (CRec bs) b ->
    let b' = dce b
        fvs = freeVars b'
        needed = filter (\(k, _) -> k `elem` fvs) bs
    in if null needed
       then b'
       else CLet (CRec (map (\(k, v) -> (k, dce v)) needed)) b'
  CApp f a -> CApp (dce f) (dce a)
  CLam x b -> CLam x (dce b)
  CCase s b alts -> CCase (dce s) b (map (\(CAlt c vs e) -> CAlt c vs (dce e)) alts)
  other -> other

-- 3.5 Full Optimization Pipeline
optimizePass :: CoreExpr -> CoreExpr
optimizePass = dce . inlineBndr . betaReduce . constFold

optimize :: CoreExpr -> CoreExpr
optimize expr =
  let e1 = optimizePass expr
      e2 = optimizePass e1
      e3 = optimizePass e2
  in e3

-- =========================================================================
-- 4. Core Evaluator / Normalizer
-- =========================================================================

data Value
  = VInt !Int
  | VBool !Bool
  | VClosure [(Var, Value)] Var CoreExpr
  | VRecClosure [(Var, Value)] [(Var, CoreExpr)] Var CoreExpr
  | VConstr String [Value]
  deriving (Show, Eq)

type Env = [(Var, Value)]

lookupEnv :: Var -> Env -> Value
lookupEnv v [] = VInt 0
lookupEnv v ((k, val) : rest)
  | v == k    = val
  | otherwise = lookupEnv v rest

eval :: Env -> CoreExpr -> Value
eval env expr = case expr of
  CApp (CApp (CVar "+") a) b ->
    case (eval env a, eval env b) of
      (VInt x, VInt y) -> VInt (x + y)
      _ -> VInt 0
  CApp (CApp (CVar "-") a) b ->
    case (eval env a, eval env b) of
      (VInt x, VInt y) -> VInt (x - y)
      _ -> VInt 0
  CApp (CApp (CVar "*") a) b ->
    case (eval env a, eval env b) of
      (VInt x, VInt y) -> VInt (x * y)
      _ -> VInt 0
  CApp (CApp (CVar "==") a) b ->
    case (eval env a, eval env b) of
      (VInt x, VInt y) -> VBool (x == y)
      _ -> VBool False
  CApp (CApp (CVar "<") a) b ->
    case (eval env a, eval env b) of
      (VInt x, VInt y) -> VBool (x < y)
      _ -> VBool False
  CApp (CApp (CVar ">") a) b ->
    case (eval env a, eval env b) of
      (VInt x, VInt y) -> VBool (x > y)
      _ -> VBool False
  CVar "True" -> VBool True
  CVar "False" -> VBool False
  CVar "Leaf" -> VConstr "Leaf" []
  CVar "Node" -> VConstr "Node" []
  CVar v -> lookupEnv v env
  CLit (LitInt n) -> VInt n
  CLit (LitBool b) -> VBool b
  CLam x body -> VClosure env x body
  CApp f arg ->
    let valArg = eval env arg
    in case eval env f of
      VClosure cEnv param body ->
        eval ((param, valArg) : cEnv) body
      VRecClosure cEnv bs param body ->
        let recBindings = map (\(k, e) -> case e of
              CLam x b -> (k, VRecClosure cEnv bs x b)
              _ -> (k, eval cEnv e)) bs
        in eval ((param, valArg) : recBindings ++ cEnv) body
      VConstr cName args ->
        VConstr cName (args ++ [valArg])
      _ -> VInt 0
  CLet (CNonRec x e) body ->
    let val = eval env e
    in eval ((x, val) : env) body
  CLet (CRec bs) body ->
    let recBindings = map (\(k, e) -> case e of
          CLam x b -> (k, VRecClosure env bs x b)
          _ -> (k, eval env e)) bs
    in eval (recBindings ++ env) body
  CCase scrut b alts ->
    let val = eval env scrut
        env' = (b, val) : env
    in matchAlts env' val alts
  where
    matchAlts _ _ [] = VInt 0
    matchAlts e val (CAlt con vars body : rest) = case (con, val) of
      (CDEFAULT, _) -> eval e body
      (CLitAlt (LitInt n), VInt m) | n == m -> eval e body
      (CDataAlt "True", VBool True) -> eval e body
      (CDataAlt "False", VBool False) -> eval e body
      (CDataAlt cName, VConstr cName' vals) | cName == cName' ->
        eval (zip vars vals ++ e) body
      _ -> matchAlts e val rest

toInt :: Value -> Int
toInt (VInt n) = n
toInt (VBool True) = 1
toInt (VBool False) = 0
toInt _ = 0

-- =========================================================================
-- 5. Benchmark Suite (Workload)
-- =========================================================================

-- Workload 1: Arithmetic with Dead Code & Constant Folding
workload1 :: CoreExpr
workload1 =
  CLet (CNonRec "dead1" (CApp (CApp (CVar "*") (CLit (LitInt 10))) (CLit (LitInt 20))))
    (CLet (CNonRec "dead2" (CApp (CApp (CVar "+") (CLit (LitInt 42))) (CLit (LitInt 8))))
      (CApp (CApp (CVar "*")
             (CApp (CApp (CVar "+") (CLit (LitInt 10))) (CLit (LitInt 20))))
           (CApp (CApp (CVar "-") (CLit (LitInt 50))) (CLit (LitInt 45)))))

-- Workload 2: Higher-Order Functions & Beta Reduction
workload2 :: CoreExpr
workload2 =
  CLet (CNonRec "compose" (CLam "f" (CLam "g" (CLam "x" (CApp (CVar "f") (CApp (CVar "g") (CVar "x")))))))
    (CLet (CNonRec "double" (CLam "x" (CApp (CApp (CVar "*") (CVar "x")) (CLit (LitInt 2)))))
      (CLet (CNonRec "inc" (CLam "x" (CApp (CApp (CVar "+") (CVar "x")) (CLit (LitInt 1)))))
        (CApp (CApp (CApp (CVar "compose") (CVar "double")) (CVar "inc")) (CLit (LitInt 10)))))

-- Workload 3: Recursive Fibonacci in Core
workload3 :: CoreExpr
workload3 =
  CLet (CRec [("fib", CLam "n"
         (CCase (CApp (CApp (CVar "<") (CVar "n")) (CLit (LitInt 2))) "cond"
           [ CAlt (CDataAlt "True") [] (CVar "n")
           , CAlt (CDataAlt "False") []
               (CApp (CApp (CVar "+")
                      (CApp (CVar "fib") (CApp (CApp (CVar "-") (CVar "n")) (CLit (LitInt 1)))))
                    (CApp (CVar "fib") (CApp (CApp (CVar "-") (CVar "n")) (CLit (LitInt 2)))))
           ]))])
    (CApp (CVar "fib") (CLit (LitInt 10)))

-- Workload 4: Binary Search Tree Insertion and Lookup in Core
workload4 :: CoreExpr
workload4 =
  CLet (CRec [ ("insert", CLam "tree" (CLam "x"
        (CCase (CVar "tree") "t"
          [ CAlt (CDataAlt "Leaf") []
              (CApp (CApp (CApp (CVar "Node") (CVar "Leaf")) (CVar "x")) (CVar "Leaf"))
          , CAlt (CDataAlt "Node") ["left", "val", "right"]
              (CCase (CApp (CApp (CVar "<") (CVar "x")) (CVar "val")) "cmp"
                [ CAlt (CDataAlt "True") []
                    (CApp (CApp (CApp (CVar "Node")
                           (CApp (CApp (CVar "insert") (CVar "left")) (CVar "x")))
                         (CVar "val"))
                         (CVar "right"))
                , CAlt (CDataAlt "False") []
                    (CApp (CApp (CApp (CVar "Node") (CVar "left")) (CVar "val"))
                         (CApp (CApp (CVar "insert") (CVar "right")) (CVar "x")))
                ])
          ])))
      , ("lookup", CLam "tree" (CLam "x"
        (CCase (CVar "tree") "t"
          [ CAlt (CDataAlt "Leaf") [] (CLit (LitInt 0))
          , CAlt (CDataAlt "Node") ["left", "val", "right"]
              (CCase (CApp (CApp (CVar "==") (CVar "x")) (CVar "val")) "eq"
                [ CAlt (CDataAlt "True") [] (CVar "val")
                , CAlt (CDataAlt "False") []
                    (CCase (CApp (CApp (CVar "<") (CVar "x")) (CVar "val")) "lt"
                      [ CAlt (CDataAlt "True") []
                          (CApp (CApp (CVar "lookup") (CVar "left")) (CVar "x"))
                      , CAlt (CDataAlt "False") []
                          (CApp (CApp (CVar "lookup") (CVar "right")) (CVar "x"))
                      ])
                ])
          ])))
      ])
    (CLet (CNonRec "t0" (CVar "Leaf"))
      (CLet (CNonRec "t1" (CApp (CApp (CVar "insert") (CVar "t0")) (CLit (LitInt 15))))
        (CLet (CNonRec "t2" (CApp (CApp (CVar "insert") (CVar "t1")) (CLit (LitInt 10))))
          (CLet (CNonRec "t3" (CApp (CApp (CVar "insert") (CVar "t2")) (CLit (LitInt 20))))
            (CLet (CNonRec "t4" (CApp (CApp (CVar "insert") (CVar "t3")) (CLit (LitInt 5))))
              (CLet (CNonRec "t5" (CApp (CApp (CVar "insert") (CVar "t4")) (CLit (LitInt 12))))
                (CApp (CApp (CVar "+")
                       (CApp (CApp (CVar "lookup") (CVar "t5")) (CLit (LitInt 12))))
                     (CApp (CApp (CVar "lookup") (CVar "t5")) (CLit (LitInt 20))))))))))

-- Run pipeline: optimize then evaluate
runBenchmark :: CoreExpr -> Int
runBenchmark expr =
  let !opt = optimize expr
      !val = eval [] opt
  in toInt val

result :: Int
result =
  let !r1 = runBenchmark workload1
      !r2 = runBenchmark workload2
      !r3 = runBenchmark workload3
      !r4 = runBenchmark workload4
      !checksum = ((r1 * 10007) + (r2 * 1009) + (r3 * 101) + r4) `rem` 1000000007
  in checksum

main :: IO ()
main = print result
