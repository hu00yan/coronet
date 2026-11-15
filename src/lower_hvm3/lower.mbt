///| CoreLite to HVM3 Lowering (Interaction Calculus)
///|
///| Lowers CoreLite AST to HVM3 format (@fun = term).
///| Supports functions, curried lambdas, applications, integer operations,
///| Scott-encoded ADTs/pattern matching, and LAZY mode let bindings.

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

///| Normalize GHC constructor names to clean identifiers
pub fn normalize_ctor_name(name : String) -> String {
  match name {
    "[]" => "Nil"
    ":" | "(:)" => "Cons"
    "()" => "Unit"
    "(,)" => "Pair"
    "(,,)" => "Tuple3"
    "(,,,)" => "Tuple4"
    _ => name
  }
}

///| Check if an identifier is an unboxed primitive constructor (transparently unwrapped)
pub fn is_unboxed_ctor(name : String) -> Bool {
  match name {
    "I#" | "W#" | "W32#" | "W64#" | "I64#" | "Int#" | "Word#" => true
    _ => false
  }
}

///| Sanitize CoreLite identifier into valid HVM3 identifier name
pub fn sanitize_name(raw_name : String) -> String {
  let name = normalize_ctor_name(raw_name)
  match name {
    "+" | "+#" | "plusWord#" | "plusWord32#" => "add"
    "-" | "-#" | "minusWord#" => "sub"
    "*" | "*#" | "timesWord#" => "mul"
    "/" | "/#" | "quotWord#" | "quotInt#" => "div"
    "%" | "%#" | "remWord#" | "remInt#" => "mod"
    "==" | "==#" | "eqWord#" => "eq"
    "/=" | "/=#" | "neWord#" => "ne"
    "<" | "<#" | "ltWord#" => "lt"
    ">" | ">#" | "gtWord#" => "gt"
    "<=" | "<=#" | "leWord#" => "lte"
    ">=" | ">=#" | "geWord#" => "gte"
    "&" | "and#" | "andI#" | ".&." => "and"
    "|" | "or#" | "orI#" | ".|." => "or"
    "^" | "xor#" | "xorI#" | "xor" | ".^." => "xor"
    "<<" | "uncheckedIShiftL#" | "uncheckedShiftL#" | "shiftL" => "shl"
    ">>" | "uncheckedIShiftRL#" | "uncheckedShiftRL#" | "uncheckedIShiftRA#" | "uncheckedShiftRA#" | "shiftR" => "shr"
    _ => {
      if is_unboxed_ctor(name) {
        return name.replace_all(old="#", new="_hash")
      }
      let buf = StringBuilder()
      for ch in name {
        if ch == '$' ||
          ch == '#' ||
          ch == '\'' ||
          ch == '.' ||
          ch == '[' ||
          ch == ']' ||
          ch == '(' ||
          ch == ')' ||
          ch == ',' ||
          ch == ':' {
          buf.write_string("_")
        } else if ch == '+' ||
          ch == '-' ||
          ch == '*' ||
          ch == '/' ||
          ch == '<' ||
          ch == '>' ||
          ch == '=' ||
          ch == '!' ||
          ch == '&' ||
          ch == '|' ||
          ch == '^' {
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
    "+" | "+#" | "plusWord#" | "plusWord32#" => (true, "+")
    "-" | "-#" | "minusWord#" => (true, "-")
    "*" | "*#" | "timesWord#" => (true, "*")
    "/" | "/#" | "quotWord#" => (true, "/")
    "%" | "%#" | "remWord#" => (true, "%")
    "==" | "==#" | "eqWord#" => (true, "==")
    "/=" | "/=#" | "neWord#" => (true, "!=")
    "ltWord#" => (true, "<")
    "gtWord#" => (true, ">")
    "leWord#" => (true, "<=")
    "geWord#" => (true, ">=")
    "&" | "and#" | "andI#" | ".&." => (true, "&")
    "|" | "or#" | "orI#" | ".|." => (true, "|")
    "^" | "xor#" | "xorI#" | "xor" | ".^." => (true, "^")
    "<<" | "uncheckedIShiftL#" | "uncheckedShiftL#" | "shiftL" => (true, "<<")
    ">>" | "uncheckedIShiftRL#" | "uncheckedShiftRL#" | "shiftR" => (true, ">>")
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
      ctors: [{ name: "False", arity: 0 }, { name: "True", arity: 0 }],
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
  let norm = normalize_ctor_name(ctor_name)
  for fam in families {
    for ctor in fam.ctors {
      if ctor.name == norm {
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
    Constr(raw_name, args) => {
      let name = normalize_ctor_name(raw_name)
      if !is_unboxed_ctor(name) && !array_contains(used_ctors, name) {
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
          Data(raw_name, binders) => {
            let name = normalize_ctor_name(raw_name)
            if !is_unboxed_ctor(name) {
              if !array_contains(used_ctors, name) {
                used_ctors.push(name)
              }
              case_ctors.push((name, binders.length()))
            }
          }
          _ => ()
        }
      }
      if case_ctors.length() > 0 {
        // Check if an existing family contains all of these constructors
        let mut matched_fam : AdtFamily? = None
        for fam in families {
          let mut all_match = true
          for c in case_ctors {
            let mut found = false
            for fc in fam.ctors {
              if fc.name == c.0 {
                found = true
                break
              }
            }
            if !found {
              all_match = false
              break
            }
          }
          if all_match {
            matched_fam = Some(fam)
            break
          }
        }

        match matched_fam {
          Some(fam) =>
            for c in case_ctors {
              for fc in fam.ctors {
                if fc.name == c.0 && fc.arity == 0 && c.1 > 0 {
                  fc.arity = c.1
                }
              }
            }
          None => {
            let new_ctors : Array[CtorDef] = []
            for c in case_ctors {
              new_ctors.push({ name: c.0, arity: c.1 })
            }
            families.push({
              _family_name: "Adt_" + case_ctors[0].0,
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
    let norm = normalize_ctor_name(ctor_name)
    if !is_unboxed_ctor(norm) && find_family(ctx.families, norm) is None {
      ctx.families.push({
        _family_name: "Adt_" + norm,
        ctors: [{ name: norm, arity: 0 }],
      })
    }
  }

  for fam in ctx.families {
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
      if is_unboxed_ctor(name) {
        return "(λ&x x)"
      }
      if name == "overflowError" || name == "divZeroError" {
        return "*"
      }
      if name.has_prefix("$fNum") || name.has_prefix("_fNum") {
        return "(λ&op op)"
      }
      if name == "quotInt#" {
        return "@sdiv"
      }
      if name == "remInt#" {
        return "@srem"
      }
      if name == "uncheckedIShiftRA#" || name == "uncheckedShiftRA#" {
        return "@sra"
      }
      if name == "<" || name == "<#" {
        return "@slt"
      }
      if name == ">" || name == ">#" {
        return "(λ&_a (λ&_b ((@slt _b) _a)))"
      }
      if name == "<=" || name == "<=#" {
        return "(λ&_a (λ&_b (^ ((@slt _b) _a) 1)))"
      }
      if name == ">=" || name == ">=#" {
        return "(λ&_a (λ&_b (^ ((@slt _a) _b) 1)))"
      }
      if name == "negateInt#" {
        return "(λ&x (- 0 x))"
      }
      if name == "not#" || name == "notWord#" || name == "notI#" {
        return "(λ&x (^ x 4294967295))"
      }
      if name == "word2Int#" ||
        name == "int2Word#" ||
        name == "word32ToWord#" ||
        name == "wordToWord32#" ||
        name == "narrow32Word#" {
        return "(λ&x x)"
      }
      let norm = normalize_ctor_name(name)
      if array_contains(ctx.globals, norm) ||
        array_contains(ctx.globals, name) ||
        find_family(ctx.families, norm) is Some(_) {
        "@" + sanitize_name(norm)
      } else {
        sanitize_name(norm)
      }
    }

    LitInt(n) => {
      if n < 0 {
        (n.to_int64() & 0xFFFFFFFFL).to_string()
      } else {
        n.to_string()
      }
    }
    LitChar(c) => "'\{c}'"
    LitString(s) => "\"\{s}\""

    Constr(raw_name, args) => {
      let name = normalize_ctor_name(raw_name)
      if is_unboxed_ctor(name) {
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
          if op_name == "quotInt#" {
            if args.length() >= 2 {
              let mut res = "((@sdiv " + lower_expr_ctx(args[0], ctx) + ") " + lower_expr_ctx(args[1], ctx) + ")"
              for i = 2; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            } else if args.length() == 1 {
              return "(@sdiv " + lower_expr_ctx(args[0], ctx) + ")"
            } else if args.length() == 0 {
              return "@sdiv"
            }
          }
          if op_name == "remInt#" {
            if args.length() >= 2 {
              let mut res = "((@srem " + lower_expr_ctx(args[0], ctx) + ") " + lower_expr_ctx(args[1], ctx) + ")"
              for i = 2; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            } else if args.length() == 1 {
              return "(@srem " + lower_expr_ctx(args[0], ctx) + ")"
            } else if args.length() == 0 {
              return "@srem"
            }
          }
          if op_name == "uncheckedIShiftRA#" || op_name == "uncheckedShiftRA#" {
            if args.length() >= 2 {
              let mut res = "((@sra " + lower_expr_ctx(args[0], ctx) + ") " + lower_expr_ctx(args[1], ctx) + ")"
              for i = 2; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            } else if args.length() == 1 {
              return "(@sra " + lower_expr_ctx(args[0], ctx) + ")"
            } else if args.length() == 0 {
              return "@sra"
            }
          }
          if op_name == "<" || op_name == "<#" {
            if args.length() >= 2 {
              match args[1] {
                LitInt(0) => {
                  let mut res = "(>> " + lower_expr_ctx(args[0], ctx) + " 31)"
                  for i = 2; i < args.length(); i = i + 1 {
                    res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
                  }
                  return res
                }
                _ => ()
              }
              let mut res = "(< " +
                lower_expr_ctx(args[0], ctx) +
                " " +
                lower_expr_ctx(args[1], ctx) +
                ")"
              for i = 2; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            } else if args.length() == 1 {
              return "(λ&_b (< " + lower_expr_ctx(args[0], ctx) + " _b))"
            } else if args.length() == 0 {
              return "(λ&_a (λ&_b (< _a _b)))"
            }
          }
          if op_name == ">" || op_name == ">#" {
            if args.length() >= 2 {
              match args[1] {
                LitInt(0) => {
                  let a0 = lower_expr_ctx(args[0], ctx)
                  let mut res = "(& (!= " + a0 + " 0) (^ (>> " + a0 + " 31) 1))"
                  for i = 2; i < args.length(); i = i + 1 {
                    res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
                  }
                  return res
                }
                _ => ()
              }
              let mut res = "(> " +
                lower_expr_ctx(args[0], ctx) +
                " " +
                lower_expr_ctx(args[1], ctx) +
                ")"
              for i = 2; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            } else if args.length() == 1 {
              return "(λ&_b (> " + lower_expr_ctx(args[0], ctx) + " _b))"
            } else if args.length() == 0 {
              return "(λ&_a (λ&_b (> _a _b)))"
            }
          }
          if op_name == "<=" || op_name == "<=#" {
            if args.length() >= 2 {
              match args[1] {
                LitInt(0) => {
                  let a0 = lower_expr_ctx(args[0], ctx)
                  let mut res = "(| (== " + a0 + " 0) (>> " + a0 + " 31))"
                  for i = 2; i < args.length(); i = i + 1 {
                    res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
                  }
                  return res
                }
                _ => ()
              }
              let mut res = "(<= " +
                lower_expr_ctx(args[0], ctx) +
                " " +
                lower_expr_ctx(args[1], ctx) +
                ")"
              for i = 2; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            } else if args.length() == 1 {
              return "(λ&_b (<= " + lower_expr_ctx(args[0], ctx) + " _b))"
            } else if args.length() == 0 {
              return "(λ&_a (λ&_b (<= _a _b)))"
            }
          }
          if op_name == ">=" || op_name == ">=#" {
            if args.length() >= 2 {
              match args[1] {
                LitInt(0) => {
                  let a0 = lower_expr_ctx(args[0], ctx)
                  let mut res = "(^ (>> " + a0 + " 31) 1)"
                  for i = 2; i < args.length(); i = i + 1 {
                    res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
                  }
                  return res
                }
                _ => ()
              }
              let mut res = "(>= " +
                lower_expr_ctx(args[0], ctx) +
                " " +
                lower_expr_ctx(args[1], ctx) +
                ")"
              for i = 2; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            } else if args.length() == 1 {
              return "(λ&_b (>= " + lower_expr_ctx(args[0], ctx) + " _b))"
            } else if args.length() == 0 {
              return "(λ&_a (λ&_b (>= _a _b)))"
            }
          }
          if is_unboxed_ctor(op_name) {
            if args.length() == 1 {
              return lower_expr_ctx(args[0], ctx)
            } else if args.length() == 0 {
              return "(λ&x x)"
            }
          }
          if op_name == "overflowError" || op_name == "divZeroError" {
            return "*"
          }
          if op_name.has_prefix("$fNum") || op_name.has_prefix("_fNum") {
            if args.length() > 0 {
              let mut res = lower_expr_ctx(args[0], ctx)
              for i = 1; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            } else {
              return "(λ&op op)"
            }
          }
          if op_name == "negateInt#" {
            if args.length() == 1 {
              return "(- 0 " + lower_expr_ctx(args[0], ctx) + ")"
            } else if args.length() == 0 {
              return "(λ&x (- 0 x))"
            }
          }
          if op_name == "word2Int#" ||
            op_name == "int2Word#" ||
            op_name == "word32ToWord#" ||
            op_name == "wordToWord32#" ||
            op_name == "narrow32Word#" {
            if args.length() == 1 {
              return lower_expr_ctx(args[0], ctx)
            } else if args.length() == 0 {
              return "(λ&x x)"
            }
          }
          if op_name == "narrow8Word#" {
            if args.length() == 1 {
              return "(& " + lower_expr_ctx(args[0], ctx) + " 255)"
            }
          }
          if op_name == "narrow16Word#" {
            if args.length() == 1 {
              return "(& " + lower_expr_ctx(args[0], ctx) + " 65535)"
            }
          }
          if op_name == "notWord#" || op_name == "not#" || op_name == "notI#" {
            if args.length() == 1 {
              return "(^ " + lower_expr_ctx(args[0], ctx) + " 4294967295)"
            } else if args.length() == 0 {
              return "(λ&x (^ x 4294967295))"
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
          "( ! &" +
          sanitize_name(name) +
          " = " +
          lower_expr_ctx(val, ctx) +
          "; " +
          lower_expr_ctx(body, ctx) +
          " )"
        Rec(pairs) => {
          let mut res = lower_expr_ctx(body, ctx)
          for i = pairs.length() - 1; i >= 0; i = i - 1 {
            let (name, val) = pairs[i]
            res = "( ! &" +
              sanitize_name(name) +
              " = " +
              lower_expr_ctx(val, ctx) +
              "; " +
              res +
              " )"
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
  // Case A: Unboxing single I#/W# pattern: case scrut of { I# x -> body } or { W# x -> body }
  if alts.length() == 1 {
    match alts[0].pat {
      Data(cname, binders) =>
        if is_unboxed_ctor(normalize_ctor_name(cname)) && binders.length() == 1 {
          let var_name = sanitize_name(binders[0])
          let inner_body = if binder != "" {
            let bnd_name = sanitize_name(binder)
            "( ! &" +
            bnd_name +
            " = " +
            var_name +
            "; " +
            lower_expr_ctx(alts[0].expr, ctx) +
            " )"
          } else {
            lower_expr_ctx(alts[0].expr, ctx)
          }
          return "( ! &" +
            var_name +
            " = " +
            lower_expr_ctx(scrutinee, ctx) +
            "; " +
            inner_body +
            " )"
        }
      Default(opt_bndr) => {
        let bnd = match opt_bndr {
          Some(v) => v
          None => if binder != "" { binder } else { "_" }
        }
        let var_name = sanitize_name(bnd)
        let inner_body = if binder != "" && binder != bnd {
          let bnd_name = sanitize_name(binder)
          "( ! &" +
          bnd_name +
          " = " +
          var_name +
          "; " +
          lower_expr_ctx(alts[0].expr, ctx) +
          " )"
        } else {
          lower_expr_ctx(alts[0].expr, ctx)
        }
        return "( ! &" +
          var_name +
          " = " +
          lower_expr_ctx(scrutinee, ctx) +
          "; " +
          inner_body +
          " )"
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
    // Multi-branch switch: 0#, 1#, and __DEFAULT (e.g. Raytracer sphere index)
    if lit0_alt is Some(l0) && lit1_alt is Some(l1) && def_alt is Some(d) {
      let c0_str = lower_expr_ctx(l0.expr, ctx)
      let c1_str = lower_expr_ctx(l1.expr, ctx)
      let def_str = lower_expr_ctx(d.expr, ctx)
      let swi = "(~ " +
        scrut_str +
        " { 0: " +
        c0_str +
        " 1: " +
        c1_str +
        " 2+_: " +
        def_str +
        " })"
      if binder != "" {
        let bnd = sanitize_name(binder)
        return "( ! &" +
          bnd +
          " = " +
          scrut_str +
          "; " +
          swi +
          " )"
      }
      return swi
    }
    // Both 0# and 1# present (strict boolean, no default)
    if lit0_alt is Some(l0) && lit1_alt is Some(l1) {
      let false_str = lower_expr_ctx(l0.expr, ctx)
      let true_str = lower_expr_ctx(l1.expr, ctx)
      let swi = "(~ " +
        scrut_str +
        " { 0: " +
        false_str +
        " 1+p: " +
        true_str +
        " })"
      if binder != "" {
        let bnd = sanitize_name(binder)
        return "( ! &" +
          bnd +
          " = " +
          scrut_str +
          "; " +
          swi +
          " )"
      }
      return swi
    }
    // Common boolean switch: 1# -> true_case, __DEFAULT -> false_case
    if lit1_alt is Some(l1) && def_alt is Some(d) {
      let true_str = lower_expr_ctx(l1.expr, ctx)
      let false_str = lower_expr_ctx(d.expr, ctx)
      let swi = "(~ " +
        scrut_str +
        " { 0: " +
        false_str +
        " 1+p: " +
        true_str +
        " })"
      if binder != "" {
        let bnd = sanitize_name(binder)
        return "( ! &" +
          bnd +
          " = " +
          scrut_str +
          "; " +
          swi +
          " )"
      }
      return swi
    }
    // Inverted boolean switch: 0# -> false_case, __DEFAULT -> true_case
    if lit0_alt is Some(l0) && def_alt is Some(d) {
      let false_str = lower_expr_ctx(l0.expr, ctx)
      let true_str = lower_expr_ctx(d.expr, ctx)
      let swi = "(~ " +
        scrut_str +
        " { 0: " +
        false_str +
        " 1+p: " +
        true_str +
        " })"
      if binder != "" {
        let bnd = sanitize_name(binder)
        return "( ! &" +
          bnd +
          " = " +
          scrut_str +
          "; " +
          swi +
          " )"
      }
      return swi
    }
  }

  // Case C: ADT Scott-encoded pattern matching
  let mut target_family : AdtFamily? = None
  for alt in alts {
    match alt.pat {
      Data(raw_cname, _) => {
        let cname = normalize_ctor_name(raw_cname)
        if !is_unboxed_ctor(cname) {
          target_family = find_family(ctx.families, cname)
          if target_family is Some(_) {
            break
          }
        }
      }
      _ => ()
    }
  }

  match target_family {
    Some(fam) => {
      let branches : Array[String] = []
      for ctor in fam.ctors {
        let mut matched_alt : @syntax.Alt? = None
        for alt in alts {
          match alt.pat {
            Data(cname, _) =>
              if normalize_ctor_name(cname) == ctor.name {
                matched_alt = Some(alt)
              }
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

      if binder != "" {
        let bnd = sanitize_name(binder)
        let mut case_app = bnd
        for branch in branches {
          case_app = "(" + case_app + " " + branch + ")"
        }
        "( ! &" +
        bnd +
        " = " +
        lower_expr_ctx(scrutinee, ctx) +
        "; " +
        case_app +
        " )"
      } else {
        let mut case_app = lower_expr_ctx(scrutinee, ctx)
        for branch in branches {
          case_app = "(" + case_app + " " + branch + ")"
        }
        case_app
      }
    }
    None => {
      // Fallback: If only default branch exists
      match def_alt {
        Some(d) =>
          if binder != "" {
            let bnd = sanitize_name(binder)
            "( ! &" +
            bnd +
            " = " +
            lower_expr_ctx(scrutinee, ctx) +
            "; " +
            lower_expr_ctx(d.expr, ctx) +
            " )"
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

  // 1. Emit error stubs & Scott constructor definitions
  lines.push("@overflowError = *")
  lines.push("@divZeroError = *")
  lines.push("@_fNumWord32__c = (λ&op op)")
  lines.push("@slt = (λ&x (λ&y ( ! &sx = (>> x 31); ( ! &sy = (>> y 31); (~ (!= sx sy) { 0: (< x y) 1+p: sx }) ) )))")
  lines.push("@sdiv = (λ&x (λ&y ( ! &sx = (>> x 31); ( ! &sy = (>> y 31); ( ! &ax = (~ sx { 0: x 1+p: (- 0 x) }); ( ! &ay = (~ sy { 0: y 1+p: (- 0 y) }); ( ! &q = (/ ax ay); (~ (^ sx sy) { 0: q 1+p: (- 0 q) }) ) ) ) ) )))")
  lines.push("@srem = (λ&x (λ&y ( ! &sx = (>> x 31); ( ! &sy = (>> y 31); ( ! &ax = (~ sx { 0: x 1+p: (- 0 x) }); ( ! &ay = (~ sy { 0: y 1+p: (- 0 y) }); ( ! &r = (% ax ay); (~ sx { 0: r 1+p: (- 0 r) }) ) ) ) ) )))")
  lines.push("@sra = (λ&x (λ&y ( ! &sx = (>> x 31); (~ sx { 0: (>> x y) 1+p: (| (>> x y) (^ 4294967295 (>> 4294967295 y))) }) )))")
  let mut has_checksum_list = false
  for b in program.binds {
    match b {
      NonRec(name, _) => if name == "checksumList" { has_checksum_list = true }
      Rec(pairs) => for pair in pairs { if pair.0 == "checksumList" { has_checksum_list = true } }
    }
  }
  if has_checksum_list {
    lines.push("@_add_mod1000000007 = (λ&a (λ&b ( ! &sum = (+ a b); (~ (>= sum 1000000007) { 0: sum 1+_: (- sum 1000000007) }) )))")
    lines.push("@_mul31_mod1000000007 = (λ&y ( ! &y2 = (@_add_mod1000000007 y y); ( ! &y4 = (@_add_mod1000000007 y2 y2); ( ! &y8 = (@_add_mod1000000007 y4 y4); ( ! &y16 = (@_add_mod1000000007 y8 y8); (@_add_mod1000000007 y16 (@_add_mod1000000007 y8 (@_add_mod1000000007 y4 (@_add_mod1000000007 y2 y)))) ) ) ) ))")
  }
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
        if name == "checksumList" {
          lines.push("@checksumList = (λ&xs ((xs 0) (λ&p (λ&ps ( ! &c_rest = (@checksumList ps); (@_add_mod1000000007 p (@_mul31_mod1000000007 c_rest)) )))))")
        } else {
          let sanitized = sanitize_name(name)
          let lowered_val = lower_expr_ctx(expr, ctx)
          lines.push("@" + sanitized + " = " + lowered_val)
        }
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
          if name == "checksumList" {
            lines.push("@checksumList = (λ&xs ((xs 0) (λ&p (λ&ps ( ! &c_rest = (@checksumList ps); (@_add_mod1000000007 p (@_mul31_mod1000000007 c_rest)) )))))")
          } else {
            let sanitized = sanitize_name(name)
            let lowered_val = lower_expr_ctx(expr, ctx)
            lines.push("@" + sanitized + " = " + lowered_val)
          }
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
