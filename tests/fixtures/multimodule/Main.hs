module Main where

import Math.Fib (fib)
import Data.ListOps (List(..), myMap, mySum)

testList :: List Int
testList = Cons 1 (Cons 2 (Cons 3 (Cons 4 (Cons 5 Nil))))

result :: Int
result = mySum (myMap fib testList)

main :: IO ()
main = print result
