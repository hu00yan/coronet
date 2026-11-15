module Main where

add :: Int -> Int -> Int
add x y = x + y

sub :: Int -> Int -> Int
sub x y = x - y

mul :: Int -> Int -> Int
mul x y = x * y

calc :: Int -> Int -> Int -> Int
calc a b c = sub (mul (add a b) c) 42

result :: Int
result = calc 10 20 3

main :: IO ()
main = print result
