///|
pub fn lower_expr(expr : @syntax.Expr) -> String {
  match expr {
    Var(x) => x
    LitInt(n) => n.to_string()
    _ => "TODO"
  }
}
