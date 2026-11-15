module Main where

data Tree = Leaf Int | Node Tree Tree

sumTree :: Tree -> Int
sumTree t = case t of
  Leaf x -> x
  Node l r -> sumTree l + sumTree r

buildTree :: Int -> Int -> Tree
buildTree d x = case d <= 0 of
  True -> Leaf x
  False -> Node (buildTree (d - 1) (x * 2)) (buildTree (d - 1) (x * 2 + 1))

myTree :: Tree
myTree = buildTree 3 1

result :: Int
result = sumTree myTree

main :: IO ()
main = print result
