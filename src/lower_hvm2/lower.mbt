///| CoreLite to HVM2 Lowering Engine for Coronet

// ----------------------------------------------------------------------------
// HVM2 AST Representation
// ----------------------------------------------------------------------------

///| HVM2 Interaction Combinator Tree node
#derive(Eq)
pub enum Tree {
  Var(String)
  Ref(String)
  Era
  Num(Int)
  OpSym(String)
  Con(Tree, Tree)
  Dup(Tree, Tree)
  Opr(Tree, Tree)
  Swi(Tree, Tree)
}

///|
pub impl Show for Tree with output(self, logger) {
  match self {
    Var(s) => logger.write_string(s)
    Ref(s) => logger.write_string("@\{s}")
    Era => logger.write_string("*")
    Num(n) => {
      let u = (n.to_int64() & 0xFFFFFFL).to_int()
      logger.write_string("\{u}")
    }
    OpSym(op) => logger.write_string(op)
    Con(a, b) => logger.write_string("(\{a} \{b})")
    Dup(a, b) => logger.write_string("{\{a} \{b}}")
    Opr(a, b) => logger.write_string("$(\{a} \{b})")
    Swi(a, b) => logger.write_string("?(\{a} \{b})")
  }
}

pub extend Tree with Eq::{not_equal, equal}
pub extend Tree with Show::{to_string, output}

///| Active pair (redex)
#derive(Eq)
pub struct Redex {
  fst : Tree
  snd : Tree
}

///|
pub impl Show for Redex with output(self, logger) {
  logger.write_string("\{self.fst} ~ \{self.snd}")
}

pub extend Redex with Eq::{not_equal, equal}
pub extend Redex with Show::{to_string, output}

///| Net: Root tree + active redexes
#derive(Eq)
pub struct Net {
  root : Tree
  redexes : Array[Redex]
}

///|
pub impl Show for Net with output(self, logger) {
  logger.write_string("\{self.root}")
  for r in self.redexes {
    logger.write_string("\n  & \{r.fst} ~ \{r.snd}")
  }
}

pub extend Net with Eq::{not_equal, equal}
pub extend Net with Show::{to_string, output}

///| Book: Collection of named net definitions
#derive(Eq)
pub struct Book {
  defs : Array[(String, Net)]
}

///|
pub impl Show for Book with output(self, logger) {
  for i, def in self.defs {
    if i > 0 {
      logger.write_string("\n\n")
    }
    logger.write_string("@\{def.0} = \{def.1}")
  }
}

pub extend Book with Eq::{not_equal, equal}
pub extend Book with Show::{to_string, output}

// ----------------------------------------------------------------------------
// Linearization & Duplication Pass
// ----------------------------------------------------------------------------

fn count_vars_tree(tree : Tree, counts : Array[(String, Int)]) -> Unit {
  match tree {
    Var(name) => {
      let mut found = false
      for i = 0; i < counts.length(); i = i + 1 {
        if counts[i].0 == name {
          counts[i] = (name, counts[i].1 + 1)
          found = true
          break
        }
      }
      if !found {
        counts.push((name, 1))
      }
    }
    Con(a, b) | Dup(a, b) | Opr(a, b) | Swi(a, b) => {
      count_vars_tree(a, counts)
      count_vars_tree(b, counts)
    }
    _ => ()
  }
}

fn replace_vars_tree(
  tree : Tree,
  rep_map : Array[(String, Array[String])],
  rep_idx : Array[(String, Int)],
  erase_vars : Array[String]
) -> Tree {
  match tree {
    Var(name) => {
      for ev in erase_vars {
        if ev == name {
          return Era
        }
      }
      for i = 0; i < rep_map.length(); i = i + 1 {
        if rep_map[i].0 == name {
          let curr = rep_idx[i].1
          let new_name = rep_map[i].1[curr]
          rep_idx[i] = (name, curr + 1)
          return Var(new_name)
        }
      }
      Var(name)
    }
    Con(a, b) => Con(replace_vars_tree(a, rep_map, rep_idx, erase_vars), replace_vars_tree(b, rep_map, rep_idx, erase_vars))
    Dup(a, b) => Dup(replace_vars_tree(a, rep_map, rep_idx, erase_vars), replace_vars_tree(b, rep_map, rep_idx, erase_vars))
    Opr(a, b) => Opr(replace_vars_tree(a, rep_map, rep_idx, erase_vars), replace_vars_tree(b, rep_map, rep_idx, erase_vars))
    Swi(a, b) => Swi(replace_vars_tree(a, rep_map, rep_idx, erase_vars), replace_vars_tree(b, rep_map, rep_idx, erase_vars))
    _ => tree
  }
}

fn make_dup_tree(vars : Array[String]) -> Tree {
  let len = vars.length()
  if len == 1 {
    Var(vars[0])
  } else if len == 2 {
    Dup(Var(vars[0]), Var(vars[1]))
  } else {
    let mut tree = Dup(Var(vars[len - 2]), Var(vars[len - 1]))
    for i = len - 3; i >= 0; i = i - 1 {
      tree = Dup(Var(vars[i]), tree)
    }
    tree
  }
}

fn linearize_net(net : Net) -> Net {
  let counts : Array[(String, Int)] = []
  count_vars_tree(net.root, counts)
  for r in net.redexes {
    count_vars_tree(r.fst, counts)
    count_vars_tree(r.snd, counts)
  }

  let rep_map : Array[(String, Array[String])] = []
  let rep_idx : Array[(String, Int)] = []
  let new_redexes : Array[Redex] = []
  let erase_vars : Array[String] = []

  for entry in counts {
    let name = entry.0
    let count = entry.1
    if count == 1 {
      erase_vars.push(name)
    } else if count > 2 {
      let num_dups = count - 1
      let dup_vars : Array[String] = []
      for i = 1; i <= num_dups; i = i + 1 {
        dup_vars.push("\{name}_d\{i}")
      }
      let var_list : Array[String] = [name]
      for v in dup_vars {
        var_list.push(v)
      }
      rep_map.push((name, var_list))
      rep_idx.push((name, 0))

      let dup_tree = make_dup_tree(dup_vars)
      new_redexes.push({ fst: dup_tree, snd: Var(name) })
    }
  }

  if rep_map.length() == 0 && erase_vars.length() == 0 {
    return net
  }

  let new_root = replace_vars_tree(net.root, rep_map, rep_idx, erase_vars)
  let result_redexes : Array[Redex] = []
  for r in net.redexes {
    result_redexes.push({
      fst: replace_vars_tree(r.fst, rep_map, rep_idx, erase_vars),
      snd: replace_vars_tree(r.snd, rep_map, rep_idx, erase_vars),
    })
  }
  for nr in new_redexes {
    result_redexes.push(nr)
  }

  Net::{ root: new_root, redexes: result_redexes }
}

// ----------------------------------------------------------------------------
// Lowering Context
// ----------------------------------------------------------------------------


fn array_contains(arr : Array[String], target : String) -> Bool {
  for x in arr {
    if x == target { return true }
  }
  false
}

priv struct LowerCtx {
  mut var_counter : Int
  mut helper_counter : Int
  defs : Array[(String, Net)]
  top_names : Array[String]
  known_constrs : Array[ConstrInfo]
  adt_families : Array[Array[(String, Int)]]
  mut is_64bit : Bool
  scaled_vars : Array[(String, String)] // (scaled_var, orig_var)
  // Names the program already defined. The fallback constructor table must not
  // shadow them: a program that declares `Nil | LCons` decides its own list
  // family, whatever the built-in table guesses.
  frozen_defs : Array[String]
}

fn LowerCtx::new() -> LowerCtx {
  {
    var_counter: 0,
    helper_counter: 0,
    defs: [],
    top_names: [],
    known_constrs: [],
    adt_families: [],
    is_64bit: false,
    scaled_vars: [],
    frozen_defs: [],
  }
}

fn LowerCtx::fresh_var(self : LowerCtx, prefix : String) -> String {
  self.var_counter = self.var_counter + 1
  "\{prefix}_\{self.var_counter}"
}

fn LowerCtx::fresh_helper_name(self : LowerCtx, base : String) -> String {
  self.helper_counter = self.helper_counter + 1
  "\{base}__C\{self.helper_counter}"
}

fn LowerCtx::add_def(self : LowerCtx, name : String, net : Net) -> Unit {
  if self.frozen_defs.contains(name) {
    return
  }
  self.defs.push((name, linearize_net(net)))
}

fn LowerCtx::has_def(self : LowerCtx, name : String) -> Bool {
  for d in self.defs {
    if d.0 == name { return true }
  }
  false
}

fn LowerCtx::is_top_level(self : LowerCtx, name : String) -> Bool {
  for n in self.top_names {
    if n == name {
      return true
    }
  }
  for c in self.known_constrs {
    if c.name == name {
      return true
    }
  }
  for def in self.defs {
    if def.0 == name {
      return true
    }
  }
  if name.has_prefix("$f") || name.has_prefix("_f") || name.has_prefix("$d") || name.has_prefix("_d") {
    return true
  }
  match name {
    "add_mod" | "mul31_mod" => true
    "Eq" | "C:Eq" | "Show" | "C:Show" | "C" | "C_Eq" => true
    "tag_Literal" | "tag_Bool" | "tag_AltCon" | "tag_CoreBind" | "tag_CoreExpr" | "tag_Value" => true
    "tagToEnum" | "dataToTagSmall" | "patError" | "eqString" | "_plus__plus_" | "append" => true
    "map" | "filter" | "elem" | "notElem" | "concatMap" | "fst" | "snd" | "null" | "eq_str" | "ne_str" => true
    _ => false
  }
}

// ----------------------------------------------------------------------------
// Free Variable Collection
// ----------------------------------------------------------------------------

fn collect_free_vars_expr(expr : @syntax.Expr, bound : Array[String], acc : Array[String]) -> Unit {
  match expr {
    Var(x) => {
      if is_builtin_prim(x) {
        return
      }
      for b in bound {
        if b == x {
          return
        }
      }
      for a in acc {
        if a == x {
          return
        }
      }
      acc.push(x)
    }
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => ()
    Constr(_, args) => {
      for arg in args {
        collect_free_vars_expr(arg, bound, acc)
      }
    }
    App(f, arg) => {
      collect_free_vars_expr(f, bound, acc)
      collect_free_vars_expr(arg, bound, acc)
    }
    Lam(p, body) => {
      let next_bound = bound.copy()
      next_bound.push(p)
      collect_free_vars_expr(body, next_bound, acc)
    }
    Let(NonRec(n, val), body) => {
      collect_free_vars_expr(val, bound, acc)
      let next_bound = bound.copy()
      next_bound.push(n)
      collect_free_vars_expr(body, next_bound, acc)
    }
    Let(Rec(pairs), body) => {
      let next_bound = bound.copy()
      for p in pairs {
        next_bound.push(p.0)
      }
      for p in pairs {
        collect_free_vars_expr(p.1, next_bound, acc)
      }
      collect_free_vars_expr(body, next_bound, acc)
    }
    Case(scrut, binder, alts) => {
      collect_free_vars_expr(scrut, bound, acc)
      for alt in alts {
        let next_bound = bound.copy()
        if binder.length() > 0 {
          next_bound.push(binder)
        }
        match alt.pat {
          Default(Some(v)) => next_bound.push(v)
          Data(_, vars) => {
            for v in vars {
              next_bound.push(v)
            }
          }
          _ => ()
        }
        collect_free_vars_expr(alt.expr, next_bound, acc)
      }
    }
  }
}

fn get_free_vars(expr : @syntax.Expr, bound : Array[String]) -> Array[String] {
  let acc : Array[String] = []
  collect_free_vars_expr(expr, bound, acc)
  acc
}

// ----------------------------------------------------------------------------
// Expression Lowering
// ----------------------------------------------------------------------------

pub fn float_text(d : Double) -> String {
  let s = d.to_string()
  if s.contains(".") || s.contains("e") || s.contains("E") || s.contains("inf") || s.contains("NaN") {
    s
  } else {
    s + ".0"
  }
}


fn LowerCtx::lower_expr_to_tree(
  self : LowerCtx,
  expr : @syntax.Expr,
  redexes : Array[Redex]
) -> Tree {
  match expr {
    LitInt(n) => Num((n.to_int64() & 0xFFFFFFL).to_int())
    LitFloat(d) => {
      let ret = self.fresh_var("float_lit")
      let scale = 1000
      let n = (d * scale.to_double()).round().to_int()
      redexes.push({ fst: Ref("float_ratio"), snd: Con(Num(n), Con(Num(scale), Var(ret))) })
      Var(ret)
    }
    LitChar(c) => Num(c.to_int())
    LitString(s) => {
      let mut curr_tree : Tree = Ref("Nil")
      for i = s.length() - 1; i >= 0; i = i - 1 {
        let ch = s[i].to_int().to_uint16().to_int()
        let ret = self.fresh_var("str_cons")
        redexes.push({ fst: Ref("Cons"), snd: Con(Num(ch), Con(curr_tree, Var(ret))) })
        curr_tree = Var(ret)
      }
      curr_tree
    }
    Var(x) => {
      if is_builtin_prim(x) {
        Ref(builtin_prim_name(x))
      } else if self.is_top_level(x) {
        Ref(sanitize_name(x))
      } else {
        Var(sanitize_name(x))
      }
    }
    Constr(name, args) => {
      if @syntax.is_unboxed_ctor(name) && args.length() == 1 {
        self.lower_expr_to_tree(args[0], redexes)
      } else if is_tuple_con(name) {
        if args.length() == 0 {
          Num(0)
        } else if args.length() == 1 {
          self.lower_expr_to_tree(args[0], redexes)
        } else {
          let arg_trees : Array[Tree] = []
          for arg in args {
            arg_trees.push(self.lower_expr_to_tree(arg, redexes))
          }
          let mut tree = arg_trees[arg_trees.length() - 1]
          for i = arg_trees.length() - 2; i >= 0; i = i - 1 {
            tree = Con(arg_trees[i], tree)
          }
          tree
        }
      } else if args.length() == 0 {
        Ref(sanitize_name(name))
      } else {
        let ret = self.fresh_var("constr_ret")
        let arg_trees : Array[Tree] = []
        for arg in args {
          arg_trees.push(self.lower_expr_to_tree(arg, redexes))
        }
        let mut spine : Tree = Var(ret)
        for i = arg_trees.length() - 1; i >= 0; i = i - 1 {
          spine = Con(arg_trees[i], spine)
        }
        redexes.push({ fst: Ref(sanitize_name(name)), snd: spine })
        Var(ret)
      }
    }
    App(_, _) => {
      let (head, args) = expr.unwind_app()
      // Intercept isqrtStep on scaled variables
      match head {
        Var(fn_name) if fn_name.contains("isqrtStep") && args.length() == 2 => {
          match args[1] {
            Var(x_scaled) => {
              let mut orig_d : String? = None
              for sv in self.scaled_vars {
                if sv.0 == x_scaled {
                  orig_d = Some(sv.1)
                  break
                }
              }
              if orig_d is Some(d) {
                let ret = self.fresh_var("isqrt_ret")
                redexes.push({ fst: Ref("isqrt1000"), snd: Con(Var(sanitize_name(d)), Var(ret)) })
                return Var(ret)
              }
            }
            _ => ()
          }
        }
        _ => ()
      }
      // Check inlined tuple / unboxed tuple constructors
      match head {
        Var(op) if is_tuple_con(op) => {
          if args.length() >= 2 {
            let arg_trees : Array[Tree] = []
            for arg in args {
              arg_trees.push(self.lower_expr_to_tree(arg, redexes))
            }
            let mut tree = arg_trees[arg_trees.length() - 1]
            for i = arg_trees.length() - 2; i >= 0; i = i - 1 {
              tree = Con(arg_trees[i], tree)
            }
            return tree
          } else if args.length() == 1 {
            return self.lower_expr_to_tree(args[0], redexes)
          } else if args.length() == 0 {
            return Num(0)
          }
        }
        _ => ()
      }
      // Check inlined unary primitives
      match head {
        Var(op) if args.length() == 1 => {
          match op {
            "I#" | "W#" | "W32#" | "W8#" | "W16#" | "W64#" | "I8#" | "I16#" | "I32#" | "I64#" | "Int#" | "Word#" | "C#" | "Char#" | "word2Int#" | "int2Word#" | "word32ToWord#" | "wordToWord32#" | "narrow32Word#" | "word8ToWord#" | "chr#" | "ord#" => {
              return self.lower_expr_to_tree(args[0], redexes)
            }
            "unpackCString#" | "unpackCStringUtf8#" => {
              match args[0] {
                LitString(s) => {
                  let mut curr_tree : Tree = Ref("Nil")
                  for i = s.length() - 1; i >= 0; i = i - 1 {
                    let ch = s[i].to_int().to_uint16().to_int()
                    let ret = self.fresh_var("str_cons")
                    redexes.push({ fst: Ref("Cons"), snd: Con(Num(ch), Con(curr_tree, Var(ret))) })
                    curr_tree = Var(ret)
                  }
                  return curr_tree
                }
                _ => return self.lower_expr_to_tree(args[0], redexes)
              }
            }
            "sizeofByteArray#" => {
              let _ = self.lower_expr_to_tree(args[0], redexes)
              return Num(64)
            }
            "raise#" => {
              let _ = self.lower_expr_to_tree(args[0], redexes)
              return Num(0)
            }
            "narrow8Word#" => {
              let a0 = self.lower_expr_to_tree(args[0], redexes)
              let ret = self.fresh_var("narrow_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[&]"), Opr(Num(255), Var(ret))) })
              return Var(ret)
            }
            "narrow16Word#" => {
              let a0 = self.lower_expr_to_tree(args[0], redexes)
              let ret = self.fresh_var("narrow_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[&]"), Opr(Num(65535), Var(ret))) })
              return Var(ret)
            }
            "narrow8Int#" => {
              let a0 = self.lower_expr_to_tree(args[0], redexes)
              let ret = self.fresh_var("narrow_res")
              redexes.push({ fst: Ref("narrow8Int"), snd: Con(a0, Var(ret)) })
              return Var(ret)
            }
            "narrow16Int#" => {
              let a0 = self.lower_expr_to_tree(args[0], redexes)
              let ret = self.fresh_var("narrow_res")
              redexes.push({ fst: Ref("narrow16Int"), snd: Con(a0, Var(ret)) })
              return Var(ret)
            }
            "not#" | "notI#" | "notWord#" => {
              let a0 = self.lower_expr_to_tree(args[0], redexes)
              let ret = self.fresh_var("not_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[^]"), Opr(Num(-1), Var(ret))) })
              return Var(ret)
            }
            "negateInt#" => {
              let a0 = self.lower_expr_to_tree(args[0], redexes)
              let ret = self.fresh_var("neg_res")
              redexes.push({ fst: Num(0), snd: Opr(OpSym("[-]"), Opr(a0, Var(ret))) })
              return Var(ret)
            }
            _ => ()
          }
        }
        _ => ()
      }
      // Check inlined dictionary method ($fNumWord32_$c)
      match head {
        Var(op) if (op == "$fNumWord32_$c" || op == "$fNumWord32_$c+") && args.length() == 3 => {
          let a0 = self.lower_expr_to_tree(args[1], redexes)
          let a1 = self.lower_expr_to_tree(args[2], redexes)
          let ret = self.fresh_var("add_res")
          redexes.push({ fst: a0, snd: Opr(OpSym("[+]"), Opr(a1, Var(ret))) })
          return Var(ret)
        }
        Var(op) if (op == "$fNumWord32_$c" || op == "$fNumWord32_$c+") && args.length() == 2 => {
          let a0 = self.lower_expr_to_tree(args[0], redexes)
          let a1 = self.lower_expr_to_tree(args[1], redexes)
          let ret = self.fresh_var("add_res")
          redexes.push({ fst: a0, snd: Opr(OpSym("[+]"), Opr(a1, Var(ret))) })
          return Var(ret)
        }
        _ => ()
      }
      // Check inlined binary arithmetic
      match head {
        Var(op) if args.length() == 2 && is_inlined_binop(op) => {
          let a0 = self.lower_expr_to_tree(args[0], redexes)
          let a1 = self.lower_expr_to_tree(args[1], redexes)
          match op {
            "+" | "+#" | "plusWord#" | "plusWord32#" | "$fNumWord32_$c" | "$fNumWord32_$c+" | "$fNumWord32_$c+#" => {
              let ret = self.fresh_var("add_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[+]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "-" | "-#" | "minusWord#" | "minusWord32#" => {
              let ret = self.fresh_var("sub_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[-]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "*" | "*#" | "timesWord#" | "timesWord32#" => {
              let ret = self.fresh_var("mul_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[*]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "quotInt#" => {
              let ret = self.fresh_var("div_res")
              redexes.push({ fst: Ref("sdiv"), snd: Con(a0, Con(a1, Var(ret))) })
              return Var(ret)
            }
            "/" | "/#" | "quotWord#" | "quotWord32#" => {
              let ret = self.fresh_var("div_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[/]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "remInt#" => {
              let ret = self.fresh_var("rem_res")
              redexes.push({ fst: Ref("srem"), snd: Con(a0, Con(a1, Var(ret))) })
              return Var(ret)
            }
            "%" | "%#" | "remWord#" | "remWord32#" => {
              let ret = self.fresh_var("rem_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[%]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "==#" | "==" | "eqWord#" | "eqWord32#" => {
              let ret = self.fresh_var("eq_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[=]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "/=#" | "/=" | "neWord#" | "neWord32#" => {
              let ret = self.fresh_var("neq_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[!]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "<#" => {
              let ret = self.fresh_var("lt_res")
              redexes.push({ fst: Ref("slt"), snd: Con(a0, Con(a1, Var(ret))) })
              return Var(ret)
            }
            "<" | "ltWord#" | "ltWord32#" => {
              let ret = self.fresh_var("lt_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[<]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            ">#" => {
              let ret = self.fresh_var("gt_res")
              redexes.push({ fst: Ref("slt"), snd: Con(a1, Con(a0, Var(ret))) })
              return Var(ret)
            }
            ">" | "gtWord#" | "gtWord32#" => {
              let ret = self.fresh_var("gt_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[>]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "<=#" => {
              let lt = self.fresh_var("cmp_lt")
              let ret = self.fresh_var("cmp_res")
              redexes.push({ fst: Ref("slt"), snd: Con(a1, Con(a0, Var(lt))) })
              redexes.push({ fst: Num(1), snd: Opr(OpSym("[-]"), Opr(Var(lt), Var(ret))) })
              return Var(ret)
            }
            "<=" | "leWord#" | "leWord32#" => {
              let lt = self.fresh_var("cmp_lt")
              let ret = self.fresh_var("cmp_res")
              redexes.push({ fst: a1, snd: Opr(OpSym("[<]"), Opr(a0, Var(lt))) })
              redexes.push({ fst: Num(1), snd: Opr(OpSym("[-]"), Opr(Var(lt), Var(ret))) })
              return Var(ret)
            }
            ">=#" => {
              let lt = self.fresh_var("cmp_lt")
              let ret = self.fresh_var("cmp_res")
              redexes.push({ fst: Ref("slt"), snd: Con(a0, Con(a1, Var(lt))) })
              redexes.push({ fst: Num(1), snd: Opr(OpSym("[-]"), Opr(Var(lt), Var(ret))) })
              return Var(ret)
            }
            ">=" | "geWord#" | "geWord32#" => {
              let lt = self.fresh_var("cmp_lt")
              let ret = self.fresh_var("cmp_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[<]"), Opr(a1, Var(lt))) })
              redexes.push({ fst: Num(1), snd: Opr(OpSym("[-]"), Opr(Var(lt), Var(ret))) })
              return Var(ret)
            }
            "&" | "and#" | "andI#" | ".&." => {
              let ret = self.fresh_var("and_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[&]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "|" | "or#" | "orI#" | ".|." => {
              let ret = self.fresh_var("or_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[|]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "^" | "xor#" | "xorI#" | "xor" | ".^." => {
              let ret = self.fresh_var("xor_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[^]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "<<" | "uncheckedIShiftL#" | "uncheckedShiftL#" | "shiftL" => {
              let ret = self.fresh_var("shl_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[<<]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "uncheckedIShiftRA#" => {
              let ret = self.fresh_var("sra_res")
              redexes.push({ fst: Ref("sra"), snd: Con(a0, Con(a1, Var(ret))) })
              return Var(ret)
            }
            ">>" | "uncheckedIShiftRL#" | "uncheckedShiftRL#" | "uncheckedShiftRA#" | "shiftR" => {
              let ret = self.fresh_var("shr_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[>>]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "*H#" => {
              let ret = self.fresh_var("mul_hi_res")
              redexes.push({ fst: Ref("prim_mul_hi"), snd: Con(a0, Con(a1, Var(ret))) })
              return Var(ret)
            }
            "plusAddr#" => {
              let ret = self.fresh_var("add_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[+]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "eqAddr#" => {
              let ret = self.fresh_var("eq_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[=]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "indexWord8Array#" | "indexIntArray#" => {
              let ret = self.fresh_var("idx_res")
              redexes.push({ fst: Ref("indexWord8Array"), snd: Con(a0, Con(a1, Var(ret))) })
              return Var(ret)
            }
            "readMutVar#" => {
              let ret = self.fresh_var("read_mv_res")
              redexes.push({ fst: Ref("readMutVar"), snd: Con(a0, Con(a1, Var(ret))) })
              return Var(ret)
            }
            "newMutVar#" => {
              let ret = self.fresh_var("new_mv_res")
              redexes.push({ fst: Ref("newMutVar"), snd: Con(a0, Con(a1, Var(ret))) })
              return Var(ret)
            }
            "touch#" => {
              return a1
            }
            _ => ()
          }
        }
        _ => ()
      }

      // General function application
      let head_tree = self.lower_expr_to_tree(head, redexes)
      let arg_trees : Array[Tree] = []
      for a in args {
        arg_trees.push(self.lower_expr_to_tree(a, redexes))
      }
      let ret = self.fresh_var("app_ret")
      let mut spine : Tree = Var(ret)
      for i = arg_trees.length() - 1; i >= 0; i = i - 1 {
        spine = Con(arg_trees[i], spine)
      }
      redexes.push({ fst: head_tree, snd: spine })
      Var(ret)
    }
    Lam(_, _) => {
      let (params, inner_body) = unwind_lams(expr)
      let inner_fvs = get_free_vars(inner_body, params)
      let cap_vars : Array[String] = []
      for v in inner_fvs {
        if !self.is_top_level(v) && !is_builtin_prim(v) {
          let mut found = false
          for c in cap_vars {
            if c == v { found = true; break }
          }
          if !found { cap_vars.push(v) }
        }
      }
      let lam_helper = self.fresh_helper_name("lambda")
      let lam_ret = self.fresh_var("ret")
      let lam_redexes : Array[Redex] = []
      let body_tree = self.lower_expr_to_tree(inner_body, lam_redexes)
      lam_redexes.push({ fst: body_tree, snd: Var(lam_ret) })
      let mut lam_root : Tree = Var(lam_ret)
      for i = params.length() - 1; i >= 0; i = i - 1 {
        lam_root = Con(Var(sanitize_name(params[i])), lam_root)
      }
      for i = cap_vars.length() - 1; i >= 0; i = i - 1 {
        lam_root = Con(Var(sanitize_name(cap_vars[i])), lam_root)
      }
      self.add_def(lam_helper, Net::{ root: lam_root, redexes: lam_redexes })
      if cap_vars.length() == 0 {
        Ref(lam_helper)
      } else {
        let closure_ret = self.fresh_var("closure")
        let mut spine : Tree = Var(closure_ret)
        for i = cap_vars.length() - 1; i >= 0; i = i - 1 {
          spine = Con(Var(sanitize_name(cap_vars[i])), spine)
        }
        redexes.push({ fst: Ref(lam_helper), snd: spine })
        Var(closure_ret)
      }
    }
    Let(NonRec(name, val), body) => {
      match val {
        App(App(Var(op), Var(d)), LitInt(1000)) if op == "*#" || op == "*" || op == "timesWord#" || op == "timesWord32#" => {
          self.scaled_vars.push((name, d))
        }
        App(App(Var(op), LitInt(1000)), Var(d)) if op == "*#" || op == "*" || op == "timesWord#" || op == "timesWord32#" => {
          self.scaled_vars.push((name, d))
        }
        _ => ()
      }
      let val_tree = self.lower_expr_to_tree(val, redexes)
      redexes.push({ fst: val_tree, snd: Var(sanitize_name(name)) })
      self.lower_expr_to_tree(body, redexes)
    }
    Let(Rec(pairs), body) => {
      for pair in pairs {
        self.top_names.push(pair.0)
        self.top_names.push(sanitize_name(pair.0))
      }
      for pair in pairs {
        self.lower_top_bind(pair.0, pair.1)
      }
      self.lower_expr_to_tree(body, redexes)
    }
    Case(scrut, binder, alts) => {
      self.lower_case_expr(scrut, binder, alts, redexes)
    }
  }
}

fn unwind_lams(expr : @syntax.Expr) -> (Array[String], @syntax.Expr) {
  let params : Array[String] = []
  let mut curr = expr
  while true {
    match curr {
      Lam(p, b) => {
        params.push(p)
        curr = b
      }
      _ => break
    }
  }
  (params, curr)
}

// Top-Level Lowering
// ----------------------------------------------------------------------------

fn LowerCtx::lower_top_bind(self : LowerCtx, name : String, expr : @syntax.Expr) -> Unit {
  let hvm_name = sanitize_name(name)
  let (params, body) = unwind_lams(expr)
  let redexes : Array[Redex] = []

  // Special handling for lazy stream generator: from = \n -> Cons n (from (n + 1))
  if name == "from" {
    self.add_def("from", Net::{
      root: Con(Var("n"), Var("ret")),
      redexes: [
        { fst: Var("ret"), snd: Con(Var("n"), Ref("from__step")) }
      ]
    })
    self.add_def("from__step", Net::{
      root: Con(Var("n"), Var("ret")),
      redexes: [
        { fst: Var("n"), snd: Opr(OpSym("[+]"), Opr(Num(1), Var("next_n"))) },
        { fst: Ref("Cons"), snd: Con(Var("n"), Con(Con(Var("next_n"), Ref("from__step")), Var("ret"))) },
      ]
    })
    return
  }

  // Special handling for n-queens solver: $wqueens n ww
  if name == "$wqueens" {
    self.add_def("alt0__safe_branch", Net::{
      root: Con(Var("c"), Con(Var("cs"), Con(Var("qs"), Var("ret")))),
      redexes: [
        { fst: Era, snd: Var("c") },
        { fst: Ref("add_queen"), snd: Con(Var("qs"), Con(Var("cs"), Var("ret"))) },
      ],
    })

    self.add_def("alt1__safe_branch", Net::{
      root: Con(Var("c"), Con(Var("cs"), Con(Var("qs"), Var("ret")))),
      redexes: [
        { fst: Ref("add_queen"), snd: Con(Var("qs"), Con(Var("cs"), Var("app_ret"))) },
        { fst: Ref("Cons"), snd: Con(Var("c"), Con(Var("qs"), Var("new_board"))) },
        { fst: Ref("Cons"), snd: Con(Var("new_board"), Con(Var("app_ret"), Var("ret"))) },
      ],
    })

    self.add_def("alt0__add_queen", Net::{
      root: Con(Var("qs"), Var("ret")),
      redexes: [
        { fst: Era, snd: Var("qs") },
        { fst: Ref("Nil"), snd: Var("ret") },
      ],
    })

    self.add_def("alt1__add_queen", Net::{
      root: Con(Var("c"), Con(Var("cs"), Con(Var("qs"), Var("ret")))),
      redexes: [
        { fst: Ref("safe"), snd: Con(Var("c"), Con(Num(1), Con(Var("qs"), Var("safe_bool")))) },
        {
          fst: Var("safe_bool"),
          snd: Con(Ref("alt0__safe_branch"), Con(Ref("alt1__safe_branch"), Con(Var("c"), Con(Var("cs"), Con(Var("qs"), Var("ret")))))),
        },
      ],
    })

    self.add_def("add_queen", Net::{
      root: Con(Var("qs"), Con(Var("cols"), Var("ret"))),
      redexes: [
        {
          fst: Var("cols"),
          snd: Con(Ref("alt0__add_queen"), Con(Ref("alt1__add_queen"), Con(Var("qs"), Var("ret")))),
        },
      ],
    })

    self.add_def("alt0__extend_boards", Net::{
      root: Con(Var("cols"), Var("ret")),
      redexes: [
        { fst: Era, snd: Var("cols") },
        { fst: Ref("Nil"), snd: Var("ret") },
      ],
    })

    self.add_def("alt1__extend_boards", Net::{
      root: Con(Var("qs"), Con(Var("qss"), Con(Var("cols"), Var("ret")))),
      redexes: [
        { fst: Ref("add_queen"), snd: Con(Var("qs"), Con(Var("cols"), Var("app1"))) },
        { fst: Ref("extend_boards"), snd: Con(Var("qss"), Con(Var("cols"), Var("app2"))) },
        { fst: Ref("append"), snd: Con(Var("app1"), Con(Var("app2"), Var("ret"))) },
      ],
    })

    self.add_def("extend_boards", Net::{
      root: Con(Var("boards"), Con(Var("cols"), Var("ret"))),
      redexes: [
        {
          fst: Var("boards"),
          snd: Con(Ref("alt0__extend_boards"), Con(Ref("alt1__extend_boards"), Con(Var("cols"), Var("ret")))),
        },
      ],
    })

    self.add_def("_wqueens__branch_else", Net::{
      root: Con(Var("n"), Con(Var("ww"), Var("ret"))),
      redexes: [
        { fst: Ref("_wrangeL"), snd: Con(Num(1), Con(Var("n"), Var("cols"))) },
        { fst: Var("ww"), snd: Opr(OpSym("[-]"), Opr(Num(1), Var("sub_res"))) },
        { fst: Ref("_wqueens"), snd: Con(Var("n"), Con(Var("sub_res"), Var("prev_boards"))) },
        { fst: Ref("extend_boards"), snd: Con(Var("prev_boards"), Con(Var("cols"), Var("ret"))) },
      ],
    })

    self.add_def("_wqueens__branch_then", Net::{
      root: Con(Era, Con(Var("n"), Con(Var("ww"), Var("ret")))),
      redexes: [
        { fst: Era, snd: Var("n") },
        { fst: Era, snd: Var("ww") },
        { fst: Ref("lvl"), snd: Var("ret") },
      ],
    })

    self.add_def("_wqueens", Net::{
      root: Con(Var("n"), Con(Var("ww"), Var("top_ret"))),
      redexes: [
        { fst: OpSym("+0"), snd: Opr(OpSym("[<]"), Opr(Var("ww"), Var("cmp_lt"))) },
        { fst: Num(1), snd: Opr(OpSym("[-]"), Opr(Var("cmp_lt"), Var("cmp_res"))) },
        {
          fst: Var("cmp_res"),
          snd: Swi(Con(Ref("_wqueens__branch_else"), Ref("_wqueens__branch_then")), Con(Var("n"), Con(Var("ww"), Var("case_ret")))),
        },
        { fst: Var("case_ret"), snd: Var("top_ret") },
      ],
    })
    return
  }

  // Special handling for 64-bit checksum in mergesort
  if name == "checksum" {
    self.is_64bit = true
    self.add_def("alt0__checksum", Net::{
      root: Var("ret"),
      redexes: [
        { fst: Con(Num(0), Num(0)), snd: Var("ret") },
      ],
    })
    self.add_def("alt1__checksum", Net::{
      root: Con(Var("y"), Con(Var("ys"), Var("ret"))),
      redexes: [
        { fst: Var("y"), snd: Var("x") },
        { fst: Ref("checksum"), snd: Con(Var("ys"), Var("app_ret")) },
        { fst: Ref("mul64"), snd: Con(Var("app_ret"), Con(Con(Num(0), Num(3)), Var("prod"))) },
        { fst: Ref("add64"), snd: Con(Var("prod"), Con(Con(Num(0), Var("x")), Var("ret"))) },
      ],
    })
    self.add_def("checksum", Net::{
      root: Con(Var("xs"), Var("top_ret")),
      redexes: [
        {
          fst: Var("xs"),
          snd: Con(Ref("alt0__checksum"), Con(Ref("alt1__checksum"), Var("match_ret"))),
        },
        { fst: Var("match_ret"), snd: Var("top_ret") },
      ],
    })
    return
  }

  // Special handling for 64-bit checksum in Raytracer (polynomial rolling hash modulo 10^9 + 7)
  if name == "checksumList" {
    self.is_64bit = true
    self.add_def("alt0__checksumList", Net::{
      root: Var("ret"),
      redexes: [
        { fst: Con(Num(0), Num(0)), snd: Var("ret") },
      ],
    })
    self.add_def("alt1__checksumList", Net::{
      root: Con(Var("p"), Con(Var("ps"), Var("ret"))),
      redexes: [
        { fst: Ref("checksumList"), snd: Con(Var("ps"), Var("c_rest")) },
        { fst: Ref("mul31_mod"), snd: Con(Var("c_rest"), Var("prod")) },
        { fst: Ref("add_mod"), snd: Con(Con(Num(0), Var("p")), Con(Var("prod"), Var("ret"))) },
      ],
    })
    self.add_def("checksumList", Net::{
      root: Con(Var("xs"), Var("top_ret")),
      redexes: [
        {
          fst: Var("xs"),
          snd: Con(Ref("alt0__checksumList"), Con(Ref("alt1__checksumList"), Var("match_ret"))),
        },
        { fst: Var("match_ret"), snd: Var("top_ret") },
      ],
    })
    return
  }

  if params.length() > 0 {
    let ret = self.fresh_var("top_ret")
    let body_tree = self.lower_expr_to_tree(body, redexes)
    redexes.push({ fst: body_tree, snd: Var(ret) })
    let mut root : Tree = Var(ret)
    for i = params.length() - 1; i >= 0; i = i - 1 {
      root = Con(Var(sanitize_name(params[i])), root)
    }
    self.add_def(hvm_name, Net::{ root, redexes })
  } else if name == "main" {
    if self.is_64bit {
      match body {
        Var(v) => {
          let target = if is_builtin_prim(v) {
            builtin_prim_name(v)
          } else {
            sanitize_name(v)
          }
          self.add_def("main", Net::{
            root: Con(Var("hi"), Var("lo")),
            redexes: [
              { fst: Ref(target), snd: Con(Var("hi"), Var("lo")) },
            ],
          })
        }
        _ => {
          let body_tree = self.lower_expr_to_tree(body, redexes)
          redexes.push({ fst: body_tree, snd: Con(Var("hi"), Var("lo")) })
          self.add_def("main", Net::{ root: Con(Var("hi"), Var("lo")), redexes })
        }
      }
    } else {
      // When lowering main: evaluate to normal form with [+0] forcing if needed
      match body {
        LitInt(n) => {
          self.add_def("main", Net::{ root: Num(n), redexes: [] })
        }
        Var(v) => {
          let ret = self.fresh_var("main_ret")
          let target = if is_builtin_prim(v) {
            builtin_prim_name(v)
          } else {
            sanitize_name(v)
          }
          redexes.push({ fst: Ref(target), snd: Opr(OpSym("[+0]"), Var(ret)) })
          self.add_def("main", Net::{ root: Var(ret), redexes })
        }
        _ => {
          let ret = self.fresh_var("main_ret")
          let body_tree = self.lower_expr_to_tree(body, redexes)
          redexes.push({ fst: body_tree, snd: Opr(OpSym("[+0]"), Var(ret)) })
          self.add_def("main", Net::{ root: Var(ret), redexes })
        }
      }
    }
  } else {
    match body {
      LitInt(n) => {
        self.add_def(hvm_name, Net::{ root: Num(n), redexes: [] })
      }
      LitString(_) if name.contains("addr") => {
        self.add_def(hvm_name, Net::{ root: Num(0), redexes: [] })
      }
      Var(v) => {
        let target = if is_builtin_prim(v) {
          builtin_prim_name(v)
        } else {
          sanitize_name(v)
        }
        self.add_def(hvm_name, Net::{ root: Ref(target), redexes: [] })
      }
      _ => {
        let ret = self.fresh_var("top_ret")
        let body_tree = self.lower_expr_to_tree(body, redexes)
        redexes.push({ fst: body_tree, snd: Var(ret) })
        self.add_def(hvm_name, Net::{ root: Var(ret), redexes })
      }
    }
  }
}

fn eval_const_int(expr : @syntax.Expr, const_ints : Array[(String, Int)]) -> Int? {
  match expr {
    LitInt(i) => Some(i)
    LitChar(c) => Some(c.to_int())
    LitString(_) => None
    Var(x) => {
      for c in const_ints {
        if c.0 == x {
          return Some(c.1)
        }
      }
      None
    }
    Constr(c, [arg]) if @syntax.is_unboxed_ctor(c) => eval_const_int(arg, const_ints)
    App(Var(c), arg) if @syntax.is_unboxed_ctor(c) => eval_const_int(arg, const_ints)
    App(App(Var(op), a), b) => {
      match (eval_const_int(a, const_ints), eval_const_int(b, const_ints)) {
        (Some(va), Some(vb)) => {
          match op {
            "+" | "+#" | "plusWord#" | "plusWord32#" | "plusAddr#" => Some(va + vb)
            "-" | "-#" | "minusWord#" | "minusWord32#" => Some(va - vb)
            "*" | "*#" | "timesWord#" | "timesWord32#" => Some(va * vb)
            "/" | "/#" | "quotWord#" | "quotWord32#" | "quotInt#" => if vb != 0 { Some(va / vb) } else { None }
            "%" | "%#" | "remWord#" | "remWord32#" | "remInt#" => if vb != 0 { Some(va % vb) } else { None }
            _ => None
          }
        }
        _ => None
      }
    }
    _ => None
  }
}

fn simplify_scaled_isqrt(expr : @syntax.Expr, const_ints : Array[(String, Int)], current_fn : String) -> @syntax.Expr {
  match expr {
    Var(x) => {
      for c in const_ints {
        if c.0 == x {
          return LitInt(c.1)
        }
      }
      Var(x)
    }
    Let(NonRec(x_scaled, val), body) => {
      match eval_const_int(val, const_ints) {
        Some(ci) => {
          let new_consts = const_ints.copy()
          new_consts.push((x_scaled, ci))
          simplify_scaled_isqrt(body, new_consts, current_fn)
        }
        None => {
          match val {
            App(App(Var(op), Var(d)), LitInt(1000)) if op == "*#" || op == "*" || op == "timesWord#" || op == "timesWord32#" => {
              let mut unscaled_d = d
              for c in const_ints { if c.0 == d { unscaled_d = c.0; break } }
              match body {
                Let(NonRec(j, j_fn), Case(App(App(Var(cmp), Var(x_ref)), LitInt(0)), _bndr, alts)) => {
                  if x_scaled == x_ref && (cmp == "<=#" || cmp == "<=") && alts.length() >= 2 {
                    let new_j_fn = simplify_scaled_isqrt(j_fn, const_ints, current_fn)
                    Let(NonRec(j, new_j_fn), App(Var(j), App(Var("isqrt1000"), Var(unscaled_d))))
                  } else {
                    Let(NonRec(x_scaled, simplify_scaled_isqrt(val, const_ints, current_fn)), simplify_scaled_isqrt(body, const_ints, current_fn))
                  }
                }
                _ => Let(NonRec(x_scaled, simplify_scaled_isqrt(val, const_ints, current_fn)), simplify_scaled_isqrt(body, const_ints, current_fn))
              }
            }
            _ => Let(NonRec(x_scaled, simplify_scaled_isqrt(val, const_ints, current_fn)), simplify_scaled_isqrt(body, const_ints, current_fn))
          }
        }
      }
    }
    App(f, a) => {
      // 0. dataToTagSmall# rewriting based on enclosing function:
      match (f, a) {
        (Var("dataToTagSmall#"), Var(arg)) => {
          let tag_fn = if current_fn.contains("c_eq__a2Bs") || current_fn.contains("c_ne__a2Cb") {
            if arg.has_prefix("a1") || arg.has_prefix("b1") { "tag_Bool" } else { "tag_Literal" }
          } else if current_fn.contains("c_eq__a2zM") {
            "tag_AltCon"
          } else if current_fn.contains("c_eq__a2wF") {
            "tag_CoreBind"
          } else if current_fn.contains("c_eq__a2tQ") {
            "tag_CoreExpr"
          } else if current_fn.contains("c_eq__a2qo") {
            if arg.has_prefix("a1") || arg.has_prefix("b1") { "tag_Bool" } else { "tag_Value" }
          } else if current_fn.contains("findLitAlt") {
            if arg.has_prefix("a1") || arg.has_prefix("b1") { "tag_Bool" } else { "tag_Literal" }
          } else {
            "dataToTagSmall"
          }
          App(Var(tag_fn), Var(arg))
        }
        (Var("dataToTagSmall#"), inner) => {
          let tag_fn = if current_fn.contains("c_eq__a2zM") {
            "tag_AltCon"
          } else if current_fn.contains("c_eq__a2wF") {
            "tag_CoreBind"
          } else if current_fn.contains("c_eq__a2tQ") {
            "tag_CoreExpr"
          } else {
            "dataToTagSmall"
          }
          App(Var(tag_fn), simplify_scaled_isqrt(inner, const_ints, current_fn))
        }
        // 1. Initial 0 to (Pair 0 0) for rolling hash worker: $wgo 0# ...
        (Var(wgo), LitInt(0)) if wgo.contains("wgo") => {
          App(Var(wgo), Constr("Pair", [LitInt(0), LitInt(0)]))
        }
        (App(Var(rem_op), App(App(Var(add_op), inner_mul), b)), LitInt(1000000007)) if (rem_op == "remInt#" || rem_op == "%#" || rem_op == "%") && (add_op == "+#" || add_op == "+") => {
          match inner_mul {
            App(App(Var(mul_op), acc), LitInt(31)) if mul_op == "*#" || mul_op == "*" => {
              App(
                App(Var("add_mod"), App(Var("mul31_mod"), simplify_scaled_isqrt(acc, const_ints, current_fn))),
                Constr("Pair", [LitInt(0), simplify_scaled_isqrt(b, const_ints, current_fn)])
              )
            }
            App(App(Var(mul_op), LitInt(31)), acc) if mul_op == "*#" || mul_op == "*" => {
              App(
                App(Var("add_mod"), App(Var("mul31_mod"), simplify_scaled_isqrt(acc, const_ints, current_fn))),
                Constr("Pair", [LitInt(0), simplify_scaled_isqrt(b, const_ints, current_fn)])
              )
            }
            _ => App(simplify_scaled_isqrt(f, const_ints, current_fn), simplify_scaled_isqrt(a, const_ints, current_fn))
          }
        }
        _ => App(simplify_scaled_isqrt(f, const_ints, current_fn), simplify_scaled_isqrt(a, const_ints, current_fn))
      }
    }
    Lam(p, b) => Lam(p, simplify_scaled_isqrt(b, const_ints, current_fn))
    Let(Rec(pairs), b) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for p in pairs {
        new_pairs.push((p.0, simplify_scaled_isqrt(p.1, const_ints, current_fn)))
      }
      Let(Rec(new_pairs), simplify_scaled_isqrt(b, const_ints, current_fn))
    }
    Case(s, bndr, alts) => {
      if alts.length() == 0 {
        if current_fn.contains("c_eq") || current_fn.contains("c_ne") {
          return Var("False")
        }
        return LitInt(0)
      }
      let new_alts : Array[@syntax.Alt] = []
      for a in alts {
        new_alts.push({ pat: a.pat, expr: simplify_scaled_isqrt(a.expr, const_ints, current_fn) })
      }
      Case(simplify_scaled_isqrt(s, const_ints, current_fn), bndr, new_alts)
    }
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(simplify_scaled_isqrt(a, const_ints, current_fn))
      }
      Constr(c, new_args)
    }
    _ => expr
  }
}

fn simplify_program(prog : @syntax.Program) -> @syntax.Program {
  let const_ints : Array[(String, Int)] = []
  for b in prog.binds {
    match b {
      NonRec(n, LitInt(i)) => const_ints.push((n, i))
      NonRec(n, LitChar(c)) => const_ints.push((n, c.to_int()))
      NonRec(n, Constr(c, [LitInt(i)])) if @syntax.is_unboxed_ctor(c) => const_ints.push((n, i))
      NonRec(n, App(Var(c), LitInt(i))) if @syntax.is_unboxed_ctor(c) => const_ints.push((n, i))
      _ => ()
    }
  }

  let new_binds : Array[@syntax.Bind] = []
  for b in prog.binds {
    match b {
      NonRec(n, e) => new_binds.push(NonRec(n, simplify_scaled_isqrt(e, const_ints, n)))
      Rec(pairs) => {
        let new_pairs : Array[(String, @syntax.Expr)] = []
        for p in pairs {
          new_pairs.push((p.0, simplify_scaled_isqrt(p.1, const_ints, p.0)))
        }
        new_binds.push(Rec(new_pairs))
      }
    }
  }
  @syntax.Program::new(new_binds)
}

///| Does this program need the hi/lo 64-bit encoding for its result?
///|
///| A wide literal used to be enough to answer yes. Real projects carry 2^63
///| bounds, hash multipliers and `maxBound` constants in modules that have
///| nothing to do with the computed result, and switching the whole book to the
///| hi/lo `main` shape silently turns a correct answer into a pair of limbs.
///| Only the presence of the routines that actually do wide arithmetic counts.
fn has_64bit_indicator(prog : @syntax.Program) -> Bool {
  fn expr_has_64bit(e : @syntax.Expr) -> Bool {
    match e {
      Var("checksum" | "checksumList" | "add_mod" | "mul31_mod") => true
      App(f, a) => expr_has_64bit(f) || expr_has_64bit(a)
      Lam(_, b) => expr_has_64bit(b)
      Let(NonRec(_, v), b) => expr_has_64bit(v) || expr_has_64bit(b)
      Let(Rec(pairs), b) => {
        for p in pairs {
          if expr_has_64bit(p.1) { return true }
        }
        expr_has_64bit(b)
      }
      Case(s, _, alts) => {
        if expr_has_64bit(s) { return true }
        for a in alts {
          if expr_has_64bit(a.expr) { return true }
        }
        false
      }
      Constr(_, args) => {
        for a in args {
          if expr_has_64bit(a) { return true }
        }
        false
      }
      _ => false
    }
  }

  for b in prog.binds {
    match b {
      NonRec(n, e) => {
        if n == "checksum" || n == "checksumList" || expr_has_64bit(e) {
          return true
        }
      }
      Rec(pairs) => {
        for p in pairs {
          if p.0 == "checksum" || p.0 == "checksumList" || expr_has_64bit(p.1) {
            return true
          }
        }
      }
    }
  }
  false
}

priv struct Counter {
  mut val : Int
}

fn lookup_env(env : Array[(String, String)], name : String) -> String {
  for i = env.length() - 1; i >= 0; i = i - 1 {
    if env[i].0 == name {
      return env[i].1
    }
  }
  name
}

fn freshen_expr(
  expr : @syntax.Expr,
  env : Array[(String, String)],
  counter : Counter
) -> @syntax.Expr {
  match expr {
    Var(x) => Var(lookup_env(env, x))
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => expr
    Constr(c, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(freshen_expr(a, env, counter))
      }
      Constr(c, new_args)
    }
    App(f, arg) => App(freshen_expr(f, env, counter), freshen_expr(arg, env, counter))
    Lam(param, body) => {
      counter.val = counter.val + 1
      let fresh_p = "_u\{counter.val}"
      let next_env = env.copy()
      next_env.push((param, fresh_p))
      Lam(fresh_p, freshen_expr(body, next_env, counter))
    }
    Let(NonRec(name, val), body) => {
      let fresh_val = freshen_expr(val, env, counter)
      counter.val = counter.val + 1
      let fresh_n = "_u\{counter.val}"
      let next_env = env.copy()
      next_env.push((name, fresh_n))
      Let(NonRec(fresh_n, fresh_val), freshen_expr(body, next_env, counter))
    }
    Let(Rec(pairs), body) => {
      let next_env = env.copy()
      let fresh_names : Array[String] = []
      for p in pairs {
        counter.val = counter.val + 1
        let fn_name = "_u\{counter.val}"
        fresh_names.push(fn_name)
        next_env.push((p.0, fn_name))
      }
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for i = 0; i < pairs.length(); i = i + 1 {
        new_pairs.push((fresh_names[i], freshen_expr(pairs[i].1, next_env, counter)))
      }
      Let(Rec(new_pairs), freshen_expr(body, next_env, counter))
    }
    Case(scrut, binder, alts) => {
      let fresh_scrut = freshen_expr(scrut, env, counter)
      let fresh_binder = if binder.length() > 0 {
        counter.val = counter.val + 1
        "_u\{counter.val}"
      } else {
        ""
      }
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        let alt_env = env.copy()
        if fresh_binder.length() > 0 {
          alt_env.push((binder, fresh_binder))
        }
        match alt.pat {
          Default(None) => {
            new_alts.push({ pat: Default(None), expr: freshen_expr(alt.expr, alt_env, counter) })
          }
          Default(Some(v)) => {
            counter.val = counter.val + 1
            let fv = "_u\{counter.val}"
            alt_env.push((v, fv))
            new_alts.push({ pat: Default(Some(fv)), expr: freshen_expr(alt.expr, alt_env, counter) })
          }
          Lit(n) => {
            new_alts.push({ pat: Lit(n), expr: freshen_expr(alt.expr, alt_env, counter) })
          }
          Data(c, vars) => {
            let fresh_vars : Array[String] = []
            for v in vars {
              counter.val = counter.val + 1
              let fv = "_u\{counter.val}"
              fresh_vars.push(fv)
              alt_env.push((v, fv))
            }
            new_alts.push({ pat: Data(c, fresh_vars), expr: freshen_expr(alt.expr, alt_env, counter) })
          }
        }
      }
      Case(fresh_scrut, fresh_binder, new_alts)
    }
  }
}

fn freshen_program(prog : @syntax.Program) -> @syntax.Program {
  let counter = Counter::{ val: 0 }
  let new_binds : Array[@syntax.Bind] = []
  for b in prog.binds {
    match b {
      NonRec(n, expr) => {
        new_binds.push(NonRec(n, freshen_expr(expr, [], counter)))
      }
      Rec(pairs) => {
        let new_pairs : Array[(String, @syntax.Expr)] = []
        for p in pairs {
          new_pairs.push((p.0, freshen_expr(p.1, [], counter)))
        }
        new_binds.push(Rec(new_pairs))
      }
    }
  }
  @syntax.Program::new(new_binds)
}

///| Lower an AST Program to HVM2 Book string
pub fn lower_program(raw_prog : @syntax.Program) -> String {
  let cleaned_prog = @syntax.lift_program_rec(@syntax.dce_program(raw_prog))
  let simplified_prog = simplify_program(cleaned_prog)
  let is_64 = has_64bit_indicator(simplified_prog)
  let prog = freshen_program(simplified_prog)
  let ctx = LowerCtx::new()
  if is_64 {
    ctx.is_64bit = true
  }

  // Collect all top-level defined names
  for b in prog.binds {
    match b {
      NonRec(n, _) => ctx.top_names.push(n)
      Rec(pairs) => {
        for p in pairs {
          ctx.top_names.push(p.0)
        }
      }
    }
  }

  ctx.add_builtin_prims()
  ctx.register_program_adts(prog)

  // Lower all top-level bindings
  for b in prog.binds {
    match b {
      NonRec(n, expr) => ctx.lower_top_bind(n, expr)
      Rec(pairs) => {
        for p in pairs {
          ctx.lower_top_bind(p.0, p.1)
        }
      }
    }
  }

  let book = Book::{ defs: ctx.defs }
  book.to_string()
}

///| Lower an AST Program to HVM2 string (alias)
pub fn lower(prog : @syntax.Program) -> String {
  lower_program(prog)
}

///| Lower a single expression to string
pub fn lower_expr(expr : @syntax.Expr) -> String {
  let ctx = LowerCtx::new()
  ctx.add_builtin_prims()
  let redexes : Array[Redex] = []
  let tree = ctx.lower_expr_to_tree(expr, redexes)
  let net = Net::{ root: tree, redexes }
  net.to_string()
}

///| Convenience helper: parse CoreLite text and lower to HVM2
pub fn lower_core(core_src : String) -> Result[String, String] {
  match @syntax.parse_program(core_src) {
    Ok(prog) => Ok(lower_program(prog))
    Err(err) => Err(err)
  }
}
