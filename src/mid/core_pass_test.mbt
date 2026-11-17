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
    LitInt(_) | LitChar(_) | LitString(_) => false
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
