module Math.Fib (fib) where

fib :: Int -> Int
fib n = case n <= 1 of
  True -> n
  False -> fib (n - 1) + fib (n - 2)
