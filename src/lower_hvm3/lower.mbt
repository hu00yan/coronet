///| CoreLite to HVM3 Lowering (Interaction Calculus)
///|
///| Lowers CoreLite AST to HVM3 format (@fun = term).
///| Supports functions, curried lambdas, applications, integer operations,
///| Scott-encoded ADTs/pattern matching, and let bindings.

///| Representation of a data constructor in an ADT family
priv struct CtorDef {
  name : String
  mut arity : Int
}

///| Representation of an ADT family containing one or more constructors
priv struct AdtFamily {
  _family_name : String
  ctors : Array[CtorDef]
}

///| Lowering context holding global definitions and discovered ADT families
priv struct LowerContext {
  globals : Array[String]
  families : Array[AdtFamily]
  used_ctors : Array[String]
}

///| Helper to test string array membership
fn array_contains(arr : Array[String], target : String) -> Bool {
  for s in arr {
    if s == target {
      return true
    }
  }
  false
}

///| Helper to join array of strings with separator
fn join_strings(arr : Array[String], sep : String) -> String {
  let buf = StringBuilder()
  for i, s in arr {
    if i > 0 {
      buf.write_string(sep)
    }
    buf.write_string(s)
  }
  buf.to_string()
}

///| Sanitize CoreLite identifier into valid HVM3 identifier name
pub fn sanitize_name(name : String) -> String {
  match name {
    "+" | "+#" => "add"
    "-" | "-#" => "sub"
    "*" | "*#" => "mul"
    "/" | "/#" => "div"
    "%" | "%#" => "mod"
    "==" | "==#" => "eq"
    "/=" | "/=#" => "ne"
    "<" | "<#" => "lt"
    ">" | ">#" => "gt"
    "<=" | "<=#" => "lte"
    ">=" | ">=#" => "gte"
    "I#" => "I_hash"
    _ => {
      let buf = StringBuilder()
      for ch in name {
        if ch == '$' || ch == '#' {
          buf.write_string("_")
        } else if ch == '+' ||
          ch == '-' ||
          ch == '*' ||
          ch == '/' ||
          ch == '<' ||
          ch == '>' ||
          ch == '=' ||
          ch == '!' {
          buf.write_string("_")
        } else {
          buf.write_char(ch)
        }
      }
      let res = buf.to_string()
      if res.length() > 0 && res[0] >= '0' && res[0] <= '9' {
        "v_" + res
      } else if res == "" {
        "_var"
      } else {
        res
      }
    }
  }
}

///| Check if an identifier is a primitive binary operator
fn is_binop(op : String) -> (Bool, String) {
  match op {
    "+" | "+#" => (true, "+")
    "-" | "-#" => (true, "-")
    "*" | "*#" => (true, "*")
    "/" | "/#" => (true, "/")
    "%" | "%#" => (true, "%")
    "==" | "==#" => (true, "==")
    "/=" | "/=#" => (true, "!=")
    "<" | "<#" => (true, "<")
    ">" | ">#" => (true, ">")
    "<=" | "<=#" => (true, "<=")
    ">=" | ">=#" => (true, ">=")
    _ => (false, "")
  }
}

///| Initialize pre-seeded standard ADT families
fn init_default_families() -> Array[AdtFamily] {
  [
    {
      _family_name: "Bool_Custom",
      ctors: [{ name: "MyTrue", arity: 0 }, { name: "MyFalse", arity: 0 }],
    },
    {
      _family_name: "Bool_Std",
      ctors: [{ name: "True", arity: 0 }, { name: "False", arity: 0 }],
    },
    {
      _family_name: "Maybe_Custom",
      ctors: [{ name: "MyNothing", arity: 0 }, { name: "MyJust", arity: 1 }],
    },
    {
      _family_name: "Maybe_Std",
      ctors: [{ name: "Nothing", arity: 0 }, { name: "Just", arity: 1 }],
    },
    {
      _family_name: "List_Custom",
      ctors: [{ name: "MyNil", arity: 0 }, { name: "MyCons", arity: 2 }],
    },
    {
      _family_name: "List_Std",
      ctors: [{ name: "Nil", arity: 0 }, { name: "Cons", arity: 2 }],
    },
    {
      _family_name: "Tree",
      ctors: [{ name: "Leaf", arity: 1 }, { name: "Node", arity: 2 }],
    },
  ]
}

///| Find the ADT family containing a constructor name
fn find_family(
  families : Array[AdtFamily],
  ctor_name : String
) -> AdtFamily? {
  for fam in families {
    for ctor in fam.ctors {
      if ctor.name == ctor_name {
        return Some(fam)
      }
    }
  }
  None
}

///| Collect all used constructors and dynamic families from expressions
fn collect_adts_from_expr(
  expr : @syntax.Expr,
  families : Array[AdtFamily],
  used_ctors : Array[String]
) -> Unit {
  match expr {
    Constr(name, args) => {
      if name != "I#" && !array_contains(used_ctors, name) {
        used_ctors.push(name)
      }
      for arg in args {
        collect_adts_from_expr(arg, families, used_ctors)
      }
    }
    Case(scrut, _bndr, alts) => {
      collect_adts_from_expr(scrut, families, used_ctors)
      let case_ctors : Array[(String, Int)] = []
      for alt in alts {
        collect_adts_from_expr(alt.expr, families, used_ctors)
        match alt.pat {
          Data(name, binders) => {
            if name != "I#" {
              if !array_contains(used_ctors, name) {
                used_ctors.push(name)
              }
              case_ctors.push((name, binders.length()))
            }
          }
          _ => ()
        }
      }
      // If case matches data constructors, check if known family exists or register new
      if case_ctors.length() > 0 {
        let first_name = case_ctors[0].0
        match find_family(families, first_name) {
          Some(fam) =>
            // Update arities if any constructor had arity 0 recorded
            for c in case_ctors {
              for fam_ctor in fam.ctors {
                if fam_ctor.name == c.0 && fam_ctor.arity == 0 && c.1 > 0 {
                  fam_ctor.arity = c.1
                }
              }
            }
          None => {
            let new_ctors : Array[CtorDef] = []
            for c in case_ctors {
              new_ctors.push({ name: c.0, arity: c.1 })
            }
            families.push({
              _family_name: "Adt_" + first_name,
              ctors: new_ctors,
            })
          }
        }
      }
    }
    App(f, arg) => {
      collect_adts_from_expr(f, families, used_ctors)
      collect_adts_from_expr(arg, families, used_ctors)
    }
    Lam(_param, body) => collect_adts_from_expr(body, families, used_ctors)
    Let(bind, body) => {
      match bind {
        NonRec(_n, val) => collect_adts_from_expr(val, families, used_ctors)
        Rec(pairs) =>
          for p in pairs {
            collect_adts_from_expr(p.1, families, used_ctors)
          }
      }
      collect_adts_from_expr(body, families, used_ctors)
    }
    _ => ()
  }
}

///| Generate HVM3 Scott-encoding definitions for all constructors in active families
fn generate_scott_constructors(ctx : LowerContext) -> Array[String] {
  let emitted_ctors : Array[String] = []
  let defs : Array[String] = []

  // Ensure any standalone used constructor belongs to a family
  for ctor_name in ctx.used_ctors {
    if ctor_name != "I#" && find_family(ctx.families, ctor_name) is None {
      ctx.families.push({
        _family_name: "Adt_" + ctor_name,
        ctors: [{ name: ctor_name, arity: 0 }],
      })
    }
  }

  for fam in ctx.families {
    // Check if any constructor of this family was used
    let mut family_used = false
    for ctor in fam.ctors {
      if array_contains(ctx.used_ctors, ctor.name) {
        family_used = true
        break
      }
    }
    if !family_used {
      continue
    }

    let n = fam.ctors.length()
    for idx, ctor in fam.ctors {
      if array_contains(emitted_ctors, ctor.name) {
        continue
      }
      emitted_ctors.push(ctor.name)

      let k = ctor.arity
      let params : Array[String] = []
      for p = 0; p < k; p = p + 1 {
        params.push("a" + p.to_string())
      }
      let conts : Array[String] = []
      for c = 0; c < n; c = c + 1 {
        conts.push("c" + c.to_string())
      }

      let all_binders : Array[String] = []
      for p in params {
        all_binders.push(p)
      }
      for c in conts {
        all_binders.push(c)
      }

      let target_cont = conts[idx]
      let body = if k == 0 {
        target_cont
      } else {
        let mut app_chain = target_cont
        for p in params {
          app_chain = "(" + app_chain + " " + p + ")"
        }
        app_chain
      }

      let mut fn_term = body
      for i = all_binders.length() - 1; i >= 0; i = i - 1 {
        fn_term = "(λ&" + all_binders[i] + " " + fn_term + ")"
      }

      defs.push("@" + sanitize_name(ctor.name) + " = " + fn_term)
    }
  }

  defs
}

///| Lower a CoreLite expression into an HVM3 term string
fn lower_expr_ctx(expr : @syntax.Expr, ctx : LowerContext) -> String {
  match expr {
    Var(name) => {
      let (is_op, op_sym) = is_binop(name)
      if is_op {
        return "(λ&_a (λ&_b (" + op_sym + " _a _b)))"
      }
      if name == "I#" {
        return "(λ&x x)"
      }
      if array_contains(ctx.globals, name) {
        "@" + sanitize_name(name)
      } else {
        sanitize_name(name)
      }
    }

    LitInt(n) => n.to_string()
    LitChar(c) => "'\{c}'"
    LitString(s) => "\"\{s}\""

    Constr(name, args) => {
      if name == "I#" {
        if args.length() == 1 {
          lower_expr_ctx(args[0], ctx)
        } else if args.length() == 0 {
          "(λ&x x)"
        } else {
          let mut res = lower_expr_ctx(args[0], ctx)
          for i = 1; i < args.length(); i = i + 1 {
            res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
          }
          res
        }
      } else {
        let ctor_ref = "@" + sanitize_name(name)
        if args.length() == 0 {
          ctor_ref
        } else {
          let mut res = ctor_ref
          for arg in args {
            res = "(" + res + " " + lower_expr_ctx(arg, ctx) + ")"
          }
          res
        }
      }
    }

    App(_, _) => {
      let (head, args) = expr.unwind_app()
      match head {
        Var(op_name) => {
          let (is_op, op_sym) = is_binop(op_name)
          if is_op {
            if args.length() == 2 {
              return "(" +
                op_sym +
                " " +
                lower_expr_ctx(args[0], ctx) +
                " " +
                lower_expr_ctx(args[1], ctx) +
                ")"
            } else if args.length() == 1 {
              return "(λ&_b (" +
                op_sym +
                " " +
                lower_expr_ctx(args[0], ctx) +
                " _b))"
            } else if args.length() == 0 {
              return "(λ&_a (λ&_b (" + op_sym + " _a _b)))"
            } else {
              let mut res = "(" +
                op_sym +
                " " +
                lower_expr_ctx(args[0], ctx) +
                " " +
                lower_expr_ctx(args[1], ctx) +
                ")"
              for i = 2; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            }
          }
          if op_name == "I#" {
            if args.length() == 1 {
              return lower_expr_ctx(args[0], ctx)
            } else if args.length() == 0 {
              return "(λ&x x)"
            }
          }
        }
        _ => ()
      }

      let mut res = lower_expr_ctx(head, ctx)
      for arg in args {
        res = "(" + res + " " + lower_expr_ctx(arg, ctx) + ")"
      }
      res
    }

    Lam(param, body) =>
      "(λ&" + sanitize_name(param) + " " + lower_expr_ctx(body, ctx) + ")"

    Let(bind, body) =>
      match bind {
        NonRec(name, val) =>
          "((λ&" +
          sanitize_name(name) +
          " " +
          lower_expr_ctx(body, ctx) +
          ") " +
          lower_expr_ctx(val, ctx) +
          ")"
        Rec(pairs) => {
          let mut res = lower_expr_ctx(body, ctx)
          for i = pairs.length() - 1; i >= 0; i = i - 1 {
            let (name, val) = pairs[i]
            res = "((λ&" +
              sanitize_name(name) +
              " " +
              res +
              ") " +
              lower_expr_ctx(val, ctx) +
              ")"
          }
          res
        }
      }

    Case(scrutinee, binder, alts) =>
      lower_case(scrutinee, binder, alts, ctx)
  }
}

///| Lower case expression
fn lower_case(
  scrutinee : @syntax.Expr,
  binder : String,
  alts : Array[@syntax.Alt],
  ctx : LowerContext
) -> String {
  // Case A: Unboxing single I# pattern: case scrut of { I# x -> body }
  if alts.length() == 1 {
    match alts[0].pat {
      Data("I#", binders) =>
        if binders.length() == 1 {
          let var_name = sanitize_name(binders[0])
          return "((λ&" +
            var_name +
            " " +
            lower_expr_ctx(alts[0].expr, ctx) +
            ") " +
            lower_expr_ctx(scrutinee, ctx) +
            ")"
        }
      Default(opt_bndr) => {
        let bnd = match opt_bndr {
          Some(v) => v
          None => if binder != "" { binder } else { "_" }
        }
        let var_name = sanitize_name(bnd)
        return "((λ&" +
          var_name +
          " " +
          lower_expr_ctx(alts[0].expr, ctx) +
          ") " +
          lower_expr_ctx(scrutinee, ctx) +
          ")"
      }
      _ => ()
    }
  }

  // Case B: Numeric match (Lit(1) / Lit(0) with Default)
  let mut lit1_alt : @syntax.Alt? = None
  let mut lit0_alt : @syntax.Alt? = None
  let mut def_alt : @syntax.Alt? = None
  let mut has_lit = false

  for alt in alts {
    match alt.pat {
      Lit(n) => {
        has_lit = true
        if n == 1 {
          lit1_alt = Some(alt)
        } else if n == 0 {
          lit0_alt = Some(alt)
        }
      }
      Default(_) => def_alt = Some(alt)
      _ => ()
    }
  }

  if has_lit {
    let scrut_str = lower_expr_ctx(scrutinee, ctx)
    // Common boolean switch: 1# -> true_case, __DEFAULT -> false_case
    if lit1_alt is Some(l1) && def_alt is Some(d) {
      let true_str = lower_expr_ctx(l1.expr, ctx)
      let false_str = lower_expr_ctx(d.expr, ctx)
      return "(~ " +
        scrut_str +
        " { 0: " +
        false_str +
        " 1+p: " +
        true_str +
        " })"
    }
    // Inverted boolean switch: 0# -> false_case, __DEFAULT -> true_case
    if lit0_alt is Some(l0) && def_alt is Some(d) {
      let false_str = lower_expr_ctx(l0.expr, ctx)
      let true_str = lower_expr_ctx(d.expr, ctx)
      return "(~ " +
        scrut_str +
        " { 0: " +
        false_str +
        " 1+p: " +
        true_str +
        " })"
    }
    // Both 0# and 1# present
    if lit0_alt is Some(l0) && lit1_alt is Some(l1) {
      let false_str = lower_expr_ctx(l0.expr, ctx)
      let true_str = lower_expr_ctx(l1.expr, ctx)
      return "(~ " +
        scrut_str +
        " { 0: " +
        false_str +
        " 1+p: " +
        true_str +
        " })"
    }
  }

  // Case C: ADT Scott-encoded pattern matching
  let mut target_family : AdtFamily? = None
  for alt in alts {
    match alt.pat {
      Data(cname, _) =>
        if cname != "I#" {
          target_family = find_family(ctx.families, cname)
          if target_family is Some(_) {
            break
          }
        }
      _ => ()
    }
  }

  match target_family {
    Some(fam) => {
      let branches : Array[String] = []
      for ctor in fam.ctors {
        // Find alternative matching this constructor
        let mut matched_alt : @syntax.Alt? = None
        for alt in alts {
          match alt.pat {
            Data(cname, _) => if cname == ctor.name { matched_alt = Some(alt) }
            _ => ()
          }
        }

        match matched_alt {
          Some(alt) =>
            match alt.pat {
              Data(_, binders) => {
                let mut b_str = lower_expr_ctx(alt.expr, ctx)
                for i = binders.length() - 1; i >= 0; i = i - 1 {
                  b_str = "(λ&" + sanitize_name(binders[i]) + " " + b_str + ")"
                }
                branches.push(b_str)
              }
              _ => branches.push(lower_expr_ctx(alt.expr, ctx))
            }
          None =>
            // Fallback to __DEFAULT alternative if present
            match def_alt {
              Some(d) => {
                let mut b_str = lower_expr_ctx(d.expr, ctx)
                for _i = 0; _i < ctor.arity; _i = _i + 1 {
                  b_str = "(λ&_ " + b_str + ")"
                }
                branches.push(b_str)
              }
              None => branches.push("*")
            }
        }
      }

      let mut case_app = lower_expr_ctx(scrutinee, ctx)
      for branch in branches {
        case_app = "(" + case_app + " " + branch + ")"
      }

      if binder != "" {
        "((λ&" +
        sanitize_name(binder) +
        " " +
        case_app +
        ") " +
        lower_expr_ctx(scrutinee, ctx) +
        ")"
      } else {
        case_app
      }
    }
    None => {
      // Fallback: If only default branch exists
      match def_alt {
        Some(d) =>
          if binder != "" {
            "((λ&" +
            sanitize_name(binder) +
            " " +
            lower_expr_ctx(d.expr, ctx) +
            ") " +
            lower_expr_ctx(scrutinee, ctx) +
            ")"
          } else {
            lower_expr_ctx(d.expr, ctx)
          }
        None => lower_expr_ctx(scrutinee, ctx)
      }
    }
  }
}

///| Lower an entire CoreLite program into complete HVM3 source code
pub fn lower_program(program : @syntax.Program) -> String {
  let globals : Array[String] = []
  for b in program.binds {
    match b {
      NonRec(name, _) =>
        if !array_contains(globals, name) {
          globals.push(name)
        }
      Rec(pairs) =>
        for p in pairs {
          if !array_contains(globals, p.0) {
            globals.push(p.0)
          }
        }
    }
  }

  let families = init_default_families()
  let used_ctors : Array[String] = []

  for b in program.binds {
    match b {
      NonRec(_, expr) =>
        collect_adts_from_expr(expr, families, used_ctors)
      Rec(pairs) =>
        for p in pairs {
          collect_adts_from_expr(p.1, families, used_ctors)
        }
    }
  }

  let ctx : LowerContext = { globals, families, used_ctors }

  let lines : Array[String] = []

  // 1. Emit Scott constructor definitions
  let scott_defs = generate_scott_constructors(ctx)
  for def in scott_defs {
    lines.push(def)
  }
  if scott_defs.length() > 0 {
    lines.push("")
  }

  // 2. Emit top-level function definitions
  let mut has_main = false
  let mut has_result = false

  for b in program.binds {
    match b {
      NonRec(name, expr) => {
        if name == "main" {
          has_main = true
        }
        if name == "result" {
          has_result = true
        }
        let sanitized = sanitize_name(name)
        let lowered_val = lower_expr_ctx(expr, ctx)
        lines.push("@" + sanitized + " = " + lowered_val)
      }
      Rec(pairs) =>
        for pair in pairs {
          let (name, expr) = pair
          if name == "main" {
            has_main = true
          }
          if name == "result" {
            has_result = true
          }
          let sanitized = sanitize_name(name)
          let lowered_val = lower_expr_ctx(expr, ctx)
          lines.push("@" + sanitized + " = " + lowered_val)
        }
    }
  }

  // 3. Ensure entrypoint @main exists
  if !has_main {
    lines.push("")
    if has_result {
      lines.push("@main = @result")
    } else if globals.length() > 0 {
      lines.push("@main = @" + sanitize_name(globals[globals.length() - 1]))
    } else {
      lines.push("@main = 0")
    }
  }

  join_strings(lines, "\n")
}

///| Alias for lower_program
pub fn lower(program : @syntax.Program) -> String {
  lower_program(program)
}

///| Lower a standalone CoreLite expression into an HVM3 term string
pub fn lower_expr(expr : @syntax.Expr) -> String {
  let ctx : LowerContext = {
    globals: [],
    families: init_default_families(),
    used_ctors: [],
  }
  lower_expr_ctx(expr, ctx)
}
