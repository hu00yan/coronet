{-# OPTIONS_GHC -fno-worker-wrapper #-}
module Main where

data List a = Nil | Cons a (List a)
data Pair a b = Pair a b

lengthL :: List a -> Int
lengthL xs = case xs of
  Nil -> 0
  Cons _ rest -> 1 + lengthL rest

div2 :: Int -> Int
div2 n = case n <= 1 of
  True -> 0
  False -> 1 + div2 (n - 2)

splitAtL :: Int -> List a -> Pair (List a) (List a)
splitAtL n xs = case n <= 0 of
  True -> Pair Nil xs
  False -> case xs of
    Nil -> Pair Nil Nil
    Cons y ys ->
      case splitAtL (n - 1) ys of
        Pair l r -> Pair (Cons y l) r

merge :: List Int -> List Int -> List Int
merge xs ys = case xs of
  Nil -> ys
  Cons x xs' -> case ys of
    Nil -> xs
    Cons y ys' ->
      case x <= y of
        True -> Cons x (merge xs' ys)
        False -> Cons y (merge xs ys')

mergesort :: List Int -> List Int
mergesort xs = case xs of
  Nil -> Nil
  Cons x Nil -> Cons x Nil
  _ ->
    let len = lengthL xs
        mid = div2 len
    in case splitAtL mid xs of
      Pair left right -> merge (mergesort left) (mergesort right)

checksum :: List Int -> Int
checksum xs = case xs of
  Nil -> 0
  Cons y ys -> y + 3 * checksum ys

testList :: List Int
testList = Cons 15 (Cons 3 (Cons 9 (Cons 1 (Cons 24 (Cons 18 (Cons 7 (Cons 12 (Cons 5 (Cons 20 (Cons 2 (Cons 14 (Cons 8 (Cons 11 (Cons 4 (Cons 16 Nil)))))))))))))))

result :: Int
result = checksum (mergesort testList)

main :: IO ()
main = print result
