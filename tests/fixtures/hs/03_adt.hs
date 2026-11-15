module Main where

data MyBool = MyTrue | MyFalse

data MyMaybe a = MyNothing | MyJust a

data MyList a = MyNil | MyCons a (MyList a)

safeHead :: MyList a -> MyMaybe a
safeHead xs = case xs of
  MyNil -> MyNothing
  MyCons h _ -> MyJust h

fromMaybe :: a -> MyMaybe a -> a
fromMaybe def m = case m of
  MyNothing -> def
  MyJust x -> x

isNil :: MyList a -> MyBool
isNil xs = case xs of
  MyNil -> MyTrue
  MyCons _ _ -> MyFalse

process :: MyList Int -> Int
process xs = case isNil xs of
  MyTrue -> 0
  MyFalse -> fromMaybe 99 (safeHead xs)

testList :: MyList Int
testList = MyCons 42 (MyCons 10 MyNil)

result :: Int
result = process testList

main :: IO ()
main = print result
