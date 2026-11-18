///| Definition-level pruning of an emitted interaction-net book.
///
///| Both targets emit a book as text: HVM2 writes a multi-line block per
///| definition, HVM3 writes one line per definition. Both emit their whole
///| runtime/prelude table on every compile, whether or not the program reaches
///| it. Pruning here keeps the emitted artifact proportional to what `@main`
///| actually needs.

///| Split text into lines, dropping the line terminator.
fn lines_of(text : String) -> Array[String] {
  let lines : Array[String] = []
  let mut start = 0
  let mut i = 0
  while i < text.length() {
    if text[i] == '\n' {
      lines.push(text[start:i].to_owned())
      start = i + 1
    }
    i = i + 1
  }
  if start < text.length() {
    lines.push(text[start:].to_owned())
  }
  lines
}

fn is_name_char(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '$' ||
  c == '.' ||
  c == '-' ||
  c == ':' ||
  c == '#' ||
  c == '\''
}

///| Definition name of a line that opens a definition, or None.
///| Accepts both `@name = ...` and `@name(args) = ...`.
fn def_name_of_line(line : String) -> String? {
  let mut offset = 0
  while offset < line.length() && (line[offset] == ' ' || line[offset] == '\t') {
    offset = offset + 1
  }
  if line.length() - offset < 2 || line[offset] != '@' {
    return None
  }
  let mut end = offset + 1
  while end < line.length() && is_name_char(line[end]) {
    end = end + 1
  }
  if end == offset + 1 {
    return None
  }
  // Must be followed by a definition separator, not an application.
  let mut rest = end
  while rest < line.length() && (line[rest] == ' ' || line[rest] == '\t') {
    rest = rest + 1
  }
  if rest < line.length() && (line[rest] == '=' || line[rest] == '(') {
    Some(line[offset + 1:end].to_owned())
  } else {
    None
  }
}

///| Names referenced as `@name` anywhere in a body.
fn refs_of(body : String) -> Array[String] {
  let refs : Array[String] = []
  let mut i = 0
  while i < body.length() {
    if body[i] == '@' {
      let mut end = i + 1
      while end < body.length() && is_name_char(body[end]) {
        end = end + 1
      }
      if end > i + 1 {
        let name = body[i + 1:end].to_owned()
        if !refs.contains(name) {
          refs.push(name)
        }
      }
      i = end
    } else {
      i = i + 1
    }
  }
  refs
}

///| Prune definitions that `roots` cannot reach.
///
///| Returns the input unchanged when no root is defined, so a book without a
///| known entry point is never emptied by accident.
pub fn prune_book_text(text : String, roots : Array[String]) -> String {
  let lines = lines_of(text)
  let preamble : Array[String] = []
  let names : Array[String] = []
  let bodies : Array[String] = []
  let current : Array[String] = []
  let mut current_name : String? = None
  for line in lines {
    match def_name_of_line(line) {
      Some(name) => {
        match current_name {
          Some(prev) => {
            names.push(prev)
            bodies.push(join_lines(current))
            current.clear()
          }
          None => ()
        }
        current_name = Some(name)
        current.push(line)
      }
      None => {
        match current_name {
          Some(_) => current.push(line)
          None => preamble.push(line)
        }
      }
    }
  }
  match current_name {
    Some(prev) => {
      names.push(prev)
      bodies.push(join_lines(current))
    }
    None => return text
  }

  let mut has_root = false
  for root in roots {
    if names.contains(root) {
      has_root = true
      break
    }
  }
  if !has_root {
    return text
  }

  let reachable : Array[String] = []
  let queue : Array[String] = []
  for root in roots {
    if names.contains(root) && !reachable.contains(root) {
      reachable.push(root)
      queue.push(root)
    }
  }
  let mut head = 0
  while head < queue.length() {
    let name = queue[head]
    head = head + 1
    // A book may define the same name twice. Both bodies load, so both
    // contribute edges; scanning only the first one drops dependencies the
    // runtime still needs.
    for i, defined in names {
      if defined != name {
        continue
      }
      for r in refs_of(bodies[i]) {
        if names.contains(r) && !reachable.contains(r) {
          reachable.push(r)
          queue.push(r)
        }
      }
    }
  }

  let kept : Array[String] = []
  for line in preamble {
    kept.push(line)
  }
  for i, name in names {
    if reachable.contains(name) {
      kept.push(bodies[i])
    }
  }
  join_lines(kept)
}

fn index_of(arr : Array[String], target : String) -> Int? {
  for i, v in arr {
    if v == target {
      return Some(i)
    }
  }
  None
}

fn join_lines(lines : Array[String]) -> String {
  let buf = StringBuilder()
  for i, line in lines {
    if i > 0 {
      buf.write_string("\n")
    }
    buf.write_string(line)
  }
  buf.to_string()
}

///| Names of the definitions in an emitted book, in emission order.
pub fn book_def_names(text : String) -> Array[String] {
  let names : Array[String] = []
  for line in lines_of(text) {
    match def_name_of_line(line) {
      Some(name) => names.push(name)
      None => ()
    }
  }
  names
}

// ----------------------------------------------------------------------------
// Merging alpha-identical definitions
// ----------------------------------------------------------------------------

///| Canonical form of a definition body: every local name becomes `vN` on its
///| first occurrence, `@global` references keep their spelling. Two bodies with
///| the same canonical form are the same net under a renaming of its wires.
pub fn canonical_body(body : String) -> String {
  let buf = StringBuilder()
  let names : Array[String] = []
  let mut i = 0
  while i < body.length() {
    let c = body[i]
    if c == '[' {
      // Preserve bracketed operators (cell-op SYMs like [N]/[R]/[W] and
      // HVM primitives like [+] / [R]) verbatim so they are not alpha-renamed.
      let mut end = i + 1
      while end < body.length() && body[end] != ']' {
        end = end + 1
      }
      if end < body.length() {
        end = end + 1
      }
      buf.write_string(body[i:end].to_owned())
      i = end
    } else if c == '@' {
      let mut end = i + 1
      while end < body.length() && is_name_char(body[end]) {
        end = end + 1
      }
      buf.write_string(body[i:end].to_owned())
      i = end
    } else if is_name_char(c) && !is_digit_char(c) {
      let mut end = i + 1
      while end < body.length() && is_name_char(body[end]) {
        end = end + 1
      }
      let name = body[i:end].to_owned()
      let idx = match index_of(names, name) {
        Some(found) => found
        None => {
          names.push(name)
          names.length() - 1
        }
      }
      buf.write_string("v\{idx}")
      i = end
    } else {
      buf.write_string(body[i:i + 1].to_owned())
      i = i + 1
    }
  }
  buf.to_string()
}

///| The part of a definition block after its `=` header. The header names the
///| definition, so two bodies that differ only there are still the same net.
fn def_value(body : String) -> String {
  let mut i = 0
  while i < body.length() {
    if body[i] == '=' {
      return body[i + 1:].to_owned()
    }
    i = i + 1
  }
  body
}

fn is_digit_char(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///| Follow a rename chain to the definition that actually survives.
///| Merging runs in rounds, so `a -> b` and a later `b -> c` must both resolve
///| to `c`; a single-hop rewrite would leave `@b` dangling.
fn resolve_rename(renames : Array[(String, String)], name : String) -> String {
  let mut current = name
  let mut steps = 0
  while steps <= renames.length() {
    let mut next = current
    for rename in renames {
      if rename.0 == current {
        next = rename.1
        break
      }
    }
    if next == current {
      return current
    }
    current = next
    steps = steps + 1
  }
  current
}

///| Replace `@from` references with `@to` in a body, whole names only.
fn rename_refs(body : String, renames : Array[(String, String)]) -> String {
  if renames.length() == 0 {
    return body
  }
  let buf = StringBuilder()
  let mut i = 0
  while i < body.length() {
    if body[i] == '@' {
      let mut end = i + 1
      while end < body.length() && is_name_char(body[end]) {
        end = end + 1
      }
      let name = body[i + 1:end].to_owned()
      let target = resolve_rename(renames, name)
      if target != name {
        buf.write_string("@")
        buf.write_string(target)
      } else {
        buf.write_string(body[i:end].to_owned())
      }
      i = end
    } else {
      buf.write_string(body[i:i + 1].to_owned())
      i = i + 1
    }
  }
  buf.to_string()
}

///| Collapse definitions whose nets are identical under a renaming of their
///| local wires. Every remaining reference points at the surviving definition,
///| so the book carries one copy of the net instead of one per occurrence.
pub fn merge_alpha_duplicate_defs(text : String) -> String {
  let lines = lines_of(text)
  let preamble : Array[String] = []
  let names : Array[String] = []
  let bodies : Array[String] = []
  let current : Array[String] = []
  let mut current_name : String? = None
  for line in lines {
    match def_name_of_line(line) {
      Some(name) => {
        match current_name {
          Some(prev) => {
            names.push(prev)
            bodies.push(join_lines(current))
            current.clear()
          }
          None => ()
        }
        current_name = Some(name)
        current.push(line)
      }
      None => {
        match current_name {
          Some(_) => current.push(line)
          None => preamble.push(line)
        }
      }
    }
  }
  match current_name {
    Some(prev) => {
      names.push(prev)
      bodies.push(join_lines(current))
    }
    None => return text
  }

  let kept_alive : Array[Bool] = []
  for _ in names {
    kept_alive.push(true)
  }
  let renames : Array[(String, String)] = []

  for round = 0; round < 3; round = round + 1 {
    let keys : Array[String] = []
    let owners : Array[String] = []
    let round_renames : Array[(String, String)] = []
    for i, name in names {
      if !kept_alive[i] {
        continue
      }
      let key = canonical_body(def_value(rename_refs(bodies[i], renames)))
      let owner = match index_of(keys, key) {
        Some(found) => owners[found]
        None => {
          keys.push(key)
          owners.push(name)
          continue
        }
      }
      if owner != name {
        round_renames.push((name, owner))
      }
    }
    if round_renames.length() == 0 {
      break
    }
    for rename in round_renames {
      renames.push(rename)
      let idx = match index_of(names, rename.0) {
        Some(found) => found
        None => continue
      }
      kept_alive[idx] = false
    }
  }

  let kept : Array[String] = []
  for line in preamble {
    kept.push(line)
  }
  for i, name in names {
    if kept_alive[i] {
      kept.push(rename_refs(bodies[i], renames))
    }
  }
  join_lines(kept)
}
