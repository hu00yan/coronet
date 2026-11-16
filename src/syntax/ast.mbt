///| CoreLite AST definitions for Coronet compiler.

///| Pattern in a case alternative.
#derive(Eq, Debug)
pub(all) enum Pat {
  Default(String?)
  Lit(Int)
  Data(String, Array[String])
}

///| Case alternative: pat -> expr.
#derive(Eq, Debug)
pub(all) struct Alt {
  pat : Pat
  expr : Expr
}

///| Top-level or let binding.
#derive(Eq, Debug)
pub(all) enum Bind {
  NonRec(String, Expr)
  Rec(Array[(String, Expr)])
}

///| CoreLite Expression.
#derive(Eq, Debug)
pub(all) enum Expr {
  Var(String)
  LitInt(Int)
  LitChar(Char)
  LitString(String)
  App(Expr, Expr)
  Lam(String, Expr)
  Let(Bind, Expr)
  Case(Expr, String, Array[Alt])
  Constr(String, Array[Expr])
}

///| CoreLite Program: a sequence of top-level bindings.
#derive(Eq, Debug)
pub(all) struct Program {
  binds : Array[Bind]
}

// ----------------------------------------------------------------------------
// Show trait implementations
// ----------------------------------------------------------------------------

///|
pub impl Show for Pat with output(self, logger) {
  match self {
    Default(None) => logger.write_string("__DEFAULT")
    Default(Some(v)) => logger.write_string(v)
    Lit(n) => logger.write_string("\{n}#")
    Data(c, vars) => {
      logger.write_string(c)
      for v in vars {
        logger.write_string(" ")
        logger.write_string(v)
      }
    }
  }
}

pub extend Pat with Eq::{not_equal, equal}
pub extend Pat with @debug.Debug::{to_repr}
pub extend Pat with Show::{to_string, output}

///|
pub impl Show for Alt with output(self, logger) {
  logger.write_string("\{self.pat} -> \{self.expr}")
}

pub extend Alt with Eq::{not_equal, equal}
pub extend Alt with @debug.Debug::{to_repr}
pub extend Alt with Show::{to_string, output}

///|
pub impl Show for Bind with output(self, logger) {
  match self {
    NonRec(name, expr) => logger.write_string("\{name} = \{expr}")
    Rec(pairs) => {
      logger.write_string("Rec {\n")
      for pair in pairs {
        logger.write_string("  \{pair.0} = \{pair.1};\n")
      }
      logger.write_string("end Rec }")
    }
  }
}

pub extend Bind with Eq::{not_equal, equal}
pub extend Bind with @debug.Debug::{to_repr}
pub extend Bind with Show::{to_string, output}

///|
pub impl Show for Expr with output(self, logger) {
  match self {
    Var(x) => logger.write_string(x)
    LitInt(n) => logger.write_string("\{n}#")
    LitChar(c) => logger.write_string("'\{c}'")
    LitString(s) => logger.write_string("\"\{s}\"")
    App(f, arg) => {
      let f_str = match f {
        Lam(_, _) | Let(_, _) | Case(_, _, _) => "(\{f})"
        _ => "\{f}"
      }
      let arg_str = match arg {
        App(_, _) | Lam(_, _) | Let(_, _) | Case(_, _, _) => "(\{arg})"
        Constr(_, args) if args.length() > 0 => "(\{arg})"
        _ => "\{arg}"
      }
      logger.write_string("\{f_str} \{arg_str}")
    }
    Lam(param, body) => logger.write_string("\\\{param} -> \{body}")
    Let(bind, body) => logger.write_string("let \{bind} in \{body}")
    Case(scrut, binder, alts) => {
      logger.write_string("case \{scrut} of")
      if binder.length() > 0 {
        logger.write_string(" ")
        logger.write_string(binder)
      }
      logger.write_string(" { ")
      for i, alt in alts {
        if i > 0 {
          logger.write_string("; ")
        }
        logger.write_string("\{alt}")
      }
      logger.write_string(" }")
    }
    Constr(c, args) => {
      if args.length() == 0 {
        logger.write_string(c)
      } else {
        logger.write_string(c)
        for arg in args {
          logger.write_string(" ")
          let arg_str = match arg {
            App(_, _) | Lam(_, _) | Let(_, _) | Case(_, _, _) => "(\{arg})"
            Constr(_, inner_args) if inner_args.length() > 0 => "(\{arg})"
            _ => "\{arg}"
          }
          logger.write_string(arg_str)
        }
      }
    }
  }
}

pub extend Expr with Eq::{not_equal, equal}
pub extend Expr with @debug.Debug::{to_repr}
pub extend Expr with Show::{to_string, output}

///|
pub impl Show for Program with output(self, logger) {
  for i, b in self.binds {
    if i > 0 {
      logger.write_string("\n\n")
    }
    logger.write_string("\{b}")
  }
}

pub extend Program with Eq::{not_equal, equal}
pub extend Program with @debug.Debug::{to_repr}
pub extend Program with Show::{to_string, output}

// ----------------------------------------------------------------------------
// Helper constructors and utilities
// ----------------------------------------------------------------------------

///|
pub fn Alt::new(pat : Pat, expr : Expr) -> Alt {
  { pat, expr }
}

///|
pub fn Alt::default(binder : String?, expr : Expr) -> Alt {
  { pat: Default(binder), expr }
}

///|
pub fn Alt::lit(n : Int, expr : Expr) -> Alt {
  { pat: Lit(n), expr }
}

///|
pub fn Alt::data(name : String, binders : Array[String], expr : Expr) -> Alt {
  { pat: Data(name, binders), expr }
}

///|
pub fn Alt::unboxed_tuple(vars : Array[String], expr : Expr) -> Alt {
  let cname = if vars.length() == 0 {
    "(##)"
  } else if vars.length() == 1 {
    "(# #)"
  } else {
    let buf = StringBuilder()
    buf.write_string("(#")
    for _ in 1..<vars.length() {
      buf.write_string(",")
    }
    buf.write_string("#)")
    buf.to_string()
  }
  { pat: Data(cname, vars), expr }
}

///|
pub fn Pat::unboxed_tuple(vars : Array[String]) -> Pat {
  let cname = if vars.length() == 0 {
    "(##)"
  } else if vars.length() == 1 {
    "(# #)"
  } else {
    let buf = StringBuilder()
    buf.write_string("(#")
    for _ in 1..<vars.length() {
      buf.write_string(",")
    }
    buf.write_string("#)")
    buf.to_string()
  }
  Data(cname, vars)
}

///|
pub fn Bind::non_rec(name : String, expr : Expr) -> Bind {
  NonRec(name, expr)
}

///|
pub fn Bind::rec(binds : Array[(String, Expr)]) -> Bind {
  Rec(binds)
}

///|
pub fn Expr::var_(name : String) -> Expr {
  Var(name)
}

///|
pub fn Expr::variable(name : String) -> Expr {
  Var(name)
}

///|
pub fn Expr::int(n : Int) -> Expr {
  LitInt(n)
}

///|
pub fn Expr::app(f : Expr, arg : Expr) -> Expr {
  App(f, arg)
}

///| Curried application: f a1 a2 ... an
pub fn Expr::apps(f : Expr, args : Array[Expr]) -> Expr {
  let mut res = f
  for arg in args {
    res = App(res, arg)
  }
  res
}

///|
pub fn Expr::lam(param : String, body : Expr) -> Expr {
  Lam(param, body)
}

///| Curried lambda: \ p1 p2 ... pn -> body
pub fn Expr::lams(params : Array[String], body : Expr) -> Expr {
  let mut res = body
  for i = params.length() - 1; i >= 0; i = i - 1 {
    res = Lam(params[i], res)
  }
  res
}

///|
pub fn Expr::let_(name : String, val : Expr, body : Expr) -> Expr {
  Let(NonRec(name, val), body)
}

///|
pub fn Expr::let_rec(bindings : Array[(String, Expr)], body : Expr) -> Expr {
  Let(Rec(bindings), body)
}

///|
pub fn Expr::case_(scrutinee : Expr, binder : String, alts : Array[Alt]) -> Expr {
  Case(scrutinee, binder, alts)
}

///|
pub fn Expr::constr(name : String, args : Array[Expr]) -> Expr {
  Constr(name, args)
}

///| Construct an unboxed tuple expression: (# a, b #)
pub fn Expr::unboxed_tuple(elements : Array[Expr]) -> Expr {
  let cname = if elements.length() == 0 {
    "(##)"
  } else if elements.length() == 1 {
    "(# #)"
  } else {
    let buf = StringBuilder()
    buf.write_string("(#")
    for _ in 1..<elements.length() {
      buf.write_string(",")
    }
    buf.write_string("#)")
    buf.to_string()
  }
  Constr(cname, elements)
}

///| Construct a boxed tuple expression: (a, b)
pub fn Expr::tuple(elements : Array[Expr]) -> Expr {
  let cname = if elements.length() == 0 {
    "()"
  } else {
    let buf = StringBuilder()
    buf.write_string("(")
    for _ in 1..<elements.length() {
      buf.write_string(",")
    }
    buf.write_string(")")
    buf.to_string()
  }
  Constr(cname, elements)
}

///| Unwind nested App(App(f, a), b) into (f, [a, b])
pub fn Expr::unwind_app(self : Expr) -> (Expr, Array[Expr]) {
  let args : Array[Expr] = []
  let mut curr = self
  while true {
    match curr {
      App(f, arg) => {
        args.push(arg)
        curr = f
      }
      _ => break
    }
  }
  // reverse in place
  let len = args.length()
  for i in 0..<(len / 2) {
    let tmp = args[i]
    args[i] = args[len - 1 - i]
    args[len - 1 - i] = tmp
  }
  (curr, args)
}

///|
pub fn Program::new(binds : Array[Bind]) -> Program {
  { binds, }
}

///| Lookup a top-level binding by name
pub fn Program::lookup(self : Program, name : String) -> Expr? {
  for b in self.binds {
    match b {
      NonRec(n, e) => if n == name { return Some(e) }
      Rec(pairs) => {
        for pair in pairs {
          if pair.0 == name { return Some(pair.1) }
        }
      }
    }
  }
  None
}

///| Collect all named bindings in the program
pub fn Program::all_bindings(self : Program) -> Array[(String, Expr)] {
  let res : Array[(String, Expr)] = []
  for b in self.binds {
    match b {
      NonRec(n, e) => res.push((n, e))
      Rec(pairs) => {
        for pair in pairs {
          res.push(pair)
        }
      }
    }
  }
  res
}
