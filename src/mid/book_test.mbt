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
