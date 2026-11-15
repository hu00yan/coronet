///| Unit tests for CoreLite to HVM3 lowering.

test "lower basic literals and operators" {
  let e1 = @syntax.Expr::LitInt(42)
  assert_eq(@lower_hvm3.lower_expr(e1), "42")

  let e2 = @syntax.Expr::Var("+#")
  assert_eq(@lower_hvm3.lower_expr(e2), "(λ&_a (λ&_b (+ _a _b)))")

  let e3 = @syntax.Expr::App(
    @syntax.Expr::App(@syntax.Expr::Var("+#"), @syntax.Expr::LitInt(10)),
    @syntax.Expr::LitInt(20),
  )
  assert_eq(@lower_hvm3.lower_expr(e3), "(+ 10 20)")
}

test "lower lambdas and applications" {
  let e = @syntax.Expr::Lam(
    "x",
    @syntax.Expr::App(
      @syntax.Expr::App(@syntax.Expr::Var("*#"), @syntax.Expr::Var("x")),
      @syntax.Expr::LitInt(2),
    ),
  )
  assert_eq(@lower_hvm3.lower_expr(e), "(λ&x (* x 2))")
}

test "lower let expressions" {
  let e = @syntax.Expr::Let(
    @syntax.Bind::NonRec("x", @syntax.Expr::LitInt(10)),
    @syntax.Expr::App(
      @syntax.Expr::App(@syntax.Expr::Var("+#"), @syntax.Expr::Var("x")),
      @syntax.Expr::LitInt(5),
    ),
  )
  assert_eq(@lower_hvm3.lower_expr(e), "( ! &x = 10; (+ x 5) )")
}

test "lower Scott-encoded ADTs and pattern matching" {
  let prog_src =
    #|safeHead = \ xs ->
    #|  case xs of {
    #|    MyNil -> 0#;
    #|    MyCons h t -> h
    #|  }
    #|main = safeHead MyNil
  let prog = @syntax.parse_program(prog_src).unwrap()
  let hvm3_code = @lower_hvm3.lower(prog)

  assert_true(hvm3_code.contains("@MyNil = (λ&c0 (λ&c1 c0))"))
  assert_true(
    hvm3_code.contains("@MyCons = (λ&a0 (λ&a1 (λ&c0 (λ&c1 ((c1 a0) a1)))))"),
  )
  assert_true(hvm3_code.contains("@safeHead = (λ&xs ((xs 0) (λ&h (λ&t h))))"))
  assert_true(hvm3_code.contains("@main = (@safeHead @MyNil)"))
}

test "lower numeric condition matching" {
  let prog_src =
    #|step = \ n ->
    #|  case <=# n 1# of {
    #|    __DEFAULT -> 0#;
    #|    1# -> 42#
    #|  }
    #|main = step 1#
  let prog = @syntax.parse_program(prog_src).unwrap()
  let hvm3_code = @lower_hvm3.lower(prog)

  assert_true(hvm3_code.contains("(~ (<= n 1) { 0: 0 1+p: 42 })"))
  assert_true(hvm3_code.contains("@main = (@step 1)"))
}

test "lower 01_arith fixture" {
  let src =
    #|mul = *
    #|sub = -
    #|add = +
    #|calc
    #|  = \ a b c ->
    #|      case a of { I# x ->
    #|      case b of { I# y ->
    #|      case c of { I# y1 -> I# (-# (*# (+# x y) y1) 42#) }
    #|      }
    #|      }
    #|result = I# 48#
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  let hvm3_code = @lower_hvm3.lower(prog)

  assert_true(hvm3_code.contains("@calc = (λ&a (λ&b (λ&c"))
  assert_true(hvm3_code.contains("(- (* (+ x y) y1) 42)"))
  assert_true(hvm3_code.contains("@result = 48"))
  assert_true(hvm3_code.contains("@main = @result"))
}

test "lower 02_fib fixture" {
  let src =
    #|Rec {
    #|$wfib
    #|  = \ ww ->
    #|      case <=# ww 1# of {
    #|        __DEFAULT ->
    #|          case $wfib (-# ww 1#) of ww1 { __DEFAULT ->
    #|          case $wfib (-# ww 2#) of ww2 { __DEFAULT -> +# ww1 ww2 }
    #|          };
    #|        1# -> ww
    #|      }
    #|end Rec }
    #|fib
    #|  = \ n ->
    #|      case n of { I# ww -> case $wfib ww of ww1 { __DEFAULT -> I# ww1 } }
    #|result = case $wfib 10# of ww { __DEFAULT -> I# ww }
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  let hvm3_code = @lower_hvm3.lower(prog)

  assert_true(hvm3_code.contains("@_wfib = (λ&ww (~ (<= ww 1)"))
  assert_true(hvm3_code.contains("(@_wfib (- ww 1))"))
  assert_true(hvm3_code.contains("(@_wfib (- ww 2))"))
  assert_true(hvm3_code.contains("@main = @result"))
}

test "lower 03_adt fixture" {
  let src =
    #|safeHead
    #|  = \ xs ->
    #|      case xs of {
    #|        MyNil -> MyNothing;
    #|        MyCons h ds -> MyJust h
    #|      }
    #|fromMaybe
    #|  = \ def m ->
    #|      case m of {
    #|        MyNothing -> def;
    #|        MyJust x -> x
    #|      }
    #|isNil
    #|  = \ xs ->
    #|      case xs of {
    #|        MyNil -> MyTrue;
    #|        MyCons ds ds1 -> MyFalse
    #|      }
    #|process1 = I# 0#
    #|process
    #|  = \ xs ->
    #|      case xs of {
    #|        MyNil -> process1;
    #|        MyCons ds ds1 -> ds
    #|      }
    #|result = I# 42#
    #|testList2 = I# 10#
    #|testList1 = MyCons testList2 MyNil
    #|testList = MyCons result testList1
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  let hvm3_code = @lower_hvm3.lower(prog)

  assert_true(hvm3_code.contains("@MyNil = (λ&c0 (λ&c1 c0))"))
  assert_true(
    hvm3_code.contains("@MyCons = (λ&a0 (λ&a1 (λ&c0 (λ&c1 ((c1 a0) a1)))))"),
  )
  assert_true(hvm3_code.contains("@MyNothing = (λ&c0 (λ&c1 c0))"))
  assert_true(hvm3_code.contains("@MyJust = (λ&a0 (λ&c0 (λ&c1 (c1 a0))))"))
  assert_true(hvm3_code.contains("@result = 42"))
  assert_true(hvm3_code.contains("@main = @result"))
}

test "lower 04_higher_order fixture" {
  let src =
    #|Rec {
    #|myMap
    #|  = \ f xs ->
    #|      case xs of {
    #|        MyNil -> MyNil;
    #|        MyCons y ys -> MyCons (f y) (myMap f ys)
    #|      }
    #|end Rec }
    #|Rec {
    #|myFold
    #|  = \ f acc xs ->
    #|      case xs of {
    #|        MyNil -> acc;
    #|        MyCons y ys -> myFold f (f acc y) ys
    #|      }
    #|end Rec }
    #|testList7 = I# 1#
    #|testList6 = I# 2#
    #|testList5 = I# 3#
    #|testList4 = I# 4#
    #|testList3 = MyCons testList4 MyNil
    #|testList2 = MyCons testList5 testList3
    #|testList1 = MyCons testList6 testList2
    #|testList = MyCons testList7 testList1
    #|double = \ x -> + x x
    #|result3 = I# 0#
    #|result2 = \ x -> case x of { I# x1 -> I# (+# (*# 2# x1) 1#) }
    #|result1 = myMap result2 testList
    #|result = myFold + result3 result1
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  let hvm3_code = @lower_hvm3.lower(prog)

  assert_true(hvm3_code.contains("@myMap = (λ&f (λ&xs ((xs @MyNil)"))
  assert_true(hvm3_code.contains("@myFold = (λ&f (λ&acc (λ&xs ((xs acc)"))
  assert_true(hvm3_code.contains("@double = (λ&x (+ x x))"))
  assert_true(hvm3_code.contains("@main = @result"))
}

test "lower 05_tree fixture" {
  let src =
    #|Rec {
    #|sumTree
    #|  = \ t ->
    #|      case t of {
    #|        Leaf x -> x;
    #|        Node l r ->
    #|          case sumTree l of { I# x ->
    #|          case sumTree r of { I# y -> I# (+# x y) }
    #|          }
    #|      }
    #|end Rec }
    #|Rec {
    #|$wbuildTree
    #|  = \ ww x ->
    #|      case <=# ww 0# of {
    #|        __DEFAULT ->
    #|          Node
    #|            ($wbuildTree (-# ww 1#) (case x of { I# x1 -> I# (*# x1 2#) }))
    #|            ($wbuildTree
    #|               (-# ww 1#) (case x of { I# x1 -> I# (+# (*# x1 2#) 1#) }));
    #|        1# -> Leaf x
    #|      }
    #|end Rec }
    #|buildTree = \ d x -> case d of { I# ww -> $wbuildTree ww x }
    #|myTree1 = I# 1#
    #|myTree = $wbuildTree 3# myTree1
    #|result = sumTree myTree
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  let hvm3_code = @lower_hvm3.lower(prog)

  assert_true(hvm3_code.contains("@Leaf = (λ&a0 (λ&c0 (λ&c1 (c0 a0))))"))
  assert_true(
    hvm3_code.contains("@Node = (λ&a0 (λ&a1 (λ&c0 (λ&c1 ((c1 a0) a1)))))"),
  )
  assert_true(hvm3_code.contains("@sumTree = (λ&t ((t (λ&x x)) (λ&l (λ&r"))
  assert_true(hvm3_code.contains("@main = @result"))
}

test "lower 06_lazy_stream fixture" {
  let src =
    #|Rec {
    #|$wsumList
    #|  = \ xs ->
    #|      case xs of {
    #|        Nil -> 0#;
    #|        LCons y ys ->
    #|          case y of { I# x ->
    #|          case $wsumList ys of ww { __DEFAULT -> +# x ww }
    #|          }
    #|      }
    #|end Rec }
    #|sumList = \ xs -> case $wsumList xs of ww { __DEFAULT -> I# ww }
    #|Rec {
    #|$wtakeStream
    #|  = \ ww s ->
    #|      case <=# ww 0# of {
    #|        __DEFAULT ->
    #|          case s of { Cons x xs -> LCons x ($wtakeStream (-# ww 1#) xs) };
    #|        1# -> Nil
    #|      }
    #|end Rec }
    #|takeStream = \ n s -> case n of { I# ww -> $wtakeStream ww s }
    #|Rec {
    #|from = \ n -> Cons n (from (case n of { I# x -> I# (+# x 1#) }))
    #|end Rec }
    #|result3 = I# 1#
    #|result2 = from result3
    #|result1 = $wtakeStream 10# result2
    #|result = case $wsumList result1 of ww { __DEFAULT -> I# ww }
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  let hvm3_code = @lower_hvm3.lower(prog)

  assert_true(hvm3_code.contains("@Nil = (λ&c0 (λ&c1 c0))"))
  assert_true(
    hvm3_code.contains("@LCons = (λ&a0 (λ&a1 (λ&c0 (λ&c1 ((c1 a0) a1)))))"),
  )
  assert_true(hvm3_code.contains("@Cons = (λ&a0 (λ&a1 (λ&c0 ((c0 a0) a1))))"))
  assert_true(hvm3_code.contains("@from = (λ&n ((@Cons n)"))
  assert_true(hvm3_code.contains("@main = @result"))
}

test "lower 07_nqueens fixture" {
  let src =
    #|Rec {
    #|append
    #|  = \ xs ys ->
    #|      case xs of {
    #|        Nil -> ys;
    #|        Cons z zs -> Cons z (append zs ys)
    #|      }
    #|end Rec }
    #|Rec {
    #|concatMapL
    #|  = \ f xs ->
    #|      case xs of {
    #|        Nil -> Nil;
    #|        Cons y ys -> append (f y) (concatMapL f ys)
    #|      }
    #|end Rec }
    #|Rec {
    #|$wlengthL
    #|  = \ xs ->
    #|      case xs of {
    #|        Nil -> 0#;
    #|        Cons ds rest -> case $wlengthL rest of ww { __DEFAULT -> +# 1# ww }
    #|      }
    #|end Rec }
    #|lengthL = \ xs -> case $wlengthL xs of ww { __DEFAULT -> I# ww }
    #|absInt
    #|  = \ x ->
    #|      case x of wild { I# x1 ->
    #|      case <# x1 0# of {
    #|        __DEFAULT -> wild;
    #|        1# -> I# (-# 0# x1)
    #|      }
    #|      }
    #|Rec {
    #|safe
    #|  = \ x d q ->
    #|      case q of {
    #|        Nil -> True;
    #|        Cons c rest ->
    #|          case x of wild1 { I# x1 ->
    #|          case c of { I# y ->
    #|          case ==# x1 y of {
    #|            __DEFAULT ->
    #|              let { x2 = -# x1 y } in
    #|              case <# x2 0# of {
    #|                __DEFAULT ->
    #|                  case d of { I# y1 ->
    #|                  case ==# x2 y1 of {
    #|                    __DEFAULT -> safe wild1 (I# (+# y1 1#)) rest;
    #|                    1# -> False
    #|                  }
    #|                  };
    #|                1# ->
    #|                  case d of { I# y1 ->
    #|                  case ==# (-# 0# x2) y1 of {
    #|                    __DEFAULT -> safe wild1 (I# (+# y1 1#)) rest;
    #|                    1# -> False
    #|                  }
    #|                  }
    #|              };
    #|            1# -> False
    #|          }
    #|          }
    #|          }
    #|      }
    #|end Rec }
    #|Rec {
    #|$wrangeL
    #|  = \ low ww ->
    #|      case low of wild { I# x ->
    #|      case ># x ww of {
    #|        __DEFAULT -> Cons wild ($wrangeL (I# (+# x 1#)) ww);
    #|        1# -> Nil
    #|      }
    #|      }
    #|end Rec }
    #|rangeL = \ low high -> case high of { I# ww -> $wrangeL low ww }
    #|lvl = Cons Nil Nil
    #|lvl1 = I# 1#
    #|Rec {
    #|$wqueens
    #|  = \ n ww ->
    #|      case <=# ww 0# of {
    #|        __DEFAULT ->
    #|          let { lvl2 = case n of { I# ww1 -> $wrangeL lvl1 ww1 } } in
    #|          concatMapL
    #|            (\ qs ->
    #|               concatMapL
    #|                 (\ c ->
    #|                    case safe c lvl1 qs of {
    #|                      False -> Nil;
    #|                      True -> Cons (Cons c qs) Nil
    #|                    })
    #|                 lvl2)
    #|            ($wqueens n (-# ww 1#));
    #|        1# -> lvl
    #|      }
    #|end Rec }
    #|queens = \ n k -> case k of { I# ww -> $wqueens n ww }
    #|result2 = I# 8#
    #|result1 = $wqueens result2 8#
    #|result = case $wlengthL result1 of ww { __DEFAULT -> I# ww }
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  let hvm3_code = @lower_hvm3.lower(prog)

  assert_true(hvm3_code.contains("@False = (λ&c0 (λ&c1 c0))"))
  assert_true(hvm3_code.contains("@True = (λ&c0 (λ&c1 c1))"))
  assert_true(hvm3_code.contains("@Nil = (λ&c0 (λ&c1 c0))"))
  assert_true(
    hvm3_code.contains("@Cons = (λ&a0 (λ&a1 (λ&c0 (λ&c1 ((c1 a0) a1)))))"),
  )
  assert_true(hvm3_code.contains("@append = (λ&xs (λ&ys ((xs ys)"))
  assert_true(hvm3_code.contains("@concatMapL = (λ&f (λ&xs ((xs @Nil)"))
  assert_true(hvm3_code.contains("@absInt = (λ&x"))
  assert_true(hvm3_code.contains("(>> x1 31)"))
  assert_true(hvm3_code.contains("(>> x2 31)"))
  assert_true(hvm3_code.contains("@safe = (λ&x (λ&d (λ&q"))
  assert_true(hvm3_code.contains("@_wqueens = (λ&n (λ&ww"))
  assert_true(hvm3_code.contains("@main = @result"))
}

test "lower 08_mergesort fixture" {
  let src =
    #|Rec {
    #|merge
    #|  = \ xs ys ->
    #|      case xs of wild {
    #|        Nil -> ys;
    #|        Cons x xs' ->
    #|          case ys of wild1 {
    #|            Nil -> wild;
    #|            Cons y ys' ->
    #|              case x of wild2 { I# x1 ->
    #|              case y of wild3 { I# y1 ->
    #|              case <=# x1 y1 of {
    #|                __DEFAULT -> Cons wild3 (merge wild ys');
    #|                1# -> Cons wild2 (merge xs' wild1)
    #|              }
    #|              }
    #|              }
    #|          }
    #|      }
    #|end Rec }
    #|lvl = Pair Nil Nil
    #|Rec {
    #|splitAtL
    #|  = \ n xs ->
    #|      case n of { I# x ->
    #|      case <=# x 0# of {
    #|        __DEFAULT ->
    #|          case xs of {
    #|            Nil -> lvl;
    #|            Cons y ys ->
    #|              case splitAtL (I# (-# x 1#)) ys of {
    #|                Pair l r -> Pair (Cons y l) r
    #|              }
    #|          };
    #|        1# -> Pair Nil xs
    #|      }
    #|      }
    #|end Rec }
    #|lvl1 = I# 0#
    #|Rec {
    #|lengthL
    #|  = \ xs ->
    #|      case xs of {
    #|        Nil -> lvl1;
    #|        Cons ds rest ->
    #|          case lengthL rest of { I# y -> I# (+# 1# y) }
    #|      }
    #|end Rec }
    #|Rec {
    #|checksum
    #|  = \ xs ->
    #|      case xs of {
    #|        Nil -> lvl1;
    #|        Cons y ys ->
    #|          case y of { I# x ->
    #|          case checksum ys of { I# y1 -> I# (+# x (*# 3# y1)) }
    #|          }
    #|      }
    #|end Rec }
    #|Rec {
    #|div2
    #|  = \ n ->
    #|      case n of { I# x ->
    #|      case <=# x 1# of {
    #|        __DEFAULT ->
    #|          case div2 (I# (-# x 2#)) of { I# y -> I# (+# 1# y) };
    #|        1# -> lvl1
    #|      }
    #|      }
    #|end Rec }
    #|Rec {
    #|mergesort
    #|  = \ xs ->
    #|      case xs of wild {
    #|        Nil -> Nil;
    #|        Cons x ds ->
    #|          case ds of {
    #|            Nil -> wild;
    #|            Cons ipv ipv1 ->
    #|              case splitAtL (div2 (lengthL wild)) wild of {
    #|                Pair left right -> merge (mergesort left) (mergesort right)
    #|              }
    #|          }
    #|      }
    #|end Rec }
    #|testList1 = Cons (I# 3#) Nil
    #|testList = Cons (I# 15#) testList1
    #|result1 = mergesort testList
    #|result = checksum result1
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  let hvm3_code = @lower_hvm3.lower(prog)

  assert_true(hvm3_code.contains("@Nil = (λ&c0 (λ&c1 c0))"))
  assert_true(
    hvm3_code.contains("@Cons = (λ&a0 (λ&a1 (λ&c0 (λ&c1 ((c1 a0) a1)))))"),
  )
  assert_true(hvm3_code.contains("@Pair = (λ&a0 (λ&a1 (λ&c0 ((c0 a0) a1))))"))
  assert_true(hvm3_code.contains("@merge = (λ&xs (λ&ys"))
  assert_true(hvm3_code.contains("@splitAtL = (λ&n (λ&xs"))
  assert_true(hvm3_code.contains("@checksum = (λ&xs"))
  assert_true(hvm3_code.contains("@div2 = (λ&n"))
  assert_true(hvm3_code.contains("@mergesort = (λ&xs"))
  assert_true(hvm3_code.contains("@main = @result"))
}
