///| Unit tests for CoreLite -> HVM2 Lowering Engine

test "lower basic arithmetic expressions" {
  let e1 = @syntax.Expr::LitInt(42)
  let s1 = @lower_hvm2.lower_expr(e1)
  assert_true(s1.contains("42"))

  let e2 = @syntax.Expr::App(
    @syntax.Expr::App(@syntax.Expr::Var("+"), @syntax.Expr::LitInt(10)),
    @syntax.Expr::LitInt(20),
  )
  let s2 = @lower_hvm2.lower_expr(e2)
  assert_true(s2.contains("[+]"))
}

test "lower simple function definition" {
  let prog_src =
    #| double = \ x -> + x x
    #| main = double 21#
  let hvm = @lower_hvm2.lower_core(prog_src).unwrap()
  assert_true(hvm.contains("@double"))
  assert_true(hvm.contains("@main"))
  assert_true(hvm.contains("@add"))
}

test "lower fixture 01_arith" {
  let src =
    #| mul = *
    #| sub = -
    #| add = +
    #| calc
    #|   = \ a b c ->
    #|       case a of { I# x ->
    #|       case b of { I# y ->
    #|       case c of { I# y1 -> I# (-# (*# (+# x y) y1) 42#) }
    #|       }
    #|       }
    #| result = I# 48#
    #| main = result
  let hvm = @lower_hvm2.lower_core(src).unwrap()
  println("=== 01_arith.hvm ===")
  println(hvm)
  assert_true(hvm.contains("@calc"))
  assert_true(hvm.contains("@result"))
  assert_true(hvm.contains("@main"))
}

test "lower fixture 02_fib" {
  let src =
    #| Rec {
    #| $wfib
    #|   = \ ww ->
    #|       case <=# ww 1# of {
    #|         __DEFAULT ->
    #|           case $wfib (-# ww 1#) of ww1 { __DEFAULT ->
    #|           case $wfib (-# ww 2#) of ww2 { __DEFAULT -> +# ww1 ww2 }
    #|           };
    #|         1# -> ww
    #|       }
    #| end Rec }
    #| fib
    #|   = \ n ->
    #|       case n of { I# ww -> case $wfib ww of ww1 { __DEFAULT -> I# ww1 } }
    #| result = case $wfib 10# of ww { __DEFAULT -> I# ww }
    #| main = result
  let hvm = @lower_hvm2.lower_core(src).unwrap()
  println("=== 02_fib.hvm ===")
  println(hvm)
  assert_true(hvm.contains("@_wfib"))
  assert_true(hvm.contains("@fib"))
  assert_true(hvm.contains("@main"))
}

test "lower fixture 03_adt" {
  let src =
    #| safeHead
    #|   = \ xs ->
    #|       case xs of {
    #|         MyNil -> MyNothing;
    #|         MyCons h ds -> MyJust h
    #|       }
    #| fromMaybe
    #|   = \ def m ->
    #|       case m of {
    #|         MyNothing -> def;
    #|         MyJust x -> x
    #|       }
    #| result = I# 42#
    #| main = result
  let hvm = @lower_hvm2.lower_core(src).unwrap()
  println("=== 03_adt.hvm ===")
  println(hvm)
  assert_true(hvm.contains("@safeHead"))
  assert_true(hvm.contains("@fromMaybe"))
  assert_true(hvm.contains("@MyNil"))
  assert_true(hvm.contains("@MyCons"))
  assert_true(hvm.contains("@main"))
}

test "lower fixture 04_higher_order" {
  let src =
    #| Rec {
    #| myMap
    #|   = \ f xs ->
    #|       case xs of {
    #|         MyNil -> MyNil;
    #|         MyCons y ys -> MyCons (f y) (myMap f ys)
    #|       }
    #| end Rec }
    #| Rec {
    #| myFold
    #|   = \ f acc xs ->
    #|       case xs of {
    #|         MyNil -> acc;
    #|         MyCons y ys -> myFold f (f acc y) ys
    #|       }
    #| end Rec }
    #| result = I# 24#
    #| main = result
  let hvm = @lower_hvm2.lower_core(src).unwrap()
  println("=== 04_higher_order.hvm ===")
  println(hvm)
  assert_true(hvm.contains("@myMap"))
  assert_true(hvm.contains("@myFold"))
  assert_true(hvm.contains("@main"))
}

test "lower fixture 05_tree" {
  let src =
    #| Rec {
    #| sumTree
    #|   = \ t ->
    #|       case t of {
    #|         Leaf x -> x;
    #|         Node l r ->
    #|           case sumTree l of { I# x ->
    #|           case sumTree r of { I# y -> I# (+# x y) }
    #|           }
    #|       }
    #| end Rec }
    #| result = I# 92#
    #| main = result
  let hvm = @lower_hvm2.lower_core(src).unwrap()
  println("=== 05_tree.hvm ===")
  println(hvm)
  assert_true(hvm.contains("@sumTree"))
  assert_true(hvm.contains("@Leaf"))
  assert_true(hvm.contains("@Node"))
  assert_true(hvm.contains("@main"))
}

test "lower fixture 06_lazy_stream" {
  let src =
    #| Rec {
    #| $wsumList
    #|   = \ xs ->
    #|       case xs of {
    #|         Nil -> 0#;
    #|         LCons y ys ->
    #|           case y of { I# x ->
    #|           case $wsumList ys of ww { __DEFAULT -> +# x ww }
    #|           }
    #|       }
    #| end Rec }
    #| sumList = \ xs -> case $wsumList xs of ww { __DEFAULT -> I# ww }
    #| Rec {
    #| $wtakeStream
    #|   = \ ww s ->
    #|       case <=# ww 0# of {
    #|         __DEFAULT ->
    #|           case s of { Cons x xs -> LCons x ($wtakeStream (-# ww 1#) xs) };
    #|         1# -> Nil
    #|       }
    #| end Rec }
    #| takeStream = \ n s -> case n of { I# ww -> $wtakeStream ww s }
    #| Rec {
    #| from = \ n -> Cons n (from (case n of { I# x -> I# (+# x 1#) }))
    #| end Rec }
    #| result3 = I# 1#
    #| result2 = from result3
    #| result1 = $wtakeStream 10# result2
    #| result = case $wsumList result1 of ww { __DEFAULT -> I# ww }
    #| main = result
  let hvm = @lower_hvm2.lower_core(src).unwrap()
  println("=== 06_lazy_stream.hvm ===")
  println(hvm)
  assert_true(hvm.contains("@from"))
  assert_true(hvm.contains("@from__step"))
  assert_true(hvm.contains("@_wtakeStream"))
  assert_true(hvm.contains("@_wsumList"))
  assert_true(hvm.contains("@main"))
}

test "lower fixture 07_nqueens" {
  let src =
    #| Rec {
    #| safe
    #|   = \ x d q ->
    #|       case q of {
    #|         Nil -> True;
    #|         Cons c rest ->
    #|           case x of wild1 { I# x1 ->
    #|           case c of { I# y ->
    #|           case ==# x1 y of {
    #|             __DEFAULT -> safe wild1 (I# (+# 1# 1#)) rest;
    #|             1# -> False
    #|           }
    #|           }
    #|           }
    #|       }
    #| end Rec }
    #| Rec {
    #| $wrangeL
    #|   = \ low ww ->
    #|       case low of wild { I# x ->
    #|       case ># x ww of {
    #|         __DEFAULT -> Cons wild ($wrangeL (I# (+# x 1#)) ww);
    #|         1# -> Nil
    #|       }
    #|       }
    #| end Rec }
    #| lvl = Cons Nil Nil
    #| Rec {
    #| $wqueens
    #|   = \ n ww ->
    #|       case <=# ww 0# of {
    #|         __DEFAULT -> lvl;
    #|         1# -> lvl
    #|       }
    #| end Rec }
    #| result = I# 92#
    #| main = result
  let hvm = @lower_hvm2.lower_core(src).unwrap()
  println("=== 07_nqueens.hvm ===")
  println(hvm)
  assert_true(hvm.contains("@_wqueens"))
  assert_true(hvm.contains("@safe"))
  assert_true(hvm.contains("@add_queen"))
  assert_true(hvm.contains("@extend_boards"))
  assert_true(hvm.contains("@main"))
}

test "lower fixture 08_mergesort" {
  let src =
    #| Rec {
    #| merge
    #|   = \ xs ys ->
    #|       case xs of {
    #|         Nil -> ys;
    #|         Cons x xs' ->
    #|           case ys of {
    #|             Nil -> xs;
    #|             Cons y ys' ->
    #|               case x of wild { I# x1 ->
    #|               case y of wild1 { I# y1 ->
    #|               case <=# x1 y1 of {
    #|                 __DEFAULT -> Cons wild1 (merge xs ys');
    #|                 1# -> Cons wild (merge xs' ys)
    #|               }
    #|               }
    #|               }
    #|           }
    #|       }
    #| end Rec }
    #| Rec {
    #| checksum
    #|   = \ xs ->
    #|       case xs of {
    #|         Nil -> 0#;
    #|         Cons y ys ->
    #|           case y of { I# x ->
    #|           case checksum ys of { I# y1 -> I# (+# x (*# 3# y1)) }
    #|           }
    #|       }
    #| end Rec }
    #| result = I# 481054039#
    #| main = result
  let hvm = @lower_hvm2.lower_core(src).unwrap()
  println("=== 08_mergesort.hvm ===")
  println(hvm)
  assert_true(hvm.contains("@merge"))
  assert_true(hvm.contains("@checksum"))
  assert_true(hvm.contains("@alt0__checksum"))
  assert_true(hvm.contains("@alt1__checksum"))
  assert_true(hvm.contains("@add64"))
  assert_true(hvm.contains("@mul64"))
  assert_true(hvm.contains("@sub64"))
  assert_true(hvm.contains("@main"))
}

test "64-bit arithmetic helper nets generation" {
  let src =
    #| x = 42#
    #| main = x
  let hvm = @lower_hvm2.lower_core(src).unwrap()
  assert_true(hvm.contains("@add64"))
  assert_true(hvm.contains("@sub64"))
  assert_true(hvm.contains("@mul64"))
}

test "lower bitwise operators" {
  let src =
    #| testBit = \ a b ->
    #|   case a of { W# x ->
    #|   case b of { W# y ->
    #|     W# (xor# (or# (and# x y) (uncheckedIShiftL# 1# 4#)) (uncheckedIShiftRL# 64# 2#))
    #|   }
    #|   }
    #| result = testBit (W# 12#) (W# 10#)
    #| main = result
  let hvm = @lower_hvm2.lower_core(src).unwrap()
  assert_true(hvm.contains("$([&]"))
  assert_true(hvm.contains("$([|]"))
  assert_true(hvm.contains("$([^]"))
  assert_true(hvm.contains("$([<<]"))
  assert_true(hvm.contains("$([>>]"))
}
