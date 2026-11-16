module Main where

import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as C

testBS :: B.ByteString
testBS = C.pack "Coronet Implicit Parallel Graph Reduction"

calcChecksum :: B.ByteString -> Int
calcChecksum bs = B.foldl' (\acc w -> (acc * 31 + fromIntegral w) `rem` 1000000007) 0 bs

result :: Int
result = calcChecksum testBS

main :: IO ()
main = print result
