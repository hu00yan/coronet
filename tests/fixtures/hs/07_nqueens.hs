module Main where

data List a = Nil | Cons a (List a)

append :: List a -> List a -> List a
append xs ys = case xs of
  Nil -> ys
  Cons z zs -> Cons z (append zs ys)

concatMapL :: (a -> List b) -> List a -> List b
concatMapL f xs = case xs of
  Nil -> Nil
  Cons y ys -> append (f y) (concatMapL f ys)

rangeL :: Int -> Int -> List Int
rangeL low high = case low > high of
  True -> Nil
  False -> Cons low (rangeL (low + 1) high)

absInt :: Int -> Int
absInt x = case x < 0 of
  True -> 0 - x
  False -> x

safe :: Int -> Int -> List Int -> Bool
safe x d q = case q of
  Nil -> True
  Cons c rest ->
    case x == c of
      True -> False
      False -> case absInt (x - c) == d of
        True -> False
        False -> safe x (d + 1) rest

queens :: Int -> Int -> List (List Int)
queens n k = case k <= 0 of
  True -> Cons Nil Nil
  False ->
    let prev = queens n (k - 1)
    in concatMapL (\qs ->
         concatMapL (\c ->
           case safe c 1 qs of
             True -> Cons (Cons c qs) Nil
             False -> Nil
         ) (rangeL 1 n)
       ) prev

lengthL :: List a -> Int
lengthL xs = case xs of
  Nil -> 0
  Cons _ rest -> 1 + lengthL rest

result :: Int
result = lengthL (queens 8 8)

main :: IO ()
main = print result
