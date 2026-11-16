-- containers: build a strict Map, fold it strictly, print the answer.
-- `result` is what Coronet compiles; `main` only exists for the GHC reference.
module Main where

import qualified Data.Map.Strict as M

result :: Int
result = M.foldl' (+) 0 (M.fromList [(i, i * i) | i <- [1 .. 100 :: Int]])

main :: IO ()
main = print result
