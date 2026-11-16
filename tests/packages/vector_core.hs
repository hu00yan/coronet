module Main where

-- Coronet High-Performance Vector & Stream Fusion Core Benchmark
-- Simulates Data.Vector.Unboxed Stream Fusion and unboxed array accumulators

data Step s a = Done | Skip !s | Yield !a !s

data Stream a = forall s. Stream !(s -> Step s a) !s

-- Stream construction from range [start..end]
enumFromToStream :: Int -> Int -> Stream Int
enumFromToStream start end = Stream step start
  where
    {-# INLINE step #-}
    step !i
      | i > end   = Done
      | otherwise = Yield i (i + 1)

-- Stream map
mapStream :: (a -> b) -> Stream a -> Stream b
mapStream f (Stream step s0) = Stream newStep s0
  where
    {-# INLINE newStep #-}
    newStep !s = case step s of
      Done       -> Done
      Skip s'    -> Skip s'
      Yield x s' -> Yield (f x) s'

-- Stream filter
filterStream :: (a -> Bool) -> Stream a -> Stream a
filterStream p (Stream step s0) = Stream newStep s0
  where
    {-# INLINE newStep #-}
    newStep !s = case step s of
      Done       -> Done
      Skip s'    -> Skip s'
      Yield x s' -> if p x then Yield x s' else Skip s'

-- Stream foldl' (Strict accumulator with unboxed Int# reduction)
foldlStream :: (b -> a -> b) -> b -> Stream a -> b
foldlStream f !z (Stream step s0) = loop z s0
  where
    loop !acc !s = case step s of
      Done       -> acc
      Skip s'    -> loop acc s'
      Yield x s' -> loop (f acc x) s'

-- Stream zipWith
data ZipState s1 s2 a = ZipNone !s1 !s2 | ZipYield !a !s2

zipWithStream :: (a -> b -> c) -> Stream a -> Stream b -> Stream c
zipWithStream f (Stream step1 s1_0) (Stream step2 s2_0) =
  Stream step (s1_0, s2_0)
  where
    {-# INLINE step #-}
    step (!s1, !s2) = case step1 s1 of
      Done        -> Done
      Skip s1'    -> Skip (s1', s2)
      Yield x s1' -> case step2 s2 of
        Done        -> Done
        Skip s2'    -> Skip (s1, s2')
        Yield y s2' -> Yield (f x y) (s1', s2')

-- Dot product of two vectors represented as fused streams
dotProduct :: Int -> Int
dotProduct n =
  let s1 = enumFromToStream 1 n
      s2 = mapStream (\x -> x * 2) (enumFromToStream 1 n)
      zipped = zipWithStream (*) s1 s2
  in foldlStream (+) 0 zipped

-- Vector accumulator with unboxed bitwise transformations
vectorAccumulator :: Int -> Int
vectorAccumulator n =
  let stream = enumFromToStream 1 n
      transformed = mapStream (\x -> (x * 3 + 7) `mod` 10007) stream
  in foldlStream (\acc x -> (acc * 7 + x) `mod` 100003) 0 transformed

result :: Int
result = dotProduct 200 + vectorAccumulator 200

main :: IO ()
main = print result
