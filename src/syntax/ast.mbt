///|
pub enum Expr {
  Var(String)
  LitInt(Int)
  App(Expr, Expr)
  Lam(String, Expr)
  Let(String, Expr, Expr)
} derive(Show, Eq)
