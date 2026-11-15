module Main where

data Stream a = Cons a (Stream a)
data List a = Nil | LCons a (List a)

from :: Int -> Stream Int
from n = Cons n (from (n + 1))

takeStream :: Int -> Stream a -> List a
takeStream n s = case n <= 0 of
  True -> Nil
  False -> case s of
    Cons x xs -> LCons x (takeStream (n - 1) xs)

sumList :: List Int -> Int
sumList xs = case xs of
  Nil -> 0
  LCons y ys -> y + sumList ys

result :: Int
result = sumList (takeStream 10 (from 1))

main :: IO ()
main = print result
