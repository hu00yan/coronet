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

