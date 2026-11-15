{-# OPTIONS_GHC -fno-worker-wrapper #-}
module Main where

-- | Heavy Pure Benchmark: SHA-256 Hash Function
-- Implements FIPS PUB 180-4 Secure Hash Standard (SHA-256) in pure Haskell,
-- processing a benchmark block with 64 schedule expansion steps and 64 compression rounds,
-- utilizing 32-bit bitwise primitives (and, or, xor, shiftR, shiftL, rotr).

import Data.Bits
import Data.Word

-- 32-bit bitwise helpers
rotr :: Word32 -> Int -> Word32
rotr x n = (x `shiftR` n) .|. (x `shiftL` (32 - n))

ch :: Word32 -> Word32 -> Word32 -> Word32
ch x y z = (x .&. y) `xor` (complement x .&. z)

maj :: Word32 -> Word32 -> Word32 -> Word32
maj x y z = (x .&. y) `xor` (x .&. z) `xor` (y .&. z)

sigma0 :: Word32 -> Word32
sigma0 x = rotr x 2 `xor` rotr x 13 `xor` rotr x 22

sigma1 :: Word32 -> Word32
sigma1 x = rotr x 6 `xor` rotr x 11 `xor` rotr x 25

gamma0 :: Word32 -> Word32
gamma0 x = rotr x 7 `xor` rotr x 18 `xor` (x `shiftR` 3)

gamma1 :: Word32 -> Word32
gamma1 x = rotr x 17 `xor` rotr x 19 `xor` (x `shiftR` 10)

data List a = Nil | Cons a (List a)

fromHsList :: [a] -> List a
fromHsList [] = Nil
fromHsList (x:xs) = Cons x (fromHsList xs)

listIndex :: List Word32 -> Int -> Word32
listIndex xs i = case xs of
  Nil -> 0
  Cons y ys -> case i <= 0 of
    True -> y
    False -> listIndex ys (i - 1)

appendL :: List a -> List a -> List a
appendL xs ys = case xs of
  Nil -> ys
  Cons z zs -> Cons z (appendL zs ys)

-- Schedule expansion: 16 words -> 64 words
expandSchedule :: List Word32 -> Int -> List Word32
expandSchedule w i = case i >= 64 of
  True -> w
  False ->
    let w_i_15 = listIndex w (i - 15)
        w_i_2  = listIndex w (i - 2)
        w_i_16 = listIndex w (i - 16)
        w_i_7  = listIndex w (i - 7)
        s0 = gamma0 w_i_15
        s1 = gamma1 w_i_2
        newWord = w_i_16 + s0 + w_i_7 + s1
    in expandSchedule (appendL w (Cons newWord Nil)) (i + 1)

-- 64 round constants K
kConstants :: List Word32
kConstants = fromHsList
  [ 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5
  , 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
  , 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3
  , 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
  , 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc
  , 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
  , 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7
  , 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
  , 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13
  , 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
  , 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3
  , 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
  , 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5
  , 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
  , 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208
  , 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ]

data HashState = HashState Word32 Word32 Word32 Word32 Word32 Word32 Word32 Word32

compressRounds :: HashState -> List Word32 -> List Word32 -> Int -> HashState
compressRounds (HashState a b c d e f g h) w k i = case i >= 64 of
  True -> HashState (a + 0x6a09e667) (b + 0xbb67ae85) (c + 0x3c6ef372) (d + 0xa54ff53a)
                    (e + 0x510e527f) (f + 0x9b05688c) (g + 0x1f83d9ab) (h + 0x5be0cd19)
  False ->
    let wi = listIndex w i
        ki = listIndex k i
        t1 = h + sigma1 e + ch e f g + ki + wi
        t2 = sigma0 a + maj a b c
        newA = t1 + t2
        newB = a
        newC = b
        newD = c
        newE = d + t1
        newF = e
        newG = f
        newH = g
    in compressRounds (HashState newA newB newC newD newE newF newG newH) w k (i + 1)

initialWords :: List Word32
initialWords = fromHsList
  [ 0x436f726f -- "Coro"
  , 0x6e65743a -- "net:"
  , 0x20486173 -- " Has"
  , 0x6b656c6c -- "kell"
  , 0x80000000 -- pad 0x80
  , 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  , 128        -- length: 128 bits
  ]

hashBlock :: HashState
hashBlock =
  let fullSchedule = expandSchedule initialWords 16
      initState = HashState 0x6a09e667 0xbb67ae85 0x3c6ef372 0xa54ff53a 0x510e527f 0x9b05688c 0x1f83d9ab 0x5be0cd19
  in compressRounds initState fullSchedule kConstants 0

stateChecksum :: HashState -> Int
stateChecksum (HashState a b c d e f g h) =
  let v = fromIntegral (a `xor` b `xor` c `xor` d `xor` e `xor` f `xor` g `xor` h) :: Int
  in v

result :: Int
result = stateChecksum hashBlock

main :: IO ()
main = print result
