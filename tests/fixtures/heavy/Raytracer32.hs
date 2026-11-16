{-# OPTIONS_GHC -fno-worker-wrapper #-}
module Main where

-- | Heavy Pure Benchmark: 3D Raytracer (32x32 = 1024 rays)
-- Baseline checksum: 224780945

data Vec3 = Vec3 Int Int Int
data Ray = Ray Vec3 Vec3
data Sphere = Sphere Vec3 Int Int
data Light = Light Vec3 Int
data List a = Nil | Cons a (List a)

vadd :: Vec3 -> Vec3 -> Vec3
vadd (Vec3 x1 y1 z1) (Vec3 x2 y2 z2) = Vec3 (x1 + x2) (y1 + y2) (z1 + z2)

vsub :: Vec3 -> Vec3 -> Vec3
vsub (Vec3 x1 y1 z1) (Vec3 x2 y2 z2) = Vec3 (x1 - x2) (y1 - y2) (z1 - z2)

vdot :: Vec3 -> Vec3 -> Int
vdot (Vec3 x1 y1 z1) (Vec3 x2 y2 z2) = (x1 * x2 + y1 * y2 + z1 * z2) `div` 1000

vscale :: Vec3 -> Int -> Vec3
vscale (Vec3 x y z) s = Vec3 ((x * s) `div` 1000) ((y * s) `div` 1000) ((z * s) `div` 1000)

isqrt :: Int -> Int
isqrt n = case n <= 0 of
  True -> 0
  False -> isqrtStep n (n `div` 2 + 1)

isqrtStep :: Int -> Int -> Int
isqrtStep n x =
  let next = (x + n `div` x) `div` 2
  in case next >= x of
    True -> x
    False -> isqrtStep n next

vnorm :: Vec3 -> Vec3
vnorm v@(Vec3 x y z) =
  let lenSq = vdot v v
      len = isqrt (lenSq * 1000)
  in case len <= 0 of
    True -> Vec3 0 0 1000
    False -> Vec3 ((x * 1000) `div` len) ((y * 1000) `div` len) ((z * 1000) `div` len)

intersectSphere :: Ray -> Sphere -> Int
intersectSphere (Ray orig dir) (Sphere center radius _) =
  let oc = vsub orig center
      a = vdot dir dir
      b = 2 * vdot oc dir
      c = vdot oc oc - (radius * radius) `div` 1000
      discr = b * b - 4 * a * c
  in case discr < 0 of
    True -> -1
    False ->
      let sqd = isqrt (discr * 1000)
          t1 = (-b * 1000 - sqd) `div` (2 * a)
      in case t1 > 10 of
        True -> t1
        False -> -1

traceRay :: Ray -> List Sphere -> Light -> Int
traceRay ray spheres light = findClosest ray spheres (-1) 999999 (-1) light

findClosest :: Ray -> List Sphere -> Int -> Int -> Int -> Light -> Int
findClosest ray spheres bestIdx bestT curIdx light = case spheres of
  Nil ->
    case bestIdx < 0 of
      True -> 20
      False -> shadeRay ray bestIdx bestT light
  Cons s rest ->
    let idx = curIdx + 1
        t = intersectSphere ray s
    in case t > 0 && t < bestT of
      True -> findClosest ray rest idx t idx light
      False -> findClosest ray rest bestIdx bestT idx light

shadeRay :: Ray -> Int -> Int -> Light -> Int
shadeRay (Ray orig dir) idx t (Light lpos intensity) =
  let hit = vadd orig (vscale dir t)
      norm = case idx of
        0 -> vnorm (vsub hit (Vec3 0 0 (-1000)))
        1 -> vnorm (vsub hit (Vec3 (-400) 200 (-1200)))
        _ -> vnorm (vsub hit (Vec3 400 (-200) (-800)))
      ldir = vnorm (vsub lpos hit)
      diff = vdot norm ldir
      diffClamped = case diff < 0 of
        True -> 0
        False -> diff
      baseColor = case idx of
        0 -> 100
        1 -> 200
        _ -> 300
  in baseColor + (diffClamped * intensity) `div` 1000

renderRow :: Int -> Int -> Int -> List Sphere -> Light -> List Int
renderRow y x width spheres light = case x >= width of
  True -> Nil
  False ->
    let sx = ((x - width `div` 2) * 800) `div` width
        sy = ((y - width `div` 2) * 800) `div` width
        dir = vnorm (Vec3 sx sy (-1000))
        ray = Ray (Vec3 0 0 1000) dir
        pixel = traceRay ray spheres light
    in Cons pixel (renderRow y (x + 1) width spheres light)

renderGrid :: Int -> Int -> Int -> List Sphere -> Light -> List Int
renderGrid y height width spheres light = case y >= height of
  True -> Nil
  False ->
    let row = renderRow y 0 width spheres light
        rest = renderGrid (y + 1) height width spheres light
    in appendL row rest

appendL :: List a -> List a -> List a
appendL xs ys = case xs of
  Nil -> ys
  Cons z zs -> Cons z (appendL zs ys)

checksumList :: List Int -> Int
checksumList xs = case xs of
  Nil -> 0
  Cons p ps -> (p + 31 * checksumList ps) `mod` 1000000007

sceneSpheres :: List Sphere
sceneSpheres =
  Cons (Sphere (Vec3 0 0 (-1000)) 400 1)
  (Cons (Sphere (Vec3 (-400) 200 (-1200)) 300 2)
  (Cons (Sphere (Vec3 400 (-200) (-800)) 250 3) Nil))

sceneLight :: Light
sceneLight = Light (Vec3 500 1000 500) 800

result :: Int
result = checksumList (renderGrid 0 32 32 sceneSpheres sceneLight)

main :: IO ()
main = print result
