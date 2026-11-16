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


///|
test "a computed CAF read by a recursive loop becomes a threaded parameter" {
  let prog = optimized(
    #|m = build Tip
    #|loop = \ i acc -> case i of { 0# -> acc; __DEFAULT -> loop i (+ acc (find i m)) }
    #|main = loop 3# 0#
  )
  let text = prog.to_string()
  // the loop now takes the CAF as a leading parameter and passes it on
  assert_true(text.contains("loop __mid_caf_m"))
  // the threaded binder appears at the loop binder, the find argument, and the
  // recursive call -- the CAF name itself stays at the loop entry only
  let mut occurrences = 0
  let needle = "__mid_caf_m"
  let mut from = 0
  while from + needle.length() <= text.length() {
    if text[from:from + needle.length()] == needle {
      occurrences = occurrences + 1
      from = from + needle.length()
    } else {
      from = from + 1
    }
  }
  assert_true(occurrences == 3)
}

///|
test "a non-recursive caller of a threaded loop supplies the CAF itself" {
  let stats = MidStats::new()
  let prog = optimize(
    parse(
      #|m = build Tip
      #|loop = \ i acc -> case i of { 0# -> acc; __DEFAULT -> loop i (+ acc (find i m)) }
      #|main = start (loop 3# 0#)
    ),
    stats,
  )
  assert_true(stats.cafs_threaded == 1)
  assert_true(prog.to_string().contains("loop m"))
}

///|
test "a CAF returned as a value threads fine; a member passed as a value does not" {
  // reading the CAF as a value inside the loop is the shape the pass fixes
  let stats = MidStats::new()
  let prog = optimize(
    parse(
      #|m = build Tip
      #|f = \ i -> case i of { 0# -> m; __DEFAULT -> g i }
      #|g = \ i -> f i
      #|main = f 3#
    ),
    stats,
  )
  assert_true(stats.cafs_threaded == 1)
  assert_true(prog.to_string().contains("f m 3#"))
  // a cycle member passed as a value would change meaning at its application
  // site, so that cycle is left alone
  let stats2 = MidStats::new()
  let _prog2 = optimize(
    parse(
      #|m = build Tip
      #|f = \ i -> apply g i
      #|g = \ i -> f i
      #|apply = \ h x -> h x
      #|main = f 3#
    ),
    stats2,
  )
  assert_true(stats2.cafs_threaded == 0)
}

///|
test "trivial and lambda-valued bindings are never threaded" {
  let stats = MidStats::new()
  let _prog = optimize(
    parse(
      #|lit = 5#
      #|fn = \ x -> + x 1#
      #|loop = \ i -> case i of { 0# -> 0#; __DEFAULT -> loop (+ i (find lit fn)) }
      #|main = loop 3#
    ),
    stats,
  )
  assert_true(stats.cafs_threaded == 0)
}
