///| Tests for the CoreLite middle-end passes.

///|
fn parse(src : String) -> @syntax.Program {
  @syntax.parse_program(src).unwrap()
}

///|
fn optimized(src : String) -> @syntax.Program {
  optimize(parse(src), MidStats::new())
}

///|
test "a let nobody uses is dropped" {
  let prog = optimized(
    #|f = \ x -> let unused = x in 1#
    #|main = f 2#
  )
  let text = prog.to_string()
  assert_false(text.contains("unused"))
}

///|
test "a let bound to a variable is substituted away" {
  let prog = optimized(
    #|f = \ x -> let y = x in y
    #|main = f 2#
  )
  assert_false(prog.to_string().contains("let"))
}

///|
test "a case on a known constructor reduces to the matching alternative" {
  let prog = optimized(
    #|f = \ x -> case Cons x Nil of { Nil -> 0#; Cons h t -> h }
    #|main = f 7#
  )
  let text = prog.to_string()
  assert_true(text.contains("main = f 7#"))
  assert_false(text.contains("case"))
}

///|
test "alternatives sharing one body keep one copy" {
  let prog = optimized(
    #|f = \ x -> case x of { Nil -> 0#; Cons h t -> 0# }
    #|main = f Nil
  )
  let text = prog.to_string()
  let mut occurrences = 0
  let needle = "0#"
  let mut from = 0
  while from + needle.length() <= text.length() {
    if text[from:from + needle.length()] == needle {
      occurrences = occurrences + 1
      from = from + needle.length()
    } else {
      from = from + 1
    }
  }
  assert_true(occurrences <= 3)
}

///|
test "identical top-level bindings merge into one definition" {
  let prog = optimized(
    #|a = \ x -> + x 1#
    #|b = \ y -> + y 1#
    #|main = + (a 2#) (b 3#)
  )
  let text = prog.to_string()
  assert_true(text.contains("b = a") || text.contains("a = b"))
}

///|
test "a known-constructor case keeps its default when no alternative matches" {
  let prog = optimized(
    #|f = \ x -> case Nil of { Cons h t -> h; __DEFAULT -> 9# }
    #|main = f Nil
  )
  assert_true(prog.to_string().contains("9#"))
}

///|
test "capture is refused rather than performed" {
  // `let y = x in \x -> y` must not become `\x -> x`.
  let prog = optimized(
    #|f = \ x -> let y = x in (\ x -> y)
    #|main = f 1#
  )
  assert_false(prog.to_string().contains("\\x -> x"))
}


test "case binder survives each mid pass" {
  let src =
    #|Data_Sequence_Internal_$cfoldMap'_a1q58
    #|  = \ $dMonoid_a1q5e eta_a1sdH eta_B0 ->
    #|      case GHC_Internal_Base_mempty $dMonoid_a1q5e of z_X0 {
    #|        __DEFAULT -> let $dSemigroup_s1UDK = GHC_Internal_Base_$p1Monoid $dMonoid_a1q5e in case eta_B0 of wild_X1 {
    #|        One a_aRLS -> GHC_Internal_Base__lt__gt_ $dSemigroup_s1UDK z_X0 (eta_a1sdH a_aRLS);
    #|        Two a_aRLV b_aRLW -> case GHC_Internal_Base__lt__gt_ $dSemigroup_s1UDK z_X0 (eta_a1sdH a_aRLV) of vx_a1sKE {
    #|        __DEFAULT -> GHC_Internal_Base__lt__gt_ $dSemigroup_s1UDK vx_a1sKE (eta_a1sdH b_aRLW)
    #|      };
    #|        Three a_aRLZ b_aRM0 c_aRM1 -> case GHC_Internal_Base__lt__gt_ $dSemigroup_s1UDK z_X0 (eta_a1sdH a_aRLZ) of vx_a1sKE {
    #|        __DEFAULT -> case GHC_Internal_Base__lt__gt_ $dSemigroup_s1UDK vx_a1sKE (eta_a1sdH b_aRM0) of vx_X2 {
    #|        __DEFAULT -> GHC_Internal_Base__lt__gt_ $dSemigroup_s1UDK vx_X2 (eta_a1sdH c_aRM1)
    #|      }
    #|      }
    #|      }
    #|      }
  let prog = @syntax.parse_program(src).unwrap()
  let expr = (prog.all_bindings()[0]).1
  assert_true(has_case_binder(expr, "vx_a1sKE"))
  let p1 = prune_dead_lets(expr, MidStats::new())
  assert_true(has_case_binder(p1, "vx_a1sKE"))
  let p2 = inline_trivial_lets(expr, MidStats::new())
  println("P2: \{p2}")
  assert_true(has_case_binder(p2, "vx_a1sKE"))
  let p3 = reduce_known_cases(expr, MidStats::new(), ["One", "Two", "Three", "Four"])
  println("P3: \{p3}")
  assert_true(has_case_binder(p3, "vx_a1sKE"))
  let p4 = merge_alt_bodies(expr, MidStats::new(), [0])
  assert_true(has_case_binder(p4, "vx_a1sKE"))
}

///| Does any case expression in `e` bind `name` as its binder?
fn has_case_binder(e : @syntax.Expr, name : String) -> Bool {
  match e {
    Var(_) => false
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => false
    App(f, a) => has_case_binder(f, name) || has_case_binder(a, name)
    Lam(_, body) => has_case_binder(body, name)
    Let(bind, body) => {
      let in_bind = match bind {
        NonRec(_, v) => has_case_binder(v, name)
        Rec(pairs) => {
          let mut hit = false
          for p in pairs {
            if has_case_binder(p.1, name) {
              hit = true
            }
          }
          hit
        }
      }
      in_bind || has_case_binder(body, name)
    }
    Case(scrut, binder, alts) => {
      let mut hit = binder == name || has_case_binder(scrut, name)
      for a in alts {
        if has_case_binder(a.expr, name) {
          hit = true
        }
      }
      hit
    }
    Constr(_, args) => {
      let mut hit = false
      for a in args {
        if has_case_binder(a, name) {
          hit = true
        }
      }
      hit
    }
  }
}

///|
test "eta reduction removes an identity wrapper" {
  let prog = optimized(
    #|f = \ x -> g x
    #|g = \ y -> y
    #|main = f 1#
  )
  let text = prog.to_string()
  assert_false(text.contains("\\x -> g x"))
  assert_true(text.contains("f = g") || text.contains("main = g 1#"))
}

///|
test "eta reduction refuses when the parameter is free in the function" {
  let prog = optimized(
    #|f = \ x -> (\ y -> + x y) x
    #|main = f 1#
  )
  assert_true(prog.to_string().contains("+ x"))
}

///|
test "constant folding evaluates literal arithmetic and bitwise primops" {
  let stats = MidStats::new()
  let src =
    #|main = + 10# 20#
  let prog = optimize(parse(src), stats)
  assert_eq(stats.constants_folded, 1)
  assert_true(prog.to_string().contains("30#"))
}

///|
test "constant folding folds comparison and bitwise operators" {
  let stats = MidStats::new()
  let src =
    #|main = & (== 5# 5#) 1#
  let prog = optimize(parse(src), stats)
  assert_eq(stats.constants_folded, 2)
  assert_true(prog.to_string().contains("1#"))
}

///|
test "dead constructor alternative pruning drops unreachable branches" {
  let stats = MidStats::new()
  let src =
    #|f = \ x -> case 1# of { 1# -> x; 2# -> + x 8#; 3# -> + x 9# }
    #|main = f 70#
  let prog = optimize(parse(src), stats)
  assert_true(stats.dead_alts_pruned >= 1 || stats.cases_reduced >= 1)
  let text = prog.to_string()
  assert_false(text.contains("8#"))
  assert_false(text.contains("9#"))
}

///|
test "unboxed constructor simplification unwraps unboxed data constructor" {
  let stats = MidStats::new()
  let src =
    #|f = \ x -> case I# x of { I# y -> + y 1# }
    #|main = f 10#
  let prog = optimize(parse(src), stats)
  assert_true(stats.unboxed_simplified >= 1 || stats.cases_reduced >= 1)
  let text = prog.to_string()
  assert_false(text.contains("case"))
}

///|
test "unboxed constructor simplification eliminates identity case" {
  let stats = MidStats::new()
  let src =
    #|f = \ x -> case x of { I# y -> I# y }
    #|main = f (I# 5#)
  let prog = optimize(parse(src), stats)
  assert_true(stats.unboxed_simplified >= 1)
  let text = prog.to_string()
  assert_false(text.contains("case"))
}

///|
test "let push-down pushes compound let into the only case branch that uses it" {
  let stats = MidStats::new()
  let src =
    #|f = \ b y -> let expensive = + (+ (+ y 1#) 2#) (+ (+ y 3#) 4#) in case b of { True -> expensive; False -> 0# }
    #|main = f True 5#
  let prog = optimize(parse(src), stats)
  assert_true(stats.lets_pushed_down >= 1 || stats.dups_sunk >= 1)
  let text = prog.to_string()
  assert_false(text.has_prefix("let expensive ="))
}

///|
test "known-call specialization and beta-reduction inlines applied lambda" {
  let stats = MidStats::new()
  let src =
    #|main = (\ x -> + x 5#) 10#
  let prog = optimize(parse(src), stats)
  assert_true(stats.known_calls_inlined >= 1)
  let text = prog.to_string()
  assert_true(text.contains("15#"))
}

///|
test "known-call inlining inlines small let-bound function used once" {
  let stats = MidStats::new()
  let src =
    #|main = let inc = \ x -> + x 1# in inc 99#
  let prog = optimize(parse(src), stats)
  assert_true(stats.known_calls_inlined >= 1)
  let text = prog.to_string()
  assert_true(text.contains("100#"))
}

///|
test "stream deforestation fuses producer-consumer case chains" {
  let stats = MidStats::new()
  let src =
    #|f = \ x -> case (case x of { True -> Cons 1# Nil; False -> Nil }) of { Cons h t -> h; Nil -> 0# }
    #|main = f True
  let prog = optimize(parse(src), stats)
  assert_true(stats.streams_fused >= 1)
  let text = prog.to_string()
  assert_false(text.contains("case (case"))
}

///|
test "stream deforestation fuses map-map composition" {
  let stats = MidStats::new()
  let src =
    #|f = \ xs -> map (\ a -> + a 1#) (map (\ b -> * b 2#) xs)
    #|main = f Nil
  let prog = optimize(parse(src), stats)
  assert_true(stats.streams_fused >= 1)
  let text = prog.to_string()
  let mut map_count = 0
  let needle = "map "
  let mut from = 0
  while from + needle.length() <= text.length() {
    if text[from:from + needle.length()] == needle {
      map_count = map_count + 1
      from = from + needle.length()
    } else {
      from = from + 1
    }
  }
  assert_true(map_count <= 1)
}

///|
test "dominator DUP sinking pushes multi-use binding into dominating branch" {
  let stats = MidStats::new()
  let src =
    #|f = \ b y -> let compound = + (+ y 1#) (+ y 2#) in case b of { True -> + compound compound; False -> 0# }
    #|main = f True 5#
  let prog = optimize(parse(src), stats)
  assert_true(stats.dups_sunk >= 1)
  let text = prog.to_string()
  assert_false(text.has_prefix("let compound ="))
}

///|
test "symbolic supercompilation propagates pattern constraint to eliminate nested case" {
  let stats = MidStats::new()
  let src =
    #|f = \ x -> case x of { Cons h t -> case x of { Cons a b -> + a 1#; Nil -> 0# }; Nil -> 0# }
    #|main = f (Cons 10# Nil)
  let prog = optimize(parse(src), stats)
  assert_true(stats.supercompiled >= 1 || stats.cases_reduced >= 1)
  let text = prog.to_string()
  assert_false(text.contains("Cons a b"))
}
