///| Common AST Transformations and ADT Analysis for Coronet.

///| Representation of an ADT constructor definition
#derive(Eq, Debug)
pub(all) struct CtorDef {
  name : String
  mut arity : Int
}
pub extend CtorDef with Eq::{not_equal, equal}
pub extend CtorDef with @moonbitlang/core/debug.Debug::{to_repr}

///| Representation of an ADT family containing one or more constructors
#derive(Eq, Debug)
pub(all) struct AdtFamily {
  family_name : String
  ctors : Array[CtorDef]
}
pub extend AdtFamily with Eq::{not_equal, equal}
pub extend AdtFamily with @moonbitlang/core/debug.Debug::{to_repr}

///| Normalize constructor names (e.g. ":" -> "Cons", "[]" -> "Nil")
pub fn normalize_ctor_name(name : String) -> String {
  match name {
    "[]" => "Nil"
    ":" | "(:)" => "Cons"
    "()" => "Unit"
    "(,)" => "Pair"
    "(,,)" => "Tuple3"
    "(,,,)" => "Tuple4"
    "(,,,,)" => "Tuple5"
    "(,,,,,)" => "Tuple6"
    "(,,,,,,)" => "Tuple7"
    "(,,,,,,,)" => "Tuple8"
    _ => name
  }
}

///| Check if a constructor is an unboxed tuple/sum constructor
pub fn is_unboxed_ctor(name : String) -> Bool {
  match name {
    "I#" | "W#" | "W32#" | "W8#" | "W16#" | "W64#" | "I8#" | "I16#" | "I32#" | "I64#" | "C#" => true
    "(#,#)" | "(#,,#)" | "(#,,,#)" | "(# #)" | "(##)" | "(#_#)" | "Solo#" | "Unit#" => true
    _ => {
      let trimmed = name.trim().to_owned()
      (trimmed.has_prefix("(#") && trimmed.has_suffix("#)")) ||
      (trimmed.has_prefix("(") && trimmed.has_suffix(")"))
    }
  }
}

///| Check if a name is a standard binary operator
pub fn is_binop(name : String) -> (Bool, String) {
  match name {
    "+" | "+#" | "plusWord#" | "plusWord32#" => (true, "+")
    "-" | "-#" | "minusWord#" | "minusWord32#" => (true, "-")
    "*" | "*#" | "timesWord#" | "timesWord32#" => (true, "*")
    "/" | "/#" | "quotWord#" | "quotWord32#" | "quotInt#" => (true, "/")
    "%" | "%#" | "remWord#" | "remWord32#" | "remInt#" => (true, "%")
    "==" | "==#" | "eqWord#" | "eqWord32#" => (true, "==")
    "!=" | "/=" | "/=#" | "neWord#" | "neWord32#" => (true, "!=")
    "<" | "<#" | "ltWord#" | "ltWord32#" => (true, "<")
    ">" | ">#" | "gtWord#" | "gtWord32#" => (true, ">")
    "<=" | "<=#" | "leWord#" | "leWord32#" => (true, "<=")
    ">=" | ">=#" | "geWord#" | "geWord32#" => (true, ">=")
    "&" | "and#" | "andI#" | ".&." => (true, "&")
    "|" | "or#" | "orI#" | ".|." => (true, "|")
    "^" | "xor#" | "xorI#" | "xor" | ".^." => (true, "^")
    "<<" | "uncheckedIShiftL#" | "uncheckedShiftL#" | "shiftL" => (true, "<<")
    ">>" | "uncheckedIShiftRL#" | "uncheckedShiftRL#" | "uncheckedIShiftRA#" | "uncheckedShiftRA#" | "shiftR" => (true, ">>")
    _ => (false, "")
  }
}

///| Sort constructors: 0-arity constructors first alphabetically, then positive-arity alphabetically
pub fn sort_ctors(ctors : Array[CtorDef]) -> Unit {
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

///| Initialize pre-seeded standard ADT families
pub fn init_default_families() -> Array[AdtFamily] {
  [
    {
      family_name: "Bool_Custom",
      ctors: [{ name: "MyTrue", arity: 0 }, { name: "MyFalse", arity: 0 }],
    },
    {
      family_name: "Bool_Std",
      ctors: [{ name: "False", arity: 0 }, { name: "True", arity: 0 }],
    },
    {
      family_name: "Maybe_Custom",
      ctors: [{ name: "MyNothing", arity: 0 }, { name: "MyJust", arity: 1 }],
    },
    {
      family_name: "Maybe_Std",
      ctors: [{ name: "Nothing", arity: 0 }, { name: "Just", arity: 1 }],
    },
    {
      family_name: "List_Custom",
      ctors: [{ name: "MyNil", arity: 0 }, { name: "MyCons", arity: 2 }],
    },
    {
      family_name: "Ordering",
      ctors: [{ name: "LT", arity: 0 }, { name: "EQ", arity: 0 }, { name: "GT", arity: 0 }],
    },
    {
      family_name: "Eq",
      ctors: [{ name: "C_Eq", arity: 2 }],
    },
    {
      family_name: "Unit",
      ctors: [{ name: "Unit", arity: 0 }],
    },
    {
      family_name: "Pair",
      ctors: [{ name: "Pair", arity: 2 }],
    },
    {
      family_name: "Tuple3",
      ctors: [{ name: "Tuple3", arity: 3 }],
    },
    {
      family_name: "Tuple4",
      ctors: [{ name: "Tuple4", arity: 4 }],
    },
    {
      family_name: "Tuple5",
      ctors: [{ name: "Tuple5", arity: 5 }],
    },
    {
      family_name: "Tuple6",
      ctors: [{ name: "Tuple6", arity: 6 }],
    },
    {
      family_name: "Tuple7",
      ctors: [{ name: "Tuple7", arity: 7 }],
    },
    {
      family_name: "Tuple8",
      ctors: [{ name: "Tuple8", arity: 8 }],
    },
  ]
}

///| Find the ADT family containing a constructor name
pub fn find_family(families : Array[AdtFamily], ctor_name : String) -> AdtFamily? {
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
pub fn collect_adts_from_expr(
  expr : Expr,
  families : Array[AdtFamily],
  used_ctors : Array[String]
) -> Unit {
  match expr {
    Constr(raw_name, args) => {
      let name = normalize_ctor_name(raw_name)
      if !is_unboxed_ctor(name) {
        if !used_ctors.contains(name) {
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
            family_name: "Adt_" + name,
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
              if !used_ctors.contains(name) {
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
            family_name: "Adt_" + case_ctors[0].0,
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
          if !target_fam.family_name.has_prefix("Bool_") && !target_fam.family_name.has_prefix("Ordering") {
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
    Var(_) | LitInt(_) | LitChar(_) | LitString(_) => ()
  }
}

///| Discover and unify all ADT families in a program
pub fn discover_adts(prog : Program) -> Array[AdtFamily] {
  let families = init_default_families()
  let used_ctors : Array[String] = []
  for b in prog.binds {
    match b {
      NonRec(_, expr) => collect_adts_from_expr(expr, families, used_ctors)
      Rec(pairs) =>
        for p in pairs {
          collect_adts_from_expr(p.1, families, used_ctors)
        }
    }
  }
  let active_families : Array[AdtFamily] = []
  for fam in families {
    if fam.ctors.length() > 0 {
      active_families.push(fam)
    }
  }
  active_families
}

///| Substitute variable occurrences in an expression
pub fn substitute_var(expr : Expr, target : String, replacement : Expr) -> Expr {
  match expr {
    Var(name) => if name == target { replacement } else { expr }
    LitInt(_) | LitChar(_) | LitString(_) => expr
    Constr(name, args) => {
      let new_args : Array[Expr] = []
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
          let new_pairs : Array[(String, Expr)] = []
          for p in pairs {
            new_pairs.push((p.0, substitute_var(p.1, target, replacement)))
          }
          if shadows {
            Let(Rec(new_pairs), body)
          } else {
            Let(Rec(new_pairs), substitute_var(body, target, replacement))
          }
        }
      }
    Case(scrut, binder, alts) => {
      let new_scrut = substitute_var(scrut, target, replacement)
      let new_alts : Array[Alt] = []
      for a in alts {
        let mut shadows = binder == target
        match a.pat {
          Default(Some(v)) => if v == target { shadows = true }
          Data(_, vars) =>
            for v in vars {
              if v == target { shadows = true; break }
            }
          _ => ()
        }
        if shadows {
          new_alts.push(a)
        } else {
          new_alts.push({ pat: a.pat, expr: substitute_var(a.expr, target, replacement) })
        }
      }
      Case(new_scrut, binder, new_alts)
    }
  }
}

fn collect_free_vars_rec(
  expr : Expr,
  bound : Array[String],
  globals : Array[String],
  acc : Array[String]
) -> Unit {
  match expr {
    Var(name) => {
      if !bound.contains(name) &&
        !globals.contains(name) &&
        !acc.contains(name) &&
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
          name != "compare" {
          acc.push(name)
        }
      }
    }
    LitInt(_) | LitChar(_) | LitString(_) => ()
    Constr(_, args) =>
      for a in args {
        collect_free_vars_rec(a, bound, globals, acc)
      }
    App(f, a) => {
      collect_free_vars_rec(f, bound, globals, acc)
      collect_free_vars_rec(a, bound, globals, acc)
    }
    Lam(p, body) => {
      let next_bound = bound.copy()
      next_bound.push(p)
      collect_free_vars_rec(body, next_bound, globals, acc)
    }
    Let(bind, body) => {
      match bind {
        NonRec(n, val) => {
          collect_free_vars_rec(val, bound, globals, acc)
          let next_bound = bound.copy()
          next_bound.push(n)
          collect_free_vars_rec(body, next_bound, globals, acc)
        }
        Rec(pairs) => {
          let next_bound = bound.copy()
          for p in pairs {
            next_bound.push(p.0)
          }
          for p in pairs {
            collect_free_vars_rec(p.1, next_bound, globals, acc)
          }
          collect_free_vars_rec(body, next_bound, globals, acc)
        }
      }
    }
    Case(scrut, binder, alts) => {
      collect_free_vars_rec(scrut, bound, globals, acc)
      for alt in alts {
        let next_bound = bound.copy()
        if binder != "" && binder != "_" {
          next_bound.push(binder)
        }
        match alt.pat {
          Default(Some(wild)) => next_bound.push(wild)
          Data(_, vars) =>
            for v in vars {
              next_bound.push(v)
            }
          _ => ()
        }
        collect_free_vars_rec(alt.expr, next_bound, globals, acc)
      }
    }
  }
}

fn lift_expr_rec_impl(
  expr : Expr,
  globals : Array[String],
  new_top_binds : Array[Bind],
  counter : Array[Int]
) -> Expr {
  match expr {
    Let(Rec(pairs), body) => {
      let mut current_body = lift_expr_rec_impl(body, globals, new_top_binds, counter)
      for pair in pairs {
        let fn_name = pair.0
        let fn_expr = lift_expr_rec_impl(pair.1, globals, new_top_binds, counter)
        let free_vars : Array[String] = []
        collect_free_vars_rec(fn_expr, [fn_name], globals, free_vars)

        let c_idx = counter[0]
        counter[0] = c_idx + 1
        let lifted_name = fn_name + "__lifted_" + c_idx.to_string()
        globals.push(lifted_name)

        let mut call_head = Expr::Var(lifted_name)
        for fv in free_vars {
          call_head = Expr::App(call_head, Expr::Var(fv))
        }

        let fn_expr_subst = substitute_var(fn_expr, fn_name, call_head)
        let mut final_lifted_expr = fn_expr_subst
        for i = free_vars.length() - 1; i >= 0; i = i - 1 {
          final_lifted_expr = Expr::Lam(free_vars[i], final_lifted_expr)
        }

        new_top_binds.push(Bind::NonRec(lifted_name, final_lifted_expr))
        current_body = substitute_var(current_body, fn_name, call_head)
      }
      current_body
    }
    Let(NonRec(name, val), body) =>
      Let(NonRec(name, lift_expr_rec_impl(val, globals, new_top_binds, counter)), lift_expr_rec_impl(body, globals, new_top_binds, counter))
    Lam(param, body) => Lam(param, lift_expr_rec_impl(body, globals, new_top_binds, counter))
    App(f, a) => App(lift_expr_rec_impl(f, globals, new_top_binds, counter), lift_expr_rec_impl(a, globals, new_top_binds, counter))
    Case(scrut, binder, alts) => {
      let new_scrut = lift_expr_rec_impl(scrut, globals, new_top_binds, counter)
      let new_alts : Array[Alt] = []
      for a in alts {
        new_alts.push({ pat: a.pat, expr: lift_expr_rec_impl(a.expr, globals, new_top_binds, counter) })
      }
      Case(new_scrut, binder, new_alts)
    }
    Constr(name, args) => {
      let new_args : Array[Expr] = []
      for a in args {
        new_args.push(lift_expr_rec_impl(a, globals, new_top_binds, counter))
      }
      Constr(name, new_args)
    }
    Var(_) | LitInt(_) | LitChar(_) | LitString(_) => expr
  }
}

///| Lift all local recursive let-bindings to globally unique top-level definitions
pub fn lift_program_rec(prog : Program) -> Program {
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
  let new_top_binds : Array[Bind] = []
  let new_binds : Array[Bind] = []

  for b in prog.binds {
    match b {
      NonRec(n, expr) => {
        let lifted_expr = lift_expr_rec_impl(expr, globals, new_top_binds, counter)
        new_binds.push(NonRec(n, lifted_expr))
      }
      Rec(pairs) => {
        let new_pairs : Array[(String, Expr)] = []
        for p in pairs {
          new_pairs.push((p.0, lift_expr_rec_impl(p.1, globals, new_top_binds, counter)))
        }
        new_binds.push(Rec(new_pairs))
      }
    }
  }

  let final_binds : Array[Bind] = []
  for b in new_top_binds {
    final_binds.push(b)
  }
  for b in new_binds {
    final_binds.push(b)
  }
  Program::new(final_binds)
}

///| Check if a name is a known primitive or builtin operation
pub fn is_known_builtin(name : String) -> Bool {
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
    // Wide, narrow and character variants: same scalars, wrapped at the net's
    // 29-bit domain rather than at 64 or 8 bits.
    "plusWord64#" | "plusInt64#" | "plusWord8#" | "minusInt64#" | "subWord8#" => true
    "timesWord64#" | "timesInt64#" | "negateInt64#" | "not64#" => true
    "and64#" | "or64#" | "xor64#" => true
    "uncheckedShiftL64#" | "uncheckedIShiftL64#" | "uncheckedShiftRL64#" | "uncheckedIShiftRA64#" => true
    "eqChar#" | "ltChar#" | "gtChar#" | "leChar#" | "geChar#" | "neChar#" => true
    "ltInt64#" | "gtInt64#" | "geInt64#" | "ltWord8#" | "leWord8#" | "geWord8#" | "gtWord8#" | "eqWord8#" => true
    "word64ToInt64#" | "int64ToWord64#" | "intToInt64#" | "int64ToInt#" | "int32ToInt#" | "integerToInt#" => true
    "int8ToInt#" | "int16ToInt#" | "wordToWord16#" | "wordToWord64#" | "word64ToWord#" => true
    "word16ToInt16#" | "int16ToWord16#" | "word8ToInt8#" | "int8ToWord8#" => true
    "intToInt8#" | "intToInt16#" | "intToInt32#" | "int32ToWord32#" | "word32ToInt32#" => true
    "newPinnedByteArray#" | "unsafeFreezeByteArray#" | "unsafeThawByteArray#" => true
    "getSizeofMutableByteArray#" | "resizeMutableByteArray#" | "shrinkMutableByteArray#" | "byteArrayContents#" => true
    "indexCharOffAddr#" | "unpackAppendCString#" | "indexArray#" | "copyMutableByteArray#" | "keepAlive#" => true
    "compareByteArrays#" | "popCnt64#" | "typeRep#" | "catch#" | "atomicModifyMutVar2#" => true
    "narrow8Int#" | "narrow16Int#" | "narrow32Int#" | "narrow8Word#" | "narrow16Word#" => true
    "chr#" | "ord#" => true
    "not#" | "notI#" | "notWord#" | "negateInt#" => true
    "runRW#" | "newByteArray#" | "writeIntArray#" | "readIntArray#" | "writeByteArray#" | "readByteArray#" => true
    "sizeofByteArray#" | "sizeofMutableByteArray#" | "indexWord8Array#" | "readWord8Array#" | "writeWord8Array#" | "indexIntArray#" | "copyByteArray#" | "setByteArray#" => true
    "newMutVar#" | "readMutVar#" | "writeMutVar#" => true
    "plusAddr#" | "eqAddr#" | "readWord8OffAddr#" | "touch#" | "word8ToWord#" | "wordToWord8#" | "compare" => true
    "unpackCString#" | "unpackCStringUtf8#" | "Addr#" => true
    "raise#" | "raiseIO#" | "patError" | "patError#" | "absentError" => true
    "realWorld#" | "void#" | "State#" | "RealWorld" | "MutVar#" => true
    "overflowError" | "divZeroError" => true
    "add_mod" | "mul31_mod" | "_fNumWord32__c" | "divModPrim" => true
    "LT" | "EQ" | "GT" => true
    "dataToTagSmall#" | "dataToTagSmall" | "tagToEnum#" | "tagToEnum" => true
    // GHC's pointer-identity fast path, which -O inserts into library code.
    // Only `True` implies anything, so answering "not the same object" is
    // always a sound approximation; lowering emits the constant 0.
    "reallyUnsafePtrEquality#" | "reallyUnsafePtrEquality" => true
    // `lazy x = x` in GHC.Exts: GHC wraps a lazily-bound value to stop strictness
    // analysis. The net encoding is already lazy, so it is the identity here.
    "lazy" => true
    // GHC's `error`/`undefined` crash paths. There is no exception channel in a
    // pure net, so lowering answers with a defined value; a program that really
    // takes this path reports a number GHC would never print.
    "error" | "errorWithoutStackTrace" | "undefined" => true
    "&&" | "||" | "isTrue#" | "isTrue" => true
    "eqString" | "map" | "filter" | "_plus__plus_" | "concatMap" | "elem" | "notElem" | "fst" | "snd" => true
    "$fEqList_$c_eq_" | "$fEqTuple2" | "$fEqList_$s$c_ne_1" | "$fEqList_$s$fEqList1" => true
    "C:Eq" | "C:Show" | "C:Num" | "C:Ord" | "Eq" | "C_Eq" => true
    _ => false
  }
}

pub fn is_known_symbol(
  v : String,
  defined_names : Array[String],
  families : Array[AdtFamily]
) -> Bool {
  if defined_names.contains(v) {
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

///| Crash primitives whose message argument is never needed.
fn is_crash_prim_name(name : String) -> Bool {
  match name {
    "error" | "errorWithoutStackTrace" | "undefined" | "patError" | "patError#" |
    "absentError" | "raise#" | "raiseIO#" => true
    _ => false
  }
}

///| Replace `error msg` / `patError msg` / `undefined` with a plain value.
///|
///| GHC only needs the message to print a diagnostic and then kill the process,
///| so the argument is dead code for a pure evaluator: it is usually a chain of
///| `unpackCString#` constants living in a module the project never compiles.
///| Dropping it here is what keeps real Core compilable, and it is also what
///| removes those dangling references from the emitted book.
pub fn strip_crash_messages(prog : Program) -> Program {
  fn rewrite(expr : Expr) -> Expr {
    match expr {
      App(_, _) => {
        let (head, args) = expr.unwind_app()
        match head {
          Var(name) =>
            if is_crash_prim_name(name) && args.length() > 0 {
              return LitInt(0)
            }
          _ => ()
        }
        let mut rebuilt = rewrite(head)
        for a in args {
          rebuilt = App(rebuilt, rewrite(a))
        }
        rebuilt
      }
      Lam(p, body) => Lam(p, rewrite(body))
      Let(bind, body) => {
        match bind {
          NonRec(n, v) => Let(NonRec(n, rewrite(v)), rewrite(body))
          Rec(pairs) => {
            let new_pairs : Array[(String, Expr)] = []
            for p in pairs {
              new_pairs.push((p.0, rewrite(p.1)))
            }
            Let(Rec(new_pairs), rewrite(body))
          }
        }
      }
      Case(scrut, binder, alts) => {
        let new_alts : Array[Alt] = []
        for alt in alts {
          new_alts.push({ pat: alt.pat, expr: rewrite(alt.expr) })
        }
        Case(rewrite(scrut), binder, new_alts)
      }
      Constr(c, args) => {
        let new_args : Array[Expr] = []
        for a in args {
          new_args.push(rewrite(a))
        }
        Constr(c, new_args)
      }
      _ => expr
    }
  }

  let new_binds : Array[Bind] = []
  for b in prog.binds {
    match b {
      NonRec(n, e) => new_binds.push(NonRec(n, rewrite(e)))
      Rec(pairs) => {
        let new_pairs : Array[(String, Expr)] = []
        for p in pairs {
          new_pairs.push((p.0, rewrite(p.1)))
        }
        new_binds.push(Rec(new_pairs))
      }
    }
  }
  Program::new(new_binds)
}

///| Free variables of one expression, in first-seen order. Used by
///| `coronet --report-gaps` to name what a Core unit still depends on.
pub fn expr_free_vars(expr : Expr) -> Array[String] {
  let acc : Array[String] = []
  collect_expr_free_vars_rec(expr, [], acc)
  acc
}

fn collect_expr_free_vars_rec(
  expr : Expr,
  bound : Array[String],
  free_vars : Array[String]
) -> Unit {
  match expr {
    Var(name) => {
      if !bound.contains(name) && !free_vars.contains(name) {
        free_vars.push(name)
      }
    }
    LitInt(_) | LitChar(_) | LitString(_) => ()
    Constr(_, args) =>
      for a in args {
        collect_expr_free_vars_rec(a, bound, free_vars)
      }
    App(f, a) => {
      collect_expr_free_vars_rec(f, bound, free_vars)
      collect_expr_free_vars_rec(a, bound, free_vars)
    }
    Lam(p, body) => {
      let next_bound = bound.copy()
      next_bound.push(p)
      collect_expr_free_vars_rec(body, next_bound, free_vars)
    }
    Let(bind, body) => {
      match bind {
        NonRec(n, val) => {
          collect_expr_free_vars_rec(val, bound, free_vars)
          let next_bound = bound.copy()
          next_bound.push(n)
          collect_expr_free_vars_rec(body, next_bound, free_vars)
        }
        Rec(pairs) => {
          let next_bound = bound.copy()
          for p in pairs {
            next_bound.push(p.0)
          }
          for p in pairs {
            collect_expr_free_vars_rec(p.1, next_bound, free_vars)
          }
          collect_expr_free_vars_rec(body, next_bound, free_vars)
        }
      }
    }
    Case(scrut, binder, alts) => {
      collect_expr_free_vars_rec(scrut, bound, free_vars)
      for alt in alts {
        let next_bound = bound.copy()
        if binder != "" && binder != "_" {
          next_bound.push(binder)
        }
        match alt.pat {
          Default(Some(wild)) => next_bound.push(wild)
          Data(_, vars) =>
            for v in vars {
              next_bound.push(v)
            }
          _ => ()
        }
        collect_expr_free_vars_rec(alt.expr, next_bound, free_vars)
      }
    }
  }
}

fn collect_var_refs_rec(expr : Expr, acc : Array[String]) -> Unit {
  match expr {
    Var(name) => if !acc.contains(name) { acc.push(name) }
    LitInt(_) | LitChar(_) | LitString(_) => ()
    Constr(_, args) =>
      for a in args {
        collect_var_refs_rec(a, acc)
      }
    App(f, a) => {
      collect_var_refs_rec(f, acc)
      collect_var_refs_rec(a, acc)
    }
    Lam(_, body) => collect_var_refs_rec(body, acc)
    Let(bind, body) => {
      match bind {
        NonRec(_, val) => collect_var_refs_rec(val, acc)
        Rec(pairs) =>
          for p in pairs {
            collect_var_refs_rec(p.1, acc)
          }
      }
      collect_var_refs_rec(body, acc)
    }
    Case(scrut, _, alts) => {
      collect_var_refs_rec(scrut, acc)
      for alt in alts {
        collect_var_refs_rec(alt.expr, acc)
      }
    }
  }
}

///| Dead-code elimination of bindings referencing unavailable external symbols
pub fn dce_program(prog : Program) -> Program {
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
        collect_expr_free_vars_rec(expr, [], fv)
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
          collect_expr_free_vars_rec(p.1, [], fv)
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
          if !invalid_names.contains(n) {
            let refs : Array[String] = []
            collect_var_refs_rec(expr, refs)
            for r in refs {
              if invalid_names.contains(r) {
                invalid_names.push(n)
                changed = true
                break
              }
            }
          }
        }
        Rec(pairs) => {
          for p in pairs {
            if !invalid_names.contains(p.0) {
              let refs : Array[String] = []
              collect_var_refs_rec(p.1, refs)
              for r in refs {
                if invalid_names.contains(r) {
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

  let kept_binds : Array[Bind] = []
  for b in prog.binds {
    match b {
      NonRec(n, _) => if !invalid_names.contains(n) { kept_binds.push(b) }
      Rec(pairs) => {
        let new_pairs : Array[(String, Expr)] = []
        for p in pairs {
          if !invalid_names.contains(p.0) {
            new_pairs.push(p)
          }
        }
        if new_pairs.length() > 0 {
          kept_binds.push(Rec(new_pairs))
        }
      }
    }
  }

  Program::new(kept_binds)
}
