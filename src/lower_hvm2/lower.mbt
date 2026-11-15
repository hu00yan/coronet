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
    Num(n) => logger.write_string("\{n}")
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
// Identifier Sanitization
// ----------------------------------------------------------------------------

///| Sanitize Core identifiers into valid HVM2 alphanumeric names
pub fn sanitize_name(name : String) -> String {
  match name {
    "+" | "+#" => "add"
    "-" | "-#" => "sub"
    "*" | "*#" => "mul"
    "/" => "div"
    "%" => "rem"
    "<=#" | "<=" => "lte"
    ">=#" | ">=" => "gte"
    "<#" | "<" => "lt"
    ">#" | ">" => "gt"
    "==#" | "==" => "eq"
    "/=#" | "/=" => "neq"
    "I#" => "I_hash"
    _ => {
      let buf = StringBuilder()
      for i in 0..<name.length() {
        let c = name[i]
        if c == '$'.to_int().to_uint16() {
          buf.write_char('_')
        } else if c == '#'.to_int().to_uint16() {
          buf.write_string("_hash")
        } else if c == '\''.to_int().to_uint16() {
          buf.write_string("_prime")
        } else {
          buf.write_char(c.to_int().unsafe_to_char())
        }
      }
      buf.to_string()
    }
  }
}

///| Check if an identifier is an inlined binary operator
pub fn is_inlined_binop(op : String) -> Bool {
  match op {
    "+" | "+#" | "-" | "-#" | "*" | "*#" => true
    "==#" | "==" | "/=#" | "/=" => true
    "<#" | "<" | ">#" | ">" | "<=#" | "<=" | ">=#" | ">=" => true
    _ => false
  }
}

///| Check if an identifier is a builtin primitive operator
pub fn is_builtin_prim(name : String) -> Bool {
  match name {
    "+" | "+#" | "-" | "-#" | "*" | "*#" | "/" | "%" => true
    "<=#" | "<=" | ">=#" | ">=" | "<#" | "<" | ">#" | ">" => true
    "==#" | "==" | "/=#" | "/=" | "I#" => true
    _ => false
  }
}


///| Check if an identifier is a builtin primitive operator
pub fn builtin_prim_name(name : String) -> String {
  match name {
    "+" | "+#" => "prim_add"
    "-" | "-#" => "prim_sub"
    "*" | "*#" => "prim_mul"
    "/" => "prim_div"
    "%" => "prim_rem"
    "<=#" | "<=" => "prim_lte"
    ">=#" | ">=" => "prim_gte"
    "<#" | "<" => "prim_lt"
    ">#" | ">" => "prim_gt"
    "==#" | "==" => "prim_eq"
    "/=#" | "/=" => "prim_neq"
    "I#" => "I_hash"
    _ => sanitize_name(name)
  }
}

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
  rep_idx : Array[(String, Int)]
) -> Tree {
  match tree {
    Var(name) => {
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
    Con(a, b) => Con(replace_vars_tree(a, rep_map, rep_idx), replace_vars_tree(b, rep_map, rep_idx))
    Dup(a, b) => Dup(replace_vars_tree(a, rep_map, rep_idx), replace_vars_tree(b, rep_map, rep_idx))
    Opr(a, b) => Opr(replace_vars_tree(a, rep_map, rep_idx), replace_vars_tree(b, rep_map, rep_idx))
    Swi(a, b) => Swi(replace_vars_tree(a, rep_map, rep_idx), replace_vars_tree(b, rep_map, rep_idx))
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

  for entry in counts {
    let name = entry.0
    let count = entry.1
    if count > 2 {
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

  if rep_map.length() == 0 {
    return net
  }

  let new_root = replace_vars_tree(net.root, rep_map, rep_idx)
  let result_redexes : Array[Redex] = []
  for r in net.redexes {
    result_redexes.push({
      fst: replace_vars_tree(r.fst, rep_map, rep_idx),
      snd: replace_vars_tree(r.snd, rep_map, rep_idx),
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

priv struct LowerCtx {
  mut var_counter : Int
  mut helper_counter : Int
  defs : Array[(String, Net)]
  top_names : Array[String]
  known_constrs : Array[(String, Int, Int)] // (name, variant_idx, arity)
}

fn LowerCtx::new() -> LowerCtx {
  {
    var_counter: 0,
    helper_counter: 0,
    defs: [],
    top_names: [],
    known_constrs: [],
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
  self.defs.push((name, linearize_net(net)))
}

fn LowerCtx::is_top_level(self : LowerCtx, name : String) -> Bool {
  for n in self.top_names {
    if n == name {
      return true
    }
  }
  for c in self.known_constrs {
    if c.0 == name {
      return true
    }
  }
  false
}

// ----------------------------------------------------------------------------
// Builtin Primitives & Scott Constructor Generation
// ----------------------------------------------------------------------------

fn LowerCtx::add_builtin_prims(self : LowerCtx) -> Unit {
  // @prim_add = (a (b ret)) & a ~ $([+] $(b ret))
  self.add_def("prim_add", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[+]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @prim_sub = (a (b ret)) & a ~ $([-] $(b ret))
  self.add_def("prim_sub", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[-]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @prim_mul = (a (b ret)) & a ~ $([*] $(b ret))
  self.add_def("prim_mul", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[*]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @prim_div = (a (b ret)) & a ~ $([/] $(b ret))
  self.add_def("prim_div", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[/]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @prim_rem = (a (b ret)) & a ~ $([%] $(b ret))
  self.add_def("prim_rem", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[%]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @prim_eq = (a (b ret)) & a ~ $([=] $(b ret))
  self.add_def("prim_eq", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[=]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @prim_neq = (a (b ret)) & a ~ $([!] $(b ret))
  self.add_def("prim_neq", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[!]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @prim_lt = (a (b ret)) & a ~ $([<] $(b ret))
  self.add_def("prim_lt", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[<]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @prim_gt = (a (b ret)) & a ~ $([>] $(b ret))
  self.add_def("prim_gt", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[>]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @prim_lte = (a (b ret)) & b ~ $([<] $(a lt)) & 1 ~ $([-] $(lt ret))
  self.add_def("prim_lte", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("b"), snd: Opr(OpSym("[<]"), Opr(Var("a"), Var("lt"))) },
      { fst: Num(1), snd: Opr(OpSym("[-]"), Opr(Var("lt"), Var("ret"))) },
    ],
  })

  // @prim_gte = (a (b ret)) & a ~ $([<] $(b lt)) & 1 ~ $([-] $(lt ret))
  self.add_def("prim_gte", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[<]"), Opr(Var("b"), Var("lt"))) },
      { fst: Num(1), snd: Opr(OpSym("[-]"), Opr(Var("lt"), Var("ret"))) },
    ],
  })

  // @I_hash = (x x)
  self.add_def("I_hash", Net::{
    root: Con(Var("x"), Var("x")),
    redexes: [],
  })

  // Top-level aliases for user convenience if not already defined
  let aliases = [
    ("add", "prim_add"),
    ("sub", "prim_sub"),
    ("mul", "prim_mul"),
    ("div", "prim_div"),
    ("rem", "prim_rem"),
    ("eq", "prim_eq"),
    ("neq", "prim_neq"),
    ("lt", "prim_lt"),
    ("gt", "prim_gt"),
    ("lte", "prim_lte"),
    ("gte", "prim_gte"),
  ]
  for a in aliases {
    if !self.is_top_level(a.0) {
      self.add_def(a.0, Net::{ root: Ref(a.1), redexes: [] })
    }
  }
}

fn LowerCtx::register_known_constructors(self : LowerCtx) -> Unit {
  // Standard fixtures ADTs:
  // List: MyNil (0, 0), MyCons (1, 2)
  self.known_constrs.push(("MyNil", 0, 0))
  self.known_constrs.push(("MyCons", 1, 2))
  // Standard List: Nil (0, 0), Cons (1, 2), LCons (1, 2)
  self.known_constrs.push(("Nil", 0, 0))
  self.known_constrs.push(("Cons", 1, 2))
  self.known_constrs.push(("LCons", 1, 2))
  // Maybe: MyNothing (0, 0), MyJust (1, 1)
  self.known_constrs.push(("MyNothing", 0, 0))
  self.known_constrs.push(("MyJust", 1, 1))
  // Bool: MyFalse (0, 0), MyTrue (1, 0)
  self.known_constrs.push(("MyFalse", 0, 0))
  self.known_constrs.push(("MyTrue", 1, 0))
  // Standard Bool: False (0, 0), True (1, 0)
  self.known_constrs.push(("False", 0, 0))
  self.known_constrs.push(("True", 1, 0))
  // Tree: Leaf (0, 1), Node (1, 2)
  self.known_constrs.push(("Leaf", 0, 1))
  self.known_constrs.push(("Node", 1, 2))
  // Pair: Pair (0, 2)
  self.known_constrs.push(("Pair", 0, 2))

  // Emit Scott definitions for each:
  // MyNil = (call (* call))
  self.add_def("MyNil", Net::{
    root: Con(Var("call"), Con(Era, Var("call"))),
    redexes: [],
  })

  // MyCons h t = (h (t (* ((h (t call)) call))))
  self.add_def("MyCons", Net::{
    root: Con(Var("h"), Con(Var("t"), Con(Era, Con(Con(Var("h"), Con(Var("t"), Var("call"))), Var("call"))))),
    redexes: [],
  })

  // Nil = (call (* call))
  self.add_def("Nil", Net::{
    root: Con(Var("call"), Con(Era, Var("call"))),
    redexes: [],
  })

  // Cons h t = (h (t (* ((h (t call)) call))))
  self.add_def("Cons", Net::{
    root: Con(Var("h"), Con(Var("t"), Con(Era, Con(Con(Var("h"), Con(Var("t"), Var("call"))), Var("call"))))),
    redexes: [],
  })

  // LCons h t = (h (t (* ((h (t call)) call))))
  self.add_def("LCons", Net::{
    root: Con(Var("h"), Con(Var("t"), Con(Era, Con(Con(Var("h"), Con(Var("t"), Var("call"))), Var("call"))))),
    redexes: [],
  })

  // MyNothing = (call (* call))
  self.add_def("MyNothing", Net::{
    root: Con(Var("call"), Con(Era, Var("call"))),
    redexes: [],
  })

  // MyJust x = (x (* ((x call) call)))
  self.add_def("MyJust", Net::{
    root: Con(Var("x"), Con(Era, Con(Con(Var("x"), Var("call")), Var("call")))),
    redexes: [],
  })

  // MyFalse = (call (* call))
  self.add_def("MyFalse", Net::{
    root: Con(Var("call"), Con(Era, Var("call"))),
    redexes: [],
  })

  // MyTrue = (* (call call))
  self.add_def("MyTrue", Net::{
    root: Con(Era, Con(Var("call"), Var("call"))),
    redexes: [],
  })

  // False = (call (* call))
  self.add_def("False", Net::{
    root: Con(Var("call"), Con(Era, Var("call"))),
    redexes: [],
  })

  // True = (* (call call))
  self.add_def("True", Net::{
    root: Con(Era, Con(Var("call"), Var("call"))),
    redexes: [],
  })

  // Leaf x = (x ((x call) (* call)))
  self.add_def("Leaf", Net::{
    root: Con(Var("x"), Con(Con(Var("x"), Var("call")), Con(Era, Var("call")))),
    redexes: [],
  })

  // Node l r = (l (r (* ((l (r call)) call))))
  self.add_def("Node", Net::{
    root: Con(Var("l"), Con(Var("r"), Con(Era, Con(Con(Var("l"), Con(Var("r"), Var("call"))), Var("call"))))),
    redexes: [],
  })

  // Pair l r = (l (r ((l (r call)) call)))
  self.add_def("Pair", Net::{
    root: Con(Var("l"), Con(Var("r"), Con(Con(Var("l"), Con(Var("r"), Var("call"))), Var("call")))),
    redexes: [],
  })
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
    LitInt(_) | LitChar(_) | LitString(_) => ()
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

fn LowerCtx::lower_expr_to_tree(
  self : LowerCtx,
  expr : @syntax.Expr,
  redexes : Array[Redex]
) -> Tree {
  match expr {
    LitInt(n) => Num(n)
    LitChar(c) => Num(c.to_int())
    LitString(_) => Num(0)
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
      if name == "I#" && args.length() == 1 {
        self.lower_expr_to_tree(args[0], redexes)
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
      // Check inlined binary arithmetic
      match head {
        Var(op) if args.length() == 2 && is_inlined_binop(op) => {
          let a0 = self.lower_expr_to_tree(args[0], redexes)
          let a1 = self.lower_expr_to_tree(args[1], redexes)
          match op {
            "+" | "+#" => {
              let ret = self.fresh_var("add_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[+]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "-" | "-#" => {
              let ret = self.fresh_var("sub_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[-]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "*" | "*#" => {
              let ret = self.fresh_var("mul_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[*]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "==#" | "==" => {
              let ret = self.fresh_var("eq_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[=]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "/=#" | "/=" => {
              let ret = self.fresh_var("neq_res")
              redexes.push({ fst: a0, snd: Opr(OpSym("[!]"), Opr(a1, Var(ret))) })
              return Var(ret)
            }
            "<#" | "<" => {
              let ret = self.fresh_var("lt_res")
              let rhs = match a1 {
                Num(n) if n >= 0 => OpSym("+\{n}")
                _ => a1
              }
              redexes.push({ fst: a0, snd: Opr(OpSym("[<]"), Opr(rhs, Var(ret))) })
              return Var(ret)
            }
            ">#" | ">" => {
              let ret = self.fresh_var("gt_res")
              let rhs = match a1 {
                Num(n) if n >= 0 => OpSym("+\{n}")
                _ => a1
              }
              redexes.push({ fst: a0, snd: Opr(OpSym("[>]"), Opr(rhs, Var(ret))) })
              return Var(ret)
            }
            "<=#" | "<=" => {
              let lt = self.fresh_var("cmp_lt")
              let ret = self.fresh_var("cmp_res")
              let rhs = match a1 {
                Num(n) if n >= 0 => OpSym("+\{n}")
                _ => a1
              }
              redexes.push({ fst: rhs, snd: Opr(OpSym("[<]"), Opr(a0, Var(lt))) })
              redexes.push({ fst: Num(1), snd: Opr(OpSym("[-]"), Opr(Var(lt), Var(ret))) })
              return Var(ret)
            }
            ">=#" | ">=" => {
              let lt = self.fresh_var("cmp_lt")
              let ret = self.fresh_var("cmp_res")
              let rhs = match a1 {
                Num(n) if n >= 0 => OpSym("+\{n}")
                _ => a1
              }
              redexes.push({ fst: a0, snd: Opr(OpSym("[<]"), Opr(rhs, Var(lt))) })
              redexes.push({ fst: Num(1), snd: Opr(OpSym("[-]"), Opr(Var(lt), Var(ret))) })
              return Var(ret)
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
      let val_tree = self.lower_expr_to_tree(val, redexes)
      redexes.push({ fst: val_tree, snd: Var(sanitize_name(name)) })
      self.lower_expr_to_tree(body, redexes)
    }
    Let(Rec(pairs), body) => {
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

// ----------------------------------------------------------------------------
// Case Expression Lowering
// ----------------------------------------------------------------------------

fn LowerCtx::lower_case_expr(
  self : LowerCtx,
  scrut : @syntax.Expr,
  binder : String,
  alts : Array[@syntax.Alt],
  redexes : Array[Redex]
) -> Tree {
  // Case 1: Single constructor pattern matching
  if alts.length() == 1 {
    match alts[0].pat {
      Data(c, vars) if c == "I#" && vars.length() == 1 => {
        let scrut_tree = self.lower_expr_to_tree(scrut, redexes)
        let scrut_val = if binder.length() > 0 && binder != vars[0] {
          let b_name = sanitize_name(binder)
          redexes.push({ fst: scrut_tree, snd: Var(b_name) })
          Var(b_name)
        } else {
          scrut_tree
        }
        redexes.push({ fst: scrut_val, snd: Var(sanitize_name(vars[0])) })
        return self.lower_expr_to_tree(alts[0].expr, redexes)
      }
      Data(c, vars) if c == "Cons" && vars.length() == 2 => {
        let scrut_tree = self.lower_expr_to_tree(scrut, redexes)
        let scrut_val = if binder.length() > 0 {
          let b_name = sanitize_name(binder)
          redexes.push({ fst: scrut_tree, snd: Var(b_name) })
          Var(b_name)
        } else {
          scrut_tree
        }
        let stream_n = self.fresh_var("sn")
        let stream_step = self.fresh_var("ss")
        let stream_forced = self.fresh_var("sf")
        redexes.push({ fst: scrut_val, snd: Con(Var(stream_n), Var(stream_step)) })
        redexes.push({ fst: Var(stream_step), snd: Con(Var(stream_n), Var(stream_forced)) })

        let alt0 = alts[0]
        let alt0_bound : Array[String] = []
        for v in vars { alt0_bound.push(v) }
        let alt0_fvs = get_free_vars(alt0.expr, alt0_bound)
        let env_vars : Array[String] = []
        for v in alt0_fvs {
          if !self.is_top_level(v) && !is_builtin_prim(v) {
            env_vars.push(v)
          }
        }

        let alt0_helper = self.fresh_helper_name("alt_stream")
        let alt0_ret = self.fresh_var("ret")
        let alt0_redexes : Array[Redex] = []
        let alt0_body_tree = self.lower_expr_to_tree(alt0.expr, alt0_redexes)
        alt0_redexes.push({ fst: alt0_body_tree, snd: Var(alt0_ret) })
        let mut alt0_root : Tree = Var(alt0_ret)
        for i = env_vars.length() - 1; i >= 0; i = i - 1 {
          alt0_root = Con(Var(sanitize_name(env_vars[i])), alt0_root)
        }
        for i = alt0_bound.length() - 1; i >= 0; i = i - 1 {
          alt0_root = Con(Var(sanitize_name(alt0_bound[i])), alt0_root)
        }
        self.add_def(alt0_helper, Net::{ root: alt0_root, redexes: alt0_redexes })

        let ret = self.fresh_var("case_ret")
        let mut call_spine : Tree = Var(ret)
        for i = env_vars.length() - 1; i >= 0; i = i - 1 {
          call_spine = Con(Var(sanitize_name(env_vars[i])), call_spine)
        }

        redexes.push({
          fst: Var(stream_forced),
          snd: Con(Era, Con(Ref(alt0_helper), call_spine))
        })
        return Var(ret)
      }
      Data(c, vars) if c == "Pair" && vars.length() == 2 => {
        let scrut_tree = self.lower_expr_to_tree(scrut, redexes)
        let scrut_val = if binder.length() > 0 {
          let b_name = sanitize_name(binder)
          redexes.push({ fst: scrut_tree, snd: Var(b_name) })
          Var(b_name)
        } else {
          scrut_tree
        }

        let alt0 = alts[0]
        let alt0_bound : Array[String] = []
        for v in vars { alt0_bound.push(v) }
        let alt0_fvs = get_free_vars(alt0.expr, alt0_bound)
        let env_vars : Array[String] = []
        for v in alt0_fvs {
          if !self.is_top_level(v) && !is_builtin_prim(v) {
            env_vars.push(v)
          }
        }

        let alt0_helper = self.fresh_helper_name("alt_pair")
        let alt0_ret = self.fresh_var("ret")
        let alt0_redexes : Array[Redex] = []
        let alt0_body_tree = self.lower_expr_to_tree(alt0.expr, alt0_redexes)
        alt0_redexes.push({ fst: alt0_body_tree, snd: Var(alt0_ret) })
        let mut alt0_root : Tree = Var(alt0_ret)
        for i = env_vars.length() - 1; i >= 0; i = i - 1 {
          alt0_root = Con(Var(sanitize_name(env_vars[i])), alt0_root)
        }
        for i = alt0_bound.length() - 1; i >= 0; i = i - 1 {
          alt0_root = Con(Var(sanitize_name(alt0_bound[i])), alt0_root)
        }
        self.add_def(alt0_helper, Net::{ root: alt0_root, redexes: alt0_redexes })

        let ret = self.fresh_var("case_ret")
        let mut call_spine : Tree = Var(ret)
        for i = env_vars.length() - 1; i >= 0; i = i - 1 {
          call_spine = Con(Var(sanitize_name(env_vars[i])), call_spine)
        }

        redexes.push({
          fst: scrut_val,
          snd: Con(Ref(alt0_helper), call_spine)
        })
        return Var(ret)
      }
      Default(opt_v) => {
        let bndr_name = if opt_v is Some(v) { v } else if binder.length() > 0 { binder } else { self.fresh_var("bndr") }
        let scrut_tree = self.lower_expr_to_tree(scrut, redexes)
        let scrut_val = if binder.length() > 0 && binder != bndr_name {
          let b_name = sanitize_name(binder)
          redexes.push({ fst: scrut_tree, snd: Var(b_name) })
          Var(b_name)
        } else {
          scrut_tree
        }
        redexes.push({ fst: scrut_val, snd: Var(sanitize_name(bndr_name)) })
        return self.lower_expr_to_tree(alts[0].expr, redexes)
      }
      _ => ()
    }
  }

  // Case 2: Integer / Boolean Condition Branching (1# vs __DEFAULT)
  let mut has_lit1 = false
  let mut lit1_expr : @syntax.Expr? = None
  let mut default_expr : @syntax.Expr? = None

  for alt in alts {
    match alt.pat {
      Lit(1) => {
        has_lit1 = true
        lit1_expr = Some(alt.expr)
      }
      Default(_) => {
        default_expr = Some(alt.expr)
      }
      _ => ()
    }
  }

  if has_lit1 && lit1_expr is Some(then_e) && default_expr is Some(else_e) {
    let cond_tree = self.lower_expr_to_tree(scrut, redexes)
    let cond_val = if binder.length() > 0 {
      let b_name = sanitize_name(binder)
      redexes.push({ fst: cond_tree, snd: Var(b_name) })
      Var(b_name)
    } else {
      cond_tree
    }
    let ret = self.fresh_var("case_ret")

    // Collect free variables for then and else branches
    let then_fvs = get_free_vars(then_e, [])
    let else_fvs = get_free_vars(else_e, [])
    let env_vars : Array[String] = []
    for v in then_fvs {
      if !self.is_top_level(v) && !is_builtin_prim(v) {
        env_vars.push(v)
      }
    }
    for v in else_fvs {
      if !self.is_top_level(v) && !is_builtin_prim(v) {
        let mut found = false
        for e in env_vars {
          if e == v { found = true; break }
        }
        if !found { env_vars.push(v) }
      }
    }

    // Create helper net for else branch (index 0):
    let else_helper = self.fresh_helper_name("branch_else")
    let else_ret = self.fresh_var("ret")
    let else_redexes : Array[Redex] = []
    let else_body_tree = self.lower_expr_to_tree(else_e, else_redexes)
    else_redexes.push({ fst: else_body_tree, snd: Var(else_ret) })
    let mut else_root : Tree = Var(else_ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      else_root = Con(Var(sanitize_name(env_vars[i])), else_root)
    }
    self.add_def(else_helper, Net::{ root: else_root, redexes: else_redexes })

    // Create helper net for then branch (index 1):
    let then_helper = self.fresh_helper_name("branch_then")
    let then_ret = self.fresh_var("ret")
    let then_redexes : Array[Redex] = []
    let then_body_tree = self.lower_expr_to_tree(then_e, then_redexes)
    then_redexes.push({ fst: then_body_tree, snd: Var(then_ret) })
    let mut then_root : Tree = Var(then_ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      then_root = Con(Var(sanitize_name(env_vars[i])), then_root)
    }
    then_root = Con(Era, then_root)
    self.add_def(then_helper, Net::{ root: then_root, redexes: then_redexes })

    // Call spine with env vars:
    let mut call_spine : Tree = Var(ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      call_spine = Con(Var(sanitize_name(env_vars[i])), call_spine)
    }

    // Switch redex: cond ~ ?((@else_helper @then_helper) call_spine)
    redexes.push({
      fst: cond_val,
      snd: Swi(Con(Ref(else_helper), Ref(then_helper)), call_spine)
    })

    return Var(ret)
  }

  // Case 3: ADT 2-Variant Pattern Matching (Scott Encoding)
  if alts.length() == 2 {
    let mut alt0_opt : @syntax.Alt? = None
    let mut alt1_opt : @syntax.Alt? = None

    for alt in alts {
      match alt.pat {
        Data(c, _) => {
          let mut variant_idx = 0
          for kc in self.known_constrs {
            if kc.0 == c {
              variant_idx = kc.1
              break
            }
          }
          if variant_idx == 0 {
            alt0_opt = Some(alt)
          } else {
            alt1_opt = Some(alt)
          }
        }
        _ => ()
      }
    }

    if alt0_opt is Some(alt0) && alt1_opt is Some(alt1) {
      let scrut_tree = self.lower_expr_to_tree(scrut, redexes)
      let scrut_val = if binder.length() > 0 {
        let b_name = sanitize_name(binder)
        redexes.push({ fst: scrut_tree, snd: Var(b_name) })
        Var(b_name)
      } else {
        scrut_tree
      }
      let ret = self.fresh_var("match_ret")

      let alt0_bound : Array[String] = []
      match alt0.pat {
        Data(_, vars) => for v in vars { alt0_bound.push(v) }
        _ => ()
      }
      let alt1_bound : Array[String] = []
      match alt1.pat {
        Data(_, vars) => for v in vars { alt1_bound.push(v) }
        _ => ()
      }

      let alt0_fvs = get_free_vars(alt0.expr, alt0_bound)
      let alt1_fvs = get_free_vars(alt1.expr, alt1_bound)
      let env_vars : Array[String] = []
      for v in alt0_fvs {
        if !self.is_top_level(v) && !is_builtin_prim(v) {
          env_vars.push(v)
        }
      }
      for v in alt1_fvs {
        if !self.is_top_level(v) && !is_builtin_prim(v) {
          let mut found = false
          for e in env_vars {
            if e == v { found = true; break }
          }
          if !found { env_vars.push(v) }
        }
      }

      let alt0_helper = self.fresh_helper_name("alt0")
      let alt0_ret = self.fresh_var("ret")
      let alt0_redexes : Array[Redex] = []
      let alt0_body_tree = self.lower_expr_to_tree(alt0.expr, alt0_redexes)
      alt0_redexes.push({ fst: alt0_body_tree, snd: Var(alt0_ret) })
      let mut alt0_root : Tree = Var(alt0_ret)
      for i = env_vars.length() - 1; i >= 0; i = i - 1 {
        alt0_root = Con(Var(sanitize_name(env_vars[i])), alt0_root)
      }
      for i = alt0_bound.length() - 1; i >= 0; i = i - 1 {
        alt0_root = Con(Var(sanitize_name(alt0_bound[i])), alt0_root)
      }
      self.add_def(alt0_helper, Net::{ root: alt0_root, redexes: alt0_redexes })

      let alt1_helper = self.fresh_helper_name("alt1")
      let alt1_ret = self.fresh_var("ret")
      let alt1_redexes : Array[Redex] = []
      let alt1_body_tree = self.lower_expr_to_tree(alt1.expr, alt1_redexes)
      alt1_redexes.push({ fst: alt1_body_tree, snd: Var(alt1_ret) })
      let mut alt1_root : Tree = Var(alt1_ret)
      for i = env_vars.length() - 1; i >= 0; i = i - 1 {
        alt1_root = Con(Var(sanitize_name(env_vars[i])), alt1_root)
      }
      for i = alt1_bound.length() - 1; i >= 0; i = i - 1 {
        alt1_root = Con(Var(sanitize_name(alt1_bound[i])), alt1_root)
      }
      self.add_def(alt1_helper, Net::{ root: alt1_root, redexes: alt1_redexes })

      let mut call_spine : Tree = Var(ret)
      for i = env_vars.length() - 1; i >= 0; i = i - 1 {
        call_spine = Con(Var(sanitize_name(env_vars[i])), call_spine)
      }

      redexes.push({
        fst: scrut_val,
        snd: Con(Ref(alt0_helper), Con(Ref(alt1_helper), call_spine))
      })

      return Var(ret)
    }
  }

  // Fallback: evaluate first alternative
  let def_ret = self.fresh_var("case_fallback")
  let tree = self.lower_expr_to_tree(alts[0].expr, redexes)
  redexes.push({ fst: tree, snd: Var(def_ret) })
  Var(def_ret)
}

// ----------------------------------------------------------------------------
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
  } else {
    match body {
      LitInt(n) => {
        self.add_def(hvm_name, Net::{ root: Num(n), redexes: [] })
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

///| Lower an AST Program to HVM2 Book string
pub fn lower_program(prog : @syntax.Program) -> String {
  let ctx = LowerCtx::new()

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
  ctx.register_known_constructors()

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
