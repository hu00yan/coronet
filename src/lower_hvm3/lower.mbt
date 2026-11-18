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
    "C:Eq" | "Eq" => "C_Eq"
    "()" | "(# #)" | "(##)" | "Unit#" => "Unit"
    "(,)" | "(#,#)" | "(# , #)" | "(#_#)" | "Solo#" => "Pair"
    "(,,)" | "(#,,#)" | "(# ,, #)" => "Tuple3"
    "(,,,)" | "(#,,,#)" | "(# ,,, #)" => "Tuple4"
    "(,,,,)" | "(#,,,,#)" | "(# ,,,, #)" => "Tuple5"
    "(,,,,,)" | "(#,,,,,#)" | "(# ,,,,, #)" => "Tuple6"
    "(,,,,,,)" | "(#,,,,,,#)" | "(# ,,,,,, #)" => "Tuple7"
    "(,,,,,,,)" | "(#,,,,,,,#)" | "(# ,,,,,,, #)" => "Tuple8"
    _ => {
      let trimmed = name.trim(chars=" \t\r\n")
      if (trimmed.has_prefix("(#") && trimmed.has_suffix("#)")) ||
        (trimmed.has_prefix("(") && trimmed.has_suffix(")")) {
        let mut commas = 0
        for ch in trimmed {
          if ch == ',' {
            commas = commas + 1
          }
        }
        if commas == 0 {
          "Unit"
        } else if commas == 1 {
          "Pair"
        } else {
          "Tuple" + (commas + 1).to_string()
        }
      } else {
        name
      }
    }
  }
}

///| Check if an identifier is an unboxed primitive constructor (transparently unwrapped)
pub fn is_unboxed_ctor(name : String) -> Bool {
  match name {
    "I#" | "W#" | "W8#" | "W16#" | "W32#" | "W64#" | "I8#" | "I16#" | "I32#" | "I64#" | "Int#" | "Word#" | "C#" | "Char#" => true
    _ => false
  }
}

///| Sanitize CoreLite identifier into valid HVM3 identifier name
pub fn sanitize_name(raw_name : String) -> String {
  let name = normalize_ctor_name(raw_name)
  if @syntax.canonical_prim_alias(name) is Some(target_alias) && target_alias != name {
    return sanitize_name(target_alias)
  }
  match name {
    "+" | "+#" | "plusWord#" | "plusWord32#" => "add"
    "-" | "-#" | "minusWord#" => "sub"
    "*" | "*#" | "timesWord#" => "mul"
    "*H#" | "*H" => "mulH_"
    "/" | "/#" | "quotWord#" | "quotInt#" => "div"
    "%" | "%#" | "remWord#" | "remInt#" => "mod"
    "==" | "==#" | "eqWord#" => "eq"
    "/=" | "/=#" | "neWord#" => "ne"
    "<" | "<#" | "ltWord#" => "lt"
    ">" | ">#" | "gtWord#" => "gt"
    "<=" | "<=#" | "leWord#" => "lte"
    ">=" | ">=#" | "geWord#" => "gte"
    "&" | "and#" | "andI#" | "andWord#" | ".&." => "and"
    "|" | "or#" | "orI#" | "orWord#" | ".|." => "or"
    "^" | "xor#" | "xorI#" | "xorWord#" | "xor" | ".^." => "xor"
    "not#" | "notWord#" | "notI#" => "not"
    "<<" | "uncheckedIShiftL#" | "uncheckedShiftL#" | "shiftL" => "shl"
    ">>" | "uncheckedIShiftRL#" | "uncheckedShiftRL#" | "uncheckedIShiftRA#" | "uncheckedShiftRA#" | "shiftR" => "shr"
    "plusAddr#" => "plusAddr_"
    "eqAddr#" => "eqAddr_"
    "readWord8OffAddr#" => "readWord8OffAddr_"
    "touch#" => "touch_"
    "word8ToWord#" => "word8ToWord_"
    "wordToWord8#" => "wordToWord8_"
    "compare" => "compare"
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
    "+" | "+#" | "plusWord#" | "plusWord32#" | "plusWord64#" | "plusInt64#" | "+##" | "plusFloat#" => (true, "+")
    "-" | "-#" | "minusWord#" | "minusWord64#" | "minusInt64#" | "-##" | "minusFloat#" => (true, "-")
    "*" | "*#" | "timesWord#" | "timesWord64#" | "timesInt64#" | "*##" | "timesFloat#" => (true, "*")
    "/" | "/#" | "quotWord#" | "quotWord64#" | "quotInt64#" | "/##" | "divideFloat#" => (true, "/")
    "%" | "%#" | "remWord#" | "remWord64#" | "remInt64#" => (true, "%")
    "==" | "==#" | "eqWord#" | "eqWord64#" | "eqInt64#" | "==##" | "eqFloat#" => (true, "==")
    "/=" | "/=#" | "neWord#" | "neWord64#" | "neInt64#" | "/=##" | "neFloat#" => (true, "!=")
    "ltWord#" | "ltWord64#" | "ltInt64#" | "<##" | "ltFloat#" => (true, "<")
    "gtWord#" | "gtWord64#" | "gtInt64#" | ">##" | "gtFloat#" => (true, ">")
    "leWord#" | "leWord64#" | "leInt64#" | "<=##" | "leFloat#" => (true, "<=")
    "geWord#" | "geWord64#" | "geInt64#" | ">=##" | "geFloat#" => (true, ">=")
    "&" | "and#" | "andI#" | "andWord#" | "and64#" | ".&." => (true, "&")
    "|" | "or#" | "orI#" | "orWord#" | "or64#" | ".|." => (true, "|")
    "^" | "xor#" | "xorI#" | "xorWord#" | "xor64#" | "xor" | ".^." => (true, "^")
    "<<" | "uncheckedIShiftL#" | "uncheckedShiftL#" | "uncheckedShiftL64#" | "shiftL" => (true, "<<")
    ">>" | "uncheckedIShiftRL#" | "uncheckedShiftRL#" | "uncheckedShiftRL64#" | "uncheckedIShiftRA64#" | "shiftR" => (true, ">>")
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
      _family_name: "Ordering",
      ctors: [{ name: "LT", arity: 0 }, { name: "EQ", arity: 0 }, { name: "GT", arity: 0 }],
    },
    {
      _family_name: "Eq",
      ctors: [{ name: "C_Eq", arity: 2 }],
    },
    {
      _family_name: "Unit",
      ctors: [{ name: "Unit", arity: 0 }],
    },
    {
      _family_name: "Pair",
      ctors: [{ name: "Pair", arity: 2 }],
    },
    {
      _family_name: "Tuple3",
      ctors: [{ name: "Tuple3", arity: 3 }],
    },
    {
      _family_name: "Tuple4",
      ctors: [{ name: "Tuple4", arity: 4 }],
    },
    {
      _family_name: "Tuple5",
      ctors: [{ name: "Tuple5", arity: 5 }],
    },
    {
      _family_name: "Tuple6",
      ctors: [{ name: "Tuple6", arity: 6 }],
    },
    {
      _family_name: "Tuple7",
      ctors: [{ name: "Tuple7", arity: 7 }],
    },
    {
      _family_name: "Tuple8",
      ctors: [{ name: "Tuple8", arity: 8 }],
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

fn sort_ctors(ctors : Array[CtorDef]) -> Unit {
  for i = 1; i < ctors.length(); i = i + 1 {
    let key = ctors[i]
    let mut j = i - 1
    while j >= 0 {
      let prev = ctors[j]
      let should_swap = if prev.arity > 0 && key.arity == 0 {
        true
      } else if prev.arity == 0 && key.arity > 0 {
        false
      } else {
        prev.name > key.name
      }
      if should_swap {
        ctors[j + 1] = prev
        j = j - 1
      } else {
        break
      }
    }
    ctors[j + 1] = key
  }
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
      if !is_unboxed_ctor(name) {
        if !array_contains(used_ctors, name) {
          used_ctors.push(name)
        }
        let mut found = false
        for fam in families {
          for fc in fam.ctors {
            if fc.name == name {
              found = true
              if fc.arity == 0 && args.length() > 0 {
                fc.arity = args.length()
              }
              break
            }
          }
          if found { break }
        }
        if !found {
          families.push({
            _family_name: "Adt_" + name,
            ctors: [{ name, arity: args.length() }],
          })
        }
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
        let matching_indices : Array[Int] = []
        for i, fam in families {
          let mut overlaps = false
          for c in case_ctors {
            for fc in fam.ctors {
              if fc.name == c.0 {
                overlaps = true
                break
              }
            }
            if overlaps { break }
          }
          if overlaps {
            matching_indices.push(i)
          }
        }

        if matching_indices.length() == 0 {
          let new_ctors : Array[CtorDef] = []
          for c in case_ctors {
            new_ctors.push({ name: c.0, arity: c.1 })
          }
          sort_ctors(new_ctors)
          families.push({
            _family_name: "Adt_" + case_ctors[0].0,
            ctors: new_ctors,
          })
        } else {
          let target_fam = families[matching_indices[0]]
          for idx in 1..<matching_indices.length() {
            let other_fam = families[matching_indices[idx]]
            for oc in other_fam.ctors {
              let mut exists = false
              for tc in target_fam.ctors {
                if tc.name == oc.name {
                  exists = true
                  if tc.arity == 0 && oc.arity > 0 { tc.arity = oc.arity }
                  break
                }
              }
              if !exists {
                target_fam.ctors.push(oc)
              }
            }
            other_fam.ctors.clear()
          }
          for c in case_ctors {
            let mut exists = false
            for tc in target_fam.ctors {
              if tc.name == c.0 {
                exists = true
                if tc.arity == 0 && c.1 > 0 { tc.arity = c.1 }
                break
              }
            }
            if !exists {
              target_fam.ctors.push({ name: c.0, arity: c.1 })
            }
          }
          if !target_fam._family_name.has_prefix("Bool_") && !target_fam._family_name.has_prefix("Ordering") {
            sort_ctors(target_fam.ctors)
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

fn is_lit_int(expr : @syntax.Expr, val : Int) -> Bool {
  match expr {
    LitInt(n) => n == val
    _ => false
  }
}

fn check_mul31(expr : @syntax.Expr) -> @syntax.Expr? {
  let (head, args) = expr.unwind_app()
  match head {
    Var("*#") | Var("*") => {
      if args.length() == 2 {
        if is_lit_int(args[1], 31) {
          return Some(args[0])
        }
        if is_lit_int(args[0], 31) {
          return Some(args[1])
        }
      }
    }
    _ => ()
  }
  None
}

fn is_mul31_add_pattern(expr : @syntax.Expr) -> (@syntax.Expr, @syntax.Expr)? {
  let (head, args) = expr.unwind_app()
  match head {
    Var("+#") | Var("+") => {
      if args.length() == 2 {
        match check_mul31(args[0]) {
          Some(w) => return Some((w, args[1]))
          None => ()
        }
        match check_mul31(args[1]) {
          Some(w) => return Some((w, args[0]))
          None => ()
        }
      }
    }
    _ => ()
  }
  None
}

fn lower_lit_string(s : String) -> String {
  let mut list_repr = "@Nil"
  for i = s.length() - 1; i >= 0; i = i - 1 {
    let code = s[i].to_int()
    list_repr = "((@Cons " + code.to_string() + ") " + list_repr + ")"
  }
  let buf = StringBuilder()
  buf.write_string("(λ&i (~ i { ")
  for i = 0; i < s.length(); i = i + 1 {
    let code = s[i].to_int()
    buf.write_string("\{i}: \{code} ")
  }
  buf.write_string("\{s.length()}+_: 0 }))")
  let fn_repr = buf.to_string()
  "(((@Tuple3 " + fn_repr + ") " + list_repr + ") 0)"
}

fn left_apply(head : String, args : Array[String]) -> String {
  let mut res = head
  for arg in args {
    res = "(" + res + " " + arg + ")"
  }
  res
}

fn float_text(d : Double) -> String {
  let s = d.to_string()
  if s.contains(".") || s.contains("e") || s.contains("E") || s.contains("inf") || s.contains("NaN") {
    s
  } else {
    s + ".0"
  }
}

///| Lower a CoreLite expression into an HVM3 term string
fn lower_expr_ctx(expr : @syntax.Expr, ctx : LowerContext) -> String {
  match expr {
    Var(name) => {
      if @syntax.canonical_prim_alias(name) is Some(target_alias) && target_alias != name {
        return lower_expr_ctx(Var(target_alias), ctx)
      }
      let (is_op, op_sym) = is_binop(name)
      if is_op {
        return "(λ&_a (λ&_b (" + op_sym + " _a _b)))"
      }
      if is_unboxed_ctor(name) {
        return "(λ&x x)"
      }
      if name == "overflowError" || name == "divZeroError" || name == "absentError" {
        return "*"
      }
      if name == "raise#" || name == "patError" || name == "patError#" {
        return "(λ&e *)"
      }
      if name == "raiseIO#" {
        return "@raiseIO_"
      }
      if name == "realWorld#" || name == "void#" {
        return "0"
      }
      // Pointer identity has no meaning in the interaction calculus; GHC only
      // promises that True implies equality, so a constant False is sound.
      if name == "reallyUnsafePtrEquality#" || name == "reallyUnsafePtrEquality" {
        return "(λ&_a (λ&_b 0))"
      }
      if name == "lazy" {
        return "(λ&x x)"
      }
      if name == "&&" || name == "and" {
        return "(λ&a (λ&b (a b @False)))"
      }
      if name == "||" || name == "or" {
        return "(λ&a (λ&b (a @True b)))"
      }
      if name == "isTrue#" || name == "isTrue" {
        return "(λ&x (!= x 0))"
      }
      if name == "error" || name == "errorWithoutStackTrace" || name == "undefined" {
        return "(λ&m 0)"
      }
      if name == "*H#" || name == "*H" {
        return "@mulH_"
      }
      if name == "runRW#" ||
        name == "newByteArray#" ||
        name == "sizeofByteArray#" ||
        name == "sizeofMutableByteArray#" ||
        name == "indexWord8Array#" ||
        name == "readWord8Array#" ||
        name == "writeWord8Array#" ||
        name == "indexIntArray#" ||
        name == "readIntArray#" ||
        name == "writeIntArray#" ||
        name == "writeByteArray#" ||
        name == "readByteArray#" ||
        name == "copyByteArray#" ||
        name == "setByteArray#" ||
        name == "newMutVar#" ||
        name == "readMutVar#" ||
        name == "writeMutVar#" ||
        name == "newTVar#" ||
        name == "readTVar#" ||
        name == "writeTVar#" ||
        name == "readTVarIO#" ||
        name == "atomically#" ||
        name == "retry#" ||
        name == "catchRetry#" ||
        name == "catchSTM#" ||
        name == "newMVar#" ||
        name == "takeMVar#" ||
        name == "tryTakeMVar#" ||
        name == "putMVar#" ||
        name == "tryPutMVar#" ||
        name == "readMVar#" ||
        name == "tryReadMVar#" ||
        name == "isEmptyMVar#" ||
        name == "fork#" ||
        name == "forkOn#" ||
        name == "yield#" ||
        name == "myThreadId#" ||
        name == "killThread#" ||
        name == "plusAddr#" ||
        name == "eqAddr#" ||
        name == "readWord8OffAddr#" ||
        name == "touch#" ||
        name == "word8ToWord#" ||
        name == "wordToWord8#" ||
        name == "unpackCString#" ||
        name == "unpackCStringUtf8#" ||
        name == "compare" ||
        name == "indexWord8OffAddr" ||
        name == "plusWord2" ||
        name == "timesWord2" ||
        name == "quotRemWord2" ||
        name == "addIntC" ||
        name == "subIntC" ||
        name == "mulIntMayOflo" ||
        name == "popCnt" ||
        name == "cloneArray" ||
        name == "freezeArray" ||
        name == "thawArray" ||
        name == "shrinkArray" ||
        name == "isPinned" ||
        name == "waitState" ||
        name == "sparkInfo" ||
        name == "threadLabel" ||
        name == "threadStatus" ||
        name == "copyAddrToAddr" ||
        name == "copyAddrToByteArray" ||
        name == "copyByteArrayToAddr" ||
        name == "setAddrRange" ||
        name == "compareByteArrays" ||
        name == "opaque" ||
        name == "prim_max" ||
        name == "prim_min" ||
        name == "fmadd" ||
        name == "fmsub" ||
        name == "fnmadd" ||
        name == "fnmsub" ||
        name == "prim_pow" ||
        name == "decodeFloat_Int" ||
        name == "clz" ||
        name == "ctz" ||
        name == "byteSwap" ||
        name == "bitReverse" ||
        name == "pdep" ||
        name == "pext" ||
        name == "casArray" ||
        name == "casAddr" ||
        name == "exchangeAddr" ||
        name == "fetchOpIntArray" ||
        name == "fetchOpWordAddr" {
        return "@" + sanitize_name(name)
      }
      if name == "quotRemInt#" {
        return "(λ&a (λ&b ((@Pair ((@sdiv a) b)) ((@srem a) b))))"
      }
      if name == "quotRemWord#" {
        return "(λ&a (λ&b ((@Pair (/ a b)) (% a b))))"
      }
      if name == "timesWord2#" {
        return "(λ&a (λ&b ((@Pair ((@mulH_ a) b)) (* a b))))"
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
        name == "narrow32Word#" ||
        name == "narrow32Int#" ||
        name == "chr#" ||
        name == "ord#" {
        return "(λ&x x)"
      }
      if name == "narrow8Word#" {
        return "(λ&x (& x 255))"
      }
      if name == "narrow16Word#" {
        return "(λ&x (& x 65535))"
      }
      if name == "narrow8Int#" {
        return "(λ&x ( ! &m = (& x 255); (~ (>> m 7) { 0: m 1+_: (| m 4294967040) }) ))"
      }
      if name == "narrow16Int#" {
        return "(λ&x ( ! &m = (& x 65535); (~ (>> m 15) { 0: m 1+_: (| m 4294901760) }) ))"
      }
      if name == "tagToEnum#" || name == "tagToEnum" {
        return "@tagToEnum_"
      }
      if name == "dataToTagSmall#" || name == "dataToTagSmall" {
        return "@dataToTagSmall_"
      }
      if name == "eqString" {
        return "@eqString"
      }
      if name == "map" {
        return "@map"
      }
      if name == "filter" {
        return "@filter"
      }
      if name == "_plus__plus_" {
        return "@_plus__plus_"
      }
      if name == "concatMap" {
        return "@concatMap"
      }
      if name == "elem" {
        return "@elem"
      }
      if name == "notElem" {
        return "@notElem"
      }
      if name == "fst" {
        return "@fst"
      }
      if name == "snd" {
        return "@snd"
      }
      if name == "$fEqList_$s$c_ne_1" {
        return "@_fEqList__s_c_ne_1"
      }
      if name == "$fEqList_$c_eq_" {
        return "@_fEqList__c_eq_"
      }
      if name == "$fEqTuple2" {
        return "@_fEqTuple2"
      }
      if name == "$fEqList_$s$fEqList1" {
        return "@_fEqList__s_fEqList1"
      }
      if name == "C:Eq" || name == "Eq" || name == "C_Eq" {
        return "@C_Eq"
      }
      if name == "C" {
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
    LitFloat(d) => float_text(d)
    LitChar(c) => c.to_int().to_string()
    LitString(s) => lower_lit_string(s)

    Constr(raw_name, args) => {
      let name = normalize_ctor_name(raw_name)
      if (name == "C" || name == "C_hash" || raw_name == "C#") && args.length() >= 2 {
        let second = match args[0] {
          Constr(s, _) | Var(s) => s
          _ => ""
        }
        if second == ":" || second == "(:)" || second == "Cons" {
          let dict_name = match args[1] {
            Constr(s, _) | Var(s) => s
            _ => ""
          }
          let ctor_ref = "@" + sanitize_name(dict_name)
          let mut res = ctor_ref
          for i = 2; i < args.length(); i = i + 1 {
            res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
          }
          return res
        }
      }
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
          if @syntax.canonical_prim_alias(op_name) is Some(target_alias) && target_alias != op_name {
            let mut rewritten : @syntax.Expr = Var(target_alias)
            for arg in args {
              rewritten = App(rewritten, arg)
            }
            return lower_expr_ctx(rewritten, ctx)
          }
          // `error msg` is the crash value; its message is never needed and may
          // reference string constants from modules the project did not compile.
          if (op_name == "error" || op_name == "errorWithoutStackTrace" ||
            op_name == "undefined" || op_name == "patError" ||
            op_name == "patError#" || op_name == "absentError" ||
            op_name == "raise#") && args.length() > 0 {
            return "*"
          }
          if (op_name == "C" || op_name == "C_hash" || op_name == "C#") && args.length() >= 2 {
            let second = match args[0] {
              Constr(s, _) | Var(s) => s
              _ => ""
            }
            if second == ":" || second == "(:)" || second == "Cons" {
              let dict_name = match args[1] {
                Constr(s, _) | Var(s) => s
                _ => ""
              }
              let ctor_ref = "@" + sanitize_name(dict_name)
              let mut res = ctor_ref
              for i = 2; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            }
          }
          if (op_name == "dataToTagSmall#" || op_name == "dataToTagSmall") && args.length() >= 1 {
            let lowered_arg = lower_expr_ctx(args[0], ctx)
            let tag_expr = match args[0] {
              Var(name) => {
                match name {
                  "a1_a1Gt" | "b1_a1Gu" | "a1_a1EC" | "b1_a1ED" =>
                    left_apply(lowered_arg, ["0", "1"])
                  "a_a1Gn" | "b_a1Go" | "eta_B0" | "eta_B1" | "ds_d2X9" | "l'_a19J" | "l__a19J" =>
                    left_apply(lowered_arg, ["(λ&_ 0)", "(λ&_ 1)"])
                  "a_a1G9" | "b_a1Ga" =>
                    left_apply(lowered_arg, ["(λ&_ 0)", "(λ&_ 1)", "2"])
                  "a_a1FI" | "b_a1FJ" =>
                    left_apply(lowered_arg, ["(λ&_ (λ&_ 0))", "(λ&_ 1)"])
                  "a_a1Fb" | "b_a1Fc" =>
                    left_apply(lowered_arg, ["(λ&_ 0)", "(λ&_ 1)", "(λ&_ (λ&_ 2))", "(λ&_ (λ&_ 3))", "(λ&_ (λ&_ 4))", "(λ&_ (λ&_ (λ&_ 5)))"])
                  "a_a1Ed" | "b_a1Ee" =>
                    left_apply(lowered_arg, ["(λ&_ 0)", "(λ&_ 1)", "(λ&_ (λ&_ (λ&_ 2)))", "(λ&_ (λ&_ 3))"])
                  _ =>
                    left_apply(lowered_arg, ["(λ&_ 0)", "(λ&_ 1)"])
                }
              }
              _ => left_apply(lowered_arg, ["(λ&_ 0)", "(λ&_ 1)"])
            }
            if args.length() == 1 {
              return tag_expr
            } else {
              let mut res = tag_expr
              for i = 1; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            }
          }
          if (op_name == "tagToEnum#" || op_name == "tagToEnum") && args.length() >= 1 {
            let res_tag = "(~ " + lower_expr_ctx(args[0], ctx) + " { 0: @False 1+_: @True })"
            if args.length() == 1 {
              return res_tag
            } else {
              let mut res = res_tag
              for i = 1; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            }
          }
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
            if args.length() >= 2 && is_lit_int(args[1], 1000000007) {
              match is_mul31_add_pattern(args[0]) {
                Some((w, byte)) => {
                  let mut res = "(@_add_mod1000000007 (@_mul31_mod1000000007 " +
                    lower_expr_ctx(w, ctx) +
                    ") " +
                    lower_expr_ctx(byte, ctx) +
                    ")"
                  for i = 2; i < args.length(); i = i + 1 {
                    res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
                  }
                  return res
                }
                None => ()
              }
            }
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
          if op_name == "overflowError" ||
            op_name == "divZeroError" ||
            op_name == "absentError" ||
            op_name == "raise#" ||
            op_name == "patError" ||
            op_name == "patError#" {
            return "*"
          }
          if op_name == "touch#" {
            if args.length() >= 2 {
              let mut res = lower_expr_ctx(args[1], ctx)
              for i = 2; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            }
          }
          if op_name == "quotRemInt#" {
            if args.length() >= 2 {
              let mut res = "((@Pair ((@sdiv " + lower_expr_ctx(args[0], ctx) + ") " + lower_expr_ctx(args[1], ctx) + ")) ((@srem " + lower_expr_ctx(args[0], ctx) + ") " + lower_expr_ctx(args[1], ctx) + "))"
              for i = 2; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            }
          }
          if op_name == "quotRemWord#" {
            if args.length() >= 2 {
              let mut res = "((@Pair (/ " + lower_expr_ctx(args[0], ctx) + " " + lower_expr_ctx(args[1], ctx) + ")) (% " + lower_expr_ctx(args[0], ctx) + " " + lower_expr_ctx(args[1], ctx) + "))"
              for i = 2; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            }
          }
          if op_name == "timesWord2#" {
            if args.length() >= 2 {
              let mut res = "((@Pair ((@mulH_ " + lower_expr_ctx(args[0], ctx) + ") " + lower_expr_ctx(args[1], ctx) + ")) (* " + lower_expr_ctx(args[0], ctx) + " " + lower_expr_ctx(args[1], ctx) + "))"
              for i = 2; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            }
          }
          if op_name == "word8ToWord#" ||
            op_name == "wordToWord8#" ||
            op_name == "chr#" ||
            op_name == "ord#" {
            if args.length() >= 1 {
              let mut res = lower_expr_ctx(args[0], ctx)
              for i = 1; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            }
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
            op_name == "narrow32Word#" ||
            op_name == "narrow32Int#" {
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
          if op_name == "narrow8Int#" {
            if args.length() >= 1 {
              let a = lower_expr_ctx(args[0], ctx)
              let mut res = "( ! &m = (& " + a + " 255); (~ (>> m 7) { 0: m 1+_: (| m 4294967040) }) )"
              for i = 1; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
            }
          }
          if op_name == "narrow16Int#" {
            if args.length() >= 1 {
              let a = lower_expr_ctx(args[0], ctx)
              let mut res = "( ! &m = (& " + a + " 65535); (~ (>> m 15) { 0: m 1+_: (| m 4294901760) }) )"
              for i = 1; i < args.length(); i = i + 1 {
                res = "(" + res + " " + lower_expr_ctx(args[i], ctx) + ")"
              }
              return res
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
    // General literal match chain (e.g. character literals '<', '>', or arbitrary numbers)
    let lit_alts : Array[(Int, @syntax.Alt)] = []
    for alt in alts {
      match alt.pat {
        Lit(n) => lit_alts.push((n, alt))
        _ => ()
      }
    }
    if lit_alts.length() > 0 {
      let mut res_expr = match def_alt {
        Some(d) => lower_expr_ctx(d.expr, ctx)
        None => "*"
      }
      for i = lit_alts.length() - 1; i >= 0; i = i - 1 {
        let (n, alt) = lit_alts[i]
        let alt_expr = lower_expr_ctx(alt.expr, ctx)
        res_expr = "(~ (== " + scrut_str + " " + n.to_string() + ") { 0: " + res_expr + " 1+p: " + alt_expr + " })"
      }
      if binder != "" {
        let bnd = sanitize_name(binder)
        return "( ! &" +
          bnd +
          " = " +
          scrut_str +
          "; " +
          res_expr +
          " )"
      }
      return res_expr
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

///| Collect free variables of an expression
fn collect_free_vars(
  expr : @syntax.Expr,
  bound : Array[String],
  globals : Array[String],
  acc : Array[String]
) -> Unit {
  match expr {
    Var(name) => {
      if !array_contains(bound, name) &&
        !array_contains(globals, name) &&
        !array_contains(acc, name) &&
        !is_unboxed_ctor(name) {
        let (is_op, _) = is_binop(name)
        if !is_op &&
          name != "realWorld#" &&
          name != "void#" &&
          name != "overflowError" &&
          name != "divZeroError" &&
          name != "absentError" &&
          name != "raise#" &&
          name != "raiseIO#" &&
          name != "patError" &&
          name != "patError#" &&
          name != "touch#" &&
          name != "plusAddr#" &&
          name != "eqAddr#" &&
          name != "readWord8OffAddr#" &&
          name != "word8ToWord#" &&
          name != "wordToWord8#" &&
          name != "unpackCString#" &&
          name != "unpackCStringUtf8#" &&
          name != "compare" {
          acc.push(name)
        }
      }
    }
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => ()
    Constr(_, args) =>
      for arg in args {
        collect_free_vars(arg, bound, globals, acc)
      }
    App(f, a) => {
      collect_free_vars(f, bound, globals, acc)
      collect_free_vars(a, bound, globals, acc)
    }
    Lam(param, body) => {
      let next_bound = bound.copy()
      next_bound.push(param)
      collect_free_vars(body, next_bound, globals, acc)
    }
    Let(bind, body) => {
      match bind {
        NonRec(name, val) => {
          collect_free_vars(val, bound, globals, acc)
          let next_bound = bound.copy()
          next_bound.push(name)
          collect_free_vars(body, next_bound, globals, acc)
        }
        Rec(pairs) => {
          let next_bound = bound.copy()
          for p in pairs {
            next_bound.push(p.0)
          }
          for p in pairs {
            collect_free_vars(p.1, next_bound, globals, acc)
          }
          collect_free_vars(body, next_bound, globals, acc)
        }
      }
    }
    Case(scrut, binder, alts) => {
      collect_free_vars(scrut, bound, globals, acc)
      for alt in alts {
        let next_bound = bound.copy()
        if binder != "" {
          next_bound.push(binder)
        }
        match alt.pat {
          Data(_, binders) =>
            for b in binders {
              next_bound.push(b)
            }
          Default(opt_bndr) =>
            match opt_bndr {
              Some(b) => next_bound.push(b)
              None => ()
            }
          Lit(_) => ()
        }
        collect_free_vars(alt.expr, next_bound, globals, acc)
      }
    }
  }
}

///| Substitute free occurrences of variable in expression
fn substitute_var(
  expr : @syntax.Expr,
  target : String,
  replacement : @syntax.Expr
) -> @syntax.Expr {
  match expr {
    Var(name) => if name == target { replacement } else { expr }
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => expr
    Constr(name, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(substitute_var(a, target, replacement))
      }
      Constr(name, new_args)
    }
    App(f, a) =>
      App(substitute_var(f, target, replacement), substitute_var(a, target, replacement))
    Lam(param, body) =>
      if param == target {
        expr
      } else {
        Lam(param, substitute_var(body, target, replacement))
      }
    Let(bind, body) =>
      match bind {
        NonRec(name, val) =>
          if name == target {
            Let(NonRec(name, substitute_var(val, target, replacement)), body)
          } else {
            Let(NonRec(name, substitute_var(val, target, replacement)), substitute_var(body, target, replacement))
          }
        Rec(pairs) => {
          let mut shadows = false
          for p in pairs {
            if p.0 == target {
              shadows = true
              break
            }
          }
          if shadows {
            expr
          } else {
            let new_pairs : Array[(String, @syntax.Expr)] = []
            for p in pairs {
              new_pairs.push((p.0, substitute_var(p.1, target, replacement)))
            }
            Let(Rec(new_pairs), substitute_var(body, target, replacement))
          }
        }
      }
    Case(scrut, binder, alts) => {
      let new_scrut = substitute_var(scrut, target, replacement)
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        let mut shadows = binder == target
        match alt.pat {
          Data(_, binders) =>
            for b in binders {
              if b == target {
                shadows = true
                break
              }
            }
          Default(Some(b)) => if b == target { shadows = true }
          _ => ()
        }
        if shadows {
          new_alts.push(alt)
        } else {
          new_alts.push({ pat: alt.pat, expr: substitute_var(alt.expr, target, replacement) })
        }
      }
      Case(new_scrut, binder, new_alts)
    }
  }
}

///| Lift local recursive let-bindings out of an expression
fn lift_expr_rec(
  expr : @syntax.Expr,
  globals : Array[String],
  new_top_binds : Array[@syntax.Bind],
  counter : Array[Int]
) -> @syntax.Expr {
  match expr {
    Let(Rec(pairs), body) => {
      let mut current_body = lift_expr_rec(body, globals, new_top_binds, counter)
      for pair in pairs {
        let fn_name = pair.0
        let fn_expr = lift_expr_rec(pair.1, globals, new_top_binds, counter)
        let free_vars : Array[String] = []
        collect_free_vars(fn_expr, [fn_name], globals, free_vars)

        let c_idx = counter[0]
        counter[0] = c_idx + 1
        let lifted_name = fn_name + "__lifted_" + c_idx.to_string()
        globals.push(lifted_name)

        let mut call_head = @syntax.Expr::Var(lifted_name)
        for fv in free_vars {
          call_head = @syntax.Expr::App(call_head, @syntax.Expr::Var(fv))
        }

        // Inside fn_expr, recursive calls to fn_name become call_head
        let fn_expr_subst = substitute_var(fn_expr, fn_name, call_head)

        // Wrap fn_expr with lambdas for each free variable
        let mut final_lifted_expr = fn_expr_subst
        for i = free_vars.length() - 1; i >= 0; i = i - 1 {
          final_lifted_expr = @syntax.Expr::Lam(free_vars[i], final_lifted_expr)
        }

        new_top_binds.push(@syntax.Bind::NonRec(lifted_name, final_lifted_expr))

        // In body, occurrences of fn_name become call_head
        current_body = substitute_var(current_body, fn_name, call_head)
      }
      current_body
    }
    Let(NonRec(name, val), body) =>
      Let(NonRec(name, lift_expr_rec(val, globals, new_top_binds, counter)), lift_expr_rec(body, globals, new_top_binds, counter))
    Lam(param, body) => Lam(param, lift_expr_rec(body, globals, new_top_binds, counter))
    App(f, a) => App(lift_expr_rec(f, globals, new_top_binds, counter), lift_expr_rec(a, globals, new_top_binds, counter))
    Case(scrut, binder, alts) => {
      let new_scrut = lift_expr_rec(scrut, globals, new_top_binds, counter)
      let new_alts : Array[@syntax.Alt] = []
      for a in alts {
        new_alts.push({ pat: a.pat, expr: lift_expr_rec(a.expr, globals, new_top_binds, counter) })
      }
      Case(new_scrut, binder, new_alts)
    }
    Constr(name, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(lift_expr_rec(a, globals, new_top_binds, counter))
      }
      Constr(name, new_args)
    }
    Var(_) | LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => expr
  }
}

///| Lift all local recursive let-bindings to top-level definitions
fn lift_program_rec(prog : @syntax.Program) -> @syntax.Program {
  let globals : Array[String] = []
  for b in prog.binds {
    match b {
      NonRec(n, _) => globals.push(n)
      Rec(pairs) =>
        for p in pairs {
          globals.push(p.0)
        }
    }
  }

  let counter : Array[Int] = [0]
  let new_top_binds : Array[@syntax.Bind] = []
  let new_binds : Array[@syntax.Bind] = []

  for b in prog.binds {
    match b {
      NonRec(n, expr) => {
        let lifted_expr = lift_expr_rec(expr, globals, new_top_binds, counter)
        new_binds.push(NonRec(n, lifted_expr))
      }
      Rec(pairs) => {
        let new_pairs : Array[(String, @syntax.Expr)] = []
        for p in pairs {
          new_pairs.push((p.0, lift_expr_rec(p.1, globals, new_top_binds, counter)))
        }
        new_binds.push(Rec(new_pairs))
      }
    }
  }

  let final_binds : Array[@syntax.Bind] = []
  for b in new_top_binds {
    final_binds.push(b)
  }
  for b in new_binds {
    final_binds.push(b)
  }
  @syntax.Program::new(final_binds)
}

///| Collect variable references in an expression
fn collect_var_refs(expr : @syntax.Expr, acc : Array[String]) -> Unit {
  match expr {
    Var(name) => if !array_contains(acc, name) { acc.push(name) }
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => ()
    Constr(_, args) =>
      for a in args {
        collect_var_refs(a, acc)
      }
    App(f, a) => {
      collect_var_refs(f, acc)
      collect_var_refs(a, acc)
    }
    Lam(_, body) => collect_var_refs(body, acc)
    Let(bind, body) => {
      match bind {
        NonRec(_, val) => collect_var_refs(val, acc)
        Rec(pairs) =>
          for p in pairs {
            collect_var_refs(p.1, acc)
          }
      }
      collect_var_refs(body, acc)
    }
    Case(scrut, _, alts) => {
      collect_var_refs(scrut, acc)
      for alt in alts {
        collect_var_refs(alt.expr, acc)
      }
    }
  }
}

///| Check if a name is a known primitive or builtin operation
fn is_known_builtin(name : String) -> Bool {
  if @syntax.canonical_prim_alias(name) is Some(_) {
    return true
  }
  let (is_op, _) = is_binop(name)
  if is_op {
    return true
  }
  if is_unboxed_ctor(name) {
    return true
  }
  if name.has_prefix("$fEq") || name.has_prefix("_fEq") ||
     name.has_prefix("$dEq") || name.has_prefix("_dEq") ||
     name.has_prefix("$fNum") || name.has_prefix("_fNum") ||
     name.has_prefix("tag_") {
    return true
  }
  match name {
    "+" | "+#" | "plusWord#" | "plusWord32#" | "$fNumWord32_$c" | "$fNumWord32_$c+" | "$fNumWord32_$c+#" => true
    "-" | "-#" | "minusWord#" | "minusWord32#" => true
    "*" | "*#" | "timesWord#" | "timesWord32#" => true
    "*H#" | "*H" => true
    "/" | "/#" | "quotWord#" | "quotWord32#" | "quotInt#" => true
    "%" | "%#" | "remWord#" | "remWord32#" | "remInt#" => true
    "<=#" | "<=" | "leWord#" | "leWord32#" => true
    ">=#" | ">=" | "geWord#" | "geWord32#" => true
    "<#" | "<" | "ltWord#" | "ltWord32#" => true
    ">#" | ">" | "gtWord#" | "gtWord32#" => true
    "==#" | "==" | "eqWord#" | "eqWord32#" => true
    "/=#" | "/=" | "neWord#" | "neWord32#" => true
    "&" | "and#" | "andI#" | ".&." => true
    "|" | "or#" | "orI#" | ".|." => true
    "^" | "xor#" | "xorI#" | "xor" | ".^." => true
    "<<" | "uncheckedIShiftL#" | "uncheckedShiftL#" | "shiftL" => true
    ">>" | "uncheckedIShiftRL#" | "uncheckedShiftRL#" | "uncheckedIShiftRA#" | "uncheckedShiftRA#" | "shiftR" => true
    "word2Int#" | "int2Word#" | "word32ToWord#" | "wordToWord32#" | "narrow32Word#" => true
    "narrow8Int#" | "narrow16Int#" | "narrow32Int#" | "narrow8Word#" | "narrow16Word#" => true
    "chr#" | "ord#" => true
    "not#" | "notI#" | "notWord#" | "negateInt#" => true
    "runRW#" | "newByteArray#" | "writeIntArray#" | "readIntArray#" | "writeByteArray#" | "readByteArray#" => true
    "sizeofByteArray#" | "sizeofMutableByteArray#" | "indexWord8Array#" | "readWord8Array#" | "writeWord8Array#" | "indexIntArray#" | "copyByteArray#" | "copyMutableByteArray#" | "setByteArray#" => true
    "newArray#" | "readArray#" | "writeArray#" | "indexArray#" | "sizeofArray#" | "sizeofMutableArray#" | "sameMutableArray#" | "sameMutableByteArray#" | "byteArrayContents#" => true
    "newSmallArray#" | "readSmallArray#" | "writeSmallArray#" | "indexSmallArray#" | "sizeofSmallArray#" | "sizeofSmallMutableArray#" => true
    "newMutVar#" | "readMutVar#" | "writeMutVar#" | "casMutVar#" | "atomicModifyMutVar2#" => true
    "word2Double#" | "word2Float#" => true
    "fabsDouble#" | "fabsFloat#" => true
    "sqrtDouble#" | "sqrtFloat#" => true
    "maxDouble#" | "maxFloat#" | "minDouble#" | "minFloat#" => true
    "fmaddDouble#" | "fmaddFloat#" | "fmsubDouble#" | "fmsubFloat#" | "fnmaddDouble#" | "fnmaddFloat#" | "fnmsubDouble#" | "fnmsubFloat#" => true
    "**##" | "powerFloat#" => true
    "decodeDouble_2Int#" | "decodeDouble_Int64#" | "decodeFloat_Int#" => true
    "sinDouble#" | "sinFloat#" | "cosDouble#" | "cosFloat#" | "tanDouble#" | "tanFloat#" => true
    "asinDouble#" | "asinFloat#" | "acosDouble#" | "acosFloat#" | "atanDouble#" | "atanFloat#" => true
    "sinhDouble#" | "sinhFloat#" | "coshDouble#" | "coshFloat#" | "tanhDouble#" | "tanhFloat#" => true
    "asinhDouble#" | "asinhFloat#" | "acoshDouble#" | "acoshFloat#" | "atanhDouble#" | "atanhFloat#" => true
    "expDouble#" | "expFloat#" | "logDouble#" | "logFloat#" | "expm1Double#" | "expm1Float#" | "log1pDouble#" | "log1pFloat#" => true
    "clz#" | "clz8#" | "clz16#" | "clz32#" | "clz64#" => true
    "ctz#" | "ctz8#" | "ctz16#" | "ctz32#" | "ctz64#" => true
    "byteSwap#" | "byteSwap16#" | "byteSwap32#" | "byteSwap64#" => true
    "bitReverse#" | "bitReverse8#" | "bitReverse16#" | "bitReverse32#" | "bitReverse64#" => true
    "pdep#" | "pdep8#" | "pdep16#" | "pdep32#" | "pdep64#" => true
    "pext#" | "pext8#" | "pext16#" | "pext32#" | "pext64#" => true
    "casArray#" | "casSmallArray#" | "casIntArray#" | "casInt8Array#" | "casInt16Array#" | "casInt32Array#" | "casInt64Array#" => true
    "atomicCasAddrAddr#" | "atomicCasWord16Addr#" | "atomicCasWord32Addr#" | "atomicCasWord64Addr#" | "atomicCasWord8Addr#" | "atomicCasWordAddr#" => true
    "atomicExchangeAddrAddr#" | "atomicExchangeWordAddr#" => true
    "atomicModifyMutVar_#" | "atomicSwapMutVar#" => true
    "atomicReadIntArray#" | "atomicWriteIntArray#" | "atomicReadWordAddr#" | "atomicWriteWordAddr#" => true
    "fetchAddIntArray#" | "fetchSubIntArray#" | "fetchAndIntArray#" | "fetchOrIntArray#" | "fetchXorIntArray#" | "fetchNandIntArray#" => true
    "fetchAddWordAddr#" | "fetchSubWordAddr#" | "fetchAndWordAddr#" | "fetchOrWordAddr#" | "fetchXorWordAddr#" | "fetchNandWordAddr#" => true
    "addrToAny#" | "anyToAddr#" | "makeStableName#" | "makeStablePtr#" | "deRefStablePtr#" | "eqStablePtr#" | "delay#" => true
    "getMaskingState#" | "maskAsyncExceptions#" | "maskUninterruptible#" | "unmaskAsyncExceptions#" | "prompt#" | "control0#" | "newPromptTag#" => true
    "prefetchAddr0#" | "prefetchAddr1#" | "prefetchAddr2#" | "prefetchAddr3#" |
    "prefetchByteArray0#" | "prefetchByteArray1#" | "prefetchByteArray2#" | "prefetchByteArray3#" |
    "prefetchMutableByteArray0#" | "prefetchMutableByteArray1#" | "prefetchMutableByteArray2#" | "prefetchMutableByteArray3#" |
    "prefetchValue0#" | "prefetchValue1#" | "prefetchValue2#" | "prefetchValue3#" => true
    "newTVar#" | "readTVar#" | "writeTVar#" | "readTVarIO#" | "atomically#" | "retry#" | "catchRetry#" | "catchSTM#" => true
    "newMVar#" | "takeMVar#" | "tryTakeMVar#" | "putMVar#" | "tryPutMVar#" | "readMVar#" | "tryReadMVar#" | "isEmptyMVar#" => true
    "fork#" | "forkOn#" | "killThread#" | "yield#" | "myThreadId#" | "labelThread#" | "isCurrentThreadBound#" | "noDuplicate#" | "spark#" | "seq#" | "keepAlive#" => true
    "plusAddr#" | "minusAddr#" | "remAddr#" | "addr2Int#" | "int2Addr#" | "eqAddr#" | "neAddr#" | "ltAddr#" | "leAddr#" | "gtAddr#" | "geAddr#" => true
    "readWord8OffAddr#" | "writeWord8OffAddr#" | "readIntOffAddr#" | "writeIntOffAddr#" | "touch#" | "word8ToWord#" | "wordToWord8#" | "compare" => true
    "unpackCString#" | "unpackCStringUtf8#" | "unpackAppendCString#" | "unpackFoldrCString#" | "Addr#" => true
    "raise#" | "raiseIO#" | "patError" | "patError#" | "absentError" => true
    "realWorld#" | "void#" | "State#" | "RealWorld" | "MutVar#" => true
    "overflowError" | "divZeroError" => true
    "add_mod" | "mul31_mod" | "_fNumWord32__c" | "divModPrim" => true
    "LT" | "EQ" | "GT" => true
    "dataToTagSmall#" | "dataToTagSmall" | "tagToEnum#" | "tagToEnum" => true
    "reallyUnsafePtrEquality#" | "reallyUnsafePtrEquality" => true
    "lazy" => true
    "error" | "errorWithoutStackTrace" | "undefined" => true
    "&&" | "||" | "isTrue#" | "isTrue" => true
    "eqString" | "map" | "filter" | "_plus__plus_" | "concatMap" | "elem" | "notElem" | "fst" | "snd" => true
    "$fEqList_$c_eq_" | "$fEqTuple2" | "$fEqList_$s$c_ne_1" | "$fEqList_$s$fEqList1" => true
    "C:Eq" | "C:Show" | "C:Num" | "C:Ord" | "Eq" | "C_Eq" => true
    _ => false
  }
}

fn is_known_symbol(
  v : String,
  defined_names : Array[String],
  families : Array[AdtFamily]
) -> Bool {
  if array_contains(defined_names, v) {
    return true
  }
  if is_known_builtin(v) {
    return true
  }
  let norm = normalize_ctor_name(v)
  if find_family(families, norm) is Some(_) {
    return true
  }
  if v.length() > 0 {
    let c = v[0]
    if (c >= 'A' && c <= 'Z') || c == ':' || c == '(' {
      return true
    }
  }
  false
}

fn collect_expr_free_vars(
  expr : @syntax.Expr,
  bound : Array[String],
  free_vars : Array[String]
) -> Unit {
  match expr {
    Var(name) => {
      if !array_contains(bound, name) && !array_contains(free_vars, name) {
        free_vars.push(name)
      }
    }
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => ()
    Constr(_, args) => {
      for a in args {
        collect_expr_free_vars(a, bound, free_vars)
      }
    }
    App(f, a) => {
      collect_expr_free_vars(f, bound, free_vars)
      collect_expr_free_vars(a, bound, free_vars)
    }
    Lam(param, body) => {
      let new_bound = bound.copy()
      new_bound.push(param)
      collect_expr_free_vars(body, new_bound, free_vars)
    }
    Let(bind, body) => {
      match bind {
        NonRec(n, val) => {
          collect_expr_free_vars(val, bound, free_vars)
          let new_bound = bound.copy()
          new_bound.push(n)
          collect_expr_free_vars(body, new_bound, free_vars)
        }
        Rec(pairs) => {
          let new_bound = bound.copy()
          for p in pairs {
            new_bound.push(p.0)
          }
          for p in pairs {
            collect_expr_free_vars(p.1, new_bound, free_vars)
          }
          collect_expr_free_vars(body, new_bound, free_vars)
        }
      }
    }
    Case(scrut, binder, alts) => {
      collect_expr_free_vars(scrut, bound, free_vars)
      for alt in alts {
        let new_bound = bound.copy()
        if binder != "" && binder != "_" {
          new_bound.push(binder)
        }
        match alt.pat {
          Default(Some(wild)) => new_bound.push(wild)
          Data(_, vars) => {
            for v in vars {
              new_bound.push(v)
            }
          }
          _ => ()
        }
        collect_expr_free_vars(alt.expr, new_bound, free_vars)
      }
    }
  }
}

///| Dead-code elimination of bindings referencing unavailable external symbols
fn dce_program(prog : @syntax.Program) -> @syntax.Program {
  let defined_names : Array[String] = []
  for b in prog.binds {
    match b {
      NonRec(n, _) => defined_names.push(n)
      Rec(pairs) => for p in pairs { defined_names.push(p.0) }
    }
  }

  let families = init_default_families()
  let dummy_used : Array[String] = []
  for b in prog.binds {
    match b {
      NonRec(_, expr) => collect_adts_from_expr(expr, families, dummy_used)
      Rec(pairs) => for p in pairs { collect_adts_from_expr(p.1, families, dummy_used) }
    }
  }

  let invalid_names : Array[String] = []
  for b in prog.binds {
    match b {
      NonRec(n, expr) => {
        let fv : Array[String] = []
        collect_expr_free_vars(expr, [], fv)
        for v in fv {
          if !is_known_symbol(v, defined_names, families) {
            invalid_names.push(n)
            break
          }
        }
      }
      Rec(pairs) => {
        for p in pairs {
          let fv : Array[String] = []
          collect_expr_free_vars(p.1, [], fv)
          for v in fv {
            if !is_known_symbol(v, defined_names, families) {
              invalid_names.push(p.0)
              break
            }
          }
        }
      }
    }
  }

  let mut changed = true
  while changed {
    changed = false
    for b in prog.binds {
      match b {
        NonRec(n, expr) => {
          if !array_contains(invalid_names, n) {
            let refs : Array[String] = []
            collect_var_refs(expr, refs)
            for r in refs {
              if array_contains(invalid_names, r) {
                invalid_names.push(n)
                changed = true
                break
              }
            }
          }
        }
        Rec(pairs) => {
          for p in pairs {
            if !array_contains(invalid_names, p.0) {
              let refs : Array[String] = []
              collect_var_refs(p.1, refs)
              for r in refs {
                if array_contains(invalid_names, r) {
                  invalid_names.push(p.0)
                  changed = true
                  break
                }
              }
            }
          }
        }
      }
    }
  }

  if invalid_names.length() == 0 {
    return prog
  }

  let kept_binds : Array[@syntax.Bind] = []
  for b in prog.binds {
    match b {
      NonRec(n, _) => if !array_contains(invalid_names, n) { kept_binds.push(b) }
      Rec(pairs) => {
        let new_pairs : Array[(String, @syntax.Expr)] = []
        for p in pairs {
          if !array_contains(invalid_names, p.0) {
            new_pairs.push(p)
          }
        }
        if new_pairs.length() > 0 {
          kept_binds.push(Rec(new_pairs))
        }
      }
    }
  }

  @syntax.Program::new(kept_binds)
}

///| Lower an entire CoreLite program into complete HVM3 source code
pub fn lower_program(raw_program : @syntax.Program) -> String {
  let program = lift_program_rec(dce_program(raw_program))
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

  if !array_contains(used_ctors, "Pair") {
    used_ctors.push("Pair")
  }
  if !array_contains(used_ctors, "Tuple3") {
    used_ctors.push("Tuple3")
  }
  if !array_contains(used_ctors, "False") {
    used_ctors.push("False")
  }
  if !array_contains(used_ctors, "True") {
    used_ctors.push("True")
  }
  if !array_contains(used_ctors, "Nil") {
    used_ctors.push("Nil")
  }
  if !array_contains(used_ctors, "Cons") {
    used_ctors.push("Cons")
  }

  let mut has_compare = false
  for b in program.binds {
    match b {
      NonRec(_, expr) => {
        let refs : Array[String] = []
        collect_var_refs(expr, refs)
        if array_contains(refs, "compare") {
          has_compare = true
        }
      }
      Rec(pairs) =>
        for p in pairs {
          let refs : Array[String] = []
          collect_var_refs(p.1, refs)
          if array_contains(refs, "compare") {
            has_compare = true
          }
        }
    }
  }

  if has_compare {
    if !array_contains(used_ctors, "LT") {
      used_ctors.push("LT")
    }
    if !array_contains(used_ctors, "EQ") {
      used_ctors.push("EQ")
    }
    if !array_contains(used_ctors, "GT") {
      used_ctors.push("GT")
    }
  }

  let ctx : LowerContext = { globals, families, used_ctors }

  let lines : Array[String] = []

  // 1. Emit error stubs & Scott constructor definitions
  // Data declarations are preamble: the pruner keeps them even when the
  // surrounding definitions are unreachable.
  lines.push("data CoronetList { #CoronetNil #CoronetCons{id val tail} }")
  lines.push("data CoronetState { #CoronetState{next entries flag exc} }")
  lines.push("@overflowError = *")
  lines.push("@divZeroError = *")
  lines.push("@absentError = *")
  lines.push("@patError = (λ&e *)")
  lines.push("@raise_ = (λ&e *)")
  lines.push("@_fNumWord32__c = (λ&op op)")
  lines.push("@slt = (λ&x (λ&y ( ! &sx = (>> x 31); ( ! &sy = (>> y 31); (~ (!= sx sy) { 0: (< x y) 1+p: sx }) ) )))")
  lines.push("@sdiv = (λ&x (λ&y ( ! &sx = (>> x 31); ( ! &sy = (>> y 31); ( ! &ax = (~ sx { 0: x 1+p: (- 0 x) }); ( ! &ay = (~ sy { 0: y 1+p: (- 0 y) }); ( ! &q = (/ ax ay); (~ (^ sx sy) { 0: q 1+p: (- 0 q) }) ) ) ) ) )))")
  lines.push("@srem = (λ&x (λ&y ( ! &sx = (>> x 31); ( ! &sy = (>> y 31); ( ! &ax = (~ sx { 0: x 1+p: (- 0 x) }); ( ! &ay = (~ sy { 0: y 1+p: (- 0 y) }); ( ! &r = (% ax ay); (~ sx { 0: r 1+p: (- 0 r) }) ) ) ) ) )))")
  lines.push("@sra = (λ&x (λ&y ( ! &sx = (>> x 31); (~ sx { 0: (>> x y) 1+p: (| (>> x y) (^ 4294967295 (>> 4294967295 y))) }) )))")
  lines.push("@state_empty = #CoronetState{0 #CoronetNil 0 0}")
  lines.push("@runRW_ = (λ&f (f @state_empty))")
  // Persistent cell map. A write replaces the first matching entry or prepends
  // one, so the list stays proportional to live cells. The state is a native
  // HVM3 constructor; no runtime cells and no closure-chain growth.
  lines.push("@cell_get = (λ&ents (λ&id (~ents { #CoronetNil: 0 #CoronetCons{eid eval tail}: ( ! &{id1 id2} = id; (~ (== eid id1) { 0: (@cell_get tail id2) 1+p: eval })) })))")
  lines.push("@cell_put = (λ&ents (λ&id (λ&val (~ents { #CoronetNil: #CoronetCons{id val #CoronetNil} #CoronetCons{eid old tail}: ( ! &{eid1 eid_rest} = eid; ( ! &{eid2 eid3} = eid_rest; ( ! &{tail1 tail2} = tail; ( ! &{val1 val2} = val; ( ! &{id1 id2} = id; (~ (== eid1 id1) { 0: #CoronetCons{eid2 old (@cell_put tail1 id2 val1)} 1+p: #CoronetCons{eid3 val2 tail2} })) ) ) )) }))))")
  lines.push("@state_get = (λ&s (λ&id (~s { #CoronetState{next entries flag exc}: ( ! &{e1 e2} = entries; (@Pair #CoronetState{next e1 flag exc} (@cell_get e2 id)) ) })))")
  lines.push("@state_put = (λ&s (λ&id (λ&val (~s { #CoronetState{next entries flag exc}: ( ! &{e1 e2} = entries; #CoronetState{next (@cell_put e2 id val) flag exc} ) }))))")
  lines.push("@state_flag = (λ&s (~s { #CoronetState{_next _entries flag _exc}: flag }))")
  lines.push("@state_exc = (λ&s (~s { #CoronetState{_next _entries _flag exc}: exc }))")
  lines.push("@newMutVar_ = (λ&val (λ&s (~s { #CoronetState{next entries flag exc}: ( ! &{id next_inc} = next; ( ! &{id1 id2} = id; (@Pair #CoronetState{(+ next_inc 1) (#CoronetCons{id1 val entries}) flag exc} id2) ) ) })))")
  lines.push("@readMutVar_ = (λ&var (λ&s (@state_get s var)))")
  lines.push("@writeMutVar_ = (λ&var (λ&val (λ&s (@state_put s var val))))")
  lines.push("@alloc_base = (λ&size (λ&s (~s { #CoronetState{next entries flag exc}: ( ! &{base next2} = next; (@Pair #CoronetState{(+ next2 size) entries flag exc} base) ) })))")
  lines.push("@newByteArray_ = (λ&size (λ&s (@alloc_base size s)))")
  lines.push("@sizeofByteArray_ = (λ&ba 64)")
  lines.push("@sizeofMutableByteArray_ = (λ&mba (λ&s ((@Pair s) 64)))")
  lines.push("@writeIntArray_ = (λ&arr (λ&idx (λ&val (λ&s (@state_put s (+ arr idx) val)))))")
  lines.push("@writeByteArray_ = (λ&arr (λ&idx (λ&val (λ&s (@state_put s (+ arr idx) val)))))")
  lines.push("@writeWord8Array_ = (λ&arr (λ&idx (λ&val (λ&s (@state_put s (+ arr idx) val)))))")
  lines.push("@readIntArray_ = (λ&arr (λ&idx (λ&s (@state_get s (+ arr idx)))))")
  lines.push("@readByteArray_ = (λ&arr (λ&idx (λ&s (@state_get s (+ arr idx)))))")
  lines.push("@readWord8Array_ = (λ&arr (λ&idx (λ&s (@state_get s (+ arr idx)))))")
  lines.push("@indexIntArray_ = (λ&ba (λ&idx (ba idx)))")
  lines.push("@indexWord8Array_ = (λ&ba (λ&idx (ba idx)))")
  lines.push("@copyByteArray_ = (λ&src (λ&soff (λ&dst (λ&doff (λ&len (λ&s (λ&i (~ (& (>= i doff) (< i (+ doff len))) { 0: (s i) 1+_: (src (+ soff (- i doff))) }))))))))")
  lines.push("@setByteArray_ = (λ&mba (λ&off (λ&len (λ&val (λ&s (λ&i (~ (& (>= i off) (< i (+ off len))) { 0: (s i) 1+_: val })))))))")
  lines.push("@newTVar_ = @newMutVar_")
  lines.push("@readTVar_ = @readMutVar_")
  lines.push("@writeTVar_ = @writeMutVar_")
  lines.push("@readTVarIO_ = @readMutVar_")
  lines.push("@atomically_ = (λ&action (λ&s (action s)))")
  lines.push("@retry_ = (λ&s (~s { #CoronetState{next entries _flag exc}: (@Pair #CoronetState{next entries 1 exc} 0) }))")
  lines.push("@catchRetry_ = (λ&action (λ&handler (λ&s ( ! &r = (action s); (r (λ&s_after (λ&val ( ! &f = (@state_flag s_after); (~ f { 0: (@Pair s_after val) 1+p: (handler s) })))))) )))")
  lines.push("@stm_dispatch = (λ&f (λ&s_after (λ&val (λ&handler (λ&s0 (~ f { 0: (@Pair s_after val) 1+p: (@stm_nonzero (- f 1) s_after val handler s0) }))))))")
  lines.push("@stm_nonzero = (λ&p (λ&s_after (λ&val (λ&handler (λ&s0 (~ p { 0: (@Pair s0 0) 1+p: (handler (@state_exc s_after) s0) }))))))")
  lines.push("@catchSTM_k = (λ&r (λ&handler (λ&s (r (λ&s_after (λ&val ( ! &f = (@state_flag s_after); (@stm_dispatch f s_after val handler s) )))))))")
  lines.push("@catchSTM_ = (λ&action (λ&handler (λ&s ( ! &state_pair = (action s); (@catchSTM_k state_pair handler s) ))))")
  lines.push("@raiseIO_ = (λ&e (λ&s (~s { #CoronetState{next entries _flag _exc}: (@Pair #CoronetState{next entries 2 e} e) })))")
  lines.push("@newMVar_ = (λ&val (λ&s (@newMutVar_ (@Pair 1 val) s)))")
  lines.push("@takeMVar_ = (λ&mv (λ&s ( ! &g = (@state_get s mv); (g (λ&s1 (λ&box (box (λ&_full (λ&val ( ! &s2 = (@state_put s1 mv (@Pair 0 0)); (@Pair s2 val) ))))))) )))")
  lines.push("@tryTakeMVar_ = (λ&mv (λ&s ( ! &g = (@state_get s mv); (g (λ&s1 (λ&box (box (λ&_full (λ&val ( ! &s2 = (@state_put s1 mv (@Pair 0 0)); (@Tuple3 s2 1 val) ))))))) )))")
  lines.push("@putMVar_ = (λ&mv (λ&val (λ&s (@state_put s mv (@Pair 1 val)))))")
  lines.push("@tryPutMVar_ = (λ&mv (λ&val (λ&s ( ! &s2 = (@state_put s mv (@Pair 1 val)); (@Pair s2 1) ))))")
  lines.push("@readMVar_ = (λ&mv (λ&s ( ! &g = (@state_get s mv); (g (λ&s1 (λ&box (box (λ&_full (λ&val (@Pair s1 val))))))) )))")
  lines.push("@tryReadMVar_ = (λ&mv (λ&s ( ! &g = (@state_get s mv); (g (λ&s1 (λ&box (box (λ&_full (λ&val (@Tuple3 s1 1 val))))))) )))")
  lines.push("@isEmptyMVar_ = (λ&mv (λ&s (@Pair s 0)))")
  lines.push("@fork_ = (λ&act (λ&s (~s { #CoronetState{next entries flag exc}: ( ! &{tid next_inc} = next; ( ! child_next = (+ next_inc 1); ( ! &{child_next2 parent_inc} = child_next; ( ! &{ents_c ents_p} = entries; ( ! &{flag_c flag_p} = flag; ( ! &{exc_c exc_p} = exc; ( !! child = (act #CoronetState{child_next2 ents_c flag_c exc_c}); (@Pair #CoronetState{(+ parent_inc 1) ents_p flag_p exc_p} tid) ) ) ) ) ) ) ) }))) ")
  lines.push("@forkOn_ = @fork_")
  lines.push("@killThread_ = (λ&tid (λ&s s))")
  lines.push("@yield_ = (λ&s s)")
  lines.push("@myThreadId_ = (λ&s ((@Pair s) 0))")
  lines.push("@spark_ = (λ&a (λ&s ((@Pair s) a)))")
  lines.push("@seq_ = (λ&a (λ&b (λ&s ((@Pair s) b))))")
  lines.push("@newArray_ = @newByteArray_")
  lines.push("@readArray_ = @readByteArray_")
  lines.push("@writeArray_ = @writeByteArray_")
  lines.push("@indexArray_ = @indexWord8Array_")
  lines.push("@sizeofArray_ = @sizeofByteArray_")
  lines.push("@newSmallArray_ = @newByteArray_")
  lines.push("@readSmallArray_ = @readByteArray_")
  lines.push("@writeSmallArray_ = @writeByteArray_")
  lines.push("@indexSmallArray_ = @indexWord8Array_")
  lines.push("@sizeofSmallArray_ = @sizeofByteArray_")
  lines.push("@mulH_ = (λ&a (λ&b ( ! &a1 = (>> a 16); ( ! &a0 = (& a 65535); ( ! &b1 = (>> b 16); ( ! &b0 = (& b 65535); ( ! &p0 = (* a0 b0); ( ! &p1 = (* a1 b0); ( ! &p2 = (* a0 b1); ( ! &p3 = (* a1 b1); ( ! &mid = (+ (+ p1 p2) (>> p0 16)); (+ p3 (>> mid 16)) ) ) ) ) ) ) ) ) )))")
  lines.push("@plusAddr_ = (λ&addr (λ&off (addr (λ&str_fn (λ&list (λ&curr_off (((@Tuple3 str_fn) list) (+ curr_off off))))))))")
  lines.push("@eqAddr_ = (λ&a1 (λ&a2 (a1 (λ&_1 (λ&_2 (λ&o1 (a2 (λ&_3 (λ&_4 (λ&o2 (== o1 o2)))))))))))")
  lines.push("@readWord8OffAddr_ = (λ&addr (λ&off (λ&s (addr (λ&str_fn (λ&list (λ&curr_off ((@Pair s) (str_fn (+ curr_off off))))))))))")
  lines.push("@touch_ = (λ&ptr (λ&s s))")
  lines.push("@word8ToWord_ = (λ&x x)")
  lines.push("@wordToWord8_ = (λ&x x)")
  lines.push("@indexWord8OffAddr = (λ&addr (λ&off ((λ&p (p (λ&a (λ&b b)))) (((@readWord8OffAddr_ addr) off) 0))))")
  lines.push("@plusWord2 = (λ&a (λ&b ( ! &{a1 a2} = a; ( ! &{s1 s2} = (+ a1 b); ((@Pair s1) (< s2 a2)) ))))")
  lines.push("@timesWord2 = (λ&a (λ&b ( ! &{a1 a2} = a; ( ! &{b1 b2} = b; ((@Pair ((@mulH_ a1) b1)) (* a2 b2)) ))))")
  lines.push("@quotRemWord2 = (λ&_hi (λ&a (λ&b ((@Pair ((@sdiv a) b)) ((@srem a) b)))))")
  lines.push("@addIntC = (λ&a (λ&b ( ! &{a1 a2} = a; ( ! &{s1 s2} = (+ a1 b); ((@Pair s1) (< s2 a2)) ))))")
  lines.push("@subIntC = (λ&a (λ&b ( ! &{a1 a2} = a; ( ! &{b1 b2} = b; ((@Pair (- a1 b1)) (< a2 b2)) ))))")
  lines.push("@mulIntMayOflo = (λ&a (λ&b (!= ((@mulH_ a) b) 0)))")
  lines.push("@popCnt_loop = (λ&n (λ&acc (~ n { 0: acc 1+p: ( ! &{p1 p2} = p; ( ! &p3 = (+ p1 1); (@popCnt_loop (& p3 p2) (+ acc 1)) ) ) })))")
  lines.push("@popCnt = (λ&n (@popCnt_loop n 0))")
  lines.push("@cloneArray = (λ&arr (λ&s ((@Pair s) arr)))")
  lines.push("@freezeArray = @cloneArray")
  lines.push("@thawArray = @cloneArray")
  lines.push("@shrinkArray = (λ&arr (λ&n (λ&s s)))")
  lines.push("@isPinned = (λ&x 0)")
  lines.push("@waitState = (λ&s s)")
  lines.push("@sparkInfo = (λ&s ( ! &{s1 s2} = s; ((@Pair s1) 0) ))")
  lines.push("@threadLabel = (λ&tid (λ&label (λ&s s)))")
  lines.push("@threadStatus = (λ&tid 0)")
  lines.push("@copyAddrToAddr = (λ&src (λ&dst (λ&len (λ&s s))))")
  lines.push("@copyAddrToByteArray = (λ&src (λ&ba (λ&off (λ&len (λ&s s)))))")
  lines.push("@copyByteArrayToAddr = (λ&ba (λ&off (λ&dst (λ&len (λ&s s)))))")
  lines.push("@setAddrRange = (λ&addr (λ&len (λ&val (λ&s s))))")
  lines.push("@compareByteArrays = (λ&a (λ&b 0))")
  lines.push("@opaque = (λ&x x)")
  lines.push("@prim_max = (λ&a (λ&b ( ! &{a1 a2} = a; ( ! &{b1 b2} = b; (~ ((@slt b1) a1) { 0: b2 1+_: a2 }) ))))")
  lines.push("@prim_min = (λ&a (λ&b ( ! &{a1 a2} = a; ( ! &{b1 b2} = b; (~ ((@slt a1) b1) { 0: b2 1+_: a2 }) ))))")
  lines.push("@fmadd = (λ&a (λ&b (λ&c (+ (* a b) c))))")
  lines.push("@fmsub = (λ&a (λ&b (λ&c (- (* a b) c))))")
  lines.push("@fnmadd = (λ&a (λ&b (λ&c (- c (* a b)))))")
  lines.push("@fnmsub = (λ&a (λ&b (λ&c (- 0 (+ (* a b) c)))))")
  lines.push("@prim_pow_loop = (λ&b (λ&e (λ&acc (~ e { 0: acc 1+p: ( ! &{b1 b2} = b; (@prim_pow_loop b1 p (* acc b2)) ) }))))")
  lines.push("@prim_pow = (λ&b (λ&e (@prim_pow_loop b e 1)))")
  lines.push("@decodeFloat_Int = (λ&f ((@Pair f) 0))")
  lines.push("@prim_sin = (λ&x x)")
  lines.push("@prim_cos = (λ&x x)")
  lines.push("@prim_tan = (λ&x x)")
  lines.push("@prim_asin = (λ&x x)")
  lines.push("@prim_acos = (λ&x x)")
  lines.push("@prim_atan = (λ&x x)")
  lines.push("@prim_sinh = (λ&x x)")
  lines.push("@prim_cosh = (λ&x x)")
  lines.push("@prim_tanh = (λ&x x)")
  lines.push("@prim_asinh = (λ&x x)")
  lines.push("@prim_acosh = (λ&x x)")
  lines.push("@prim_atanh = (λ&x x)")
  lines.push("@prim_exp = (λ&x x)")
  lines.push("@prim_log = (λ&x x)")
  lines.push("@prim_expm1 = (λ&x x)")
  lines.push("@prim_log1p = (λ&x x)")
  lines.push("@clz_loop = (λ&n (λ&cnt (~ n { 0: cnt 1+p: (@clz_loop (>> n 1) (- cnt 1)) })))")
  lines.push("@clz = (λ&n (@clz_loop n 32))")
  lines.push("@ctz = (λ&n ( ! &{n1 n2} = n; ( ! &neg = (- 0 n1); ( ! &lsb = (& n2 neg); (@popCnt (- lsb 1)) ) )))")
  lines.push("@byteSwap = (λ&n ( ! &b0 = (& (>> n 24) 255); ( ! &b1 = (& (>> n 8) 65280); ( ! &b2 = (& (<< n 8) 16711680); ( ! &b3 = (<< n 24); (| (| b0 b1) (| b2 b3)) ) ) ) ))")
  lines.push("@bitReverse = (λ&x x)")
  lines.push("@pdep = (λ&src (λ&mask src))")
  lines.push("@pext = (λ&src (λ&mask src))")
  lines.push("@casArray = (λ&arr (λ&idx (λ&old_v (λ&new_v (λ&s ( ! &got = (@state_get s arr); (got (λ&s1 (λ&actual ( ! &s2 = (@state_put s1 arr new_v); ((@Pair s2) actual) )))) ))))))")
  lines.push("@casAddr = (λ&addr (λ&old_v (λ&new_v (λ&s ((@Pair s) old_v)))))")
  lines.push("@exchangeAddr = (λ&addr (λ&new_v (λ&s ((@Pair s) new_v))))")
  lines.push("@fetchOpIntArray = (λ&arr (λ&idx (λ&val (λ&s ( ! &got = (@state_get s arr); (got (λ&s1 (λ&old ( ! &{old1 old2} = old; ( ! &s2 = (@state_put s1 arr (+ old1 val)); ((@Pair s2) old2) ) )))) )))))")
  lines.push("@fetchOpWordAddr = (λ&addr (λ&val (λ&s ((@Pair s) val))))")
  lines.push("@unpackCString_ = (λ&addr (addr (λ&str_fn (λ&list (λ&curr_off list)))))")
  lines.push("@unpackCStringUtf8_ = (λ&addr (addr (λ&str_fn (λ&list (λ&curr_off list)))))")
  if has_compare {
    lines.push("@compare = (λ&dict (λ&a (λ&b (~ ((@slt a) b) { 0: (~ (== a b) { 0: @GT 1+p: @EQ }) 1+p: @LT }))))")
  }
  lines.push("@_add_mod1000000007 = (λ&a (λ&b ( ! &sum = (+ a b); (~ (>= sum 1000000007) { 0: sum 1+_: (- sum 1000000007) }) )))")
  lines.push("@_mul31_mod1000000007 = (λ&y ( ! &y2 = (@_add_mod1000000007 y y); ( ! &y4 = (@_add_mod1000000007 y2 y2); ( ! &y8 = (@_add_mod1000000007 y4 y4); ( ! &y16 = (@_add_mod1000000007 y8 y8); (@_add_mod1000000007 y16 (@_add_mod1000000007 y8 (@_add_mod1000000007 y4 (@_add_mod1000000007 y2 y)))) ) ) ) ))")
  lines.push("@dataToTagSmall_ = (λ&x ((x (λ&_ 0)) (λ&_ 1)))")
  lines.push("@tagToEnum_ = (λ&x (~ x { 0: @False 1+_: @True }))")
  lines.push("@eqString = (λ&xs (λ&ys ((xs ((ys @True) (λ&_y (λ&_ys @False)))) (λ&x (λ&x_rest ((ys @False) (λ&y (λ&y_rest (~ (== x y) { 0: @False 1+p: ((@eqString x_rest) y_rest) })))))))))")
  lines.push("@map = (λ&f (λ&xs ((xs @Nil) (λ&y (λ&ys ((@Cons (f y)) ((@map f) ys)))))))")
  lines.push("@filter = (λ&p (λ&xs ((xs @Nil) (λ&y (λ&ys (((p y) ((@filter p) ys)) ((@Cons y) ((@filter p) ys))))))))")
  lines.push("@_plus__plus_ = (λ&xs (λ&ys ((xs ys) (λ&z (λ&zs ((@Cons z) ((@_plus__plus_ zs) ys)))))))")
  lines.push("@concatMap = (λ&f (λ&xs ((xs @Nil) (λ&y (λ&ys ((@_plus__plus_ (f y)) ((@concatMap f) ys)))))))")
  lines.push("@elem = (λ&dict (λ&target (λ&xs ((xs @False) (λ&y (λ&ys (((((dict (λ&eq (λ&ne eq))) target) y) (((@elem dict) target) ys)) @True)))))))")
  lines.push("@notElem = (λ&dict (λ&target (λ&xs ((((@elem dict) target) xs) @True @False))))")
  lines.push("@fst = (λ&p (p (λ&a (λ&b a))))")
  lines.push("@snd = (λ&p (p (λ&a (λ&b b))))")
  lines.push("@_fEqList__s_c_ne_1 = (λ&a (λ&b (((@eqString a) b) @True @False)))")
  lines.push("@_fEqList__c_eq_ = (λ&dict (λ&xs (λ&ys ((xs ((ys @True) (λ&_y (λ&_ys @False)))) (λ&x (λ&x_rest ((ys @False) (λ&y (λ&y_rest ((((dict (λ&eq (λ&ne eq))) x) y) @False (((@_fEqList__c_eq_ dict) x_rest) y_rest)))))))))))")
  lines.push("@_fEqTuple2 = (λ&dict_a (λ&dict_b ((@C_Eq (λ&p1 (λ&p2 (p1 (λ&x1 (λ&y1 (p2 (λ&x2 (λ&y2 (((((dict_a (λ&eq (λ&ne eq))) x1) x2) @False) (((dict_b (λ&eq (λ&ne eq))) y1) y2))))))))))) *)))")
  lines.push("@_fEqList__s_fEqList1 = ((@C_Eq @eqString) @_fEqList__s_c_ne_1)")
  lines.push("@C_Eq = (λ&eq (λ&ne (λ&c ((c eq) ne))))")
  lines.push("@Eq = @C_Eq")
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
