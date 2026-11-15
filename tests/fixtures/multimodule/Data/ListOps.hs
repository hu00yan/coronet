module Data.ListOps (List(..), myMap, mySum) where

data List a = Nil | Cons a (List a)

myMap :: (a -> b) -> List a -> List b
myMap f xs = case xs of
  Nil -> Nil
  Cons y ys -> Cons (f y) (myMap f ys)

mySum :: List Int -> Int
mySum xs = case xs of
  Nil -> 0
  Cons y ys -> y + mySum ys
