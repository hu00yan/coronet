module Main where

fib :: Int -> Int
fib n = if n <= 1 then n else fib (n - 1) + fib (n - 2)

result :: Int
result = fib 10

main :: IO ()
main = print result
