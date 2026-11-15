module Main where

data MyList a = MyNil | MyCons a (MyList a)

myMap :: (a -> b) -> MyList a -> MyList b
myMap f xs = case xs of
  MyNil -> MyNil
  MyCons y ys -> MyCons (f y) (myMap f ys)

myFold :: (b -> a -> b) -> b -> MyList a -> b
myFold f acc xs = case xs of
  MyNil -> acc
  MyCons y ys -> myFold f (f acc y) ys

double :: Int -> Int
double x = x + x

testList :: MyList Int
testList = MyCons 1 (MyCons 2 (MyCons 3 (MyCons 4 MyNil)))

result :: Int
result = myFold (\acc x -> acc + x) 0 (myMap (\x -> double x + 1) testList)

main :: IO ()
main = print result
