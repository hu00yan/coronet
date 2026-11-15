///| Unit tests for CoreLite AST and Parser.

test "parse basic literals and variables" {
  let e1 = @syntax.parse_expr("42#").unwrap()
  assert_eq(e1, @syntax.Expr::LitInt(42))

  let e2 = @syntax.parse_expr("0#").unwrap()
  assert_eq(e2, @syntax.Expr::LitInt(0))

  let e3 = @syntax.parse_expr("-5#").unwrap()
  assert_eq(e3, @syntax.Expr::LitInt(-5))

  let e4 = @syntax.parse_expr("foo_123").unwrap()
  assert_eq(e4, @syntax.Expr::Var("foo_123"))

  let e5 = @syntax.parse_expr("+#").unwrap()
  assert_eq(e5, @syntax.Expr::Var("+#"))

  let e6 = @syntax.parse_expr("$wfib").unwrap()
  assert_eq(e6, @syntax.Expr::Var("$wfib"))

  let e7 = @syntax.parse_expr("'a'").unwrap()
  assert_eq(e7, @syntax.Expr::LitChar('a'))

  let e8 = @syntax.parse_expr("\"hello\"").unwrap()
  assert_eq(e8, @syntax.Expr::LitString("hello"))
}

test "parse constructors and applications" {
  let e1 = @syntax.parse_expr("MyNil").unwrap()
  assert_eq(e1, @syntax.Expr::Constr("MyNil", []))

  let e2 = @syntax.parse_expr("I# 48#").unwrap()
  assert_eq(e2, @syntax.Expr::Constr("I#", [@syntax.Expr::LitInt(48)]))

  let e3 = @syntax.parse_expr("MyCons 1# MyNil").unwrap()
  assert_eq(e3, @syntax.Expr::Constr("MyCons", [@syntax.Expr::LitInt(1), @syntax.Expr::Constr("MyNil", [])]))

  let e4 = @syntax.parse_expr("f x y").unwrap()
  assert_eq(e4, @syntax.Expr::App(@syntax.Expr::App(@syntax.Expr::Var("f"), @syntax.Expr::Var("x")), @syntax.Expr::Var("y")))

  let (head, args) = e4.unwind_app()
  assert_eq(head, @syntax.Expr::Var("f"))
  assert_eq(args.length(), 2)
  assert_eq(args[0], @syntax.Expr::Var("x"))
  assert_eq(args[1], @syntax.Expr::Var("y"))
}

test "parse lambdas and currying" {
  let e1 = @syntax.parse_expr("\\ x -> x").unwrap()
  assert_eq(e1, @syntax.Expr::Lam("x", @syntax.Expr::Var("x")))

  let e2 = @syntax.parse_expr("\\ a b c -> + a b").unwrap()
  assert_eq(
    e2,
    @syntax.Expr::Lam(
      "a",
      @syntax.Expr::Lam(
        "b",
        @syntax.Expr::Lam("c", @syntax.Expr::App(@syntax.Expr::App(@syntax.Expr::Var("+"), @syntax.Expr::Var("a")), @syntax.Expr::Var("b")))
      )
    )
  )

  // Type parameters @a @b are erased
  let e3 = @syntax.parse_expr("\\ @a @b x y -> x").unwrap()
  assert_eq(e3, @syntax.Expr::Lam("x", @syntax.Expr::Lam("y", @syntax.Expr::Var("x"))))
}

test "parse let expressions" {
  let e1 = @syntax.parse_expr("let x = 10# in + x 1#").unwrap()
  assert_eq(
    e1,
    @syntax.Expr::Let(
      @syntax.Bind::NonRec("x", @syntax.Expr::LitInt(10)),
      @syntax.Expr::App(@syntax.Expr::App(@syntax.Expr::Var("+"), @syntax.Expr::Var("x")), @syntax.Expr::LitInt(1))
    )
  )

  let e2 = @syntax.parse_expr("let Rec { f = \\ x -> f x } in f 0#").unwrap()
  assert_eq(
    e2,
    @syntax.Expr::Let(
      @syntax.Bind::Rec([("f", @syntax.Expr::Lam("x", @syntax.Expr::App(@syntax.Expr::Var("f"), @syntax.Expr::Var("x"))))]),
      @syntax.Expr::App(@syntax.Expr::Var("f"), @syntax.Expr::LitInt(0))
    )
  )
}

test "parse case expressions" {
  let e1 = @syntax.parse_expr("case xs of { MyNil -> 0#; MyCons h t -> 1# }").unwrap()
  match e1 {
    @syntax.Expr::Case(scrut, binder, alts) => {
      assert_eq(scrut, @syntax.Expr::Var("xs"))
      assert_eq(binder, "")
      assert_eq(alts.length(), 2)
      assert_eq(alts[0].pat, @syntax.Pat::Data("MyNil", []))
      assert_eq(alts[0].expr, @syntax.Expr::LitInt(0))
      assert_eq(alts[1].pat, @syntax.Pat::Data("MyCons", ["h", "t"]))
      assert_eq(alts[1].expr, @syntax.Expr::LitInt(1))
    }
    _ => assert_true(false)
  }

  // Case with case binder
  let e2 = @syntax.parse_expr("case n of wild { I# ds -> ds }").unwrap()
  match e2 {
    @syntax.Expr::Case(scrut, binder, alts) => {
      assert_eq(scrut, @syntax.Expr::Var("n"))
      assert_eq(binder, "wild")
      assert_eq(alts.length(), 1)
      assert_eq(alts[0].pat, @syntax.Pat::Data("I#", ["ds"]))
      assert_eq(alts[0].expr, @syntax.Expr::Var("ds"))
    }
    _ => assert_true(false)
  }

  // Case with __DEFAULT and literal
  let e3 = @syntax.parse_expr("case x of { 0# -> 10#; __DEFAULT -> 20# }").unwrap()
  match e3 {
    @syntax.Expr::Case(_, _, alts) => {
      assert_eq(alts.length(), 2)
      assert_eq(alts[0].pat, @syntax.Pat::Lit(0))
      assert_eq(alts[1].pat, @syntax.Pat::Default(None))
    }
    _ => assert_true(false)
  }

  // Case with wildcard _
  let e4 = @syntax.parse_expr("case x of { _ -> 42# }").unwrap()
  match e4 {
    @syntax.Expr::Case(_, _, alts) => {
      assert_eq(alts.length(), 1)
      assert_eq(alts[0].pat, @syntax.Pat::Default(None))
      assert_eq(alts[0].expr, @syntax.Expr::LitInt(42))
    }
    _ => assert_true(false)
  }
}

test "parse fixture 01_arith" {
  let src =
    #|mul = *
    #|
    #|sub = -
    #|
    #|add = +
    #|
    #|calc
    #|  = \ a b c ->
    #|      case a of { I# x ->
    #|      case b of { I# y ->
    #|      case c of { I# y1 -> I# (-# (*# (+# x y) y1) 42#) }
    #|      }
    #|      }
    #|
    #|result = I# 48#
    #|
    #|main = result
  let prog = match @syntax.parse_program(src) {
    Ok(p) => p
    Err(e) => {
      println("Error in 01_arith: \{e}")
      panic()
    }
  }
  assert_eq(prog.binds.length(), 6)

  let main_expr = prog.lookup("main").unwrap()
  assert_eq(main_expr, @syntax.Expr::Var("result"))

  let result_expr = prog.lookup("result").unwrap()
  assert_eq(result_expr, @syntax.Expr::Constr("I#", [@syntax.Expr::LitInt(48)]))

  let all = prog.all_bindings()
  assert_eq(all.length(), 6)
}

test "parse fixture 02_fib" {
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
    #|
    #|fib
    #|  = \ n ->
    #|      case n of { I# ww -> case $wfib ww of ww1 { __DEFAULT -> I# ww1 } }
    #|
    #|result = case $wfib 10# of ww { __DEFAULT -> I# ww }
    #|
    #|main = result
  let prog = match @syntax.parse_program(src) {
    Ok(p) => p
    Err(e) => {
      println("Error in 01_arith: \{e}")
      panic()
    }
  }
  assert_eq(prog.binds.length(), 4)

  // Verify Rec block
  match prog.binds[0] {
    @syntax.Bind::Rec(pairs) => {
      assert_eq(pairs.length(), 1)
      assert_eq(pairs[0].0, "$wfib")
    }
    _ => assert_true(false)
  }

  assert_true(prog.lookup("fib") is Some(_))
  assert_true(prog.lookup("result") is Some(_))
  assert_true(prog.lookup("main") is Some(_))
}

test "parse fixture 03_adt" {
  let src =
    #|safeHead
    #|  = \ xs ->
    #|      case xs of {
    #|        MyNil -> MyNothing;
    #|        MyCons h ds -> MyJust h
    #|      }
    #|
    #|fromMaybe
    #|  = \ def m ->
    #|      case m of {
    #|        MyNothing -> def;
    #|        MyJust x -> x
    #|      }
    #|
    #|isNil
    #|  = \ xs ->
    #|      case xs of {
    #|        MyNil -> MyTrue;
    #|        MyCons ds ds1 -> MyFalse
    #|      }
    #|
    #|process1 = I# 0#
    #|
    #|process
    #|  = \ xs ->
    #|      case xs of {
    #|        MyNil -> process1;
    #|        MyCons ds ds1 -> ds
    #|      }
    #|
    #|result = I# 42#
    #|
    #|testList2 = I# 10#
    #|
    #|testList1 = MyCons testList2 MyNil
    #|
    #|testList = MyCons result testList1
    #|
    #|main = result
  let prog = match @syntax.parse_program(src) {
    Ok(p) => p
    Err(e) => {
      println("Error in 01_arith: \{e}")
      panic()
    }
  }
  assert_eq(prog.binds.length(), 10)

  let fromMaybe_e = prog.lookup("fromMaybe").unwrap()
  match fromMaybe_e {
    @syntax.Expr::Lam("def", @syntax.Expr::Lam("m", @syntax.Expr::Case(_, _, alts))) => {
      assert_eq(alts.length(), 2)
      assert_eq(alts[0].pat, @syntax.Pat::Data("MyNothing", []))
      assert_eq(alts[1].pat, @syntax.Pat::Data("MyJust", ["x"]))
    }
    _ => assert_true(false)
  }
}

test "parse fixture 04_higher_order" {
  let src =
    #|Rec {
    #|myMap
    #|  = \ f xs ->
    #|      case xs of {
    #|        MyNil -> MyNil;
    #|        MyCons y ys -> MyCons (f y) (myMap f ys)
    #|      }
    #|end Rec }
    #|
    #|Rec {
    #|myFold
    #|  = \ f acc xs ->
    #|      case xs of {
    #|        MyNil -> acc;
    #|        MyCons y ys -> myFold f (f acc y) ys
    #|      }
    #|end Rec }
    #|
    #|double = \ x -> + x x
    #|
    #|result = myFold + 0# (myMap double MyNil)
    #|
    #|main = result
  let prog = match @syntax.parse_program(src) {
    Ok(p) => p
    Err(e) => {
      println("Error in 01_arith: \{e}")
      panic()
    }
  }
  assert_eq(prog.binds.length(), 5)
  assert_true(prog.lookup("myMap") is Some(_))
  assert_true(prog.lookup("myFold") is Some(_))
}

test "parse fixture 05_tree" {
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
    #|
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
    #|
    #|result = sumTree (Leaf (I# 42#))
    #|
    #|main = result
  let prog = match @syntax.parse_program(src) {
    Ok(p) => p
    Err(e) => {
      println("Error in 01_arith: \{e}")
      panic()
    }
  }
  assert_eq(prog.binds.length(), 4)
  assert_true(prog.lookup("sumTree") is Some(_))
  assert_true(prog.lookup("$wbuildTree") is Some(_))
}

test "parse raw GHC dump with headers, type signatures, and type applications" {
  let raw =
    #|[1 of 1] Compiling Arith ( ... )
    #|==================== Tidy Core ====================
    #|Result size of Tidy Core = {terms: 46, types: 26}
    #|
    #|-- Line comment
    #|{- Block comment -}
    #|
    #|add :: Int -> Int -> Int
    #|add = \ @a x y -> + x y
    #|
    #|val = add @Int 10# 20#
  let prog = @syntax.parse_program(raw).unwrap()
  assert_eq(prog.binds.length(), 2)
  assert_true(prog.lookup("add") is Some(_))
  assert_true(prog.lookup("val") is Some(_))
}

test "parse list constructor and tuple syntax" {
  let e1 = @syntax.parse_expr("(:) 1# []").unwrap()
  assert_eq(e1, @syntax.Expr::Constr("(:)", [@syntax.Expr::LitInt(1), @syntax.Expr::Constr("[]", [])]))

  let e2 = @syntax.parse_expr(": 1# []").unwrap()
  assert_eq(e2, @syntax.Expr::Constr(":", [@syntax.Expr::LitInt(1), @syntax.Expr::Constr("[]", [])]))

  let e3 = @syntax.parse_expr("(,) a b").unwrap()
  assert_eq(e3, @syntax.Expr::Constr("(,)", [@syntax.Expr::Var("a"), @syntax.Expr::Var("b")]))

  let e4 = @syntax.parse_expr("(,,) a b c").unwrap()
  assert_eq(e4, @syntax.Expr::Constr("(,,)", [@syntax.Expr::Var("a"), @syntax.Expr::Var("b"), @syntax.Expr::Var("c")]))

  let e5 = @syntax.parse_expr("[1#, 2#, 3#]").unwrap()
  assert_eq(
    e5,
    @syntax.Expr::Constr(
      ":",
      [@syntax.Expr::LitInt(1), @syntax.Expr::Constr(":", [@syntax.Expr::LitInt(2), @syntax.Expr::Constr(":", [@syntax.Expr::LitInt(3), @syntax.Expr::Constr("[]", [])])])]
    )
  )
}

test "parse fixture 06_lazy_stream" {
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
    #|
    #|sumList = \ xs -> case $wsumList xs of ww { __DEFAULT -> I# ww }
    #|
    #|Rec {
    #|$wtakeStream
    #|  = \ ww s ->
    #|      case <=# ww 0# of {
    #|        __DEFAULT ->
    #|          case s of { Cons x xs -> LCons x ($wtakeStream (-# ww 1#) xs) };
    #|        1# -> Nil
    #|      }
    #|end Rec }
    #|
    #|takeStream = \ n s -> case n of { I# ww -> $wtakeStream ww s }
    #|
    #|Rec {
    #|from = \ n -> Cons n (from (case n of { I# x -> I# (+# x 1#) }))
    #|end Rec }
    #|
    #|result3 = I# 1#
    #|result2 = from result3
    #|result1 = $wtakeStream 10# result2
    #|result = case $wsumList result1 of ww { __DEFAULT -> I# ww }
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("$wsumList") is Some(_))
  assert_true(prog.lookup("$wtakeStream") is Some(_))
  assert_true(prog.lookup("from") is Some(_))
  assert_true(prog.lookup("main") is Some(_))
}

test "parse fixture 07_nqueens" {
  let src =
    #|Rec {
    #|append
    #|  = \ xs ys ->
    #|      case xs of {
    #|        Nil -> ys;
    #|        Cons z zs -> Cons z (append zs ys)
    #|      }
    #|end Rec }
    #|
    #|Rec {
    #|concatMapL
    #|  = \ f xs ->
    #|      case xs of {
    #|        Nil -> Nil;
    #|        Cons y ys -> append (f y) (concatMapL f ys)
    #|      }
    #|end Rec }
    #|
    #|Rec {
    #|$wlengthL
    #|  = \ xs ->
    #|      case xs of {
    #|        Nil -> 0#;
    #|        Cons ds rest -> case $wlengthL rest of ww { __DEFAULT -> +# 1# ww }
    #|      }
    #|end Rec }
    #|
    #|lengthL = \ xs -> case $wlengthL xs of ww { __DEFAULT -> I# ww }
    #|
    #|absInt
    #|  = \ x ->
    #|      case x of wild { I# x1 ->
    #|      case <# x1 0# of {
    #|        __DEFAULT -> wild;
    #|        1# -> I# (-# 0# x1)
    #|      }
    #|      }
    #|
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
    #|
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
    #|
    #|rangeL = \ low high -> case high of { I# ww -> $wrangeL low ww }
    #|lvl = Cons Nil Nil
    #|lvl1 = I# 1#
    #|
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
    #|                     case safe c lvl1 qs of {
    #|                       False -> Nil;
    #|                       True -> Cons (Cons c qs) Nil
    #|                     })
    #|                  lvl2)
    #|            ($wqueens n (-# ww 1#));
    #|        1# -> lvl
    #|      }
    #|end Rec }
    #|
    #|queens = \ n k -> case k of { I# ww -> $wqueens n ww }
    #|result2 = I# 8#
    #|result1 = $wqueens result2 8#
    #|result = case $wlengthL result1 of ww { __DEFAULT -> I# ww }
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("append") is Some(_))
  assert_true(prog.lookup("concatMapL") is Some(_))
  assert_true(prog.lookup("safe") is Some(_))
  assert_true(prog.lookup("$wqueens") is Some(_))
  assert_true(prog.lookup("main") is Some(_))
}

test "parse fixture 08_mergesort" {
  let src =
    #|testList1 = Cons 1# Nil
    #|testList = Cons 2# testList1
    #|
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
    #|
    #|lvl = Pair Nil Nil
    #|
    #|Rec {
    #|splitAtL
    #|  = \ n xs ->
    #|      case n of { I# x ->
    #|      case <=# x 0# of {
    #|        __DEFAULT ->
    #|          case xs of {
    #|            Nil -> lvl;
    #|            Cons y ys ->
    #|              case splitAtL (I# (-# x 1#)) ys of { Pair l r ->
    #|              Pair (Cons y l) r
    #|              }
    #|          };
    #|        1# -> Pair Nil xs
    #|      }
    #|      }
    #|end Rec }
    #|
    #|Rec {
    #|mergesort
    #|  = \ xs ->
    #|      case xs of wild {
    #|        Nil -> Nil;
    #|        Cons x ds ->
    #|          case ds of {
    #|            Nil -> wild;
    #|            Cons ipv ipv1 ->
    #|              case splitAtL 2# wild of { Pair left right ->
    #|              merge (mergesort left) (mergesort right)
    #|              }
    #|          }
    #|      }
    #|end Rec }
    #|
    #|result = mergesort testList
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("merge") is Some(_))
  assert_true(prog.lookup("splitAtL") is Some(_))
  assert_true(prog.lookup("mergesort") is Some(_))
  assert_true(prog.lookup("main") is Some(_))
}
