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
  mut readers_rebuilt : Int
  mut etas_reduced : Int
  mut constants_folded : Int
  mut dead_alts_pruned : Int
  mut unboxed_simplified : Int
  mut lets_pushed_down : Int
  mut known_calls_inlined : Int
  mut streams_fused : Int
  mut dups_sunk : Int
  mut supercompiled : Int
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
    readers_rebuilt: 0,
    etas_reduced: 0,
    constants_folded: 0,
    dead_alts_pruned: 0,
    unboxed_simplified: 0,
    lets_pushed_down: 0,
    known_calls_inlined: 0,
    streams_fused: 0,
    dups_sunk: 0,
    supercompiled: 0,
  }
}

pub impl Show for MidStats with output(self, logger) {
  logger.write_string(
    "dead lets \{self.dead_lets}, inlined lets \{self.inlined_lets}, cases reduced \{self.cases_reduced}, alternatives merged \{self.alts_merged}, binds merged \{self.binds_merged}, binds pruned \{self.binds_pruned}, cafs threaded \{self.cafs_threaded}, readers rebuilt \{self.readers_rebuilt}, etas reduced \{self.etas_reduced}, constants folded \{self.constants_folded}, dead alts pruned \{self.dead_alts_pruned}, unboxed simplified \{self.unboxed_simplified}, lets pushed down \{self.lets_pushed_down}, known calls inlined \{self.known_calls_inlined}, streams fused \{self.streams_fused}, dups sunk \{self.dups_sunk}, supercompiled \{self.supercompiled}",
  )
}

// ----------------------------------------------------------------------------
// Name use analysis
// ----------------------------------------------------------------------------

///| Does `expr` reference `name` outside of a binding that shadows it?
pub fn uses_name(expr : @syntax.Expr, name : String) -> Bool {
  match expr {
    Var(x) => x == name
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => false
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

///| Number of free occurrences of `name`, stopping at its binders.
fn count_name_uses(expr : @syntax.Expr, name : String) -> Int {
  match expr {
    Var(x) => if x == name { 1 } else { 0 }
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => 0
    App(f, a) => count_name_uses(f, name) + count_name_uses(a, name)
    Lam(p, body) => if p == name { 0 } else { count_name_uses(body, name) }
    Let(NonRec(n, v), body) =>
      count_name_uses(v, name) + (if n == name { 0 } else { count_name_uses(body, name) })
    Let(Rec(pairs), body) => {
      let mut total = 0
      let mut shadows = false
      for pair in pairs {
        if pair.0 == name {
          shadows = true
        } else {
          total = total + count_name_uses(pair.1, name)
        }
      }
      if shadows { total } else { total + count_name_uses(body, name) }
    }
    Case(scrut, binder, alts) => {
      let mut total = count_name_uses(scrut, name)
      for alt in alts {
        let mut shadows = binder == name
        match alt.pat {
          Default(Some(v)) => if v == name { shadows = true }
          Data(_, vars) => {
            for v in vars {
              if v == name {
                shadows = true
                break
              }
            }
          }
          _ => ()
        }
        if !shadows {
          total = total + count_name_uses(alt.expr, name)
        }
      }
      total
    }
    Constr(_, args) => {
      let mut total = 0
      for a in args {
        total = total + count_name_uses(a, name)
      }
      total
    }
  }
}

fn is_trivial_value(expr : @syntax.Expr) -> Bool {
  match expr {
    Var(_) | LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => true
    _ => false
  }
}

fn all_trivial_args(args : Array[@syntax.Expr]) -> Bool {
  for a in args {
    if !is_trivial_value(a) {
      return false
    }
  }
  true
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
    Var(_) | LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => ()
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
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => ()
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
    LitFloat(d) => buf.write_string("f\{d}")
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
      let inline_ok = match value {
        Var(_) | LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => true
        Constr(_, args) =>
          count_name_uses(body, name) <= 1 || all_trivial_args(args)
        _ => false
      }
      if inline_ok && !name.has_prefix("_caf_force_") {
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
      } else {
        Let(NonRec(name, value), body)
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

///| Constructor names this program actually matches on, plus the primitive
///| constructors the runtime answers. The parser classifies every
///| capitalized name as a constructor and a qualified GHC function name
///| (`GHC_Internal_Base__lt__gt_`) arrives looking exactly like one, so a
///| case reduction must check this set before treating a scrutinee as data.
pub fn collect_ctor_names(prog : @syntax.Program) -> Array[String] {
  let names : Array[String] = []
  fn add(name : String) -> Unit {
    if !names.contains(name) {
      names.push(name)
    }
  }
  for b in prog.all_bindings() {
    let stack : Array[@syntax.Expr] = [b.1]
    while stack.length() > 0 {
      match stack.pop() {
        Some(e) =>
          match e {
            Var(_) | LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => ()
            App(f, a) => {
              stack.push(f)
              stack.push(a)
            }
            Lam(_, body) => stack.push(body)
            Let(bind, body) => {
              match bind {
                NonRec(_, v) => stack.push(v)
                Rec(pairs) => for p in pairs { stack.push(p.1) }
              }
              stack.push(body)
            }
            Case(_, _, alts) => {
              for alt in alts {
                match alt.pat {
                  Data(c, _) => add(c)
                  _ => ()
                }
                stack.push(alt.expr)
              }
            }
            Constr(c, args) => {
              add(c)
              for a in args {
                stack.push(a)
              }
            }
          }
        None => ()
      }
    }
  }
  for prim in [
      "I#", "D#", "C#", "W#", "W8#", "W16#", "W32#", "W64#", "I8#", "I16#",
      "I32#", "I64#", "True", "False", "LT", "EQ", "GT", "[]", "(:)",
      "()", "(##)", "(# #)", "(,)", "(,,)", "(,,,)", "(,,,,)", "(,,,,,)",
    ] {
    add(prim)
  }
  names
}

///| Substitute the case binder, when the body uses it; refuse instead of
///| renaming, exactly like every other substitution here.
fn reduce_with_binder(
  body : @syntax.Expr,
  binder : String,
  scrut : @syntax.Expr,
) -> @syntax.Expr? {
  if binder == "" || binder == "_" || !uses_name(body, binder) {
    return Some(body)
  }
  substitute_without_capture(body, binder, scrut)
}

pub fn reduce_known_cases(
  expr : @syntax.Expr,
  stats : MidStats,
  ctor_names : Array[String],
) -> @syntax.Expr {
  match expr {
    Case(scrut, binder, alts) => {
      let scrut = reduce_known_cases(scrut, stats, ctor_names)
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({
          pat: alt.pat,
          expr: reduce_known_cases(alt.expr, stats, ctor_names),
        })
      }
      match scrut {
        Constr(c, args) => {
          let norm = @syntax.normalize_ctor_name(c)
          if !ctor_names.contains(norm) {
            return Case(scrut, binder, new_alts)
          }
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
                  match reduce_with_binder(body, binder, scrut) {
                    Some(next) => {
                      stats.cases_reduced = stats.cases_reduced + 1
                      return next
                    }
                    None => return Case(scrut, binder, new_alts)
                  }
                }
                return Case(scrut, binder, new_alts)
              }
              _ => ()
            }
          }
          // No alternative matches: the case can only reach its default, and
          // the case binder stands for the scrutinee.
          for alt in new_alts {
            match alt.pat {
              Default(_) =>
                match reduce_with_binder(alt.expr, binder, scrut) {
                  Some(next) => {
                    stats.cases_reduced = stats.cases_reduced + 1
                    return next
                  }
                  None => return Case(scrut, binder, new_alts)
                }
              _ => ()
            }
          }
          Case(scrut, binder, new_alts)
        }
        LitInt(n) => {
          for alt in new_alts {
            match alt.pat {
              Lit(k) if k == n =>
                match reduce_with_binder(alt.expr, binder, scrut) {
                  Some(next) => {
                    stats.cases_reduced = stats.cases_reduced + 1
                    return next
                  }
                  None => return Case(scrut, binder, new_alts)
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
              Default(None) =>
                match reduce_with_binder(alt.expr, binder, scrut) {
                  Some(next) => {
                    stats.cases_reduced = stats.cases_reduced + 1
                    return next
                  }
                  None => return Case(scrut, binder, new_alts)
                }
              _ => ()
            }
          }
          Case(scrut, binder, new_alts)
        }
        _ => Case(scrut, binder, new_alts)
      }
    }
    App(f, a) =>
      App(
        reduce_known_cases(f, stats, ctor_names),
        reduce_known_cases(a, stats, ctor_names),
      )
    Lam(p, body) => Lam(p, reduce_known_cases(body, stats, ctor_names))
    Let(NonRec(n, v), body) =>
      Let(
        NonRec(n, reduce_known_cases(v, stats, ctor_names)),
        reduce_known_cases(body, stats, ctor_names),
      )
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, reduce_known_cases(pair.1, stats, ctor_names)))
      }
      Let(Rec(new_pairs), reduce_known_cases(body, stats, ctor_names))
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(reduce_known_cases(a, stats, ctor_names))
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
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => ()
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
    Var(_) | LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => false
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


// ----------------------------------------------------------------------------
// Rebuild-shared-reads pass
// ----------------------------------------------------------------------------

///| A threaded CAF's wire is consumed destructively by every reader: the case
///| selector annihilates the Scott cells, so each reader needs its own copy and
///| the per-iteration DUP split of the CAF degrades into a growing SUP chain
///| whose crossings clone whole subtrees. The fix is to make the reader put the
///| structure back: the reader returns ``Pair result rebuilt`` and the loop
///| threads the rebuilt structure, which is freshly allocated and therefore
///| singly referenced -- no DUP on the structure's wire at any point.

///| A reader call site found in a threaded cycle member's body.
priv struct ReaderCallSite {
  fn_name : String
  arg_pos : Int
  args : Array[@syntax.Expr]
}

///| Unwinds a nested single-parameter lambda chain into its parameter list and
///| the innermost body.
fn unwind_reader_lams(expr : @syntax.Expr) -> (Array[String], @syntax.Expr) {
  let params : Array[String] = []
  let mut cur = expr
  while true {
    match cur {
      Lam(p, rest) => {
        params.push(p)
        cur = rest
      }
      _ => break
    }
  }
  (params, cur)
}

///| Reads of `name` in `expr` that no lambda, let or pattern binder shadows.
fn param_uses(expr : @syntax.Expr, name : String) -> Int {
  match expr {
    Var(x) => if x == name { 1 } else { 0 }
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => 0
    App(f, a) => param_uses(f, name) + param_uses(a, name)
    Lam(p, body) => if p == name { 0 } else { param_uses(body, name) }
    Let(NonRec(n, v), body) =>
      if n == name {
        0
      } else {
        param_uses(v, name) + param_uses(body, name)
      }
    Let(Rec(pairs), body) => {
      for p in pairs {
        if p.0 == name {
          return 0
        }
      }
      let mut total = param_uses(body, name)
      for p in pairs {
        total = total + param_uses(p.1, name)
      }
      total
    }
    Case(scrut, binder, alts) => {
      let mut total = param_uses(scrut, name)
      for alt in alts {
        let mut shadows = binder == name
        match alt.pat {
          Default(Some(v)) => if v == name { shadows = true }
          Data(_, vars) =>
            for v in vars {
              if v == name {
                shadows = true
              }
            }
          _ => ()
        }
        if !shadows {
          total = total + param_uses(alt.expr, name)
        }
      }
      total
    }
    Constr(_, args) => {
      let mut total = 0
      for a in args {
        total = total + param_uses(a, name)
      }
      total
    }
  }
}

///| Does `expr` apply `fn_name` anywhere?
fn calls_fn(expr : @syntax.Expr, fn_name : String) -> Bool {
  match expr {
    App(_, _) => {
      let (head, args) = expr.unwind_app()
      let mut hit = false
      match head {
        Var(n) => if n == fn_name { hit = true }
        _ => ()
      }
      if hit {
        return true
      }
      if calls_fn(head, fn_name) {
        return true
      }
      for a in args {
        if calls_fn(a, fn_name) {
          return true
        }
      }
      false
    }
    Lam(_, body) => calls_fn(body, fn_name)
    Let(bind, body) =>
      match bind {
        NonRec(_, v) => calls_fn(v, fn_name) || calls_fn(body, fn_name)
        Rec(pairs) => {
          for p in pairs {
            if calls_fn(p.1, fn_name) {
              return true
            }
          }
          calls_fn(body, fn_name)
        }
      }
    Case(scrut, _, alts) => {
      if calls_fn(scrut, fn_name) {
        return true
      }
      for alt in alts {
        if calls_fn(alt.expr, fn_name) {
          return true
        }
      }
      false
    }
    Constr(_, args) => {
      for a in args {
        if calls_fn(a, fn_name) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///| A direct application handing the threaded CAF parameter to a function of
///| matching arity. The member's own self-calls are not readers.
fn reader_call_site(
  expr : @syntax.Expr,
  param : String,
  member : String,
  prog : @syntax.Program
) -> ReaderCallSite? {
  match expr {
    App(_, _) => {
      let (head, args) = expr.unwind_app()
      match head {
        Var(n) =>
          if n != member && args.length() > 0 {
            for i, a in args {
              match a {
                Var(v) =>
                  if v == param {
                    match prog.lookup(n) {
                      Some(fexpr) => {
                        let (fparams, _) = unwind_reader_lams(fexpr)
                        if fparams.length() == args.length() {
                          return Some({ fn_name: n, arg_pos: i, args })
                        }
                      }
                      _ => ()
                    }
                  }
                _ => ()
              }
            }
          }
        _ => ()
      }
      None
    }
    _ => None
  }
}

///| Rewrites one reader alternative body into an expression evaluating to
///| `(result, node rebuilt from the recursive reads)`. A branch that reads no
///| child returns the node unchanged, so exactly one pair is produced per path.
fn rb_pair(
  expr : @syntax.Expr,
  ctor : String,
  vars : Array[String],
  fn_name : String,
  twin : String,
  read_pos : Int,
  taken : Array[String]
) -> Option[@syntax.Expr] {
  match expr {
    App(_, _) => {
      let (head, args) = expr.unwind_app()
      let mut is_self = false
      match head {
        Var(n) => if n == fn_name { is_self = true }
        _ => ()
      }
      if !is_self {
        return None
      }
      if args.length() <= read_pos {
        return None
      }
      match args[read_pos] {
        Var(v) =>
          match index_of_str(vars, v) {
            Some(j) => {
              let y = fresh_name(fn_name + "_rbres", taken)
              taken.push(y)
              let m = fresh_name(fn_name + "_rbmap", taken)
              taken.push(m)
              let call_args : Array[@syntax.Expr] = []
              for a in args {
                call_args.push(a)
              }
              let call = @syntax.Expr::apps(Var(twin), call_args)
              let fields : Array[@syntax.Expr] = []
              for i, f in vars {
                if i == j {
                  fields.push(Var(m))
                } else {
                  fields.push(Var(f))
                }
              }
              let rebuilt = @syntax.Constr(ctor, fields)
              let pair = @syntax.Constr("(,)", [Var(y), rebuilt])
              Some(@syntax.Case(call, "", [@syntax.Alt::data("(,)", [y, m], pair)]))
            }
            None => None
          }
        _ => None
      }
    }
    Case(scrut, binder, alts) => {
      if calls_fn(scrut, fn_name) {
        return None
      }
      if binder.length() > 0 {
        for v in vars {
          if v == binder {
            return None
          }
        }
      }
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        match rb_pair(alt.expr, ctor, vars, fn_name, twin, read_pos, taken) {
          Some(e) => new_alts.push(@syntax.Alt::new(alt.pat, e))
          None => return None
        }
      }
      Some(@syntax.Case(scrut, binder, new_alts))
    }
    _ =>
      if calls_fn(expr, fn_name) {
        None
      } else {
        let fields : Array[@syntax.Expr] = []
        for f in vars {
          fields.push(Var(f))
        }
        Some(@syntax.Constr("(,)", [expr, @syntax.Constr(ctor, fields)]))
      }
  }
}

///| Builds the pair-returning twin of the reader `fn_name`: same parameters, and
///| each alternative returns `(result, node)`. `None` when the reader's shape
///| cannot carry a rebuilt node.
fn build_reader_twin(
  prog : @syntax.Program,
  taken : Array[String],
  fn_name : String,
  arg_pos : Int
) -> (String, @syntax.Expr)? {
  match prog.lookup(fn_name) {
    Some(fexpr) => {
      let (params, body) = unwind_reader_lams(fexpr)
      if arg_pos >= params.length() {
        return None
      }
      let s = params[arg_pos]
      match body {
        Case(scrut, binder, alts) => {
          let x : String = match scrut {
            Var(v) => v
            _ => return None
          }
          if !(x == s && alts.length() >= 2) {
            return None
          }
          let twin = fresh_name(fn_name + "_rb", taken)
          taken.push(twin)
          let new_alts : Array[@syntax.Alt] = []
          for alt in alts {
            match alt.pat {
              Data(ctor, vars) =>
                match rb_pair(alt.expr, ctor, vars, fn_name, twin, arg_pos, taken) {
                  Some(e) => new_alts.push(@syntax.Alt::data(ctor, vars, e))
                  None => return None
                }
              _ => return None
            }
          }
          let twin_body = @syntax.Case(@syntax.Var(x), binder, new_alts)
          Some((twin, @syntax.Expr::lams(params, twin_body)))
        }
        _ => None
      }
    }
    _ => None
  }
}

///| Rewrites the `case` the reader call feeds: the twin takes the same arguments,
///| its pair is destructured, and the body continues with the rebuilt node in
///| place of the threaded parameter.
fn wrap_reader_case(
  site : ReaderCallSite,
  binder : String,
  alts : Array[@syntax.Alt],
  param : String,
  prog : @syntax.Program,
  taken : Array[String],
  twins : Map[String, String],
  twin_defs : Array[(String, @syntax.Expr)]
) -> Option[@syntax.Expr] {
  let twin = match twins.get(site.fn_name) {
    Some(t) => t
    None =>
      match build_reader_twin(prog, taken, site.fn_name, site.arg_pos) {
        Some((name, def)) => {
          twins[site.fn_name] = name
          twin_defs.push((name, def))
          name
        }
        None => return None
      }
  }
  let y = fresh_name(site.fn_name + "_rbres", taken)
  taken.push(y)
  let m = fresh_name(site.fn_name + "_rbmap", taken)
  taken.push(m)
  let call = @syntax.Expr::apps(Var(twin), site.args)
  let inner_alts : Array[@syntax.Alt] = []
  for alt in alts {
    let body = @syntax.substitute_var(alt.expr, param, Var(m))
    inner_alts.push(@syntax.Alt::new(alt.pat, body))
  }
  let inner = @syntax.Case(Var(y), binder, inner_alts)
  Some(@syntax.Case(call, "", [@syntax.Alt::data("(,)", [y, m], inner)]))
}

///| Finds the `case` the reader call feeds and wraps it. The wrap goes at the
///| innermost point that still holds every read of the threaded parameter, so the
///| rebuilt node is in scope everywhere the old one was.
fn rewrite_member_body(
  expr : @syntax.Expr,
  param : String,
  member : String,
  prog : @syntax.Program,
  taken : Array[String],
  twins : Map[String, String],
  twin_defs : Array[(String, @syntax.Expr)],
  root_uses : Int
) -> Option[@syntax.Expr] {
  match expr {
    Case(scrut, binder, alts) => {
      let mut inside = param_uses(scrut, param)
      for alt in alts {
        inside = inside + param_uses(alt.expr, param)
      }
      if inside == root_uses {
        match reader_call_site(scrut, param, member, prog) {
          Some(site) =>
            return wrap_reader_case(
              site, binder, alts, param, prog, taken, twins, twin_defs,
            )
          None => ()
        }
      }
      match rewrite_member_body(
        scrut, param, member, prog, taken, twins, twin_defs, root_uses,
      ) {
        Some(s2) => return Some(@syntax.Case(s2, binder, alts))
        None => ()
      }
      let new_alts : Array[@syntax.Alt] = []
      let mut changed = false
      for alt in alts {
        match rewrite_member_body(
          alt.expr, param, member, prog, taken, twins, twin_defs, root_uses,
        ) {
          Some(e2) => {
            new_alts.push(@syntax.Alt::new(alt.pat, e2))
            changed = true
          }
          None => new_alts.push(alt)
        }
      }
      if changed {
        Some(@syntax.Case(scrut, binder, new_alts))
      } else {
        None
      }
    }
    Lam(p, body) => {
      if p == param {
        return None
      }
      match rewrite_member_body(
        body, param, member, prog, taken, twins, twin_defs, root_uses,
      ) {
        Some(b2) => Some(Lam(p, b2))
        None => None
      }
    }
    Let(NonRec(n, v), body) => {
      if n == param {
        return None
      }
      match rewrite_member_body(v, param, member, prog, taken, twins, twin_defs, root_uses) {
        Some(v2) => return Some(Let(NonRec(n, v2), body))
        None => ()
      }
      match rewrite_member_body(
        body, param, member, prog, taken, twins, twin_defs, root_uses,
      ) {
        Some(b2) => Some(Let(NonRec(n, v), b2))
        None => None
      }
    }
    Let(Rec(pairs), body) => {
      for p in pairs {
        if p.0 == param {
          return None
        }
      }
      let new_pairs : Array[(String, @syntax.Expr)] = []
      let mut changed = false
      for p in pairs {
        match rewrite_member_body(
          p.1, param, member, prog, taken, twins, twin_defs, root_uses,
        ) {
          Some(v2) => {
            new_pairs.push((p.0, v2))
            changed = true
          }
          None => new_pairs.push(p)
        }
      }
      if changed {
        return Some(Let(Rec(new_pairs), body))
      }
      match rewrite_member_body(
        body, param, member, prog, taken, twins, twin_defs, root_uses,
      ) {
        Some(b2) => Some(Let(Rec(pairs), b2))
        None => None
      }
    }
    _ => None
  }
}

///| The rebuild-shared-reads pass. Runs after ``thread_caf_sharing``: for a cycle
///| member carrying a threaded CAF parameter, the call that hands the parameter
///| to a reader is redirected to a pair-returning twin, and the member threads
///| the node the twin rebuilt. The CAF wire is read exactly once.
pub fn rebuild_shared_reads(
  prog : @syntax.Program,
  stats : MidStats
) -> @syntax.Program {
  let taken = collect_all_binders(prog)
  let twins : Map[String, String] = Map([])
  let twin_defs : Array[(String, @syntax.Expr)] = []
  let new_binds : Array[@syntax.Bind] = []
  for bind in prog.binds {
    match bind {
      NonRec(name, expr) =>
        match rebuild_member(expr, name, prog, taken, twins, twin_defs) {
          Some(expr2) => new_binds.push(NonRec(name, expr2))
          None => new_binds.push(bind)
        }
      Rec(pairs) => {
        let new_pairs : Array[(String, @syntax.Expr)] = []
        for pair in pairs {
          match rebuild_member(pair.1, pair.0, prog, taken, twins, twin_defs) {
            Some(expr2) => new_pairs.push((pair.0, expr2))
            None => new_pairs.push(pair)
          }
        }
        new_binds.push(Rec(new_pairs))
      }
    }
  }
  if twin_defs.length() > 0 {
    new_binds.push(Rec(twin_defs))
    stats.readers_rebuilt = stats.readers_rebuilt + twin_defs.length()
  }
  @syntax.Program::new(new_binds)
}

///| Rewrites one cycle member's body around the reader call that consumes its
///| threaded CAF parameter.
fn rebuild_member(
  expr : @syntax.Expr,
  member : String,
  prog : @syntax.Program,
  taken : Array[String],
  twins : Map[String, String],
  twin_defs : Array[(String, @syntax.Expr)]
) -> Option[@syntax.Expr] {
  match expr {
    Lam(param, body) =>
      if param.has_prefix("__mid_caf_") {
        let root_uses = param_uses(body, param)
        if root_uses > 0 {
          match rewrite_member_body(body, param, member, prog, taken, twins, twin_defs, root_uses) {
            Some(b2) => Some(Lam(param, b2))
            None => None
          }
        } else {
          None
        }
      } else {
        None
      }
    _ => None
  }
}

// ----------------------------------------------------------------------------
// Eta reduction
// ----------------------------------------------------------------------------

///| `\x -> f x` is `f` when `x` is not free in `f`. Removing the wrapper avoids
///| one closure and one call spine at lowering; both backends are pure, so this
///| is semantics-preserving.
fn eta_reduce(expr : @syntax.Expr, stats : MidStats) -> @syntax.Expr {
  match expr {
    Var(_) | LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => expr
    App(f, a) => App(eta_reduce(f, stats), eta_reduce(a, stats))
    Lam(p, body) => {
      let body = eta_reduce(body, stats)
      match body {
        App(f, Var(x)) =>
          if x == p && !uses_name(f, p) {
            stats.etas_reduced = stats.etas_reduced + 1
            eta_reduce(f, stats)
          } else {
            Lam(p, body)
          }
        _ => Lam(p, body)
      }
    }
    Let(bind, body) =>
      match bind {
        NonRec(n, v) => Let(NonRec(n, eta_reduce(v, stats)), eta_reduce(body, stats))
        Rec(pairs) => {
          let new_pairs : Array[(String, @syntax.Expr)] = []
          for pair in pairs {
            new_pairs.push((pair.0, eta_reduce(pair.1, stats)))
          }
          Let(Rec(new_pairs), eta_reduce(body, stats))
        }
      }
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: eta_reduce(alt.expr, stats) })
      }
      Case(eta_reduce(scrut, stats), binder, new_alts)
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(eta_reduce(a, stats))
      }
      Constr(c, new_args)
    }
  }
}

// ----------------------------------------------------------------------------
// Pass: Constant folding
// ----------------------------------------------------------------------------

///| Fold applications of known primops on literal arguments to their result.
///| `+ 2# 3#` becomes `5#`, `* 4# 0#` becomes `0#`, etc.  Only folds when both
///| operands are `LitInt`; refuses division by zero.
pub fn fold_constants(expr : @syntax.Expr, stats : MidStats) -> @syntax.Expr {
  match expr {
    App(App(Var(op), LitInt(a)), LitInt(b)) => {
      let result : Int? = match op {
        "+" | "+#" => Some(a + b)
        "-" | "-#" => Some(a - b)
        "*" | "*#" => Some(a * b)
        "/" | "/#" => if b != 0 { Some(a / b) } else { None }
        "%" | "%#" => if b != 0 { Some(a % b) } else { None }
        "==" | "==#" => Some(if a == b { 1 } else { 0 })
        "/=" | "/=#" => Some(if a != b { 1 } else { 0 })
        "<" | "<#" => Some(if a < b { 1 } else { 0 })
        ">" | ">#" => Some(if a > b { 1 } else { 0 })
        "<=" | "<=#" => Some(if a <= b { 1 } else { 0 })
        ">=" | ">=#" => Some(if a >= b { 1 } else { 0 })
        "&" | "and#" => Some(a.land(b))
        "|" | "or#" => Some(a.lor(b))
        "^" | "xor#" => Some(a.lxor(b))
        "<<" | "uncheckedIShiftL#" => Some(a << b)
        ">>" | "uncheckedIShiftRA#" | "uncheckedIShiftRL#" => Some(a >> b)
        _ => None
      }
      match result {
        Some(v) => {
          stats.constants_folded = stats.constants_folded + 1
          LitInt(v)
        }
        None => App(App(Var(op), LitInt(a)), fold_constants(LitInt(b), stats))
      }
    }
    App(f, a) => App(fold_constants(f, stats), fold_constants(a, stats))
    Lam(p, body) => Lam(p, fold_constants(body, stats))
    Let(NonRec(n, v), body) =>
      Let(NonRec(n, fold_constants(v, stats)), fold_constants(body, stats))
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, fold_constants(pair.1, stats)))
      }
      Let(Rec(new_pairs), fold_constants(body, stats))
    }
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: fold_constants(alt.expr, stats) })
      }
      Case(fold_constants(scrut, stats), binder, new_alts)
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(fold_constants(a, stats))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

// ----------------------------------------------------------------------------
// Pass: Dead constructor branch pruning
// ----------------------------------------------------------------------------

///| When a case scrutinises a known constructor, prune the alternative branches
///| that provably cannot match.  This reduces the number of nets the lowerer
///| emits for the remaining alternatives.  Unlike `reduce_known_cases`, which
///| collapses the whole case, this pass keeps the case but drops dead branches.
pub fn prune_dead_alts(
  expr : @syntax.Expr,
  stats : MidStats,
  ctor_names : Array[String]
) -> @syntax.Expr {
  match expr {
    Case(scrut, binder, alts) => {
      let scrut = prune_dead_alts(scrut, stats, ctor_names)
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({
          pat: alt.pat,
          expr: prune_dead_alts(alt.expr, stats, ctor_names),
        })
      }
      // When the scrutinee is a known constructor, only keep the matching alt
      // and the default.  reduce_known_cases already handled exact reduction;
      // this catches the case where substitution was refused.
      match scrut {
        Constr(c, _) => {
          let norm = @syntax.normalize_ctor_name(c)
          if ctor_names.contains(norm) && new_alts.length() > 1 {
            let kept : Array[@syntax.Alt] = []
            for alt in new_alts {
              match alt.pat {
                Data(pc, _) =>
                  if @syntax.normalize_ctor_name(pc) == norm {
                    kept.push(alt)
                  } else {
                    stats.dead_alts_pruned = stats.dead_alts_pruned + 1
                  }
                Default(_) => kept.push(alt)
                Lit(_) => {
                  stats.dead_alts_pruned = stats.dead_alts_pruned + 1
                }
              }
            }
            if kept.length() > 0 && kept.length() < new_alts.length() {
              return Case(scrut, binder, kept)
            }
          }
        }
        LitInt(n) => {
          if new_alts.length() > 1 {
            let kept : Array[@syntax.Alt] = []
            for alt in new_alts {
              match alt.pat {
                Lit(k) =>
                  if k == n {
                    kept.push(alt)
                  } else {
                    stats.dead_alts_pruned = stats.dead_alts_pruned + 1
                  }
                Default(_) => kept.push(alt)
                Data(_, _) => {
                  stats.dead_alts_pruned = stats.dead_alts_pruned + 1
                }
              }
            }
            if kept.length() > 0 && kept.length() < new_alts.length() {
              return Case(scrut, binder, kept)
            }
          }
        }
        _ => ()
      }
      Case(scrut, binder, new_alts)
    }
    App(f, a) =>
      App(
        prune_dead_alts(f, stats, ctor_names),
        prune_dead_alts(a, stats, ctor_names),
      )
    Lam(p, body) => Lam(p, prune_dead_alts(body, stats, ctor_names))
    Let(NonRec(n, v), body) =>
      Let(
        NonRec(n, prune_dead_alts(v, stats, ctor_names)),
        prune_dead_alts(body, stats, ctor_names),
      )
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, prune_dead_alts(pair.1, stats, ctor_names)))
      }
      Let(Rec(new_pairs), prune_dead_alts(body, stats, ctor_names))
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(prune_dead_alts(a, stats, ctor_names))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

// ----------------------------------------------------------------------------
// Pass: Unboxed constructor simplification (Worker-Wrapper)
// ----------------------------------------------------------------------------

///| Simplify redundant unboxed constructor wrapping/unwrapping patterns.
///|
///| Pattern 1: `case (I# x) of { I# y -> body }` => `body[y := x]`
///| When a constructor is immediately cased on the same constructor, the
///| wrapping is redundant.
///|
///| Pattern 2: `Constr(C, [case e of { C x -> x }])` for single-field unboxed
///| constructors — the wrap-unwrap cancels out when `C` is an identity wrapper.
pub fn simplify_unboxed(
  expr : @syntax.Expr,
  stats : MidStats,
  ctor_names : Array[String]
) -> @syntax.Expr {
  match expr {
    // Pattern 1: case (Constr C args) of { C vars -> body } -- cancel wrap/unwrap
    Case(Constr(c, args), binder, alts) => {
      let norm = @syntax.normalize_ctor_name(c)
      if ctor_names.contains(norm) && @syntax.is_unboxed_ctor(c) && alts.length() == 1 {
        match alts[0].pat {
          Data(pc, vars) =>
            if @syntax.normalize_ctor_name(pc) == norm && vars.length() == args.length() {
              let mut body = simplify_unboxed(alts[0].expr, stats, ctor_names)
              let mut ok = true
              for i, v in vars {
                match substitute_without_capture(body, v, simplify_unboxed(args[i], stats, ctor_names)) {
                  Some(next) => body = next
                  None => { ok = false; break }
                }
              }
              if ok {
                match reduce_with_binder(body, binder, Constr(c, args)) {
                  Some(result) => {
                    stats.unboxed_simplified = stats.unboxed_simplified + 1
                    return result
                  }
                  None => ()
                }
              }
            }
          _ => ()
        }
      }
      let new_scrut = simplify_unboxed(Constr(c, args), stats, ctor_names)
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: simplify_unboxed(alt.expr, stats, ctor_names) })
      }
      Case(new_scrut, binder, new_alts)
    }
    // Pattern 2: Float let out of case scrutinee: case (let n = v in inner) of alts => let n = v in (case inner of alts)
    Case(Let(NonRec(n, v), inner_scrut), binder, alts) => {
      let case_inner : @syntax.Expr = Case(inner_scrut, binder, alts)
      let binders = binder_names(case_inner)
      if !binders.contains(n) && binder != n {
        let frees = free_names(v)
        let mut clashing = false
        for f in frees {
          if binders.contains(f) {
            clashing = true
            break
          }
        }
        if !clashing {
          stats.unboxed_simplified = stats.unboxed_simplified + 1
          return simplify_unboxed(Let(NonRec(n, v), case_inner), stats, ctor_names)
        }
      }
      let new_scrut = simplify_unboxed(Let(NonRec(n, v), inner_scrut), stats, ctor_names)
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: simplify_unboxed(alt.expr, stats, ctor_names) })
      }
      Case(new_scrut, binder, new_alts)
    }
    // Pattern 3: Case-of-identity: case x of { C vars -> C vars } => x for single unboxed constructor
    Case(scrut, binder, alts) => {
      if alts.length() == 1 {
        match alts[0].pat {
          Data(pc, vars) => {
            let norm = @syntax.normalize_ctor_name(pc)
            if @syntax.is_unboxed_ctor(pc) {
              match alts[0].expr {
                Constr(c2, cargs) if @syntax.normalize_ctor_name(c2) == norm && cargs.length() == vars.length() => {
                  let mut is_id = true
                  for i, v in vars {
                    match cargs[i] {
                      Var(cv) => if cv != v { is_id = false; break }
                      _ => { is_id = false; break }
                    }
                  }
                  if is_id {
                    stats.unboxed_simplified = stats.unboxed_simplified + 1
                    return simplify_unboxed(scrut, stats, ctor_names)
                  }
                }
                _ => ()
              }
            }
          }
          _ => ()
        }
      }
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: simplify_unboxed(alt.expr, stats, ctor_names) })
      }
      Case(simplify_unboxed(scrut, stats, ctor_names), binder, new_alts)
    }
    App(f, a) => App(simplify_unboxed(f, stats, ctor_names), simplify_unboxed(a, stats, ctor_names))
    Lam(p, body) => Lam(p, simplify_unboxed(body, stats, ctor_names))
    Let(NonRec(n, v), body) =>
      Let(NonRec(n, simplify_unboxed(v, stats, ctor_names)), simplify_unboxed(body, stats, ctor_names))
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, simplify_unboxed(pair.1, stats, ctor_names)))
      }
      Let(Rec(new_pairs), simplify_unboxed(body, stats, ctor_names))
    }
    // Pattern 4: Constr(C, [Case(e, _, [Alt { pat: Data(C, [x]), expr: Var(x) }])]) => e
    Constr(c, args) => {
      let norm = @syntax.normalize_ctor_name(c)
      if @syntax.is_unboxed_ctor(c) && args.length() == 1 {
        match args[0] {
          Case(inner_e, _, alts) if alts.length() == 1 => {
            match alts[0].pat {
              Data(pc, vars) if @syntax.normalize_ctor_name(pc) == norm && vars.length() == 1 => {
                match alts[0].expr {
                  Var(vx) if vx == vars[0] => {
                    stats.unboxed_simplified = stats.unboxed_simplified + 1
                    return simplify_unboxed(inner_e, stats, ctor_names)
                  }
                  _ => ()
                }
              }
              _ => ()
            }
          }
          _ => ()
        }
      }
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(simplify_unboxed(a, stats, ctor_names))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

// ----------------------------------------------------------------------------
// Pass: Let push-down (DUP minimisation)
// ----------------------------------------------------------------------------

///| Push a `let` binding into only the case branch that uses it. When a binding
///| is used in one of several alternatives, keeping it outside the case forces
///| the lowerer to DUP the wire across all branches; pushing it into the single
///| branch that needs it eliminates the DUP entirely.
pub fn push_let_into_case(expr : @syntax.Expr, stats : MidStats) -> @syntax.Expr {
  match expr {
    Let(NonRec(name, value), Case(scrut, binder, alts)) => {
      // Don't push if the scrutinee uses the name -- we'd change evaluation order
      if uses_name(scrut, name) {
        return Let(
          NonRec(name, push_let_into_case(value, stats)),
          Case(push_let_into_case(scrut, stats), binder, {
            let new_alts : Array[@syntax.Alt] = []
            for alt in alts {
              new_alts.push({ pat: alt.pat, expr: push_let_into_case(alt.expr, stats) })
            }
            new_alts
          }),
        )
      }
      // Count which alternatives use the binding
      let mut use_count = 0
      for alt in alts {
        let shadowed = {
          let binders = alt_binders(alt, binder)
          binders.contains(name)
        }
        if !shadowed && uses_name(alt.expr, name) {
          use_count = use_count + 1
        }
      }
      // Push only when exactly one alternative uses the binding
      if use_count == 1 {
        stats.lets_pushed_down = stats.lets_pushed_down + 1
        let new_alts : Array[@syntax.Alt] = []
        for alt in alts {
          let shadowed = {
            let binders = alt_binders(alt, binder)
            binders.contains(name)
          }
          if !shadowed && uses_name(alt.expr, name) {
            new_alts.push({
              pat: alt.pat,
              expr: push_let_into_case(
                Let(NonRec(name, value), alt.expr),
                stats,
              ),
            })
          } else {
            new_alts.push({ pat: alt.pat, expr: push_let_into_case(alt.expr, stats) })
          }
        }
        Case(push_let_into_case(scrut, stats), binder, new_alts)
      } else {
        Let(
          NonRec(name, push_let_into_case(value, stats)),
          push_let_into_case(Case(scrut, binder, alts), stats),
        )
      }
    }
    Let(NonRec(n, v), body) =>
      Let(NonRec(n, push_let_into_case(v, stats)), push_let_into_case(body, stats))
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, push_let_into_case(pair.1, stats)))
      }
      Let(Rec(new_pairs), push_let_into_case(body, stats))
    }
    App(f, a) => App(push_let_into_case(f, stats), push_let_into_case(a, stats))
    Lam(p, body) => Lam(p, push_let_into_case(body, stats))
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: push_let_into_case(alt.expr, stats) })
      }
      Case(push_let_into_case(scrut, stats), binder, new_alts)
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(push_let_into_case(a, stats))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

// ----------------------------------------------------------------------------
// Pass: Inline known calls (small non-recursive let bindings used once)
// ----------------------------------------------------------------------------

///| Inline a `let`-bound expression when it is used exactly once and is "small"
///| (a constructor application, a single application, a lambda wrapping a small
///| body).  This eliminates the indirection node the lowerer would otherwise
///| create.  Differs from `inline_trivial_lets` in that the value need not be
///| trivial — it must be small and used exactly once.
fn expr_size(expr : @syntax.Expr) -> Int {
  match expr {
    Var(_) | LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => 1
    App(f, a) => expr_size(f) + expr_size(a)
    Lam(_, body) => 1 + expr_size(body)
    Let(NonRec(_, v), body) => expr_size(v) + expr_size(body)
    Let(Rec(pairs), body) => {
      let mut total = expr_size(body)
      for pair in pairs {
        total = total + expr_size(pair.1)
      }
      total
    }
    Case(scrut, _, alts) => {
      let mut total = expr_size(scrut)
      for alt in alts {
        total = total + expr_size(alt.expr)
      }
      total
    }
    Constr(_, args) => {
      let mut total = 1
      for a in args {
        total = total + expr_size(a)
      }
      total
    }
  }
}

///| Parse a profile JSON file (emitted by scripts/hvm_profile.py --json) into a map of def name -> iteration count.
pub fn parse_pgo_profile(json_str : String) -> Map[String, Int] {
  let profile_map : Map[String, Int] = Map([])
  try {
    let json = @json.parse(json_str[:])
    match json {
      Object(obj) => {
        match obj.get("profile") {
          Some(Array(rows)) => {
            for row in rows {
              match row {
                Object(row_obj) => {
                  let def_name = match row_obj.get("def") {
                    Some(String(s)) => s
                    _ => ""
                  }
                  let count = match row_obj.get("count") {
                    Some(Number(n, ..)) => n.to_int()
                    _ => 0
                  }
                  if def_name.length() > 0 && count > 0 {
                    profile_map[def_name] = count
                    if def_name.has_prefix("@") {
                      profile_map[def_name[1:].to_owned()] = count
                    } else {
                      profile_map["@" + def_name] = count
                    }
                  }
                }
                _ => ()
              }
            }
          }
          _ => ()
        }
      }
      _ => ()
    }
  } catch {
    _ => ()
  }
  profile_map
}

pub(all) struct PgoContext {
  counts : Map[String, Int]
  hot_defs : Map[String, Bool]
}

pub fn PgoContext::new(pgo : Map[String, Int]?) -> PgoContext {
  let counts : Map[String, Int] = match pgo {
    Some(m) => m
    None => Map([])
  }
  let hot_defs : Map[String, Bool] = Map([])
  let mut max_count = 0
  for _, c in counts {
    if c > max_count {
      max_count = c
    }
  }
  for k, c in counts {
    let is_hot = if max_count >= 100 {
      c * 5 >= max_count || c >= 100
    } else {
      c > 0
    }
    if is_hot {
      hot_defs[k] = true
      if k.has_prefix("@") {
        hot_defs[k[1:].to_owned()] = true
      } else {
        hot_defs["@" + k] = true
      }
    }
  }
  { counts, hot_defs }
}

pub fn PgoContext::is_hot(self : PgoContext, name : String) -> Bool {
  self.hot_defs.get(name).unwrap_or(false)
}

pub fn PgoContext::get_count(self : PgoContext, name : String) -> Int {
  match self.counts.get(name) {
    Some(c) => c
    None => {
      let alt = if name.has_prefix("@") { name[1:].to_owned() } else { "@" + name }
      self.counts.get(alt).unwrap_or(0)
    }
  }
}

pub fn inline_known_calls(expr : @syntax.Expr, stats : MidStats) -> @syntax.Expr {
  inline_known_calls_pgo(expr, stats, Map([]), PgoContext::new(None))
}

pub fn inline_known_calls_pgo(
  expr : @syntax.Expr,
  stats : MidStats,
  top_defs : Map[String, @syntax.Expr],
  pgo_ctx : PgoContext
) -> @syntax.Expr {
  match expr {
    Let(NonRec(name, value), body) => {
      let value = inline_known_calls_pgo(value, stats, top_defs, pgo_ctx)
      let body = inline_known_calls_pgo(body, stats, top_defs, pgo_ctx)
      if name.has_prefix("_caf_force_") {
        return Let(NonRec(name, value), body)
      }
      let uses = count_name_uses(body, name)
      let is_hot = pgo_ctx.is_hot(name)
      // Relax size heuristic when hot according to PGO
      let can_inline = if is_hot {
        (uses == 1 && expr_size(value) <= 50) || (uses <= 3 && expr_size(value) <= 20)
      } else {
        uses == 1 && expr_size(value) <= 6
      }
      if can_inline {
        match substitute_without_capture(body, name, value) {
          Some(inlined) => {
            stats.known_calls_inlined = stats.known_calls_inlined + 1
            inlined
          }
          None => Let(NonRec(name, value), body)
        }
      } else {
        Let(NonRec(name, value), body)
      }
    }
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, inline_known_calls_pgo(pair.1, stats, top_defs, pgo_ctx)))
      }
      Let(Rec(new_pairs), inline_known_calls_pgo(body, stats, top_defs, pgo_ctx))
    }
    App(f, a) => {
      let f = inline_known_calls_pgo(f, stats, top_defs, pgo_ctx)
      let a = inline_known_calls_pgo(a, stats, top_defs, pgo_ctx)
      match f {
        Lam(p, body) => {
          let uses = count_name_uses(body, p)
          let is_hot_arg = match a {
            Var(v) => pgo_ctx.is_hot(v)
            _ => false
          }
          if uses <= 1 || is_trivial_value(a) || is_hot_arg || (expr_size(a) <= 15 && uses <= 3) {
            match substitute_without_capture(body, p, a) {
              Some(inlined) => {
                stats.known_calls_inlined = stats.known_calls_inlined + 1
                inline_known_calls_pgo(inlined, stats, top_defs, pgo_ctx)
              }
              None => Let(NonRec(p, a), body)
            }
          } else {
            Let(NonRec(p, a), body)
          }
        }
        Var(fn_name) => {
          let is_hot = pgo_ctx.is_hot(fn_name)
          if is_hot {
            match top_defs.get(fn_name) {
              Some(fn_body) => {
                if count_name_uses(fn_body, fn_name) == 0 {
                  match fn_body {
                    Lam(p, body) => {
                      match substitute_without_capture(body, p, a) {
                        Some(inlined) => {
                          stats.known_calls_inlined = stats.known_calls_inlined + 1
                          inline_known_calls_pgo(inlined, stats, top_defs, pgo_ctx)
                        }
                        None => App(f, a)
                      }
                    }
                    _ => {
                      if expr_size(fn_body) <= 30 {
                        stats.known_calls_inlined = stats.known_calls_inlined + 1
                        inline_known_calls_pgo(App(fn_body, a), stats, top_defs, pgo_ctx)
                      } else {
                        App(f, a)
                      }
                    }
                  }
                } else {
                  App(f, a)
                }
              }
              None => App(f, a)
            }
          } else {
            App(f, a)
          }
        }
        _ => App(f, a)
      }
    }
    Var(fn_name) => {
      let is_hot = pgo_ctx.is_hot(fn_name)
      if is_hot {
        match top_defs.get(fn_name) {
          Some(fn_body) => {
            if count_name_uses(fn_body, fn_name) == 0 && expr_size(fn_body) <= 15 {
              stats.known_calls_inlined = stats.known_calls_inlined + 1
              fn_body
            } else {
              expr
            }
          }
          None => expr
        }
      } else {
        expr
      }
    }
    Lam(p, body) => Lam(p, inline_known_calls_pgo(body, stats, top_defs, pgo_ctx))
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: inline_known_calls_pgo(alt.expr, stats, top_defs, pgo_ctx) })
      }
      Case(inline_known_calls_pgo(scrut, stats, top_defs, pgo_ctx), binder, new_alts)
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(inline_known_calls_pgo(a, stats, top_defs, pgo_ctx))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

// ----------------------------------------------------------------------------
// Pass: Stream Fusion / Deforestation
// ----------------------------------------------------------------------------

fn alts_all_constructors(alts : Array[@syntax.Alt]) -> Bool {
  for alt in alts {
    match alt.expr {
      Constr(_, _) | LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => ()
      _ => return false
    }
  }
  true
}

fn try_fuse_case_constr(
  c : String,
  args : Array[@syntax.Expr],
  binder : String,
  alts : Array[@syntax.Alt]
) -> @syntax.Expr? {
  let norm_c = @syntax.normalize_ctor_name(c)
  for alt in alts {
    match alt.pat {
      Data(pat_c, vars) => {
        let norm_pat = @syntax.normalize_ctor_name(pat_c)
        if (norm_c == norm_pat || c == pat_c) && vars.length() == args.length() {
          let mut body = alt.expr
          for i = 0; i < vars.length(); i = i + 1 {
            let v = vars[i]
            let a = args[i]
            match substitute_without_capture(body, v, a) {
              Some(subst) => body = subst
              None => body = Let(NonRec(v, a), body)
            }
          }
          if binder.length() > 0 && binder != "_" {
            match substitute_without_capture(body, binder, Constr(c, args)) {
              Some(subst) => body = subst
              None => ()
            }
          }
          return Some(body)
        }
      }
      Default(_) => {
        let mut body = alt.expr
        if binder.length() > 0 && binder != "_" {
          match substitute_without_capture(body, binder, Constr(c, args)) {
            Some(subst) => body = subst
            None => ()
          }
        }
        return Some(body)
      }
      _ => ()
    }
  }
  None
}

///| Deforest producer-consumer chains on intermediate data structures:
///| 1. General user ADT constructor fusion: `case (Constr c args) of alts`
///|    eliminates intermediate constructor nets across all user ADTs.
///| 2. Case-of-case deforestation: `case (case inner of alts1) of alts2`
///|    distributes the consumer into each producer branch, eliminating intermediate
///|    constructor nets when branches produce constructors.
///| 3. Stream pipeline fusion: `map f (map g xs)` -> `map (\x -> f (g x)) xs`.
///| 4. Immediate list consumer fusion: `map f (Cons x xs)` -> `Cons (f x) (map f xs)`,
///|    `map f Nil` -> `Nil`.
pub fn deforest_streams(
  expr : @syntax.Expr,
  stats : MidStats,
  ctor_names : Array[String]
) -> @syntax.Expr {
  match expr {
    // Let-bound intermediate constructor consumed by case
    Let(NonRec(x, Constr(c, args)), Case(Var(v), binder, alts)) => {
      if v == x {
        match try_fuse_case_constr(c, args, binder, alts) {
          Some(fused) => {
            stats.streams_fused = stats.streams_fused + 1
            deforest_streams(fused, stats, ctor_names)
          }
          None => Let(NonRec(x, Constr(c, args)), Case(Var(v), binder, alts))
        }
      } else {
        Let(NonRec(x, Constr(c, args)), deforest_streams(Case(Var(v), binder, alts), stats, ctor_names))
      }
    }
    // Intermediate constructor chain inside let-scrutinee
    Case(Let(NonRec(v, val), Constr(c, args)), outer_bndr, outer_alts) => {
      match try_fuse_case_constr(c, args, outer_bndr, outer_alts) {
        Some(fused) => {
          stats.streams_fused = stats.streams_fused + 1
          Let(NonRec(v, val), deforest_streams(fused, stats, ctor_names))
        }
        None => {
          let outer_case : @syntax.Expr = Case(Constr(c, args), outer_bndr, outer_alts)
          Let(NonRec(v, val), deforest_streams(outer_case, stats, ctor_names))
        }
      }
    }
    // Applied lambda consuming general user ADT constructor
    App(Lam(p, Case(Var(v), bndr, alts)), Constr(c, args)) => {
      if p == v {
        match try_fuse_case_constr(c, args, bndr, alts) {
          Some(fused) => {
            stats.streams_fused = stats.streams_fused + 1
            deforest_streams(fused, stats, ctor_names)
          }
          None => App(Lam(p, Case(Var(v), bndr, alts)), Constr(c, args))
        }
      } else {
        App(Lam(p, deforest_streams(Case(Var(v), bndr, alts), stats, ctor_names)), Constr(c, args))
      }
    }
    // Case-of-case deforestation across general user ADTs
    Case(Case(inner_scrut, inner_bndr, inner_alts), outer_bndr, outer_alts) => {
      if alts_all_constructors(inner_alts) || outer_alts.length() <= 3 {
        let new_inner_alts : Array[@syntax.Alt] = []
        for alt in inner_alts {
          let fused_expr = match alt.expr {
            Constr(c, args) => {
              match try_fuse_case_constr(c, args, outer_bndr, outer_alts) {
                Some(fused) => deforest_streams(fused, stats, ctor_names)
                None => {
                  let outer_case : @syntax.Expr = Case(alt.expr, outer_bndr, outer_alts)
                  deforest_streams(outer_case, stats, ctor_names)
                }
              }
            }
            _ => {
              let outer_case : @syntax.Expr = Case(alt.expr, outer_bndr, outer_alts)
              deforest_streams(outer_case, stats, ctor_names)
            }
          }
          new_inner_alts.push({ pat: alt.pat, expr: fused_expr })
        }
        stats.streams_fused = stats.streams_fused + 1
        Case(deforest_streams(inner_scrut, stats, ctor_names), inner_bndr, new_inner_alts)
      } else {
        let new_outer_alts : Array[@syntax.Alt] = []
        for alt in outer_alts {
          new_outer_alts.push({ pat: alt.pat, expr: deforest_streams(alt.expr, stats, ctor_names) })
        }
        Case(deforest_streams(Case(inner_scrut, inner_bndr, inner_alts), stats, ctor_names), outer_bndr, new_outer_alts)
      }
    }
    // 2. Stream map-map fusion: map f (map g xs) => map (\x -> f (g x)) xs
    App(App(Var(m1), f), App(App(Var(m2), g), xs)) => {
      let is_m1 = m1 == "map" || m1 == "GHC_Internal_Base_map" || m1.has_suffix("_map")
      let is_m2 = m2 == "map" || m2 == "GHC_Internal_Base_map" || m2.has_suffix("_map")
      if is_m1 && is_m2 {
        stats.streams_fused = stats.streams_fused + 1
        let f_def = deforest_streams(f, stats, ctor_names)
        let g_def = deforest_streams(g, stats, ctor_names)
        let xs_def = deforest_streams(xs, stats, ctor_names)
        let fused_fn : @syntax.Expr = Lam("__strm_x", App(f_def, App(g_def, Var("__strm_x"))))
        App(App(Var(m1), fused_fn), xs_def)
      } else {
        App(App(Var(m1), deforest_streams(f, stats, ctor_names)), deforest_streams(App(App(Var(m2), g), xs), stats, ctor_names))
      }
    }
    // 3. Map on known list constructor: map f (Cons x xs) => Cons (f x) (map f xs)
    App(App(Var(m), f), Constr(c, args)) => {
      let is_m = m == "map" || m == "GHC_Internal_Base_map" || m.has_suffix("_map")
      let norm = @syntax.normalize_ctor_name(c)
      if is_m && norm == "Cons" && args.length() == 2 {
        stats.streams_fused = stats.streams_fused + 1
        let f_def = deforest_streams(f, stats, ctor_names)
        let hd = deforest_streams(args[0], stats, ctor_names)
        let tl = deforest_streams(args[1], stats, ctor_names)
        Constr("(:)", [App(f_def, hd), App(App(Var(m), f_def), tl)])
      } else if is_m && norm == "Nil" && args.length() == 0 {
        stats.streams_fused = stats.streams_fused + 1
        Constr("[]", [])
      } else {
        App(App(Var(m), deforest_streams(f, stats, ctor_names)), Constr(c, args))
      }
    }
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: deforest_streams(alt.expr, stats, ctor_names) })
      }
      Case(deforest_streams(scrut, stats, ctor_names), binder, new_alts)
    }
    App(f, a) => App(deforest_streams(f, stats, ctor_names), deforest_streams(a, stats, ctor_names))
    Lam(p, body) => Lam(p, deforest_streams(body, stats, ctor_names))
    Let(NonRec(n, v), body) =>
      Let(NonRec(n, deforest_streams(v, stats, ctor_names)), deforest_streams(body, stats, ctor_names))
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, deforest_streams(pair.1, stats, ctor_names)))
      }
      Let(Rec(new_pairs), deforest_streams(body, stats, ctor_names))
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(deforest_streams(a, stats, ctor_names))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

// ----------------------------------------------------------------------------
// Pass: Dominator DUP Sinking
// ----------------------------------------------------------------------------

///| Sinks let bindings that produce compound expressions into the specific
///| case branch that dominates all their occurrences. This prevents premature
///| global DUP fan-out across alternative execution paths.
pub fn sink_dominator_dups(expr : @syntax.Expr, stats : MidStats) -> @syntax.Expr {
  match expr {
    Let(NonRec(name, value), body) => {
      let value = sink_dominator_dups(value, stats)
      let body = sink_dominator_dups(body, stats)
      match body {
        Case(scrut, binder, alts) => {
          if uses_name(scrut, name) {
            return Let(NonRec(name, value), Case(scrut, binder, alts))
          }
          let mut target_idx = -1
          let mut count_branches = 0
          for i, alt in alts {
            let shadowed = alt_binders(alt, binder).contains(name)
            if !shadowed && uses_name(alt.expr, name) {
              target_idx = i
              count_branches = count_branches + 1
            }
          }
          if count_branches == 1 {
            stats.dups_sunk = stats.dups_sunk + 1
            let new_alts : Array[@syntax.Alt] = []
            for i, alt in alts {
              if i == target_idx {
                let sunk_expr = sink_dominator_dups(
                  Let(NonRec(name, value), alt.expr),
                  stats,
                )
                new_alts.push({ pat: alt.pat, expr: sunk_expr })
              } else {
                new_alts.push(alt)
              }
            }
            Case(scrut, binder, new_alts)
          } else {
            Let(NonRec(name, value), Case(scrut, binder, alts))
          }
        }
        Let(NonRec(n2, v2), inner) => {
          if !uses_name(v2, name) && n2 != name {
            match inner {
              Case(scrut, binder, alts) if !uses_name(scrut, name) => {
                let mut target_idx = -1
                let mut count_branches = 0
                for i, alt in alts {
                  let shadowed = alt_binders(alt, binder).contains(name)
                  if !shadowed && uses_name(alt.expr, name) {
                    target_idx = i
                    count_branches = count_branches + 1
                  }
                }
                if count_branches == 1 {
                  stats.dups_sunk = stats.dups_sunk + 1
                  let new_alts : Array[@syntax.Alt] = []
                  for i, alt in alts {
                    if i == target_idx {
                      let sunk_expr = sink_dominator_dups(
                        Let(NonRec(name, value), alt.expr),
                        stats,
                      )
                      new_alts.push({ pat: alt.pat, expr: sunk_expr })
                    } else {
                      new_alts.push(alt)
                    }
                  }
                  return Let(NonRec(n2, v2), Case(scrut, binder, new_alts))
                }
              }
              _ => ()
            }
          }
          Let(NonRec(name, value), Let(NonRec(n2, v2), inner))
        }
        _ => Let(NonRec(name, value), body)
      }
    }
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, sink_dominator_dups(pair.1, stats)))
      }
      Let(Rec(new_pairs), sink_dominator_dups(body, stats))
    }
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: sink_dominator_dups(alt.expr, stats) })
      }
      Case(sink_dominator_dups(scrut, stats), binder, new_alts)
    }
    App(f, a) => App(sink_dominator_dups(f, stats), sink_dominator_dups(a, stats))
    Lam(p, body) => Lam(p, sink_dominator_dups(body, stats))
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(sink_dominator_dups(a, stats))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

// ----------------------------------------------------------------------------
// Pass: Supercompilation / Symbolic Driving
// ----------------------------------------------------------------------------

fn propagate_scrutinee_info(
  expr : @syntax.Expr,
  target : String,
  replacement : @syntax.Expr
) -> @syntax.Expr {
  match expr {
    Case(Var(x), binder, alts) if x == target => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({
          pat: alt.pat,
          expr: propagate_scrutinee_info(alt.expr, target, replacement),
        })
      }
      Case(replacement, binder, new_alts)
    }
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({
          pat: alt.pat,
          expr: propagate_scrutinee_info(alt.expr, target, replacement),
        })
      }
      Case(propagate_scrutinee_info(scrut, target, replacement), binder, new_alts)
    }
    App(f, a) =>
      App(
        propagate_scrutinee_info(f, target, replacement),
        propagate_scrutinee_info(a, target, replacement),
      )
    Lam(p, body) =>
      if p == target {
        expr
      } else {
        Lam(p, propagate_scrutinee_info(body, target, replacement))
      }
    Let(NonRec(n, v), body) =>
      if n == target {
        Let(NonRec(n, propagate_scrutinee_info(v, target, replacement)), body)
      } else {
        Let(
          NonRec(n, propagate_scrutinee_info(v, target, replacement)),
          propagate_scrutinee_info(body, target, replacement),
        )
      }
    Let(Rec(pairs), body) => {
      let mut shadows = false
      for p in pairs {
        if p.0 == target {
          shadows = true
          break
        }
      }
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for p in pairs {
        new_pairs.push((p.0, propagate_scrutinee_info(p.1, target, replacement)))
      }
      if shadows {
        Let(Rec(new_pairs), body)
      } else {
        Let(Rec(new_pairs), propagate_scrutinee_info(body, target, replacement))
      }
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(propagate_scrutinee_info(a, target, replacement))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

///| Supercompilation / Symbolic Driving:
///| 1. Drives case expressions by propagating pattern constraints into alternatives.
///| 2. Flattens nested function calls on known constructors into single-step rules.
///| 3. Unrolls hot recursive steps and drives hot branches according to PGO weights.
pub fn symbolic_supercompile(
  expr : @syntax.Expr,
  stats : MidStats,
  ctor_names : Array[String]
) -> @syntax.Expr {
  symbolic_supercompile_pgo(expr, stats, ctor_names, Map([]), PgoContext::new(None))
}

pub fn symbolic_supercompile_pgo(
  expr : @syntax.Expr,
  stats : MidStats,
  ctor_names : Array[String],
  top_defs : Map[String, @syntax.Expr],
  pgo_ctx : PgoContext
) -> @syntax.Expr {
  match expr {
    Case(scrut, binder, alts) => {
      let scrut = symbolic_supercompile_pgo(scrut, stats, ctor_names, top_defs, pgo_ctx)
      // If scrutinee is an application of a hot definition, drive it
      let scrut = match scrut {
        App(Var(f), arg) => {
          if pgo_ctx.is_hot(f) {
            match top_defs.get(f) {
              Some(Lam(p, f_body)) => {
                match substitute_without_capture(f_body, p, arg) {
                  Some(driven) => {
                    stats.supercompiled = stats.supercompiled + 1
                    symbolic_supercompile_pgo(driven, stats, ctor_names, top_defs, pgo_ctx)
                  }
                  None => scrut
                }
              }
              _ => scrut
            }
          } else {
            scrut
          }
        }
        _ => scrut
      }
      let scrut_var = match scrut {
        Var(v) => Some(v)
        _ => None
      }
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        match alt.pat {
          Data(c, vars) => {
            let cargs : Array[@syntax.Expr] = []
            for v in vars {
              cargs.push(Var(v))
            }
            let ctor_repr : @syntax.Expr = Constr(c, cargs)
            let mut branch_body = alt.expr
            match scrut_var {
              Some(sv) => {
                let driven = propagate_scrutinee_info(branch_body, sv, ctor_repr)
                if driven != branch_body {
                  stats.supercompiled = stats.supercompiled + 1
                  branch_body = driven
                }
              }
              None => ()
            }
            if binder.length() > 0 && binder != "_" {
              let driven = propagate_scrutinee_info(branch_body, binder, ctor_repr)
              if driven != branch_body {
                stats.supercompiled = stats.supercompiled + 1
                branch_body = driven
              }
            }
            // Drive hot branches deeper
            let is_hot_branch = pgo_ctx.is_hot(c) || (scrut_var != None && pgo_ctx.is_hot(scrut_var.unwrap()))
            let driven_body = symbolic_supercompile_pgo(branch_body, stats, ctor_names, top_defs, pgo_ctx)
            let final_body = if is_hot_branch {
              symbolic_supercompile_pgo(driven_body, stats, ctor_names, top_defs, pgo_ctx)
            } else {
              driven_body
            }
            new_alts.push({
              pat: alt.pat,
              expr: final_body,
            })
          }
          Lit(n) => {
            let lit_repr : @syntax.Expr = LitInt(n)
            let mut branch_body = alt.expr
            match scrut_var {
              Some(sv) => {
                let driven = propagate_scrutinee_info(branch_body, sv, lit_repr)
                if driven != branch_body {
                  stats.supercompiled = stats.supercompiled + 1
                  branch_body = driven
                }
              }
              None => ()
            }
            new_alts.push({
              pat: alt.pat,
              expr: symbolic_supercompile_pgo(branch_body, stats, ctor_names, top_defs, pgo_ctx),
            })
          }
          Default(_) => {
            new_alts.push({
              pat: alt.pat,
              expr: symbolic_supercompile_pgo(alt.expr, stats, ctor_names, top_defs, pgo_ctx),
            })
          }
        }
      }
      Case(scrut, binder, new_alts)
    }
    // Unroll hot recursion / call on known constructor
    App(Var(f), Constr(c, args)) => {
      if pgo_ctx.is_hot(f) {
        match top_defs.get(f) {
          Some(Lam(p, body)) => {
            match substitute_without_capture(body, p, Constr(c, args)) {
              Some(unrolled) => {
                stats.supercompiled = stats.supercompiled + 1
                symbolic_supercompile_pgo(unrolled, stats, ctor_names, top_defs, pgo_ctx)
              }
              None => App(Var(f), Constr(c, args))
            }
          }
          _ => App(Var(f), Constr(c, args))
        }
      } else {
        App(Var(f), Constr(c, args))
      }
    }
    // Unroll hot recursion / call on known integer literal
    App(Var(f), LitInt(n)) => {
      if pgo_ctx.is_hot(f) {
        match top_defs.get(f) {
          Some(Lam(p, body)) => {
            match substitute_without_capture(body, p, LitInt(n)) {
              Some(unrolled) => {
                stats.supercompiled = stats.supercompiled + 1
                symbolic_supercompile_pgo(unrolled, stats, ctor_names, top_defs, pgo_ctx)
              }
              None => App(Var(f), LitInt(n))
            }
          }
          _ => App(Var(f), LitInt(n))
        }
      } else {
        App(Var(f), LitInt(n))
      }
    }
    App(Lam(p, body), Constr(c, args)) => {
      match substitute_without_capture(body, p, Constr(c, args)) {
        Some(driven) => {
          stats.supercompiled = stats.supercompiled + 1
          symbolic_supercompile_pgo(driven, stats, ctor_names, top_defs, pgo_ctx)
        }
        None =>
          App(
            Lam(p, symbolic_supercompile_pgo(body, stats, ctor_names, top_defs, pgo_ctx)),
            Constr(c, args),
          )
      }
    }
    App(Lam(p, body), LitInt(n)) => {
      match substitute_without_capture(body, p, LitInt(n)) {
        Some(driven) => {
          stats.supercompiled = stats.supercompiled + 1
          symbolic_supercompile_pgo(driven, stats, ctor_names, top_defs, pgo_ctx)
        }
        None =>
          App(
            Lam(p, symbolic_supercompile_pgo(body, stats, ctor_names, top_defs, pgo_ctx)),
            LitInt(n),
          )
      }
    }
    App(f, a) =>
      App(
        symbolic_supercompile_pgo(f, stats, ctor_names, top_defs, pgo_ctx),
        symbolic_supercompile_pgo(a, stats, ctor_names, top_defs, pgo_ctx),
      )
    Lam(p, body) => Lam(p, symbolic_supercompile_pgo(body, stats, ctor_names, top_defs, pgo_ctx))
    Let(NonRec(n, v), body) =>
      Let(
        NonRec(n, symbolic_supercompile_pgo(v, stats, ctor_names, top_defs, pgo_ctx)),
        symbolic_supercompile_pgo(body, stats, ctor_names, top_defs, pgo_ctx),
      )
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, symbolic_supercompile_pgo(pair.1, stats, ctor_names, top_defs, pgo_ctx)))
      }
      Let(Rec(new_pairs), symbolic_supercompile_pgo(body, stats, ctor_names, top_defs, pgo_ctx))
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(symbolic_supercompile_pgo(a, stats, ctor_names, top_defs, pgo_ctx))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

// ----------------------------------------------------------------------------
// Pipeline
// ----------------------------------------------------------------------------

///| Run the middle-end. Passes run to a fixpoint so a reduction that exposes a
///| dead binding or a duplicate body is picked up in the same compile.
pub fn optimize(
  prog : @syntax.Program,
  stats : MidStats,
  pgo? : Map[String, Int]
) -> @syntax.Program {
  let pgo_ctx = PgoContext::new(pgo)
  let mut current = prune_top_bindings(prog, stats)
  current = thread_caf_sharing(current, stats)
  current = rebuild_shared_reads(current, stats)
  let ctor_names = collect_ctor_names(current)
  let counter : Array[Int] = [0]
  for pass = 0; pass < 3; pass = pass + 1 {
    let top_defs : Map[String, @syntax.Expr] = Map([])
    for bind in current.binds {
      match bind {
        NonRec(name, expr) => top_defs[name] = expr
        Rec(pairs) =>
          for pair in pairs {
            top_defs[pair.0] = pair.1
          }
      }
    }
    let before = stats.dead_lets +
      stats.inlined_lets +
      stats.cases_reduced +
      stats.alts_merged +
      stats.binds_merged +
      stats.etas_reduced +
      stats.constants_folded +
      stats.dead_alts_pruned +
      stats.unboxed_simplified +
      stats.lets_pushed_down +
      stats.known_calls_inlined +
      stats.streams_fused +
      stats.dups_sunk +
      stats.supercompiled
    let new_binds : Array[@syntax.Bind] = []
    for bind in current.binds {
      match bind {
        NonRec(name, expr) => {
          let expr = eta_reduce(expr, stats)
          let expr = fold_constants(expr, stats)
          let expr = prune_dead_lets(expr, stats)
          let expr = inline_trivial_lets(expr, stats)
          let expr = inline_known_calls_pgo(expr, stats, top_defs, pgo_ctx)
          let expr = simplify_unboxed(expr, stats, ctor_names)
          let expr = prune_dead_alts(expr, stats, ctor_names)
          let expr = reduce_known_cases(expr, stats, ctor_names)
          let expr = deforest_streams(expr, stats, ctor_names)
          let expr = sink_dominator_dups(expr, stats)
          let expr = symbolic_supercompile_pgo(expr, stats, ctor_names, top_defs, pgo_ctx)
          let expr = push_let_into_case(expr, stats)
          let expr = merge_alt_bodies(expr, stats, counter)
          new_binds.push(NonRec(name, expr))
        }
        Rec(pairs) => {
          let new_pairs : Array[(String, @syntax.Expr)] = []
          for pair in pairs {
            let expr = eta_reduce(pair.1, stats)
            let expr = fold_constants(expr, stats)
            let expr = prune_dead_lets(expr, stats)
            let expr = inline_trivial_lets(expr, stats)
            let expr = inline_known_calls_pgo(expr, stats, top_defs, pgo_ctx)
            let expr = simplify_unboxed(expr, stats, ctor_names)
            let expr = prune_dead_alts(expr, stats, ctor_names)
            let expr = reduce_known_cases(expr, stats, ctor_names)
            let expr = deforest_streams(expr, stats, ctor_names)
            let expr = sink_dominator_dups(expr, stats)
            let expr = symbolic_supercompile_pgo(expr, stats, ctor_names, top_defs, pgo_ctx)
            let expr = push_let_into_case(expr, stats)
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
      stats.binds_merged +
      stats.etas_reduced +
      stats.constants_folded +
      stats.dead_alts_pruned +
      stats.unboxed_simplified +
      stats.lets_pushed_down +
      stats.known_calls_inlined +
      stats.streams_fused +
      stats.dups_sunk +
      stats.supercompiled
    if after == before {
      break
    }
  }
  current
}
