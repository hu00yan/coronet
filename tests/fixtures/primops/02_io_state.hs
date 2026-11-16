{-# LANGUAGE MagicHash, UnboxedTuples #-}
module Main where

import GHC.Exts

computeWithState :: Int# -> Int#
computeWithState n =
  case runRW# (\s0 ->
    case newByteArray# 16# s0 of { (# s1, mba #) ->
    case writeIntArray# mba 0# n s1 of { s2 ->
    case writeIntArray# mba 1# (n *# 2#) s2 of { s3 ->
    case readIntArray# mba 0# s3 of { (# s4, v0 #) ->
    case readIntArray# mba 1# s4 of { (# s5, v1 #) ->
    (# s5, v0 +# v1 #)
    }}}}}) of
    (# _, res #) -> res

result :: Int
result = case computeWithState 21# of
  r -> I# r

main :: IO ()
main = print result
