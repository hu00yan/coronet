///| Multi-Module Linker for CoreLite AST.

fn collect_free_vars_in_expr(expr : Expr, bound : Array[String], free : Array[String]) -> Unit {
  match expr {
    Var(name) => {
      if !bound.contains(name) && !free.contains(name) {
        free.push(name)
      }
    }
    LitInt(_) | LitChar(_) | LitString(_) => ()
    App(f, a) => {
      collect_free_vars_in_expr(f, bound, free)
      collect_free_vars_in_expr(a, bound, free)
    }
    Lam(p, body) => {
      bound.push(p)
      collect_free_vars_in_expr(body, bound, free)
      let _ = bound.pop()
    }
    Let(bind, body) => {
      match bind {
        NonRec(name, val) => {
          collect_free_vars_in_expr(val, bound, free)
          bound.push(name)
          collect_free_vars_in_expr(body, bound, free)
          let _ = bound.pop()
        }
        Rec(pairs) => {
          for pair in pairs {
            bound.push(pair.0)
          }
          for pair in pairs {
            collect_free_vars_in_expr(pair.1, bound, free)
          }
          collect_free_vars_in_expr(body, bound, free)
          for _ in 0..<pairs.length() {
            let _ = bound.pop()
          }
        }
      }
    }
    Case(scrut, binder, alts) => {
      collect_free_vars_in_expr(scrut, bound, free)
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
        collect_free_vars_in_expr(alt.expr, bound, free)
        for _ in 0..<added_binders.length() {
          let _ = bound.pop()
        }
      }
    }
    Constr(_, args) => {
      for a in args {
        collect_free_vars_in_expr(a, bound, free)
      }
    }
  }
}

///| Link multiple CoreLite programs into a single unified Program.
///| Resolves imported / qualified symbols across modules (e.g. Math_fib -> fib,
///| Data_ListOps_myMap -> myMap) and creates alias bindings.
pub fn link_programs(programs : Array[Program]) -> Program {
  let seen_names : Array[String] = []
  let unified_binds : Array[Bind] = []

  // 1. Collect all bindings from all programs, deduplicating identical names
  for prog in programs {
    for bind in prog.binds {
      match bind {
        NonRec(name, expr) => {
          if seen_names.contains(name) {
            continue
          }
          seen_names.push(name)
          unified_binds.push(NonRec(name, expr))
        }
        Rec(pairs) => {
          let new_pairs : Array[(String, Expr)] = []
          for pair in pairs {
            if !seen_names.contains(pair.0) {
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
  let free_vars : Array[String] = []
  for bind in unified_binds {
    match bind {
      NonRec(_, expr) => collect_free_vars_in_expr(expr, [], free_vars)
      Rec(pairs) => {
        let bound : Array[String] = []
        for pair in pairs { bound.push(pair.0) }
        for pair in pairs { collect_free_vars_in_expr(pair.1, bound, free_vars) }
      }
    }
  }

  // 3. Resolve cross-module qualified names
  // Case A: Free variable is qualified (e.g. Math_Fib_fib or Math.Fib.fib)
  // and an unqualified symbol (fib) is defined.
  for fv in free_vars {
    if !seen_names.contains(fv) {
      let unqual = get_unqualified_name(fv)
      if seen_names.contains(unqual) && unqual != fv {
        seen_names.push(fv)
        unified_binds.push(Bind::NonRec(fv, Expr::Var(unqual)))
      }
    }
  }

  // Case B: Free variable is unqualified (e.g. fib)
  // and a defined symbol is qualified (e.g. Math_Fib_fib).
  for fv in free_vars {
    if !seen_names.contains(fv) {
      let mut matched : String? = None
      for def_name in seen_names {
        if get_unqualified_name(def_name) == fv && def_name != fv {
          matched = Some(def_name)
          break
        }
      }
      match matched {
        Some(target) => {
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
    if !seen_names.contains(fv) {
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
          seen_names.push(fv)
          unified_binds.push(Bind::NonRec(fv, Expr::Var(target)))
        }
        None => ()
      }
    }
  }

  // 4. Ensure entry point 'main = result' if result exists and main does not
  if !seen_names.contains("main") && seen_names.contains("result") {
    unified_binds.push(Bind::NonRec("main", Expr::Var("result")))
  }

  Program::new(unified_binds)
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
