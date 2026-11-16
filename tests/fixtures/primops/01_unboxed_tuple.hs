{-# LANGUAGE MagicHash, UnboxedTuples #-}
module Main where

import GHC.Exts

{-# NOINLINE divModPrim #-}
divModPrim :: Int# -> Int# -> (# Int#, Int# #)
divModPrim a b = (# quotInt# a b, remInt# a b #)

compute :: Int# -> Int# -> Int#
compute a b = case divModPrim a b of
  (# q, r #) -> (q *# 10#) +# r

result :: Int
result = case compute 123# 10# of
  r -> I# r

main :: IO ()
main = print result
