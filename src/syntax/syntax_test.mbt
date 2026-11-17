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

test "multi-module linker simple merge" {
  let p1 = @syntax.parse_program("fib = \\ n -> n").unwrap()
  let p2 = @syntax.parse_program("add = \\ a b -> + a b").unwrap()
  let linked = @syntax.link_programs([p1, p2])
  assert_eq(linked.binds.length(), 2)
  assert_true(linked.lookup("fib") is Some(_))
  assert_true(linked.lookup("add") is Some(_))
}

test "multi-module linker cross-module symbol resolution" {
  let s_math =
    #|Rec {
    #|$wfib = \ ww -> ww
    #|end Rec }
    #|fib = \ n -> $wfib n
  let math_fib = @syntax.parse_program(s_math).unwrap()

  let s_list =
    #|myMap = \ f xs -> xs
    #|mySum = \ xs -> 42#
  let list_ops = @syntax.parse_program(s_list).unwrap()

  let s_main =
    #|result = Math_Fib_fib (Data_ListOps_mySum Nil)
    #|main = result
  let main_mod = @syntax.parse_program(s_main).unwrap()

  let linked = @syntax.link_programs([math_fib, list_ops, main_mod])

  // Original definitions present
  assert_true(linked.lookup("fib") is Some(_))
  assert_true(linked.lookup("mySum") is Some(_))
  assert_true(linked.lookup("result") is Some(_))
  assert_true(linked.lookup("main") is Some(_))

  // Cross-module aliases resolved
  assert_eq(linked.lookup("Math_Fib_fib"), Some(@syntax.Expr::Var("fib")))
  assert_eq(linked.lookup("Data_ListOps_mySum"), Some(@syntax.Expr::Var("mySum")))
}

test "multi-module linker reverse qualified resolution and auto main" {
  let callee = @syntax.parse_program("Math_calc = \\ x -> + x 1#").unwrap()
  let caller = @syntax.parse_program("result = calc 10#").unwrap()
  let linked = @syntax.link_programs([callee, caller])

  assert_true(linked.lookup("Math_calc") is Some(_))
  assert_eq(linked.lookup("calc"), Some(@syntax.Expr::Var("Math_calc")))
  // Auto-linked main = result
  assert_eq(linked.lookup("main"), Some(@syntax.Expr::Var("result")))
}

test "multi-module link_core_sources" {
  let s1 = "val1 = 10#"
  let s2 = "val2 = 20#"
  let linked = @syntax.link_core_sources([s1, s2]).unwrap()
  assert_eq(linked.binds.length(), 2)
  assert_true(linked.lookup("val1") is Some(_))
  assert_true(linked.lookup("val2") is Some(_))
}

test "parse and link multimodule fixtures (Math_Fib, Data_ListOps, Main)" {
  let math_fib_src =
    #|Rec {
    #|Math_Fib_$wfib
    #|  = \ ww ->
    #|      case <=# ww 1# of lwild {
    #|        __DEFAULT -> case $wfib (-# ww 1#) of ww {
    #|        __DEFAULT -> case $wfib (-# ww 2#) of ww {
    #|        __DEFAULT -> +# ww ww
    #|      }
    #|      };
    #|        1# -> ww
    #|      };
    #|end Rec }
    #|
    #|$wfib = Math_Fib_$wfib
    #|
    #|Math_Fib_fib
    #|  = \ n ->
    #|      case n of {
    #|        I# ww -> case $wfib ww of ww {
    #|        __DEFAULT -> I# ww
    #|      }
    #|      }
    #|
    #|fib = Math_Fib_fib

  let data_list_ops_src =
    #|Rec {
    #|Data_ListOps_myMap
    #|  = \ f xs ->
    #|      case xs of {
    #|        Nil -> Nil;
    #|        Cons y ys -> Cons (f y) (myMap f ys)
    #|      };
    #|end Rec }
    #|
    #|myMap = Data_ListOps_myMap
    #|
    #|Rec {
    #|Data_ListOps_$wmySum
    #|  = \ xs ->
    #|      case xs of {
    #|        Nil -> 0#;
    #|        Cons y ys -> case y of {
    #|        I# x -> case $wmySum ys of ww {
    #|        __DEFAULT -> +# x ww
    #|      }
    #|      }
    #|      };
    #|end Rec }
    #|
    #|$wmySum = Data_ListOps_$wmySum
    #|
    #|Data_ListOps_mySum
    #|  = \ xs ->
    #|      case $wmySum xs of ww {
    #|        __DEFAULT -> I# ww
    #|      }
    #|
    #|mySum = Data_ListOps_mySum

  let main_src =
    #|testList
    #|  = I# 1#
    #|
    #|testList
    #|  = I# 2#
    #|
    #|testList
    #|  = I# 3#
    #|
    #|testList
    #|  = I# 4#
    #|
    #|testList
    #|  = I# 5#
    #|
    #|testList
    #|  = Cons testList Nil
    #|
    #|testList
    #|  = Cons testList testList
    #|
    #|testList
    #|  = Cons testList testList
    #|
    #|testList
    #|  = Cons testList testList
    #|
    #|testList
    #|  = Cons testList testList
    #|
    #|lvl
    #|  = Data_ListOps_myMap Math_Fib_fib testList
    #|
    #|result
    #|  = case Data_ListOps_$wmySum lvl of ww {
    #|        __DEFAULT -> I# ww
    #|      }
    #|
    #|lvl
    #|  = case result of {
    #|        I# n -> itos n []
    #|      }
    #|
    #|main = result

  let p_math = @syntax.parse_program(math_fib_src).unwrap()
  let p_list = @syntax.parse_program(data_list_ops_src).unwrap()
  let p_main = @syntax.parse_program(main_src).unwrap()

  let linked = @syntax.link_programs([p_math, p_list, p_main])

  // Verify Math.Fib bindings
  assert_true(linked.lookup("Math_Fib_$wfib") is Some(_))
  assert_true(linked.lookup("Math_Fib_fib") is Some(_))
  assert_true(linked.lookup("fib") is Some(_))
  assert_true(linked.lookup("$wfib") is Some(_))

  // Verify Data.ListOps bindings
  assert_true(linked.lookup("Data_ListOps_myMap") is Some(_))
  assert_true(linked.lookup("myMap") is Some(_))
  assert_true(linked.lookup("Data_ListOps_$wmySum") is Some(_))
  assert_true(linked.lookup("$wmySum") is Some(_))
  assert_true(linked.lookup("Data_ListOps_mySum") is Some(_))
  assert_true(linked.lookup("mySum") is Some(_))

  // Verify Main bindings
  assert_true(linked.lookup("testList") is Some(_))
  assert_true(linked.lookup("result") is Some(_))
  assert_true(linked.lookup("main") is Some(_))

  // Test link_core_sources
  let linked_from_sources = @syntax.link_core_sources([math_fib_src, data_list_ops_src, main_src]).unwrap()
  assert_true(linked_from_sources.lookup("main") is Some(_))
  assert_true(linked_from_sources.lookup("Math_Fib_fib") is Some(_))
  assert_true(linked_from_sources.lookup("Data_ListOps_myMap") is Some(_))
}

test "multi-module linker whole-program tree shaking LTO" {
  let s_lib =
    #|usedHelper = \ x -> + x 1#
    #|unusedHelper1 = \ y -> * y 2#
    #|unusedHelper2 = \ z -> - z 3#
    #|libFunc = \ a -> usedHelper a
  let p_lib = @syntax.parse_program(s_lib).unwrap()

  let s_app =
    #|result = libFunc 10#
    #|main = result
    #|unusedAppFunc = 42#
  let p_app = @syntax.parse_program(s_app).unwrap()

  // With link_programs (no LTO), all 7 bindings remain
  let unpruned = @syntax.link_programs([p_lib, p_app])
  assert_eq(unpruned.binds.length(), 7)
  assert_true(unpruned.lookup("unusedHelper1") is Some(_))
  assert_true(unpruned.lookup("unusedAppFunc") is Some(_))

  // With link_programs_lto, dead bindings are pruned, keeping only transitively reachable ones
  let pruned = @syntax.link_programs_lto([p_lib, p_app], ["main"])
  assert_true(pruned.lookup("main") is Some(_))
  assert_true(pruned.lookup("result") is Some(_))
  assert_true(pruned.lookup("libFunc") is Some(_))
  assert_true(pruned.lookup("usedHelper") is Some(_))

  // Unreferenced bindings must be pruned
  assert_true(pruned.lookup("unusedHelper1") is None)
  assert_true(pruned.lookup("unusedHelper2") is None)
  assert_true(pruned.lookup("unusedAppFunc") is None)
  assert_eq(pruned.binds.length(), 4)
}

test "prune_unreachable on library without roots preserves all" {
  let s_lib =
    #|f1 = \ x -> x
    #|f2 = \ y -> y
  let p_lib = @syntax.parse_program(s_lib).unwrap()
  let pruned = @syntax.prune_unreachable(p_lib, [])
  assert_eq(pruned.binds.length(), 2)
  assert_true(pruned.lookup("f1") is Some(_))
  assert_true(pruned.lookup("f2") is Some(_))
}

test "parse 32-bit bitwise primitives and operators" {
  let e1 = @syntax.parse_expr("and# a b").unwrap()
  assert_eq(e1, @syntax.Expr::App(@syntax.Expr::App(@syntax.Expr::Var("and#"), @syntax.Expr::Var("a")), @syntax.Expr::Var("b")))

  let e2 = @syntax.parse_expr("or# x y").unwrap()
  assert_eq(e2, @syntax.Expr::App(@syntax.Expr::App(@syntax.Expr::Var("or#"), @syntax.Expr::Var("x")), @syntax.Expr::Var("y")))

  let e3 = @syntax.parse_expr("xor# a (uncheckedIShiftRL# b 2#)").unwrap()
  assert_eq(
    e3,
    @syntax.Expr::App(
      @syntax.Expr::App(@syntax.Expr::Var("xor#"), @syntax.Expr::Var("a")),
      @syntax.Expr::App(@syntax.Expr::App(@syntax.Expr::Var("uncheckedIShiftRL#"), @syntax.Expr::Var("b")), @syntax.Expr::LitInt(2))
    )
  )

  let e4 = @syntax.parse_expr("uncheckedIShiftL# x 5#").unwrap()
  assert_eq(e4, @syntax.Expr::App(@syntax.Expr::App(@syntax.Expr::Var("uncheckedIShiftL#"), @syntax.Expr::Var("x")), @syntax.Expr::LitInt(5)))

  let e5 = @syntax.parse_expr("(.&.) a b").unwrap()
  assert_eq(e5, @syntax.Expr::App(@syntax.Expr::App(@syntax.Expr::Var(".&."), @syntax.Expr::Var("a")), @syntax.Expr::Var("b")))

  let e6 = @syntax.parse_expr("not# (word32ToWord# x)").unwrap()
  assert_true(e6 is @syntax.Expr::App(@syntax.Expr::Var("not#"), _))
}

test "parse hex literals, float patterns, and large 32-bit unsigned words" {
  let e_hex1 = @syntax.parse_expr("0x428a2f98#").unwrap()
  assert_eq(e_hex1, @syntax.Expr::LitInt(0x428a2f98))

  let e_hex2 = @syntax.parse_expr("0x80##").unwrap()
  assert_eq(e_hex2, @syntax.Expr::LitInt(0x80))

  let e_max_word = @syntax.parse_expr("4294967295#").unwrap()
  assert_eq(e_max_word, @syntax.Expr::LitInt(-1))

  let e_high_bit = @syntax.parse_expr("2147483648#").unwrap()
  assert_eq(e_high_bit, @syntax.Expr::LitInt(-2147483648))

  let e_float1 = @syntax.parse_expr("1.5##").unwrap()
  assert_eq(e_float1, @syntax.Expr::LitInt(1))

  let e_float2 = @syntax.parse_expr("0.0##").unwrap()
  assert_eq(e_float2, @syntax.Expr::LitInt(0))

  let e_min64 = @syntax.parse_expr("-9223372036854775808#").unwrap()
  assert_eq(e_min64, @syntax.Expr::LitInt(-2147483648))
}

test "parse empty case expression alternatives" {
  let src =
    #|foo = \ x ->
    #|  case x of {
    #|    0# -> case overflowError of { };
    #|    __DEFAULT -> 42#
    #|  }
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("foo") is Some(_))
}

test "parse Raytracer Core pattern with fixed-point math and Vec3 ADT" {
  let src =
    #|vdot
    #|  = \ ds_d1O9 ds_d1Oa ->
    #|      case ds_d1O9 of {
    #|        Vec3 x1_aJ6 y1_aJ7 z1_aJ8 -> case ds_d1Oa of {
    #|        Vec3 x2_aJ9 y2_aJa z2_aJb -> case x1_aJ6 of {
    #|        I# x_a1kS -> case x2_aJ9 of {
    #|        I# y_a1kU -> case y1_aJ7 of {
    #|        I# x_X1j -> case y2_aJa of {
    #|        I# y_X1l -> case z1_aJ8 of {
    #|        I# x_X1n -> case z2_aJb of {
    #|        I# y_X1p -> case divZeroError of {
    #|          -9223372036854775808# -> case overflowError of { };
    #|          __DEFAULT -> I# (quotInt# (+# (+# (*# x_a1kS y_a1kU) (*# x_X1j y_X1l)) (*# x_X1n y_X1p)) 1000#)
    #|        }
    #|        }
    #|        }
    #|        }
    #|        }
    #|        }
    #|        }
    #|      }
    #|      }
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("vdot") is Some(_))
}

test "parse Sha256 Core pattern with schedule expansion and bitwise compression" {
  let src =
    #|sigma0
    #|  = \ x_aPL ->
    #|      case x_aPL of {
    #|        W32# x#_a1TY -> W32# (wordToWord32# (xor# (and# (xor# (and# (or# (and# (uncheckedShiftRL# (word32ToWord# x#_a1TY) 2#) 4294967295#) (and# (uncheckedShiftL# (word32ToWord# x#_a1TY) 30#) 4294967295#)) 4294967295#) (and# (or# (and# (uncheckedShiftRL# (word32ToWord# x#_a1TY) 13#) 4294967295#) (and# (uncheckedShiftL# (word32ToWord# x#_a1TY) 19#) 4294967295#)) 4294967295#)) 4294967295#) (and# (or# (and# (uncheckedShiftRL# (word32ToWord# x#_a1TY) 22#) 4294967295#) (and# (uncheckedShiftL# (word32ToWord# x#_a1TY) 10#) 4294967295#)) 4294967295#)))
    #|      }
    #|
    #|rotr
    #|  = \ x_aKk n_aKl ->
    #|      case x_aKk of {
    #|        W32# x#_a1TY -> case n_aKl of {
    #|        I# i#_a1U1 -> case >=# i#_a1U1 0# of lwild_a1U3 {
    #|        __DEFAULT -> case overflowError of { };
    #|        1# -> let i#_s2FC = -# 32# i#_a1U1 in case >=# i#_s2FC 0# of lwild_a1TL {
    #|        __DEFAULT -> case overflowError of { };
    #|        1# -> W32# (wordToWord32# (or# (and# (and# (uncheckedShiftRL# (word32ToWord# x#_a1TY) i#_a1U1) (int2Word# (negateInt# (<# i#_a1U1 64#)))) 4294967295#) (and# (and# (uncheckedShiftL# (word32ToWord# x#_a1TY) i#_s2FC) (int2Word# (negateInt# (<# i#_s2FC 64#)))) 4294967295#)))
    #|      }
    #|      }
    #|      }
    #|      }
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("sigma0") is Some(_))
  assert_true(prog.lookup("rotr") is Some(_))
}

test "parse unboxed tuple expressions and prefix constructors" {
  let e1 = @syntax.parse_expr("(# 1#, 2# #)").unwrap()
  assert_eq(e1, @syntax.Expr::Constr("(#,#)", [@syntax.Expr::LitInt(1), @syntax.Expr::LitInt(2)]))

  let e2 = @syntax.parse_expr("(# a, b, c #)").unwrap()
  assert_eq(e2, @syntax.Expr::Constr("(#,,#)", [@syntax.Expr::Var("a"), @syntax.Expr::Var("b"), @syntax.Expr::Var("c")]))

  let e3 = @syntax.parse_expr("(# #)").unwrap()
  assert_eq(e3, @syntax.Expr::Constr("(##)", []))

  let e4 = @syntax.parse_expr("(# x #)").unwrap()
  assert_eq(e4, @syntax.Expr::Constr("(# #)", [@syntax.Expr::Var("x")]))

  let e5 = @syntax.parse_expr("(#,#) 10# 20#").unwrap()
  assert_eq(e5, @syntax.Expr::Constr("(#,#)", [@syntax.Expr::LitInt(10), @syntax.Expr::LitInt(20)]))

  let e6 = @syntax.parse_expr("(#,,#) a b c").unwrap()
  assert_eq(e6, @syntax.Expr::Constr("(#,,#)", [@syntax.Expr::Var("a"), @syntax.Expr::Var("b"), @syntax.Expr::Var("c")]))
}

test "parse boxed tuple expressions and unit" {
  let e1 = @syntax.parse_expr("(1#, 2#)").unwrap()
  assert_eq(e1, @syntax.Expr::Constr("(,)", [@syntax.Expr::LitInt(1), @syntax.Expr::LitInt(2)]))

  let e2 = @syntax.parse_expr("(a, b, c)").unwrap()
  assert_eq(e2, @syntax.Expr::Constr("(,,)", [@syntax.Expr::Var("a"), @syntax.Expr::Var("b"), @syntax.Expr::Var("c")]))

  let e3 = @syntax.parse_expr("()").unwrap()
  assert_eq(e3, @syntax.Expr::Constr("()", []))

  let e4 = @syntax.parse_expr("(42#)").unwrap()
  assert_eq(e4, @syntax.Expr::LitInt(42))
}

test "parse unboxed and boxed tuple pattern matching in case" {
  let src =
    #|testCase = \ p ->
    #|  case p of {
    #|    (# a, b #) -> +# a b;
    #|    (# x, y, z #) -> +# (+# x y) z;
    #|    (u, v) -> *# u v;
    #|    (# #) -> 0#
    #|  }
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("testCase") is Some(_))
}

test "parse lambda with unboxed tuple and typed parameters" {
  let src =
    #|unboxedLam = \ (# a, b #) -> +# a b
    #|stateLam = \ (s :: State# RealWorld) -> (# s, 42# #)
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("unboxedLam") is Some(_))
  assert_true(prog.lookup("stateLam") is Some(_))
}

test "parse GHC Core IO and State primop patterns" {
  let src =
    #|writeByteArray = \ (s :: State# RealWorld) (ba :: ByteArray#) ->
    #|  case realWorld# of s1 {
    #|    __DEFAULT -> (# s1, () #)
    #|  }
    #|
    #|runIO = \ ioAction ->
    #|  case ioAction realWorld# of {
    #|    (# s2, res #) -> res
    #|  }
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("writeByteArray") is Some(_))
  assert_true(prog.lookup("runIO") is Some(_))
}

test "parse tests/fixtures/primops/01_unboxed_tuple.core" {
  let src =
    #|divModPrim
    #|  = \ a_aD4 b_aD5 ->
    #|      (# quotInt# a_aD4 b_aD5, remInt# a_aD4 b_aD5 #)
    #|
    #|compute
    #|  = \ a_aD6 b_aD7 ->
    #|      case divModPrim a_aD6 b_aD7 of ds_dZ4 {
    #|        (# ipv_sZ9, ipv_sZa #) -> +# (*# ipv_sZ9 10#) ipv_sZa
    #|      }
    #|
    #|result
    #|  = case divModPrim 123# 10# of ds_dZ4 {
    #|        (# ipv_sZ9, ipv_sZa #) -> I# (+# (*# ipv_sZ9 10#) ipv_sZa)
    #|      }
    #|
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("divModPrim") is Some(_))
  assert_true(prog.lookup("compute") is Some(_))
  assert_true(prog.lookup("result") is Some(_))
  assert_true(prog.lookup("main") is Some(_))
}

test "parse tests/fixtures/primops/02_io_state.core" {
  let src =
    #|computeWithState
    #|  = \ n_aD3 ->
    #|      runRW# (\ s0_aDl ->
    #|      case newByteArray# 16# s0_aDl of ds_dZy {
    #|        (# ipv_sZV, ipv_sZW #) -> case writeIntArray# ipv_sZW 0# n_aD3 ipv_sZV of s2_aDo {
    #|        __DEFAULT -> case writeIntArray# ipv_sZW 1# (*# n_aD3 2#) s2_aDo of s3_aDp {
    #|        __DEFAULT -> case readIntArray# ipv_sZW 0# s3_aDp of ds_dZD {
    #|        (# ipv_sZY, ipv_sZZ #) -> case readIntArray# ipv_sZW 1# ipv_sZY of ds_dZF {
    #|        (# ipv_s101, ipv_s102 #) -> +# ipv_sZZ ipv_s102
    #|      }
    #|      }
    #|      }
    #|      }
    #|      })
    #|
    #|result
    #|  = runRW# (\ s0_aDl ->
    #|      case newByteArray# 16# s0_aDl of ds_dZy {
    #|        (# ipv_sZV, ipv_sZW #) -> case writeIntArray# ipv_sZW 0# 21# ipv_sZV of s2_aDo {
    #|        __DEFAULT -> case writeIntArray# ipv_sZW 1# 42# s2_aDo of s3_aDp {
    #|        __DEFAULT -> case readIntArray# ipv_sZW 0# s3_aDp of ds_dZD {
    #|        (# ipv_sZY, ipv_sZZ #) -> case readIntArray# ipv_sZW 1# ipv_sZY of ds_dZF {
    #|        (# ipv_s101, ipv_s102 #) -> I# (+# ipv_sZZ ipv_s102)
    #|      }
    #|      }
    #|      }
    #|      }
    #|      })
    #|
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("computeWithState") is Some(_))
  assert_true(prog.lookup("result") is Some(_))
  assert_true(prog.lookup("main") is Some(_))
}

test "parse Addr# string literal and *H# high multiplication primop" {
  let e1 = @syntax.parse_expr("\"Hello, World!\"#").unwrap()
  assert_eq(e1, @syntax.Expr::LitString("Hello, World!"))

  let e2 = @syntax.parse_expr("unpackCString# \"test\"#").unwrap()
  assert_eq(
    e2,
    @syntax.Expr::App(@syntax.Expr::Var("unpackCString#"), @syntax.Expr::LitString("test"))
  )

  let e3 = @syntax.parse_expr("*H# 12345# 67890#").unwrap()
  assert_eq(
    e3,
    @syntax.Expr::App(
      @syntax.Expr::App(@syntax.Expr::Var("*H#"), @syntax.Expr::LitInt(12345)),
      @syntax.Expr::LitInt(67890)
    )
  )
}

test "parse comprehensive GHC primops table" {
  let src =
    #|-- Arithmetic and Bitwise
    #|testArith = \ a b ->
    #|  let r1 = +# a b in
    #|  let r2 = -# a b in
    #|  let r3 = *# a b in
    #|  let r4 = *H# a b in
    #|  let r5 = negateInt# a in
    #|  let r6 = quotInt# a b in
    #|  let r7 = remInt# a b in
    #|  let r8 = ==# a b in
    #|  let r9 = /=# a b in
    #|  let r10 = <# a b in
    #|  let r11 = <=# a b in
    #|  let r12 = ># a b in
    #|  let r13 = >=# a b in
    #|  let r14 = and# a b in
    #|  let r15 = or# a b in
    #|  let r16 = xor# a b in
    #|  let r17 = not# a in
    #|  let r18 = uncheckedShiftL# a b in
    #|  let r19 = uncheckedShiftRL# a b in
    #|  let r20 = uncheckedIShiftL# a b in
    #|  let r21 = uncheckedIShiftRA# a b in
    #|  let r22 = uncheckedIShiftRL# a b in
    #|  r1
    #|
    #|-- Word operations
    #|testWord = \ w1 w2 ->
    #|  let w3 = plusWord# w1 w2 in
    #|  let w4 = minusWord# w1 w2 in
    #|  let w5 = timesWord# w1 w2 in
    #|  let w6 = quotWord# w1 w2 in
    #|  let w7 = remWord# w1 w2 in
    #|  let w8 = eqWord# w1 w2 in
    #|  let w9 = neWord# w1 w2 in
    #|  let w10 = ltWord# w1 w2 in
    #|  let w11 = leWord# w1 w2 in
    #|  let w12 = gtWord# w1 w2 in
    #|  let w13 = geWord# w1 w2 in
    #|  w3
    #|
    #|-- Word / Int conversions
    #|testConv = \ x ->
    #|  let c1 = int2Word# x in
    #|  let c2 = word2Int# c1 in
    #|  let c3 = narrow8Int# x in
    #|  let c4 = narrow16Int# x in
    #|  let c5 = narrow8Word# c1 in
    #|  let c6 = narrow16Word# c1 in
    #|  let c7 = chr# x in
    #|  let c8 = ord# c7 in
    #|  c8
    #|
    #|-- Addr# and CString
    #|testCString = \ () ->
    #|  let s1 = unpackCString# "hello"# in
    #|  let s2 = unpackCStringUtf8# "world"# in
    #|  s1
    #|
    #|-- ByteArray# and MutableByteArray#
    #|testByteArray = \ s ->
    #|  case newByteArray# 64# s of {
    #|    (# s1, mba #) ->
    #|      case writeWord8Array# mba 0# 42# s1 of s2 {
    #|        __DEFAULT ->
    #|          case readWord8Array# mba 0# s2 of {
    #|            (# s3, w8 #) ->
    #|              case writeIntArray# mba 1# 123# s3 of s4 {
    #|                __DEFAULT ->
    #|                  case readIntArray# mba 1# s4 of {
    #|                    (# s5, val #) ->
    #|                      let sz = sizeofByteArray# mba in
    #|                      let w = indexWord8Array# mba 0# in
    #|                      let i = indexIntArray# mba 1# in
    #|                      case copyByteArray# mba 0# mba 16# 8# s5 of s6 {
    #|                        __DEFAULT -> (# s6, val #)
    #|                      }
    #|                  }
    #|              }
    #|          }
    #|      }
    #|  }
    #|
    #|-- MutVar# and State#
    #|testMutVar = \ s ->
    #|  case newMutVar# 99# s of {
    #|    (# s1, mv #) ->
    #|      case writeMutVar# mv 100# s1 of s2 {
    #|        __DEFAULT ->
    #|          case readMutVar# mv s2 of {
    #|            (# s3, val #) -> (# s3, val #)
    #|          }
    #|      }
    #|  }
    #|
    #|-- Raise and error
    #|testRaise = \ err ->
    #|  let x = raise# err in
    #|  let y = raiseIO# err in
    #|  x
    #|
    #|main = testCString ()
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("testArith") is Some(_))
  assert_true(prog.lookup("testWord") is Some(_))
  assert_true(prog.lookup("testConv") is Some(_))
  assert_true(prog.lookup("testCString") is Some(_))
  assert_true(prog.lookup("testByteArray") is Some(_))
  assert_true(prog.lookup("testMutVar") is Some(_))
  assert_true(prog.lookup("testRaise") is Some(_))
  assert_true(prog.lookup("main") is Some(_))
}

test "parse char literal in case pattern" {
  let src =
    #|testCharPattern = \ c ->
    #|  case c of {
    #|    'a' -> 1#;
    #|    'b' -> 2#;
    #|    __DEFAULT -> 0#
    #|  }
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("testCharPattern") is Some(_))
}

test "parse tests/packages/bytestring_core.core" {
  let src =
    #|addr#_a2v9
    #|  = "Coronet Implicit Parallel Graph Reduction"#
    #|
    #|testBS
    #|  = BS addr#_a2v9 FinalPtr 41#
    #|
    #|lvl_s2uP
    #|  = I# 0#
    #|
    #|calcChecksum
    #|  = \ bs_aQ2 ->
    #|      case bs_aQ2 of wild_a1Iv {
    #|        BS bx_a1KX bx1_a1KY bx2_a1KZ -> let end_s2uA = plusAddr# bx_a1KX bx2_a1KZ in let Rec { $wgo_s2wQ = \ ww_s2wI ww_s2wM ww_s2wN eta_s2wP ->
    #|      case eqAddr# ww_s2wM end_s2uA of lwild_a1L9 {
    #|        __DEFAULT -> case readWord8OffAddr# ww_s2wM 0# eta_s2wP of ds2_a1Lb {
    #|        (# ipv2_a1Lc, ipv3_a1Ld #) -> case touch# ww_s2wN ipv2_a1Lc of s'_a1Lf {
    #|        __DEFAULT -> $wgo_s2wQ (remInt# (+# (*# ww_s2wI 31#) (word2Int# (word8ToWord# ipv3_a1Ld))) 1000000007#) (plusAddr# ww_s2wM 1#) ww_s2wN s'_a1Lf
    #|      }
    #|      };
    #|        1# -> I# ww_s2wI
    #|      } end Rec } in $wgo_s2wQ 0# bx_a1KX bx1_a1KY realWorld#
    #|      }
    #|
    #|result
    #|  = let end_s2uA = plusAddr# addr#_a2v9 41# in let Rec { $wgo_s2xc = \ ww_s2x4 ww_s2x8 ww_s2x9 eta_s2xb ->
    #|      case eqAddr# ww_s2x8 end_s2uA of lwild_a1L9 {
    #|        __DEFAULT -> case readWord8OffAddr# ww_s2x8 0# eta_s2xb of ds2_a1Lb {
    #|        (# ipv2_a1Lc, ipv3_a1Ld #) -> case touch# ww_s2x9 ipv2_a1Lc of s'_a1Lf {
    #|        __DEFAULT -> $wgo_s2xc (remInt# (+# (*# ww_s2x4 31#) (word2Int# (word8ToWord# ipv3_a1Ld))) 1000000007#) (plusAddr# ww_s2x8 1#) ww_s2x9 s'_a1Lf
    #|      }
    #|      };
    #|        1# -> I# ww_s2x4
    #|      } end Rec } in $wgo_s2xc 0# addr#_a2v9 FinalPtr realWorld#
    #|
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("addr#_a2v9") is Some(_))
  assert_true(prog.lookup("testBS") is Some(_))
  assert_true(prog.lookup("calcChecksum") is Some(_))
  assert_true(prog.lookup("result") is Some(_))
  assert_true(prog.lookup("main") is Some(_))
}

test "parse char pattern in case" {
  let src =
    #|f = \ c -> case c of {
    #|  __DEFAULT -> 0#;
    #|  '*' -> 1#;
    #|  '+' -> 2#;
    #|  '-' -> 3#
    #|}
  let prog = @syntax.parse_core(src).unwrap()
  println("prog: \{prog}")
}

test "parse Level 4 GhcCompiler Core AST patterns and optimizer pipelines" {
  let src =
    #|lvl_s4z8
    #|  = "tests/packages/ghc/GhcCompiler.hs:13:19-20|case"#
    #|
    #|lvl_s49a
    #|  = patError lvl_s4z8
    #|
    #|$c_eq__a2Bs
    #|  = \ a_a1Gn b_a1Go ->
    #|      case dataToTagSmall# a_a1Gn of a#_a1Gp {
    #|        __DEFAULT -> case dataToTagSmall# b_a1Go of b#_a1Gq {
    #|        __DEFAULT -> case /=# a#_a1Gp b#_a1Gq of ds_d322 {
    #|        __DEFAULT -> case a_a1Gn of wild_X1 {
    #|        LitInt bx_d33r -> case b_a1Go of wild_X2 {
    #|        LitInt bx_d33t -> tagToEnum# (==# bx_d33r bx_d33t);
    #|        LitBool ipv_s3a1 -> case lvl_s49a of wild_48_0 {
    #|
    #|      }
    #|      };
    #|        LitBool a1_a1Gt -> case b_a1Go of wild_X2 {
    #|        LitInt ipv_s3a3 -> case lvl_s49a of wild_48_0 {
    #|
    #|      };
    #|        LitBool b1_a1Gu -> case dataToTagSmall# a1_a1Gt of a#_a3a7 {
    #|        __DEFAULT -> case dataToTagSmall# b1_a1Gu of b#_a3a8 {
    #|        __DEFAULT -> tagToEnum# (==# a#_a3a7 b#_a3a8)
    #|      }
    #|      }
    #|      }
    #|      };
    #|        1# -> False
    #|      }
    #|      }
    #|      }
    #|
    #|Rec {
    #|$c_ne__a2vD
    #|  = \ eta_B0 eta_B1 ->
    #|      case $c_eq__a2Bs eta_B0 eta_B1 of wild_a33m {
    #|        False -> True;
    #|        True -> False
    #|      };
    #|$c_eq__a2yp
    #|  = \ ds_d31I ds_d31J ->
    #|      case ds_d31I of wild_X1E {
    #|        CAlt a1_a1FX a2_a1FY a3_a1FZ -> case ds_d31J of wild_X1 {
    #|        CAlt b1_a1G0 b2_a1G1 b3_a1G2 -> True
    #|      }
    #|      }
    #|end Rec }
    #|
    #|runBenchmark
    #|  = \ expr_s4yK ->
    #|      case expr_s4yK of opt_a1fw {
    #|        __DEFAULT -> 1528835#
    #|      }
    #|
    #|result
    #|  = I# 1528835#
    #|
    #|main = result
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("lvl_s4z8") is Some(_))
  assert_true(prog.lookup("lvl_s49a") is Some(_))
  assert_true(prog.lookup("$c_eq__a2Bs") is Some(_))
  assert_true(prog.lookup("$c_ne__a2vD") is Some(_))
  assert_true(prog.lookup("$c_eq__a2yp") is Some(_))
  assert_true(prog.lookup("runBenchmark") is Some(_))
  assert_true(prog.lookup("result") is Some(_))
  assert_true(prog.lookup("main") is Some(_))

  // Linker verification
  let linked = @syntax.link_programs([prog])
  assert_true(linked.lookup("main") is Some(_))
}








test "parse Haskell string escapes a GHC dump contains" {
  let src =
    #|msg = "\ESC[1m\NUL\SO\&x\&\n\t\\\"\65\o101\0x42\^A\DEL"#
  let prog = @syntax.parse_program(src).unwrap()
  let expr = prog.lookup("msg").unwrap()
  let expected = "\u{1b}[1m\u{0}\u{e}x&\n\t\\\"AAB\u{1}\u{7f}"
  assert_true(expr is LitString(expected))
}

test "parse char escapes" {
  let src =
    #|f = \ c -> case c of { '\ESC' -> 1#; '\NUL' -> 2#; '\t' -> 3#; __DEFAULT -> 0# }
  let prog = @syntax.parse_program(src).unwrap()
  assert_true(prog.lookup("f") is Some(_))
}
