{-# LANGUAGE BangPatterns #-}
module Main where

-- | Size-Balanced Binary Search Tree Map (Canonical algorithm of Haskell Data.Map)
data Map k a = Bin {-# UNPACK #-} !Int !k a !(Map k a) !(Map k a)
             | Tip
             deriving (Show)

empty :: Map k a
empty = Tip

singleton :: k -> a -> Map k a
singleton k v = Bin 1 k v Tip Tip

size :: Map k a -> Int
size Tip = 0
size (Bin s _ _ _ _) = s

delta :: Int
delta = 3

gamma :: Int
gamma = 2

balanceL :: k -> a -> Map k a -> Map k a -> Map k a
balanceL k v l r = case r of
  Tip -> case l of
    Tip -> Bin 1 k v Tip Tip
    Bin _ _ _ Tip Tip -> Bin 2 k v l Tip
    Bin _ lk lv Tip (Bin _ lrk lrv _ _) ->
      Bin 3 lrk lrv (Bin 1 lk lv Tip Tip) (Bin 1 k v Tip Tip)
    Bin _ lk lv (Bin _ _ _ _ _) Tip ->
      Bin 3 lk lv Tip (Bin 1 k v Tip Tip)
    Bin _ lk lv (Bin ls _ _ _ _) (Bin rs lrk lrv lrl lrr) ->
      if rs < gamma * ls
      then Bin (1 + ls + size r) lk lv (Bin ls lk lv Tip Tip) (Bin (1 + rs) k v (Bin rs lrk lrv lrl lrr) Tip)
      else Bin (1 + ls + size r) lrk lrv (Bin (1 + ls + size lrl) lk lv Tip lrl) (Bin (1 + size lrr) k v lrr Tip)
  Bin rs _ _ _ _ -> case l of
    Tip -> Bin (1 + rs) k v Tip r
    Bin ls lk lv ll lr ->
      if ls > delta * rs
      then case lr of
        Bin lrs lrk lrv lrl lrr ->
          if lrs < gamma * size ll
          then Bin (1 + ls + rs) lk lv ll (balanceR k v lr r)
          else Bin (1 + ls + rs) lrk lrv (balanceL lk lv ll lrl) (balanceR k v lrr r)
        Tip -> Bin (1 + ls + rs) lk lv ll (Bin (1 + rs) k v Tip r)
      else Bin (1 + ls + rs) k v l r

balanceR :: k -> a -> Map k a -> Map k a -> Map k a
balanceR k v l r = case l of
  Tip -> case r of
    Tip -> Bin 1 k v Tip Tip
    Bin _ _ _ Tip Tip -> Bin 2 k v Tip r
    Bin _ rk rv (Bin _ rlk rlv _ _) Tip ->
      Bin 3 rlk rlv (Bin 1 k v Tip Tip) (Bin 1 rk rv Tip Tip)
    Bin _ rk rv Tip (Bin _ _ _ _ _) ->
      Bin 3 rk rv (Bin 1 k v Tip Tip) Tip
    Bin _ rk rv (Bin ls rlk rlv rll rlr) (Bin rs _ _ _ _) ->
      if ls < gamma * rs
      then Bin (1 + size l + rs) rk rv (Bin (1 + ls) k v Tip (Bin ls rlk rlv rll rlr)) (Bin rs rk rv Tip Tip)
      else Bin (1 + size l + rs) rlk rlv (Bin (1 + size rll) k v Tip rll) (Bin (1 + rs + size rlr) rk rv rlr Tip)
  Bin ls _ _ _ _ -> case r of
    Tip -> Bin (1 + ls) k v l Tip
    Bin rs rk rv rl rr ->
      if rs > delta * ls
      then case rl of
        Bin rls rlk rlv rll rlr ->
          if rls < gamma * size rr
          then Bin (1 + ls + rs) rk rv (balanceL k v l rl) rr
          else Bin (1 + ls + rs) rlk rlv (balanceL k v l rll) (balanceR rk rv rlr rr)
        Tip -> Bin (1 + ls + rs) k v (Bin (1 + ls) k v l Tip) rr
      else Bin (1 + ls + rs) k v l r

insert :: Ord k => k -> a -> Map k a -> Map k a
insert kx x Tip = singleton kx x
insert kx x (Bin sz ky y l r) = case compare kx ky of
  LT -> balanceL ky y (insert kx x l) r
  GT -> balanceR ky y l (insert kx x r)
  EQ -> Bin sz kx x l r

findWithDefault :: Ord k => a -> k -> Map k a -> a
findWithDefault def _ Tip = def
findWithDefault def kx (Bin _ ky y l r) = case compare kx ky of
  LT -> findWithDefault def kx l
  GT -> findWithDefault def kx r
  EQ -> y

foldlWithKey :: (b -> k -> a -> b) -> b -> Map k a -> b
foldlWithKey _ !z Tip = z
foldlWithKey f !z (Bin _ kx x l r) =
  let !z1 = foldlWithKey f z l
      !z2 = f z1 kx x
  in foldlWithKey f z2 r

buildMap :: Int -> Map Int Int
buildMap n = go 1 empty
  where
    go !i !m
      | i > n     = m
      | otherwise = go (i + 1) (insert i (i * 3 + 7) m)

queryMap :: Map Int Int -> Int -> Int
queryMap m n = go 1 0
  where
    go !i !acc
      | i > n     = acc
      | otherwise = go (i + 1) (acc + findWithDefault 0 i m)

result :: Int
result =
  let m = buildMap 100
  in queryMap m 100

main :: IO ()
main = print result
