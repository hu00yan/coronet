///|
test "prune keeps only definitions reachable from the root" {
  let book = "@dead = 1\n\n@live = @dead2\n\n@dead2 = 2\n\n@main = 3"
  let pruned = prune_book_text(book, ["main"])
  assert_eq(pruned, "@main = 3")
}

///|
test "prune keeps the transitive closure of the root" {
  let book = "@a = @b\n\n@b = @c\n\n@c = 1\n\n@main = @a\n\n@unused = 9"
  let pruned = prune_book_text(book, ["main"])
  assert_eq(pruned, "@a = @b\n\n@b = @c\n\n@c = 1\n\n@main = @a\n")
}

///|
test "prune leaves a book without a root untouched" {
  let book = "@a = 1"
  assert_eq(prune_book_text(book, ["main"]), book)
}

///|
test "def names are extracted from both definition shapes" {
  assert_eq(book_def_names("@a = 1\n@b(x) = 2"), ["a", "b"])
}

///|
test "alpha-identical definitions collapse to one and refs follow" {
  let book = "@a = (x x)\n\n@b = (y y)\n\n@main = (@a @b)"
  assert_eq(merge_alpha_duplicate_defs(book), "@a = (x x)\n\n@main = (@a @a)")
}

///|
test "definitions that differ keep both" {
  let book = "@a = (x x)\n\n@b = (x (y x))\n\n@main = (@a @b)"
  assert_eq(merge_alpha_duplicate_defs(book), book)
}

///|
test "shared references are renamed before deciding a duplicate" {
  let book = "@l1 = 1\n\n@l2 = 2\n\n@a = (* @l1)\n\n@b = (* @l2)\n\n@main = (@a @b)"
  // @l1 and @l2 are not identical, so @a and @b stay distinct.
  assert_eq(merge_alpha_duplicate_defs(book), book)
}
test "multi-line branch nets with different wire names collapse" {
  let book = "@alt0 = (* (_u1 (* (* r1))))\n  & _u1 ~ (0 a1)\n  & a1 ~ r1\n\n@alt1 = (* (_u2 (* (* r2))))\n  & _u2 ~ (0 a2)\n  & a2 ~ r2\n\n@main = (@alt0 @alt1)"
  assert_eq(
    merge_alpha_duplicate_defs(book),
    "@alt0 = (* (_u1 (* (* r1))))\n  & _u1 ~ (0 a1)\n  & a1 ~ r1\n\n@main = (@alt0 @alt0)",
  )
}
