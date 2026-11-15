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
