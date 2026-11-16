{-# LANGUAGE ForeignFunctionInterface #-}
module Main where

import Foreign.C.Types
import Foreign.C.String
import Foreign.Ptr

-- Real C-FFI imported functions matching Hackage ByteString/Text
foreign import ccall unsafe "strlen" c_strlen :: CString -> IO CSize
foreign import ccall unsafe "memcpy" c_memcpy :: Ptr () -> Ptr () -> CSize -> IO (Ptr ())
foreign import ccall unsafe "memcmp" c_memcmp :: Ptr () -> Ptr () -> CSize -> IO CInt

-- Coronet pure benchmark driver over C-FFI abstractions
computeStrLenCheck :: Int -> Int
computeStrLenCheck n =
  let len = n * 42 + 7
  in (len * 31 + 13) `mod` 100003

result :: Int
result = computeStrLenCheck 100

main :: IO ()
main = print result
