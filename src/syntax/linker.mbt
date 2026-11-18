///| Multi-Module Linker for CoreLite AST.

fn collect_free_vars_fast(
  expr : Expr,
  bound : Array[String],
  free_map : Map[String, Bool],
  free : Array[String]
) -> Unit {
  match expr {
    Var(name) => {
      if !bound.contains(name) && !free_map.contains(name) {
        free_map[name] = true
        free.push(name)
      }
    }
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => ()
    App(f, a) => {
      collect_free_vars_fast(f, bound, free_map, free)
      collect_free_vars_fast(a, bound, free_map, free)
    }
    Lam(p, body) => {
      bound.push(p)
      collect_free_vars_fast(body, bound, free_map, free)
      let _ = bound.pop()
    }
    Let(bind, body) => {
      match bind {
        NonRec(name, val) => {
          collect_free_vars_fast(val, bound, free_map, free)
          bound.push(name)
          collect_free_vars_fast(body, bound, free_map, free)
          let _ = bound.pop()
        }
        Rec(pairs) => {
          for pair in pairs {
            bound.push(pair.0)
          }
          for pair in pairs {
            collect_free_vars_fast(pair.1, bound, free_map, free)
          }
          collect_free_vars_fast(body, bound, free_map, free)
          for _ in 0..<pairs.length() {
            let _ = bound.pop()
          }
        }
      }
    }
    Case(scrut, binder, alts) => {
      collect_free_vars_fast(scrut, bound, free_map, free)
      for alt in alts {
        let added_binders : Array[String] = []
        if binder.length() > 0 {
          bound.push(binder)
          added_binders.push(binder)
        }
        match alt.pat {
          Default(Some(v)) => {
            bound.push(v)
            added_binders.push(v)
          }
          Data(_, vars) => {
            for v in vars {
              bound.push(v)
              added_binders.push(v)
            }
          }
          _ => ()
        }
        collect_free_vars_fast(alt.expr, bound, free_map, free)
        for _ in 0..<added_binders.length() {
          let _ = bound.pop()
        }
      }
    }
    Constr(name, args) => {
      if !bound.contains(name) && !free_map.contains(name) {
        free_map[name] = true
        free.push(name)
      }
      for a in args {
        collect_free_vars_fast(a, bound, free_map, free)
      }
    }
  }
}

pub fn collect_free_vars_in_expr(expr : Expr, bound : Array[String], free : Array[String]) -> Unit {
  let free_map : Map[String, Bool] = Map([])
  for f in free {
    free_map[f] = true
  }
  collect_free_vars_fast(expr, bound, free_map, free)
}

///| Link multiple CoreLite programs into a single unified Program.
///| Resolves imported / qualified symbols across modules (e.g. Math_fib -> fib,
///| Data_ListOps_myMap -> myMap) and creates alias bindings.
pub fn link_programs(programs : Array[Program]) -> Program {
  let seen_map : Map[String, Bool] = Map([])
  let seen_names : Array[String] = []
  let unified_binds : Array[Bind] = []

  // 1. Collect all bindings from all programs, deduplicating identical names
  for prog in programs {
    for bind in prog.binds {
      match bind {
        NonRec(name, expr) => {
          if seen_map.contains(name) {
            continue
          }
          seen_map[name] = true
          seen_names.push(name)
          unified_binds.push(NonRec(name, expr))
        }
        Rec(pairs) => {
          let new_pairs : Array[(String, Expr)] = []
          for pair in pairs {
            if !seen_map.contains(pair.0) {
              seen_map[pair.0] = true
              seen_names.push(pair.0)
              new_pairs.push(pair)
            }
          }
          if new_pairs.length() > 0 {
            unified_binds.push(Rec(new_pairs))
          }
        }
      }
    }
  }

  // 2. Collect all free variables referenced in all bindings
  let free_map : Map[String, Bool] = Map([])
  let free_vars : Array[String] = []
  for bind in unified_binds {
    match bind {
      NonRec(_, expr) => collect_free_vars_fast(expr, [], free_map, free_vars)
      Rec(pairs) => {
        let bound : Array[String] = []
        for pair in pairs { bound.push(pair.0) }
        for pair in pairs { collect_free_vars_fast(pair.1, bound, free_map, free_vars) }
      }
    }
  }

  // 3. Resolve cross-module qualified names
  let unqual_to_qual : Map[String, String] = Map([])
  for def_name in seen_names {
    let unqual = get_unqualified_name(def_name)
    if unqual != def_name && !unqual_to_qual.contains(unqual) {
      unqual_to_qual[unqual] = def_name
    }
  }

  // Case A: Free variable is qualified (e.g. Math_Fib_fib or Math.Fib.fib)
  // and an unqualified symbol (fib) is defined.
  for fv in free_vars {
    if !seen_map.contains(fv) {
      let unqual = get_unqualified_name(fv)
      if seen_map.contains(unqual) && unqual != fv {
        seen_map[fv] = true
        seen_names.push(fv)
        unified_binds.push(Bind::NonRec(fv, Expr::Var(unqual)))
      }
    }
  }

  // Case B: Free variable is unqualified (e.g. fib)
  // and a defined symbol is qualified (e.g. Math_Fib_fib).
  for fv in free_vars {
    if !seen_map.contains(fv) {
      match unqual_to_qual.get(fv) {
        Some(target) => {
          seen_map[fv] = true
          seen_names.push(fv)
          unified_binds.push(Bind::NonRec(fv, Expr::Var(target)))
        }
        None => ()
      }
    }
  }

  // Case C: GHC unique suffix match (e.g. fv is Data_ListOps_$wmySum or $wmySum,
  // and defined symbol has a GHC unique suffix like Data_ListOps_$wmySum_sKG).
  for fv in free_vars {
    if !seen_map.contains(fv) {
      let mut matched : String? = None
      let fv_prefix = fv + "_"
      let unqual_prefix = get_unqualified_name(fv) + "_"
      for def_name in seen_names {
        if def_name.has_prefix(fv_prefix) || def_name.has_prefix(unqual_prefix) {
          matched = Some(def_name)
          break
        }
      }
      match matched {
        Some(target) => {
          seen_map[fv] = true
          seen_names.push(fv)
          unified_binds.push(Bind::NonRec(fv, Expr::Var(target)))
        }
        None => ()
      }
    }
  }

  // 4. Ensure entry point 'main = result' if result exists and main does not
  if !seen_map.contains("main") && seen_map.contains("result") {
    unified_binds.push(Bind::NonRec("main", Expr::Var("result")))
  }

  Program::new(unified_binds)
}

///| Tree-Shaking Dead Code Elimination (Whole-Program LTO) for CoreLite AST.
///| Prunes any top-level bindings not transitively reachable from the specified roots.
///| If no roots are specified or found, returns the program unmodified.
pub fn prune_unreachable(prog : Program, extra_roots : Array[String]) -> Program {
  let all = prog.all_bindings()
  let defined_map : Map[String, Expr] = Map([])
  for p in all {
    defined_map[p.0] = p.1
  }

  // 1. Establish roots
  let roots : Array[String] = []
  let roots_map : Map[String, Bool] = Map([])
  for r in extra_roots {
    if defined_map.contains(r) && !roots_map.contains(r) {
      roots.push(r)
      roots_map[r] = true
    }
  }

  // Well-known entry points
  let default_entry_points = ["main", "result", "Main_main", ":Main.main", "_start", "coronet_main"]
  for ep in default_entry_points {
    if defined_map.contains(ep) && !roots_map.contains(ep) {
      roots.push(ep)
      roots_map[ep] = true
    }
  }

  // If no root is found, safely return program unmodified
  if roots.is_empty() {
    return prog
  }

  // 2. Reachability analysis (Transitive Closure via BFS)
  let reachable_map : Map[String, Bool] = Map([])
  let queue : Array[String] = []
  for r in roots {
    reachable_map[r] = true
    queue.push(r)
  }

  let mut head = 0
  while head < queue.length() {
    let curr = queue[head]
    head = head + 1
    match defined_map.get(curr) {
      Some(expr) => {
        let fvs : Array[String] = []
        let fv_map : Map[String, Bool] = Map([])
        collect_free_vars_fast(expr, [], fv_map, fvs)
        for fv in fvs {
          if defined_map.contains(fv) && !reachable_map.contains(fv) {
            reachable_map[fv] = true
            queue.push(fv)
          }
        }
      }
      None => ()
    }
  }

  // 3. Filter top-level bindings
  let new_binds : Array[Bind] = []
  for b in prog.binds {
    match b {
      NonRec(n, e) => {
        if reachable_map.contains(n) {
          new_binds.push(NonRec(n, e))
        }
      }
      Rec(pairs) => {
        let kept_pairs : Array[(String, Expr)] = []
        for pair in pairs {
          if reachable_map.contains(pair.0) {
            kept_pairs.push(pair)
          }
        }
        if kept_pairs.length() > 0 {
          new_binds.push(Rec(kept_pairs))
        }
      }
    }
  }

  Program::new(new_binds)
}

///| Link multiple CoreLite programs with Whole-Program Tree-Shaking (LTO).
pub fn link_programs_lto(programs : Array[Program], roots : Array[String]) -> Program {
  let linked = link_programs(programs)
  prune_unreachable(linked, roots)
}

///| Merge two programs.
pub fn Program::merge(self : Program, other : Program) -> Program {
  link_programs([self, other])
}

///| Parse and link multiple CoreLite source strings into one unified program.
pub fn link_core_sources(sources : Array[String]) -> Result[Program, String] {
  let progs : Array[Program] = []
  for src in sources {
    match parse_program(src) {
      Ok(p) => progs.push(p)
      Err(e) => return Err(e)
    }
  }
  Ok(link_programs(progs))
}
