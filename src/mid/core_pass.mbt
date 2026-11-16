///| Target-neutral CoreLite middle-end.
///
///| Lowering is an expansion: each case alternative and each lambda becomes its
///| own top-level net with its captured free variables threaded through a call
///| spine. Whatever survives into lowering gets expanded, so the cheapest place
///| to remove work is here, on the tree, before any encoding exists.
///
///| The passes are deliberately small and each one reports what it removed, so a
///| reviewer can see the effect on real inputs through `--mid-stats`.

///| What the pipeline removed, for the `--mid-stats` report.
pub(all) struct MidStats {
  mut dead_lets : Int
  mut inlined_lets : Int
  mut cases_reduced : Int
  mut alts_merged : Int
  mut binds_merged : Int
  mut binds_pruned : Int
  mut cafs_threaded : Int
}

pub fn MidStats::new() -> MidStats {
  {
    dead_lets: 0,
    inlined_lets: 0,
    cases_reduced: 0,
    alts_merged: 0,
    binds_merged: 0,
    binds_pruned: 0,
    cafs_threaded: 0,
  }
}

pub impl Show for MidStats with output(self, logger) {
  logger.write_string(
    "dead lets \{self.dead_lets}, inlined lets \{self.inlined_lets}, cases reduced \{self.cases_reduced}, alternatives merged \{self.alts_merged}, binds merged \{self.binds_merged}, binds pruned \{self.binds_pruned}, cafs threaded \{self.cafs_threaded}",
  )
}

// ----------------------------------------------------------------------------
// Name use analysis
// ----------------------------------------------------------------------------

///| Does `expr` reference `name` outside of a binding that shadows it?
pub fn uses_name(expr : @syntax.Expr, name : String) -> Bool {
  match expr {
    Var(x) => x == name
    LitInt(_) | LitChar(_) | LitString(_) => false
    App(f, a) => uses_name(f, name) || uses_name(a, name)
    Lam(p, body) => p != name && uses_name(body, name)
    Let(NonRec(n, v), body) =>
      uses_name(v, name) || (n != name && uses_name(body, name))
    Let(Rec(pairs), body) => {
      let mut shadows = false
      for pair in pairs {
        if pair.0 == name {
          shadows = true
          break
        }
        if uses_name(pair.1, name) {
          return true
        }
      }
      !shadows && uses_name(body, name)
    }
    Case(scrut, binder, alts) => {
      if uses_name(scrut, name) {
        return true
      }
      for alt in alts {
        let mut shadows = binder == name
        match alt.pat {
          Default(Some(v)) => if v == name { shadows = true }
          Data(_, vars) =>
            for v in vars {
              if v == name {
                shadows = true
                break
              }
            }
          _ => ()
        }
        if !shadows && uses_name(alt.expr, name) {
          return true
        }
      }
      false
    }
    Constr(_, args) => {
      for a in args {
        if uses_name(a, name) {
          return true
        }
      }
      false
    }
  }
}

///| Names bound by an alternative's pattern, plus the case binder.
fn alt_binders(alt : @syntax.Alt, binder : String) -> Array[String] {
  let names : Array[String] = []
  if binder.length() > 0 {
    names.push(binder)
  }
  match alt.pat {
    Default(Some(v)) => names.push(v)
    Data(_, vars) => {
      for v in vars {
        names.push(v)
      }
    }
    _ => ()
  }
  names
}

///| Names bound anywhere inside `expr` (lam, let, case binders).
fn binder_names(expr : @syntax.Expr) -> Array[String] {
  let names : Array[String] = []
  collect_binders(expr, names)
  names
}

fn collect_binders(expr : @syntax.Expr, acc : Array[String]) -> Unit {
  match expr {
    Var(_) | LitInt(_) | LitChar(_) | LitString(_) => ()
    App(f, a) => {
      collect_binders(f, acc)
      collect_binders(a, acc)
    }
    Lam(p, body) => {
      acc.push(p)
      collect_binders(body, acc)
    }
    Let(NonRec(n, v), body) => {
      acc.push(n)
      collect_binders(v, acc)
      collect_binders(body, acc)
    }
    Let(Rec(pairs), body) => {
      for pair in pairs {
        acc.push(pair.0)
        collect_binders(pair.1, acc)
      }
      collect_binders(body, acc)
    }
    Case(scrut, binder, alts) => {
      collect_binders(scrut, acc)
      if binder.length() > 0 {
        acc.push(binder)
      }
      for alt in alts {
        for b in alt_binders(alt, binder) {
          acc.push(b)
        }
        collect_binders(alt.expr, acc)
      }
    }
    Constr(_, args) => {
      for a in args {
        collect_binders(a, acc)
      }
    }
  }
}

///| Names `expr` reads without binding them itself.
pub fn free_names(expr : @syntax.Expr) -> Array[String] {
  let acc : Array[String] = []
  collect_free(expr, [], acc)
  acc
}

fn collect_free(expr : @syntax.Expr, bound : Array[String], acc : Array[String]) -> Unit {
  match expr {
    Var(x) => {
      if !bound.contains(x) && !acc.contains(x) {
        acc.push(x)
      }
    }
    LitInt(_) | LitChar(_) | LitString(_) => ()
    App(f, a) => {
      collect_free(f, bound, acc)
      collect_free(a, bound, acc)
    }
    Lam(p, body) => {
      let next = bound.copy()
      next.push(p)
      collect_free(body, next, acc)
    }
    Let(NonRec(n, v), body) => {
      collect_free(v, bound, acc)
      let next = bound.copy()
      next.push(n)
      collect_free(body, next, acc)
    }
    Let(Rec(pairs), body) => {
      let next = bound.copy()
      for pair in pairs {
        next.push(pair.0)
      }
      for pair in pairs {
        collect_free(pair.1, next, acc)
      }
      collect_free(body, next, acc)
    }
    Case(scrut, binder, alts) => {
      collect_free(scrut, bound, acc)
      for alt in alts {
        let next = bound.copy()
        for b in alt_binders(alt, binder) {
          next.push(b)
        }
        collect_free(alt.expr, next, acc)
      }
    }
    Constr(_, args) => {
      for a in args {
        collect_free(a, bound, acc)
      }
    }
  }
}

///| Substitute only when no binder in `body` would capture a name from `value`.
///| Substitution here exists to delete a wire, so refusing is always sound.
fn substitute_without_capture(
  body : @syntax.Expr,
  name : String,
  value : @syntax.Expr
) -> @syntax.Expr? {
  let binders = binder_names(body)
  for free in free_names(value) {
    if binders.contains(free) {
      return None
    }
  }
  Some(@syntax.substitute_var(body, name, value))
}

// ----------------------------------------------------------------------------
// Canonical form, for merging structurally identical bodies
// ----------------------------------------------------------------------------

///| Alpha-canonical text for an expression. Local binders become `#depth`
///| indices; free (top-level) names keep their spelling, so two bindings that
///| differ only in binder names collapse while recursive self-references do not.
pub fn canonical(expr : @syntax.Expr) -> String {
  let buf = StringBuilder()
  canonical_into(expr, [], buf)
  buf.to_string()
}

fn canonical_var(name : String, bound : Array[String], buf : StringBuilder) -> Unit {
  let mut idx = -1
  for i = bound.length() - 1; i >= 0; i = i - 1 {
    if bound[i] == name {
      idx = bound.length() - 1 - i
      break
    }
  }
  if idx >= 0 {
    buf.write_string("#\{idx}")
  } else {
    buf.write_string("$\{name}")
  }
}

fn canonical_into(
  expr : @syntax.Expr,
  bound : Array[String],
  buf : StringBuilder
) -> Unit {
  match expr {
    Var(x) => canonical_var(x, bound, buf)
    LitInt(n) => buf.write_string("i\{n}")
    LitChar(c) => buf.write_string("c\{c.to_int()}")
    LitString(s) => buf.write_string("s\{s}")
    App(f, a) => {
      buf.write_string("a(")
      canonical_into(f, bound, buf)
      buf.write_string(",")
      canonical_into(a, bound, buf)
      buf.write_string(")")
    }
    Lam(p, body) => {
      buf.write_string("l(")
      let next = bound.copy()
      next.push(p)
      canonical_into(body, next, buf)
      buf.write_string(")")
    }
    Let(NonRec(n, v), body) => {
      buf.write_string("t(")
      canonical_into(v, bound, buf)
      buf.write_string(",")
      let next = bound.copy()
      next.push(n)
      canonical_into(body, next, buf)
      buf.write_string(")")
    }
    Let(Rec(pairs), body) => {
      buf.write_string("r(")
      let next = bound.copy()
      for pair in pairs {
        next.push(pair.0)
      }
      for pair in pairs {
        canonical_into(pair.1, next, buf)
        buf.write_string(";")
      }
      canonical_into(body, next, buf)
      buf.write_string(")")
    }
    Case(scrut, binder, alts) => {
      buf.write_string("k(")
      canonical_into(scrut, bound, buf)
      buf.write_string(";")
      for alt in alts {
        match alt.pat {
          Default(Some(_)) => buf.write_string("d")
          Default(None) => buf.write_string("D")
          Lit(n) => buf.write_string("n\{n}")
          Data(c, vars) => buf.write_string("o\{c}/\{vars.length()}")
        }
        let next = bound.copy()
        for b in alt_binders(alt, binder) {
          next.push(b)
        }
        canonical_into(alt.expr, next, buf)
        buf.write_string(";")
      }
      buf.write_string(")")
    }
    Constr(c, args) => {
      buf.write_string("C\{c}(\{args.length()}")
      for a in args {
        buf.write_string(",")
        canonical_into(a, bound, buf)
      }
      buf.write_string(")")
    }
  }
}

// ----------------------------------------------------------------------------
// Pass 1: drop let bindings whose value nobody uses
// ----------------------------------------------------------------------------

///| CoreLite is lazy, so an unused binding is never demanded. Dropping it is
///| what keeps lowering from synthesizing a net for a value that cannot be
///| reached.
pub fn prune_dead_lets(expr : @syntax.Expr, stats : MidStats) -> @syntax.Expr {
  match expr {
    Let(NonRec(name, value), body) => {
      let value = prune_dead_lets(value, stats)
      let body = prune_dead_lets(body, stats)
      if !uses_name(body, name) {
        stats.dead_lets = stats.dead_lets + 1
        body
      } else {
        Let(NonRec(name, value), body)
      }
    }
    Let(Rec(pairs), body) => {
      let body = prune_dead_lets(body, stats)
      let kept : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        if uses_name(body, pair.0) || rec_group_uses(pairs, pair.0) {
          kept.push((pair.0, prune_dead_lets(pair.1, stats)))
        } else {
          stats.dead_lets = stats.dead_lets + 1
        }
      }
      if kept.length() == 0 {
        body
      } else {
        Let(Rec(kept), body)
      }
    }
    App(f, a) => App(prune_dead_lets(f, stats), prune_dead_lets(a, stats))
    Lam(p, body) => Lam(p, prune_dead_lets(body, stats))
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: prune_dead_lets(alt.expr, stats) })
      }
      Case(prune_dead_lets(scrut, stats), binder, new_alts)
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(prune_dead_lets(a, stats))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

fn rec_group_uses(pairs : Array[(String, @syntax.Expr)], name : String) -> Bool {
  for pair in pairs {
    if pair.0 != name && uses_name(pair.1, name) {
      return true
    }
  }
  false
}

// ----------------------------------------------------------------------------
// Pass 2: substitute trivial values
// ----------------------------------------------------------------------------

///| `let x = y in b` and `let x = 42# in b` only add a wire for the lowerer to
///| linearize. Substituting the value removes the binding and, when `x` is used
///| in several branches, the duplication node that wire would need.
pub fn inline_trivial_lets(expr : @syntax.Expr, stats : MidStats) -> @syntax.Expr {
  match expr {
    Let(NonRec(name, value), body) => {
      let value = inline_trivial_lets(value, stats)
      let body = inline_trivial_lets(body, stats)
      match value {
        Var(_) | LitInt(_) | LitChar(_) | LitString(_) => {
          match substitute_without_capture(body, name, value) {
            Some(inlined) => {
              if uses_name(body, name) {
                stats.inlined_lets = stats.inlined_lets + 1
              } else {
                stats.dead_lets = stats.dead_lets + 1
              }
              inlined
            }
            None => Let(NonRec(name, value), body)
          }
        }
        _ => Let(NonRec(name, value), body)
      }
    }
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, inline_trivial_lets(pair.1, stats)))
      }
      Let(Rec(new_pairs), inline_trivial_lets(body, stats))
    }
    App(f, a) => App(inline_trivial_lets(f, stats), inline_trivial_lets(a, stats))
    Lam(p, body) => Lam(p, inline_trivial_lets(body, stats))
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: inline_trivial_lets(alt.expr, stats) })
      }
      Case(inline_trivial_lets(scrut, stats), binder, new_alts)
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(inline_trivial_lets(a, stats))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

// ----------------------------------------------------------------------------
// Pass 3: reduce a case whose scrutinee is already a constructor or literal
// ----------------------------------------------------------------------------

///| `case Constr c args of { c vars -> e; ... }` is a beta redex that the
///| lowerer would otherwise turn into a match net plus branch helpers. Reducing
///| it here also drops the alternatives that can never be taken.
pub fn reduce_known_cases(expr : @syntax.Expr, stats : MidStats) -> @syntax.Expr {
  match expr {
    Case(scrut, binder, alts) => {
      let scrut = reduce_known_cases(scrut, stats)
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: reduce_known_cases(alt.expr, stats) })
      }
      match scrut {
        Constr(c, args) => {
          let norm = @syntax.normalize_ctor_name(c)
          for alt in new_alts {
            match alt.pat {
              Data(pc, vars) if @syntax.normalize_ctor_name(pc) == norm => {
                let mut body = alt.expr
                let mut ok = true
                for i, v in vars {
                  if i < args.length() {
                    match substitute_without_capture(body, v, args[i]) {
                      Some(next) => body = next
                      None => {
                        ok = false
                        break
                      }
                    }
                  }
                }
                if ok {
                  stats.cases_reduced = stats.cases_reduced + 1
                  return body
                }
                return Case(scrut, binder, new_alts)
              }
              _ => ()
            }
          }
          // No alternative matches: the case can only reach its default.
          for alt in new_alts {
            match alt.pat {
              Default(_) => {
                stats.cases_reduced = stats.cases_reduced + 1
                return alt.expr
              }
              _ => ()
            }
          }
          Case(scrut, binder, new_alts)
        }
        LitInt(n) => {
          for alt in new_alts {
            match alt.pat {
              Lit(k) if k == n => {
                stats.cases_reduced = stats.cases_reduced + 1
                return alt.expr
              }
              _ => ()
            }
          }
          for alt in new_alts {
            match alt.pat {
              Default(Some(v)) => {
                match substitute_without_capture(alt.expr, v, scrut) {
                  Some(body) => {
                    stats.cases_reduced = stats.cases_reduced + 1
                    return body
                  }
                  None => return Case(scrut, binder, new_alts)
                }
              }
              Default(None) => {
                stats.cases_reduced = stats.cases_reduced + 1
                return alt.expr
              }
              _ => ()
            }
          }
          Case(scrut, binder, new_alts)
        }
        _ => Case(scrut, binder, new_alts)
      }
    }
    App(f, a) => App(reduce_known_cases(f, stats), reduce_known_cases(a, stats))
    Lam(p, body) => Lam(p, reduce_known_cases(body, stats))
    Let(NonRec(n, v), body) =>
      Let(NonRec(n, reduce_known_cases(v, stats)), reduce_known_cases(body, stats))
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, reduce_known_cases(pair.1, stats)))
      }
      Let(Rec(new_pairs), reduce_known_cases(body, stats))
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(reduce_known_cases(a, stats))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

// ----------------------------------------------------------------------------
// Pass 4: hoist one copy of a body shared by several alternatives
// ----------------------------------------------------------------------------

///| Alternatives whose bodies are identical and ignore their own pattern
///| binders become one binding referenced from each of them. The lowerer then
///| emits one branch net instead of one per alternative.
pub fn merge_alt_bodies(
  expr : @syntax.Expr,
  stats : MidStats,
  counter : Array[Int]
) -> @syntax.Expr {
  match expr {
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({
          pat: alt.pat,
          expr: merge_alt_bodies(alt.expr, stats, counter),
        })
      }
      // Group alternatives by canonical body, ignoring binders they do not use.
      let keys : Array[String] = []
      let bodies : Array[@syntax.Expr] = []
      let counts : Array[Int] = []
      let usable : Array[Bool] = []
      for alt in new_alts {
        let mut ignores_binders = true
        for b in alt_binders(alt, binder) {
          if uses_name(alt.expr, b) {
            ignores_binders = false
            break
          }
        }
        usable.push(ignores_binders)
        if !ignores_binders {
          continue
        }
        let key = canonical(alt.expr)
        let idx = match index_of_str(keys, key) {
          Some(i) => i
          None => {
            keys.push(key)
            bodies.push(alt.expr)
            counts.push(0)
            keys.length() - 1
          }
        }
        counts[idx] = counts[idx] + 1
      }
      let shared : Array[(String, @syntax.Expr)] = []
      for i, count in counts {
        if count > 1 {
          counter[0] = counter[0] + 1
          shared.push(("__mid_share_\{counter[0]}", bodies[i]))
        }
      }
      if shared.length() == 0 {
        return Case(merge_alt_bodies(scrut, stats, counter), binder, new_alts)
      }
      let shared_names : Array[String] = []
      for s in shared {
        shared_names.push(s.0)
      }
      let final_alts : Array[@syntax.Alt] = []
      for alt in new_alts {
        let mut replacement : String? = None
        let mut ignores_binders = true
        for b in alt_binders(alt, binder) {
          if uses_name(alt.expr, b) {
            ignores_binders = false
            break
          }
        }
        if ignores_binders {
          let key = canonical(alt.expr)
          for i, k in keys {
            if k == key && counts[i] > 1 {
              let mut rank = 0
              for j, c in counts {
                if j < i && c > 1 {
                  rank = rank + 1
                }
              }
              replacement = Some(shared_names[rank])
              break
            }
          }
        }
        match replacement {
          Some(name) => {
            stats.alts_merged = stats.alts_merged + 1
            final_alts.push({ pat: alt.pat, expr: Var(name) })
          }
          None => final_alts.push(alt)
        }
      }
      let mut result : @syntax.Expr = Case(
        merge_alt_bodies(scrut, stats, counter),
        binder,
        final_alts,
      )
      for i = shared.length() - 1; i >= 0; i = i - 1 {
        result = Let(NonRec(shared[i].0, shared[i].1), result)
      }
      result
    }
    App(f, a) =>
      App(
        merge_alt_bodies(f, stats, counter),
        merge_alt_bodies(a, stats, counter),
      )
    Lam(p, body) => Lam(p, merge_alt_bodies(body, stats, counter))
    Let(NonRec(n, v), body) =>
      Let(
        NonRec(n, merge_alt_bodies(v, stats, counter)),
        merge_alt_bodies(body, stats, counter),
      )
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, merge_alt_bodies(pair.1, stats, counter)))
      }
      Let(Rec(new_pairs), merge_alt_bodies(body, stats, counter))
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(merge_alt_bodies(a, stats, counter))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

fn find_alias(aliases : Array[(String, String)], name : String) -> String? {
  for alias in aliases {
    if alias.0 == name {
      return Some(alias.1)
    }
  }
  None
}

fn index_of_str(arr : Array[String], target : String) -> Int? {
  for i, v in arr {
    if v == target {
      return Some(i)
    }
  }
  None
}

// ----------------------------------------------------------------------------
// Pass 5: merge structurally identical top-level bindings
// ----------------------------------------------------------------------------

///| Two top-level bindings with the same canonical body compute the same
///| function. Keep the first and point the rest at it, so the lowerer emits one
///| net and a one-line alias instead of a second copy.
pub fn merge_top_bindings(prog : @syntax.Program, stats : MidStats) -> @syntax.Program {
  let keys : Array[String] = []
  let owners : Array[String] = []
  let aliases : Array[(String, String)] = []
  for bind in prog.binds {
    match bind {
      NonRec(name, expr) => {
        match index_of_str(keys, canonical(expr)) {
          Some(i) => {
            if owners[i] != name {
              aliases.push((name, owners[i]))
              stats.binds_merged = stats.binds_merged + 1
            }
          }
          None => {
            keys.push(canonical(expr))
            owners.push(name)
          }
        }
      }
      Rec(_) => ()
    }
  }
  if aliases.length() == 0 {
    return prog
  }
  let new_binds : Array[@syntax.Bind] = []
  for bind in prog.binds {
    match bind {
      NonRec(name, expr) => {
        match find_alias(aliases, name) {
          Some(target) => new_binds.push(NonRec(name, Var(target)))
          None => new_binds.push(NonRec(name, expr))
        }
      }
      Rec(pairs) => new_binds.push(Rec(pairs))
    }
  }
  @syntax.Program::new(new_binds)
}

// ----------------------------------------------------------------------------
// Pass 6: prune top-level bindings no entry point reaches
// ----------------------------------------------------------------------------

///| Runs before lowering, so dead functions never get expanded into nets at all.
pub fn prune_top_bindings(prog : @syntax.Program, stats : MidStats) -> @syntax.Program {
  let pruned = @syntax.prune_unreachable(prog, ["main", "result"])
  for bind in prog.binds {
    match bind {
      NonRec(name, _) => {
        let mut kept = false
        for b in pruned.binds {
          match b {
            NonRec(n, _) => if n == name { kept = true }
            Rec(pairs) =>
              for p in pairs {
                if p.0 == name {
                  kept = true
                }
              }
          }
        }
        if !kept {
          stats.binds_pruned = stats.binds_pruned + 1
        }
      }
      Rec(_) => ()
    }
  }
  pruned
}

// ----------------------------------------------------------------------------
// Pass 7: thread computed top-level bindings through the recursive loops that
// read them
// ----------------------------------------------------------------------------

///| A reference to a computed top-level binding (`m = go ... Tip`, a CAF)
///| lowers to a REF that re-expands on every activation of the net containing
///| it. When that net sits on a recursive loop, the whole computation reruns
///| per iteration. Adding the CAF as an explicit parameter to every definition
///| of the loop's call cycle turns those re-expansions into one shared value:
///| the wire is computed once and the lowerer's linearize step inserts the DUP
///| nodes that clone it to each iteration.
///
///| The pass is conservative: a cycle is threaded only when every member is
///| referenced in head-of-application position (never passed as a value), no
///| member is itself an alias, and the binding is worth sharing (computed,
///| non-recursive, not a lambda). Substitution inserts a fresh binder, so it
///| cannot capture, and top_names membership is untouched.

///| Walk `expr`, recording which top-level names are called (head of an
///| application) and which are used as values.
fn scan_top_refs(
  expr : @syntax.Expr,
  tops : Array[String],
  calls : Array[String],
  value_uses : Array[String],
  is_head : Bool
) -> Unit {
  match expr {
    Var(n) =>
      if is_top_name(n, tops) {
        if is_head {
          if !array_contains(calls, n) {
            calls.push(n)
          }
        } else if !array_contains(value_uses, n) {
          value_uses.push(n)
        }
      }
    LitInt(_) | LitChar(_) | LitString(_) => ()
    App(f, a) => {
      scan_top_refs(f, tops, calls, value_uses, true)
      scan_top_refs(a, tops, calls, value_uses, false)
    }
    Lam(_, body) => scan_top_refs(body, tops, calls, value_uses, false)
    Let(bind, body) =>
      match bind {
        NonRec(_, v) => {
          scan_top_refs(v, tops, calls, value_uses, false)
          scan_top_refs(body, tops, calls, value_uses, false)
        }
        Rec(pairs) => {
          for pair in pairs {
            scan_top_refs(pair.1, tops, calls, value_uses, false)
          }
          scan_top_refs(body, tops, calls, value_uses, false)
        }
      }
    Case(scrut, _, alts) => {
      scan_top_refs(scrut, tops, calls, value_uses, false)
      for alt in alts {
        scan_top_refs(alt.expr, tops, calls, value_uses, false)
      }
    }
    Constr(_, args) =>
      for a in args {
        scan_top_refs(a, tops, calls, value_uses, false)
      }
  }
}

fn is_top_name(name : String, tops : Array[String]) -> Bool {
  array_contains(tops, name)
}

///| Per-binding call edges over top-level names, in the order of `nodes`.
fn build_call_graph(
  prog : @syntax.Program
) -> (Array[String], Array[Array[String]]) {
  let nodes : Array[String] = []
  for bind in prog.binds {
    match bind {
      NonRec(name, _) => nodes.push(name)
      Rec(pairs) => for pair in pairs {
        nodes.push(pair.0)
      }
    }
  }
  let adj : Array[Array[String]] = []
  for _i in nodes {
    adj.push([])
  }
  for bind in prog.binds {
    match bind {
      NonRec(name, expr) => {
        let calls : Array[String] = []
        scan_top_refs(expr, nodes, calls, [], false)
        adj[node_index(nodes, name)].clear()
        for c in calls {
          adj[node_index(nodes, name)].push(c)
        }
      }
      Rec(pairs) =>
        for pair in pairs {
          let calls : Array[String] = []
          scan_top_refs(pair.1, nodes, calls, [], false)
          adj[node_index(nodes, pair.0)].clear()
          for c in calls {
            adj[node_index(nodes, pair.0)].push(c)
          }
        }
    }
  }
  (nodes, adj)
}

fn node_index(nodes : Array[String], name : String) -> Int {
  match index_of_str(nodes, name) {
    Some(i) => i
    None => panic()
  }
}

///| Tarjan strongly connected components over the call graph.
fn tarjan_sccs(nodes : Array[String], adj : Array[Array[String]]) -> Array[Array[String]] {
  let n = nodes.length()
  let index_arr : Array[Int] = []
  let low_arr : Array[Int] = []
  let on_stack : Array[Bool] = []
  for _i in 0..<n {
    index_arr.push(-1)
    low_arr.push(-1)
    on_stack.push(false)
  }
  let stack : Array[Int] = []
  let counter : Array[Int] = [0]
  let out : Array[Array[String]] = []
  for start = 0; start < n; start = start + 1 {
    if index_arr[start] == -1 {
      tarjan_dfs(
        start, nodes, adj, index_arr, low_arr, on_stack, stack, counter, out,
      )
    }
  }
  out
}

fn tarjan_dfs(
  v : Int,
  nodes : Array[String],
  adj : Array[Array[String]],
  index_arr : Array[Int],
  low_arr : Array[Int],
  on_stack : Array[Bool],
  stack : Array[Int],
  counter : Array[Int],
  out : Array[Array[String]]
) -> Unit {
  index_arr[v] = counter[0]
  low_arr[v] = counter[0]
  counter[0] = counter[0] + 1
  stack.push(v)
  on_stack[v] = true
  for w_name in adj[v] {
    let w = node_index(nodes, w_name)
    if index_arr[w] == -1 {
      tarjan_dfs(
        w, nodes, adj, index_arr, low_arr, on_stack, stack, counter, out,
      )
      if low_arr[w] < low_arr[v] {
        low_arr[v] = low_arr[w]
      }
    } else if on_stack[w] {
      if index_arr[w] < low_arr[v] {
        low_arr[v] = index_arr[w]
      }
    }
  }
  if low_arr[v] == index_arr[v] {
    let scc : Array[String] = []
    while stack.length() > 0 {
      let w = stack[stack.length() - 1]
      let _ignored = stack.pop()
      on_stack[w] = false
      scc.push(nodes[w])
      if w == v {
        break
      }
    }
    out.push(scc)
  }
}

///| A component repeats work only when it can run again: self-recursion or a
///| mutual-recursion cycle.
fn scc_is_cyclic(scc : Array[String], nodes : Array[String], adj : Array[Array[String]]) -> Bool {
  if scc.length() > 1 {
    return true
  }
  let v = node_index(nodes, scc[0])
  array_contains(adj[v], scc[0])
}

///| Rewrite every application chain whose head is in `targets` so the head is
///| applied to `insert` first.
fn extend_calls(
  expr : @syntax.Expr,
  targets : Array[String],
  insert : @syntax.Expr
) -> @syntax.Expr {
  match expr {
    App(_, _) => {
      let (head, args) = expr.unwind_app()
      let is_target = match head {
        Var(n) => args.length() > 0 && array_contains(targets, n)
        _ => false
      }
      if is_target {
        let mut chain : @syntax.Expr = App(head, insert)
        for arg in args {
          chain = App(chain, extend_calls(arg, targets, insert))
        }
        chain
      } else {
        let head2 = extend_calls(head, targets, insert)
        let mut chain : @syntax.Expr = head2
        for arg in args {
          chain = App(chain, extend_calls(arg, targets, insert))
        }
        chain
      }
    }
    Lam(p, body) => Lam(p, extend_calls(body, targets, insert))
    Let(bind, body) =>
      match bind {
        NonRec(n, v) =>
          Let(NonRec(n, extend_calls(v, targets, insert)), extend_calls(body, targets, insert))
        Rec(pairs) => {
          let new_pairs : Array[(String, @syntax.Expr)] = []
          for pair in pairs {
            new_pairs.push((pair.0, extend_calls(pair.1, targets, insert)))
          }
          Let(Rec(new_pairs), extend_calls(body, targets, insert))
        }
      }
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: extend_calls(alt.expr, targets, insert) })
      }
      Case(extend_calls(scrut, targets, insert), binder, new_alts)
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(extend_calls(a, targets, insert))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

///| Names no binding may shadow, for the threaded CAF parameter.
fn collect_all_binders(prog : @syntax.Program) -> Array[String] {
  let names : Array[String] = []
  for bind in prog.binds {
    match bind {
      NonRec(name, expr) => {
        names.push(name)
        collect_binders(expr, names)
      }
      Rec(pairs) =>
        for pair in pairs {
          names.push(pair.0)
          collect_binders(pair.1, names)
        }
    }
  }
  names
}

fn fresh_name(base : String, taken : Array[String]) -> String {
  let mut candidate = base
  let mut i = 0
  while array_contains(taken, candidate) {
    candidate = "\{base}_\{i}"
    i = i + 1
  }
  candidate
}

///| Is this binding worth threading? Only computed values pay off: re-running
///| a literal, an alias, or a lambda per iteration costs no recomputation.
fn caf_worth_sharing(expr : @syntax.Expr) -> Bool {
  match expr {
    Var(_) | LitInt(_) | LitChar(_) | LitString(_) => false
    Lam(_, _) => false
    Constr(_, args) => {
      let mut any = false
      for a in args {
        if caf_worth_sharing(a) {
          any = true
        }
      }
      any
    }
    App(_, _) | Let(_, _) | Case(_, _, _) => true
  }
}

///| A cycle member may only gain a parameter when every reference to it is a
///| call. A member passed as a value would change meaning at its application
///| site, so the whole cycle is left alone.
fn scc_members_called_only(
  prog : @syntax.Program,
  members : Array[String]
) -> Bool {
  let uses : Array[String] = []
  for bind in prog.binds {
    match bind {
      NonRec(_, expr) => scan_top_refs(expr, members, [], uses, false)
      Rec(pairs) =>
        for pair in pairs {
          scan_top_refs(pair.1, members, [], uses, false)
        }
    }
  }
  uses.length() == 0
}

///| Does any cycle member alias another binding (`D = Var(E)`)? Such a member
///| cannot receive a parameter.
fn scc_member_is_alias(prog : @syntax.Program, member : String) -> Bool {
  for bind in prog.binds {
    match bind {
      NonRec(name, expr) =>
        if name == member {
          match expr {
            Var(_) => return true
            _ => return false
          }
        }
      Rec(pairs) =>
        for pair in pairs {
          if pair.0 == member {
            match pair.1 {
              Var(_) => return true
              _ => return false
            }
          }
        }
    }
  }
  false
}

fn binding_expr(prog : @syntax.Program, member : String) -> @syntax.Expr? {
  for bind in prog.binds {
    match bind {
      NonRec(name, e) => if name == member { return Some(e) }
      Rec(pairs) =>
        for pair in pairs {
          if pair.0 == member { return Some(pair.1) }
        }
    }
  }
  None
}

///| Thread `caf` through the cycle `scc`: every member gains the CAF as a
///| leading parameter, internal recursive calls pass it on, and external
///| callers supply the CAF itself.
fn thread_one(
  prog : @syntax.Program,
  caf : String,
  scc : Array[String],
  stats : MidStats
) -> @syntax.Program {
  let taken = collect_all_binders(prog)
  let param = fresh_name("__mid_caf_" + caf, taken)
  let members : Array[String] = []
  for m in scc {
    members.push(m)
  }
  let new_binds : Array[@syntax.Bind] = []
  for bind in prog.binds {
    match bind {
      NonRec(name, expr) => {
        if array_contains(members, name) {
          let expr1 = @syntax.substitute_var(expr, caf, Var(param))
          let expr2 = extend_calls(expr1, members, Var(param))
          new_binds.push(NonRec(name, Lam(param, expr2)))
        } else {
          new_binds.push(NonRec(name, extend_calls(expr, members, Var(caf))))
        }
      }
      Rec(pairs) => {
        let new_pairs : Array[(String, @syntax.Expr)] = []
        for pair in pairs {
          if array_contains(members, pair.0) {
            let expr1 = @syntax.substitute_var(pair.1, caf, Var(param))
            let expr2 = extend_calls(expr1, members, Var(param))
            new_pairs.push((pair.0, Lam(param, expr2)))
          } else {
            new_pairs.push((pair.0, extend_calls(pair.1, members, Var(caf))))
          }
        }
        new_binds.push(Rec(new_pairs))
      }
    }
  }
  stats.cafs_threaded = stats.cafs_threaded + 1
  @syntax.Program::new(new_binds)
}

///| Run the sharing pass to a fixpoint: threading a cycle makes its external
///| callers reference the CAF, and a caller that is itself inside another loop
///| needs threading too.
pub fn thread_caf_sharing(prog : @syntax.Program, stats : MidStats) -> @syntax.Program {
  let mut current = prog
  let processed : Array[String] = []
  for _round = 0; _round < 3; _round = _round + 1 {
    let (nodes, adj) = build_call_graph(current)
    let sccs = tarjan_sccs(nodes, adj)
    let mut changed = false
    for scc in sccs {
      if !scc_is_cyclic(scc, nodes, adj) {
        continue
      }
      let mut skip = false
      for m in scc {
        if scc_member_is_alias(current, m) {
          skip = true
        }
      }
      if skip || !scc_members_called_only(current, scc) {
        continue
      }
      let refs : Array[String] = []
      for m in scc {
        match binding_expr(current, m) {
          Some(expr) => scan_top_refs(expr, nodes, refs, refs, false)
          None => ()
        }
      }
      for caf in refs {
        if array_contains(scc, caf) {
          continue
        }
        match binding_expr(current, caf) {
          Some(caf_expr) => {
            if !caf_worth_sharing(caf_expr) {
              continue
            }
          }
          None => continue
        }
        let key = caf + "|" + join_names(scc)
        if array_contains(processed, key) {
          continue
        }
        processed.push(key)
        current = thread_one(current, caf, scc, stats)
        changed = true
      }
    }
    if !changed {
      break
    }
  }
  current
}

fn join_names(names : Array[String]) -> String {
  let buf = StringBuilder()
  for i, n in names {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string(n)
  }
  buf.to_string()
}

fn array_contains(arr : Array[String], target : String) -> Bool {
  index_of_str(arr, target) is Some(_)
}

///| Run the middle-end. Passes run to a fixpoint so a reduction that exposes a
///| dead binding or a duplicate body is picked up in the same compile.
pub fn optimize(prog : @syntax.Program, stats : MidStats) -> @syntax.Program {
  let mut current = prune_top_bindings(prog, stats)
  current = thread_caf_sharing(current, stats)
  let counter : Array[Int] = [0]
  for pass = 0; pass < 3; pass = pass + 1 {
    let before = stats.dead_lets +
      stats.inlined_lets +
      stats.cases_reduced +
      stats.alts_merged +
      stats.binds_merged
    let new_binds : Array[@syntax.Bind] = []
    for bind in current.binds {
      match bind {
        NonRec(name, expr) => {
          let expr = prune_dead_lets(expr, stats)
          let expr = inline_trivial_lets(expr, stats)
          let expr = reduce_known_cases(expr, stats)
          let expr = merge_alt_bodies(expr, stats, counter)
          new_binds.push(NonRec(name, expr))
        }
        Rec(pairs) => {
          let new_pairs : Array[(String, @syntax.Expr)] = []
          for pair in pairs {
            let expr = prune_dead_lets(pair.1, stats)
            let expr = inline_trivial_lets(expr, stats)
            let expr = reduce_known_cases(expr, stats)
            let expr = merge_alt_bodies(expr, stats, counter)
            new_pairs.push((pair.0, expr))
          }
          new_binds.push(Rec(new_pairs))
        }
      }
    }
    current = merge_top_bindings(@syntax.Program::new(new_binds), stats)
    let after = stats.dead_lets +
      stats.inlined_lets +
      stats.cases_reduced +
      stats.alts_merged +
      stats.binds_merged
    if after == before {
      break
    }
  }
  current
}
