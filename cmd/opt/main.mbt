///| CoreLite semantic plugin.
///
/// This is intentionally a separate executable: it rewrites CoreLite before
/// `cmd/main` lowers it, so the compiler and both HVM backends stay untouched.
/// The first shipped transform is HVM3 software floating point. HVM3 has no
/// float literal or float opcode, so every float is represented by a Q4.12
/// biased U32. `BIAS = 2^31` makes unsigned comparison monotone, and the
/// 4.12 split keeps multiplication inside 32 bits for the supported range.

let scale : Int = 4096

fn is_float_op(name : String) -> String? {
  match name {
    "plusFloat#" | "plusDouble#" | "+##" | "plusFloat" | "plusDouble" => Some("Coronet_fadd")
    "minusFloat#" | "minusDouble#" | "-##" | "minusFloat" | "minusDouble" => Some("Coronet_fsub")
    "timesFloat#" | "timesDouble#" | "*##" | "timesFloat" | "timesDouble" => Some("Coronet_fmul")
    "divideFloat#" | "divideDouble#" | "/##" | "divideFloat" | "divideDouble" => Some("Coronet_fdiv")
    "negateFloat#" | "negateDouble#" => Some("Coronet_fneg")
    "int2Float#" | "int2Double#" | "word2Float#" | "word2Double#" | "float2Double#" | "double2Float#" | "word2Float" | "word2Double" => Some("Coronet_i2f")
    "float2Int#" | "double2Int#" | "float2Word#" | "double2Word#" => Some("Coronet_f2i")
    "sqrtFloat#" | "sqrtDouble#" => Some("Coronet_fsqrt")
    "fabsFloat#" | "fabsDouble#" | "absFloat#" | "absDouble#" => Some("Coronet_fabs")
    "maxFloat#" | "maxDouble#" | "maxFloat" | "maxDouble" => Some("Coronet_fmax")
    "minFloat#" | "minDouble#" | "minFloat" | "minDouble" => Some("Coronet_fmin")
    "ltFloat#" | "ltDouble#" | "<##" | "ltFloat" | "ltDouble" => Some("Coronet_flt")
    "leFloat#" | "leDouble#" | "<=##" | "leFloat" | "leDouble" => Some("Coronet_fle")
    "gtFloat#" | "gtDouble#" | ">##" | "gtFloat" | "gtDouble" => Some("Coronet_fgt")
    "geFloat#" | "geDouble#" | ">=##" | "geFloat" | "geDouble" => Some("Coronet_fge")
    "eqFloat#" | "eqDouble#" | "==##" | "eqFloat" | "eqDouble" => Some("Coronet_feq")
    "neFloat#" | "neDouble#" | "/=##" | "neFloat" | "neDouble" => Some("Coronet_fne")
    "expFloat#" | "expDouble#" | "expFloat" | "expDouble" => Some("Coronet_fexp")
    "expm1Float#" | "expm1Double#" => Some("Coronet_fexpm1")
    "logFloat#" | "logDouble#" | "logFloat" | "logDouble" => Some("Coronet_flog")
    "log1pFloat#" | "log1pDouble#" => Some("Coronet_flog1p")
    "sinFloat#" | "sinDouble#" | "sinFloat" | "sinDouble" => Some("Coronet_fsin")
    "cosFloat#" | "cosDouble#" | "cosFloat" | "cosDouble" => Some("Coronet_fcos")
    "tanFloat#" | "tanDouble#" | "tanFloat" | "tanDouble" => Some("Coronet_ftan")
    "asinFloat#" | "asinDouble#" => Some("Coronet_fasin")
    "acosFloat#" | "acosDouble#" => Some("Coronet_facos")
    "atanFloat#" | "atanDouble#" => Some("Coronet_fatan")
    "sinhFloat#" | "sinhDouble#" => Some("Coronet_fsinh")
    "coshFloat#" | "coshDouble#" => Some("Coronet_fcosh")
    "tanhFloat#" | "tanhDouble#" => Some("Coronet_ftanh")
    "asinhFloat#" | "asinhDouble#" => Some("Coronet_fasinh")
    "acoshFloat#" | "acoshDouble#" => Some("Coronet_facosh")
    "atanhFloat#" | "atanhDouble#" => Some("Coronet_fatanh")
    "**##" | "powerFloat#" => Some("Coronet_fpow")
    "fmaddFloat#" | "fmaddDouble#" => Some("Coronet_ffmadd")
    "fmsubFloat#" | "fmsubDouble#" => Some("Coronet_ffmsub")
    "fnmaddFloat#" | "fnmaddDouble#" => Some("Coronet_ffnmadd")
    "fnmsubFloat#" | "fnmsubDouble#" => Some("Coronet_ffnmsub")
    "decodeFloat_Int#" => Some("Coronet_fdecode")
    "decodeDouble_2Int#" => Some("Coronet_fdecode2")
    "decodeDouble_Int64#" => Some("Coronet_fdecode64")
    _ => None
  }
}

fn encode_float(d : Double) -> Int {
  let mut n = (d * scale.to_double()).round().to_int()
  if n < -524288 {
    n = -524288
  }
  if n > 524287 {
    n = 524287
  }
  ((n.to_int64() + 2147483648L) & 0xFFFFFFFFL).to_int()
}

fn rewrite_expr(expr : @syntax.Expr) -> @syntax.Expr {
  match expr {
    Var(name) =>
      match is_float_op(name) {
        Some(target) => Var(target)
        None => if name == "catch#" { Var("catchSTM#") } else { Var(name) }
      }
    LitFloat(d) => LitInt(encode_float(d))
    LitInt(_) | LitChar(_) | LitString(_) => expr
    App(f, a) => App(rewrite_expr(f), rewrite_expr(a))
    Lam(p, body) => Lam(p, rewrite_expr(body))
    Let(NonRec(n, v), body) => Let(NonRec(n, rewrite_expr(v)), rewrite_expr(body))
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, rewrite_expr(pair.1)))
      }
      Let(Rec(new_pairs), rewrite_expr(body))
    }
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: rewrite_expr(alt.expr) })
      }
      Case(rewrite_expr(scrut), binder, new_alts)
    }
    Constr(name, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(rewrite_expr(a))
      }
      Constr(name, new_args)
    }
  }
}

fn decimal_parts(d : Double) -> (Int, String, Int) {
  let text = d.to_string()
  let mut mant = text
  let mut exp = 0
  for i in 0..<text.length() {
    let c = text.code_unit_at(i)
    if c == 101 || c == 69 { // e/E
      mant = text.substring(start=0, end=i)
      let rest = text.substring(start=i + 1)
      if rest.length() > 0 {
        let neg = rest.code_unit_at(0) == 45 // '-'
        let digits = if neg || rest.code_unit_at(0) == 43 {
          rest.substring(start=1)
        } else {
          rest
        }
        for ch in digits {
          let q = ch.to_int()
          if q >= 48 && q <= 57 {
            exp = exp * 10 + (q - 48)
          }
        }
        if neg {
          exp = -exp
        }
      }
      break
    }
  }
  let mut sign = 0
  let mut body = mant
  if body.length() > 0 && body.code_unit_at(0) == 45 {
    sign = 1
    body = body.substring(start=1)
  } else if body.length() > 0 && body.code_unit_at(0) == 43 {
    body = body.substring(start=1)
  }
  let digits = StringBuilder()
  let mut frac = 0
  let mut seen_dot = false
  for ch in body {
    let c = ch.to_int()
    if c == 46 { // '.'
      seen_dot = true
    } else if c >= 48 && c <= 57 {
      digits.write_char(ch)
      if seen_dot {
        frac = frac + 1
      }
    }
  }
  let mut ds = digits.to_string()
  if ds == "" {
    ds = "0"
  }
  // Apply the exponent to the fixed-point position.
  let mut frac2 = frac - exp
  if frac2 < 0 {
    for _ in 0..<(-frac2) {
      ds = ds + "0"
    }
    frac2 = 0
  }
  // Double::to_string can expose binary noise (0.1234 -> ...0001). Keep at
  // most 12 fractional digits, then remove insignificant trailing zeros.
  if frac2 > 12 {
    let keep = ds.length() - (frac2 - 12)
    ds = if keep > 0 { ds.substring(start=0, end=keep) } else { "0" }
    frac2 = 12
  }
  while frac2 > 0 && ds.length() > 1 && ds.code_unit_at(ds.length() - 1) == 48 {
    ds = ds.substring(start=0, end=ds.length() - 1)
    frac2 = frac2 - 1
  }
  // Strip leading zeros, but keep one zero.
  let mut first = 0
  while first + 1 < ds.length() && ds.code_unit_at(first) == 48 {
    first = first + 1
  }
  ds = ds.substring(start=first)
  if ds == "0" {
    frac2 = 0
  }
  (sign, ds, frac2)
}

fn decimal_chunks_ast(digits : String) -> @syntax.Expr {
  // big-endian groups of at most 9 decimal digits, consumed by bfromdec.
  let n = digits.length()
  let groups = (n + 8) / 9
  let args : Array[@syntax.Expr] = []
  for g in 0..<groups {
    let start = g * 9
    let end = if start + 9 < n { start + 9 } else { n }
    let mut value = 0
    for i in start..<end {
      value = value * 10 + (digits.code_unit_at(i).to_int() - 48)
    }
    args.push(LitInt(value))
  }
  let mut tail : @syntax.Expr = @syntax.Constr("BNil", [])
  for i = args.length() - 1; i >= 0; i = i - 1 {
    tail = @syntax.Constr("BCons", [args[i], tail])
  }
  @syntax.App(@syntax.Var("bfromdec"), tail)
}

fn br_literal(d : Double) -> @syntax.Expr {
  let (sign, digits, frac) = decimal_parts(d)
  let numerator = @syntax.Constr("Pair", [@syntax.LitInt(sign), decimal_chunks_ast(digits)])
  let mut den_digits = "1"
  for _ in 0..<frac {
    den_digits = den_digits + "0"
  }
  let denominator = @syntax.Constr("Pair", [@syntax.LitInt(0), decimal_chunks_ast(den_digits)])
  @syntax.Constr("Pair", [numerator, denominator])
}

fn is_br_op(name : String) -> String? {
  match name {
    "plusFloat#" | "plusDouble#" | "+##" => Some("bradd")
    "minusFloat#" | "minusDouble#" | "-##" => Some("brsub")
    "timesFloat#" | "timesDouble#" | "*##" => Some("brmul")
    "divideFloat#" | "divideDouble#" | "/##" => Some("brdiv")
    "negateFloat#" | "negateDouble#" => Some("brneg")
    "int2Float#" | "int2Double#" | "word2Float#" | "word2Double#" | "float2Double#" | "double2Float#" => Some("brfromint")
    "float2Int#" | "double2Int#" | "float2Word#" | "double2Word#" => Some("brtoint")
    "sqrtFloat#" | "sqrtDouble#" => Some("brsqrt")
    "ltFloat#" | "ltDouble#" | "<##" => Some("brlt")
    "leFloat#" | "leDouble#" | "<=##" => Some("brle")
    "gtFloat#" | "gtDouble#" | ">##" => Some("brgt")
    "geFloat#" | "geDouble#" | ">=##" => Some("brge")
    "eqFloat#" | "eqDouble#" | "==##" => Some("breq")
    "neFloat#" | "neDouble#" | "/=##" => Some("brne")
    "absFloat#" | "absDouble#" | "fabsFloat#" | "fabsDouble#" => Some("brabs")
    "maxFloat#" | "maxDouble#" => Some("brmax")
    "minFloat#" | "minDouble#" => Some("brmin")
    "expFloat#" | "expDouble#" => Some("brexp")
    "expm1Float#" | "expm1Double#" => Some("brexpm1")
    "logFloat#" | "logDouble#" => Some("brlog")
    "log1pFloat#" | "log1pDouble#" => Some("brlog1p")
    "sinFloat#" | "sinDouble#" => Some("brsin")
    "cosFloat#" | "cosDouble#" => Some("brcos")
    "tanFloat#" | "tanDouble#" => Some("brtan")
    "asinFloat#" | "asinDouble#" => Some("brasin")
    "acosFloat#" | "acosDouble#" => Some("bracos")
    "atanFloat#" | "atanDouble#" => Some("bratan")
    "sinhFloat#" | "sinhDouble#" => Some("brsinh")
    "coshFloat#" | "coshDouble#" => Some("brcosh")
    "tanhFloat#" | "tanhDouble#" => Some("brtanh")
    "asinhFloat#" | "asinhDouble#" => Some("brasinh")
    "acoshFloat#" | "acoshDouble#" => Some("bracosh")
    "atanhFloat#" | "atanhDouble#" => Some("bratanh")
    "**##" | "powerFloat#" => Some("brpow")
    "fmaddFloat#" | "fmaddDouble#" => Some("brfmadd")
    "fmsubFloat#" | "fmsubDouble#" => Some("brfmsub")
    "fnmaddFloat#" | "fnmaddDouble#" => Some("brfnmadd")
    "fnmsubFloat#" | "fnmsubDouble#" => Some("brfnmsub")
    "decodeFloat_Int#" => Some("brdecode")
    "decodeDouble_2Int#" => Some("brdecode2")
    "decodeDouble_Int64#" => Some("brdecode64")
    _ => None
  }
}

fn rewrite_expr_br(expr : @syntax.Expr) -> @syntax.Expr {
  match expr {
    Var(name) =>
      match is_br_op(name) {
        Some(target) => Var(target)
        None => if name == "catch#" { Var("catchSTM#") } else { Var(name) }
      }
    LitFloat(d) => br_literal(d)
    LitInt(_) | LitChar(_) | LitString(_) => expr
    App(f, a) => App(rewrite_expr_br(f), rewrite_expr_br(a))
    Lam(p, body) => Lam(p, rewrite_expr_br(body))
    Let(NonRec(n, v), body) => Let(NonRec(n, rewrite_expr_br(v)), rewrite_expr_br(body))
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, rewrite_expr_br(pair.1)))
      }
      Let(Rec(new_pairs), rewrite_expr_br(body))
    }
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: rewrite_expr_br(alt.expr) })
      }
      Case(rewrite_expr_br(scrut), binder, new_alts)
    }
    Constr(name, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(rewrite_expr_br(a))
      }
      Constr(name, new_args)
    }
  }
}

fn rewrite_program_br(prog : @syntax.Program) -> @syntax.Program {
  let binds : Array[@syntax.Bind] = []
  for bind in prog.binds {
    match bind {
      NonRec(n, e) => binds.push(NonRec(n, rewrite_expr_br(e)))
      Rec(pairs) => {
        let new_pairs : Array[(String, @syntax.Expr)] = []
        for pair in pairs {
          new_pairs.push((pair.0, rewrite_expr_br(pair.1)))
        }
        binds.push(Rec(new_pairs))
      }
    }
  }
  @syntax.Program::new(binds)
}

fn rewrite_sched_expr(expr : @syntax.Expr) -> @syntax.Expr {
  match expr {
    Var(name) =>
      match name {
        "fork#" | "forkOn#" => Var("Coronet_fork")
        "yield#" => Var("Coronet_yield")
        "myThreadId#" => Var("Coronet_myThreadId")
        "killThread#" => Var("Coronet_killThread")
        "par#" | "spark#" => Var("Coronet_par")
        _ => Var(name)
      }
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => expr
    App(f, a) => App(rewrite_sched_expr(f), rewrite_sched_expr(a))
    Lam(p, body) => Lam(p, rewrite_sched_expr(body))
    Let(NonRec(n, v), body) => Let(NonRec(n, rewrite_sched_expr(v)), rewrite_sched_expr(body))
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, rewrite_sched_expr(pair.1)))
      }
      Let(Rec(new_pairs), rewrite_sched_expr(body))
    }
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: rewrite_sched_expr(alt.expr) })
      }
      Case(rewrite_sched_expr(scrut), binder, new_alts)
    }
    Constr(name, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(rewrite_sched_expr(a))
      }
      Constr(name, new_args)
    }
  }
}

fn rewrite_program_sched(prog : @syntax.Program) -> @syntax.Program {
  let binds : Array[@syntax.Bind] = []
  for bind in prog.binds {
    match bind {
      NonRec(n, e) => binds.push(NonRec(n, rewrite_sched_expr(e)))
      Rec(pairs) => {
        let new_pairs : Array[(String, @syntax.Expr)] = []
        for pair in pairs {
          new_pairs.push((pair.0, rewrite_sched_expr(pair.1)))
        }
        binds.push(Rec(new_pairs))
      }
    }
  }
  @syntax.Program::new(binds)
}

fn rewrite_array_expr(expr : @syntax.Expr) -> @syntax.Expr {
  match expr {
    App(App(App(Var(name), size), init), state) => {
      let new_name = match name {
        "newArray#" | "newSmallArray#" | "newPinnedArray#" | "newAlignedPinnedArray#" => "newByteArray#"
        _ => ""
      }
      if new_name != "" {
        App(App(Var(new_name), rewrite_array_expr(size)), rewrite_array_expr(state))
      } else {
        App(rewrite_array_expr(App(App(Var(name), size), init)), rewrite_array_expr(state))
      }
    }
    Var(name) =>
      match name {
        "copyArray#" | "copySmallArray#" | "copyMutableArray#" => Var("Coronet_copyArray")
        "setArray#" | "setSmallArray#" => Var("Coronet_setArray")
        _ => Var(name)
      }
    LitInt(_) | LitFloat(_) | LitChar(_) | LitString(_) => expr
    App(f, a) => App(rewrite_array_expr(f), rewrite_array_expr(a))
    Lam(p, body) => Lam(p, rewrite_array_expr(body))
    Let(NonRec(n, v), body) => Let(NonRec(n, rewrite_array_expr(v)), rewrite_array_expr(body))
    Let(Rec(pairs), body) => {
      let new_pairs : Array[(String, @syntax.Expr)] = []
      for pair in pairs {
        new_pairs.push((pair.0, rewrite_array_expr(pair.1)))
      }
      Let(Rec(new_pairs), rewrite_array_expr(body))
    }
    Case(scrut, binder, alts) => {
      let new_alts : Array[@syntax.Alt] = []
      for alt in alts {
        new_alts.push({ pat: alt.pat, expr: rewrite_array_expr(alt.expr) })
      }
      Case(rewrite_array_expr(scrut), binder, new_alts)
    }
    Constr(name, args) => {
      let new_args : Array[@syntax.Expr] = []
      for a in args {
        new_args.push(rewrite_array_expr(a))
      }
      Constr(name, new_args)
    }
  }
}

fn rewrite_program_arrays(prog : @syntax.Program) -> @syntax.Program {
  let binds : Array[@syntax.Bind] = []
  for bind in prog.binds {
    match bind {
      NonRec(n, e) => binds.push(NonRec(n, rewrite_array_expr(e)))
      Rec(pairs) => {
        let new_pairs : Array[(String, @syntax.Expr)] = []
        for pair in pairs {
          new_pairs.push((pair.0, rewrite_array_expr(pair.1)))
        }
        binds.push(Rec(new_pairs))
      }
    }
  }
  @syntax.Program::new(binds)
}

fn collect_unknown_float(expr : @syntax.Expr, acc : Array[String]) -> Unit {
  match expr {
    Var(name) => {
      if (name.contains("Float") || name.contains("Double")) &&
        is_float_op(name) is None &&
        !acc.contains(name) {
        acc.push(name)
      }
    }
    App(f, a) => {
      collect_unknown_float(f, acc)
      collect_unknown_float(a, acc)
    }
    Lam(_, body) => collect_unknown_float(body, acc)
    Let(bind, body) => {
      match bind {
        NonRec(_, v) => collect_unknown_float(v, acc)
        Rec(pairs) => for pair in pairs { collect_unknown_float(pair.1, acc) }
      }
      collect_unknown_float(body, acc)
    }
    Case(scrut, _, alts) => {
      collect_unknown_float(scrut, acc)
      for alt in alts { collect_unknown_float(alt.expr, acc) }
    }
    Constr(_, args) => for a in args { collect_unknown_float(a, acc) }
    _ => ()
  }
}

fn unknown_float_ops(prog : @syntax.Program) -> Array[String] {
  let acc : Array[String] = []
  for bind in prog.binds {
    match bind {
      NonRec(_, e) => collect_unknown_float(e, acc)
      Rec(pairs) => for pair in pairs { collect_unknown_float(pair.1, acc) }
    }
  }
  acc
}

fn is_gc_prim(name : String) -> Bool {
  match name {
    "mkWeak#" | "mkWeakNoFinalizer#" | "addCFinalizerToWeak#" | "deRefWeak#" | "finalizeWeak#" |
    "makeStablePtr#" | "deRefStablePtr#" | "eqStablePtr#" | "makeStableName#" | "stableNameToInt#" |
    "compactNew#" | "compactResize#" | "compactContains#" | "compactContainsAny#" |
    "compactGetFirstBlock#" | "compactGetNextBlock#" | "compactAllocateBlock#" |
    "compactFixupPointers#" | "compactAdd#" | "compactAddWithSharing#" | "compactSize#" |
    "setThreadAllocationCounter#" | "setOtherThreadAllocationCounter#" |
    "listThreads#" => true
    _ => false
  }
}

fn collect_gc_prim(expr : @syntax.Expr, acc : Array[String]) -> Unit {
  match expr {
    Var(name) => if is_gc_prim(name) && !acc.contains(name) { acc.push(name) }
    App(f, a) => {
      collect_gc_prim(f, acc)
      collect_gc_prim(a, acc)
    }
    Lam(_, body) => collect_gc_prim(body, acc)
    Let(bind, body) => {
      match bind {
        NonRec(_, v) => collect_gc_prim(v, acc)
        Rec(pairs) => for pair in pairs { collect_gc_prim(pair.1, acc) }
      }
      collect_gc_prim(body, acc)
    }
    Case(scrut, _, alts) => {
      collect_gc_prim(scrut, acc)
      for alt in alts { collect_gc_prim(alt.expr, acc) }
    }
    Constr(_, args) => for a in args { collect_gc_prim(a, acc) }
    _ => ()
  }
}

fn gc_prims(prog : @syntax.Program) -> Array[String] {
  let acc : Array[String] = []
  for bind in prog.binds {
    match bind {
      NonRec(_, e) => collect_gc_prim(e, acc)
      Rec(pairs) => for pair in pairs { collect_gc_prim(pair.1, acc) }
    }
  }
  acc
}

fn rewrite_program(prog : @syntax.Program) -> @syntax.Program {
  let binds : Array[@syntax.Bind] = []
  for bind in prog.binds {
    match bind {
      NonRec(n, e) => binds.push(NonRec(n, rewrite_expr(e)))
      Rec(pairs) => {
        let new_pairs : Array[(String, @syntax.Expr)] = []
        for pair in pairs {
          new_pairs.push((pair.0, rewrite_expr(pair.1)))
        }
        binds.push(Rec(new_pairs))
      }
    }
  }
  @syntax.Program::new(binds)
}

fn prelude() -> String {
  let lines : Array[String] = []
  lines.push("Coronet_abs = \\ a -> let u = -# a -2147483648# in -# u (*# 2# (*# (quotInt# u -2147483648#) u))")
  lines.push("Coronet_sign = \\ a -> quotInt# (-# a -2147483648#) -2147483648#")
  lines.push("Coronet_fadd = \\ a b -> -# (+# a b) -2147483648#")
  lines.push("Coronet_fsub = \\ a b -> +# (-# a b) -2147483648#")
  lines.push("Coronet_fneg = \\ a -> -# 0# a")
  lines.push("Coronet_i2f = \\ n -> +# (*# n 4096#) -2147483648#")
  lines.push("Coronet_f2i = \\ a -> let u = -# a -2147483648# in let s = quotInt# u -2147483648# in let m = Coronet_abs a in let q = quotInt# m 4096# in -# q (*# 2# (*# s q))")
  lines.push("Coronet_fmul = \\ a b -> let u = -# a -2147483648# in let v = -# b -2147483648# in let s = xor# (quotInt# u -2147483648#) (quotInt# v -2147483648#) in let m = quotInt# (*# (Coronet_abs a) (Coronet_abs b)) 4096# in +# (-# m (*# 2# (*# s m))) -2147483648#")
  lines.push("Coronet_fdiv = \\ a b -> let u = -# a -2147483648# in let v = -# b -2147483648# in let s = xor# (quotInt# u -2147483648#) (quotInt# v -2147483648#) in let m = quotInt# (*# (Coronet_abs a) 4096#) (Coronet_abs b) in +# (-# m (*# 2# (*# s m))) -2147483648#")
  lines.push("Coronet_fabs = \\ a -> let u = -# a -2147483648# in +# (Coronet_abs a) -2147483648#")
  lines.push("Coronet_fmax = \\ a b -> case gtInt# a b of { 1# -> a; __DEFAULT -> b }")
  lines.push("Coronet_fmin = \\ a b -> case ltInt# a b of { 1# -> a; __DEFAULT -> b }")
  lines.push("Coronet_flt = \\ a b -> ltInt# a b")
  lines.push("Coronet_fle = \\ a b -> leInt# a b")
  lines.push("Coronet_fgt = \\ a b -> gtInt# a b")
  lines.push("Coronet_fge = \\ a b -> geInt# a b")
  lines.push("Coronet_feq = \\ a b -> eqInt# a b")
  lines.push("Coronet_fne = \\ a b -> neInt# a b")
  lines.push("Coronet_fzero = -2147483648#")
  lines.push("Coronet_fone = -2147479552#")
  lines.push("Coronet_ftwo = -2147475456#")
  lines.push("Coronet_fhalf = -2147481600#")
  lines.push("Coronet_fpi = -2147470780#")
  lines.push("Coronet_fpi2 = -2147477214#")
  lines.push("Coronet_ftwopi = -2147457912#")
  lines.push("Coronet_fln2 = -2147480809#")
  lines.push("Coronet_finvln2 = -2147477739#")
  lines.push("Coronet_fsqr = \\ x -> Coronet_fmul x x")
  lines.push("Coronet_fpow2 = \\ k -> case eqInt# k 0# of { 1# -> Coronet_fone; __DEFAULT -> case gtInt# k 0# of { 1# -> Coronet_fmul (Coronet_fpow2 (-# k 1#)) Coronet_ftwo; __DEFAULT -> Coronet_fdiv (Coronet_fpow2 (+# k 1#)) Coronet_ftwo } }")
  lines.push("Rec {")
  lines.push("Coronet_fexp_taylor = \\ r i n term acc -> case eqInt# i n of { 1# -> acc; __DEFAULT -> let nt = Coronet_fmul term (Coronet_fdiv r (Coronet_i2f (+# i 1#))) in Coronet_fexp_taylor r (+# i 1#) n nt (Coronet_fadd acc nt) }")
  lines.push("Coronet_fsin_taylor = \\ r r2 i n term acc -> case eqInt# i n of { 1# -> acc; __DEFAULT -> let nt = Coronet_fneg (Coronet_fmul term (Coronet_fdiv r2 (Coronet_i2f (*# (+# (*# 2# i) 2#) (+# (*# 2# i) 3#))))) in Coronet_fsin_taylor r r2 (+# i 1#) n nt (Coronet_fadd acc nt) }")
  lines.push("Coronet_fcos_taylor = \\ r r2 i n term acc -> case eqInt# i n of { 1# -> acc; __DEFAULT -> let nt = Coronet_fneg (Coronet_fmul term (Coronet_fdiv r2 (Coronet_i2f (*# (+# (*# 2# i) 1#) (+# (*# 2# i) 2#))))) in Coronet_fcos_taylor r r2 (+# i 1#) n nt (Coronet_fadd acc nt) }")
  lines.push("Coronet_flog_series = \\ z z2 j n term acc -> case eqInt# j n of { 1# -> acc; __DEFAULT -> let nt = Coronet_fmul term z2 in Coronet_flog_series z z2 (+# j 1#) n nt (Coronet_fadd acc (Coronet_fdiv nt (Coronet_i2f (+# 3# (*# 2# j))))) }")
  lines.push("Coronet_fatan_series = \\ x x2 j n term acc -> case eqInt# j n of { 1# -> acc; __DEFAULT -> let nt = Coronet_fneg (Coronet_fmul term x2) in Coronet_fatan_series x x2 (+# j 1#) n nt (Coronet_fadd acc (Coronet_fdiv nt (Coronet_i2f (+# 3# (*# 2# j))))) }")
  lines.push("Coronet_flog_norm = \\ m k n -> case geInt# m Coronet_ftwo of { 1# -> Coronet_flog_norm (Coronet_fdiv m Coronet_ftwo) (+# k 1#) n; __DEFAULT -> case ltInt# m Coronet_fone of { 1# -> Coronet_flog_norm (Coronet_fmul m Coronet_ftwo) (-# k 1#) n; __DEFAULT -> Pair m k } }")
  lines.push("end Rec }")
  lines.push("Coronet_fexp = \\ x -> let k = Coronet_f2i (Coronet_fmul x Coronet_finvln2) in let r = Coronet_fsub x (Coronet_fmul (Coronet_i2f k) Coronet_fln2) in Coronet_fmul (Coronet_fexp_taylor r 0# 14# Coronet_fone Coronet_fone) (Coronet_fpow2 k)")
  lines.push("Coronet_fexpm1 = \\ x -> Coronet_fsub (Coronet_fexp x) Coronet_fone")
  lines.push("Coronet_flog = \\ x -> case leInt# x Coronet_fone of { 1# -> Coronet_fzero; __DEFAULT -> let mk = Coronet_flog_norm x 0# 0# in let m = case mk of { Pair m k -> m } in let k = case mk of { Pair m k -> k } in let z = Coronet_fdiv (Coronet_fsub m Coronet_fone) (Coronet_fadd m Coronet_fone) in let z2 = Coronet_fsqr z in Coronet_fadd (Coronet_fmul Coronet_ftwo (Coronet_flog_series z z2 0# 12# z z)) (Coronet_fmul (Coronet_i2f k) Coronet_fln2) }")
  lines.push("Coronet_flog1p = \\ x -> Coronet_flog (Coronet_fadd Coronet_fone x)")
  lines.push("Coronet_fsin = \\ x -> let k = Coronet_f2i (Coronet_fdiv x Coronet_ftwopi) in let r = Coronet_fsub x (Coronet_fmul (Coronet_i2f k) Coronet_ftwopi) in Coronet_fsin_taylor r (Coronet_fsqr r) 0# 10# r r")
  lines.push("Coronet_fcos = \\ x -> let k = Coronet_f2i (Coronet_fdiv x Coronet_ftwopi) in let r = Coronet_fsub x (Coronet_fmul (Coronet_i2f k) Coronet_ftwopi) in Coronet_fcos_taylor r (Coronet_fsqr r) 0# 11# Coronet_fone Coronet_fone")
  lines.push("Coronet_ftan = \\ x -> Coronet_fdiv (Coronet_fsin x) (Coronet_fcos x)")
  lines.push("Coronet_fatan = \\ x -> let ax = Coronet_fabs x in case gtInt# ax Coronet_fone of { 1# -> let s = Coronet_sign x in Coronet_fsub (Coronet_fmul (Coronet_i2f s) Coronet_fpi2) (Coronet_fatan (Coronet_fdiv Coronet_fone x)); __DEFAULT -> let y = Coronet_fdiv x (Coronet_fadd Coronet_fone (Coronet_fsqrt (Coronet_fadd Coronet_fone (Coronet_fsqr x)))) in Coronet_fmul Coronet_ftwo (Coronet_fatan_series y (Coronet_fsqr y) 0# 20# y y) }")
  lines.push("Coronet_fasin = \\ x -> let ax = Coronet_fabs x in case geInt# ax Coronet_fone of { 1# -> Coronet_fmul (Coronet_i2f (Coronet_sign x)) Coronet_fpi2; __DEFAULT -> Coronet_fatan (Coronet_fdiv x (Coronet_fsqrt (Coronet_fsub Coronet_fone (Coronet_fsqr x)))) }")
  lines.push("Coronet_facos = \\ x -> Coronet_fsub Coronet_fpi2 (Coronet_fasin x)")
  lines.push("Coronet_fsinh = \\ x -> Coronet_fmul (Coronet_fsub (Coronet_fexp x) (Coronet_fexp (Coronet_fneg x))) Coronet_fhalf")
  lines.push("Coronet_fcosh = \\ x -> Coronet_fmul (Coronet_fadd (Coronet_fexp x) (Coronet_fexp (Coronet_fneg x))) Coronet_fhalf")
  lines.push("Coronet_ftanh = \\ x -> Coronet_fdiv (Coronet_fsinh x) (Coronet_fcosh x)")
  lines.push("Coronet_fasinh = \\ x -> Coronet_flog (Coronet_fadd x (Coronet_fsqrt (Coronet_fadd (Coronet_fsqr x) Coronet_fone)))")
  lines.push("Coronet_facosh = \\ x -> Coronet_flog (Coronet_fadd x (Coronet_fsqrt (Coronet_fsub (Coronet_fsqr x) Coronet_fone)))")
  lines.push("Coronet_fatanh = \\ x -> Coronet_fmul Coronet_fhalf (Coronet_flog (Coronet_fdiv (Coronet_fadd Coronet_fone x) (Coronet_fsub Coronet_fone x)))")
  lines.push("Rec {")
  lines.push("Coronet_fpow_int = \\ x n acc -> case eqInt# n 0# of { 1# -> acc; __DEFAULT -> Coronet_fpow_int x (-# n 1#) (Coronet_fmul acc x) }")
  lines.push("end Rec }")
  lines.push("Coronet_fpow = \\ x y -> let yi = Coronet_f2i y in case Coronet_feq (Coronet_i2f yi) y of { 1# -> case geInt# yi 0# of { 1# -> Coronet_fpow_int x yi Coronet_fone; __DEFAULT -> Coronet_fdiv Coronet_fone (Coronet_fpow_int x (-# 0# yi) Coronet_fone) }; __DEFAULT -> Coronet_fexp (Coronet_fmul y (Coronet_flog x)) }")
  lines.push("Coronet_ffmadd = \\ a b c -> Coronet_fadd (Coronet_fmul a b) c")
  lines.push("Coronet_ffmsub = \\ a b c -> Coronet_fsub (Coronet_fmul a b) c")
  lines.push("Coronet_ffnmadd = \\ a b c -> Coronet_fneg (Coronet_fadd (Coronet_fmul a b) c)")
  lines.push("Coronet_ffnmsub = \\ a b c -> Coronet_fneg (Coronet_fsub (Coronet_fmul a b) c)")
  lines.push("Coronet_fdecode = \\ a -> Pair (-# a -2147483648#) -12#")
  lines.push("Coronet_fdecode2 = \\ a -> Tuple4 0# (-# a -2147483648#) -12# (case ltInt# a -2147483648# of { 1# -> 1#; __DEFAULT -> 0# })")
  lines.push("Coronet_fdecode64 = \\ a -> Pair (-# a -2147483648#) -12#")
  lines.push("Coronet_fork = \\ act -> \\ s -> case act s of { Pair s1 v -> Pair s1 0# }")
  lines.push("Coronet_forkOn = \\ tid -> \\ act -> \\ s -> case act s of { Pair s1 v -> Pair s1 0# }")
  lines.push("Coronet_yield = \\ s -> s")
  lines.push("Coronet_myThreadId = \\ s -> Pair s 0#")
  lines.push("Coronet_killThread = \\ tid -> \\ s -> s")
  lines.push("Coronet_par = \\ a -> \\ s -> Pair s a")
  lines.push("Coronet_actor_spawn = \\ body -> \\ init -> \\ s -> case newMVar# init s of { (# s1, box #) -> case Coronet_fork (\\ s -> body box s) s1 of { (# s2, tid #) -> (# s2, Pair box tid #) } }")
  lines.push("Coronet_actor_take = \\ addr -> \\ s -> case addr of { Pair box tid -> takeMVar# box s }")
  lines.push("Coronet_actor_put = \\ addr -> \\ val -> \\ s -> case addr of { Pair box tid -> putMVar# box val s }")
  lines.push("Rec {")
  lines.push("Coronet_setArray = \\ a off len val s -> case eqInt# len 0# of { 1# -> s; __DEFAULT -> Coronet_setArray a (+# off 1#) (-# len 1#) val (writeArray# a off val s) }")
  lines.push("Coronet_copyArray = \\ src so dst do len s -> case eqInt# len 0# of { 1# -> s; __DEFAULT -> case readArray# src so s of { (# s1, v #) -> Coronet_copyArray src (+# so 1#) dst (+# do 1#) (-# len 1#) (writeArray# dst do v s1) } }")
  lines.push("end Rec }")
  // Newton iteration, 12 rounds. `g` is a float, `n` counts down.
  lines.push("Rec {")
  lines.push("Coronet_fsqrt_iter = \\ x g n -> case n of { 0# -> g; _ -> Coronet_fsqrt_iter x (Coronet_fmul (Coronet_fadd g (Coronet_fdiv x g)) -2147481600#) (-# n 1#) }")
  lines.push("end Rec }")
  // 0.5 is not representable as an integer literal here; use e(0.5)=2048+bias
  // and divide by 2 via multiplication with that constant.
  lines.push("Coronet_fsqrt = \\ x -> case leInt# x -2147483648# of { 1# -> Coronet_fzero; __DEFAULT -> Coronet_fsqrt_iter x x 12# }")
  let mut out = ""
  for line in lines {
    out = out + line + "\n"
  }
  out
}

fn bigint_prelude() -> String {
  let lines : Array[String] = []
  lines.push("Rec {")
  lines.push("badd = \\ x y -> case x of { BNil -> y; BCons hx tx -> case y of { BNil -> x; BCons hy ty -> let s = +# hx hy in case geInt# s 1000# of { 1# -> badd (BCons 1# BNil) (BCons (-# s 1000#) (badd tx ty)); __DEFAULT -> BCons s (badd tx ty) } } }")
  lines.push("bmd = \\ d x c -> case x of { BNil -> case eqInt# c 0# of { 1# -> BNil; __DEFAULT -> BCons c BNil }; BCons h t -> let p = +# (*# h d) c in BCons (remInt# p 1000#) (bmd d t (quotInt# p 1000#)) }")
  lines.push("bmul_digit = \\ d x -> bmd d x 0#")
  lines.push("bmul = \\ x y -> case y of { BNil -> BNil; BCons h t -> badd (bmul_digit h x) (BCons 0# (bmul x t)) }")
  lines.push("bfromint = \\ n -> case ltInt# n 1000# of { 1# -> BCons n BNil; __DEFAULT -> BCons (remInt# n 1000#) (bfromint (quotInt# n 1000#)) }")
  lines.push("btoint = \\ x -> btoint_acc x 0# 1#")
  lines.push("btoint_acc = \\ x acc p -> case x of { BNil -> acc; BCons h t -> btoint_acc t (+# acc (*# h p)) (*# p 1000#) }")
  lines.push("bfromdec_acc = \\ xs acc -> case xs of { BNil -> acc; BCons h t -> bfromdec_acc t (badd (bmul acc (bfromint 1000000000#)) (bfromint h)) }")
  lines.push("bfromdec = \\ xs -> bfromdec_acc xs BNil")
  lines.push("end Rec }")
  let mut out = ""
  for line in lines {
    out = out + line + "\n"
  }
  out
}

fn bigrat_prelude() -> String {
  let lines : Array[String] = []
  lines.push(prelude())
  lines.push(bigint_prelude())
  lines.push("Rec {")
  lines.push("bineg = \\ a -> case a of { Pair s m -> Pair (-# 1# s) m }")
  lines.push("bsign = \\ a -> case a of { Pair s m -> case bstrip m of { BNil -> 0#; _ -> -# 1# (*# 2# s) } }")
  lines.push("bstrip = \\ x -> case x of { BNil -> BNil; BCons h t -> let r = bstrip t in case r of { BNil -> case eqInt# h 0# of { 1# -> BNil; __DEFAULT -> BCons h BNil }; _ -> BCons h r } }")
  lines.push("bsubb = \\ x y b -> case x of { BNil -> BNil; BCons hx tx -> let yh = case y of { BNil -> 0#; BCons h t -> h } in let yt = case y of { BNil -> BNil; BCons h t -> t } in let d = -# (-# hx yh) b in case ltInt# d 0# of { 1# -> BCons (+# d 1000#) (bsubb tx yt 1#); __DEFAULT -> BCons d (bsubb tx yt 0#) } }")
  lines.push("bsub = \\ x y -> bstrip (bsubb x y 0#)")
  lines.push("bcmp = \\ x y -> case x of { BNil -> case y of { BNil -> 0#; _ -> -1# }; BCons hx tx -> case y of { BNil -> 1#; BCons hy ty -> case ltInt# hx hy of { 1# -> -1#; _ -> case gtInt# hx hy of { 1# -> 1#; _ -> bcmp tx ty } } } }")
  lines.push("biadd = \\ a b -> case a of { Pair sa ma -> case b of { Pair sb mb -> case eqInt# sa sb of { 1# -> Pair sa (badd ma mb); __DEFAULT -> case bcmp ma mb of { 1# -> Pair sa (bsub ma mb); 0# -> Pair 0# BNil; __DEFAULT -> Pair sb (bsub mb ma) } } } }")
  lines.push("bimul = \\ a b -> case a of { Pair sa ma -> case b of { Pair sb mb -> Pair (xor# sa sb) (bmul ma mb) } }")
  lines.push("bisub = \\ a b -> biadd a (bineg b)")
  lines.push("bicmp = \\ a b -> bsign (bisub a b)")
  lines.push("bifromint = \\ n -> case ltInt# n 0# of { 1# -> Pair 1# (bfromint (-# 0# n)); __DEFAULT -> Pair 0# (bfromint n) }")
  lines.push("btoint = \\ a -> case a of { Pair s m -> let v = btoint_acc m 0# 1# in -# v (*# 2# (*# s v)) }")
  lines.push("brnorm = \\ n d -> case d of { Pair sd md -> case eqInt# sd 1# of { 1# -> Pair (bineg n) (bineg d); __DEFAULT -> Pair n d } }")
  lines.push("bradd = \\ a b -> case a of { Pair n1 d1 -> case b of { Pair n2 d2 -> brnorm (biadd (bimul n1 d2) (bimul n2 d1)) (bimul d1 d2) } }")
  lines.push("brsub = \\ a b -> bradd a (Pair (bineg (case b of { Pair n d -> n })) (case b of { Pair n d -> d }))")
  lines.push("brmul = \\ a b -> case a of { Pair n1 d1 -> case b of { Pair n2 d2 -> brnorm (bimul n1 n2) (bimul d1 d2) } }")
  lines.push("brdiv = \\ a b -> case a of { Pair n1 d1 -> case b of { Pair n2 d2 -> brnorm (bimul n1 d2) (bimul d1 n2) } }")
  lines.push("brneg = \\ a -> case a of { Pair n d -> Pair (bineg n) d }")
  lines.push("brcmp = \\ a b -> case a of { Pair n1 d1 -> case b of { Pair n2 d2 -> bicmp (bimul n1 d2) (bimul n2 d1) } }")
  lines.push("breq = \\ a b -> case brcmp a b of { 0# -> 1#; __DEFAULT -> 0# }")
  lines.push("brne = \\ a b -> case brcmp a b of { 0# -> 0#; __DEFAULT -> 1# }")
  lines.push("brlt = \\ a b -> case brcmp a b of { 1# -> 0#; 0# -> 0#; __DEFAULT -> 1# }")
  lines.push("brle = \\ a b -> case brcmp a b of { 1# -> 0#; __DEFAULT -> 1# }")
  lines.push("brgt = \\ a b -> case brcmp a b of { 1# -> 1#; __DEFAULT -> 0# }")
  lines.push("brge = \\ a b -> case brcmp a b of { 1# -> 1#; 0# -> 1#; __DEFAULT -> 0# }")
  lines.push("brfromint = \\ n -> Pair (bifromint n) (Pair 0# (BCons 1# BNil))")
  lines.push("brabs = \\ a -> case a of { Pair n d -> case n of { Pair s m -> Pair (Pair 0# m) d } }")
  lines.push("brtoint = \\ a -> case a of { Pair n d -> case n of { Pair sn mn -> case d of { Pair sd md -> let nv = btoint_acc mn 0# 1# in let dv = btoint_acc md 0# 1# in let q = quotInt# nv dv in -# q (*# 2# (*# sn q)) } } }")
  lines.push("isqrt_iter = \\ x g n -> case n of { 0# -> g; __DEFAULT -> isqrt_iter x (quotInt# (+# g (quotInt# x g)) 2#) (-# n 1#) }")
  lines.push("isqrt = \\ x -> isqrt_iter x x 16#")
  lines.push("brsqrt = \\ a -> case a of { Pair n d -> case n of { Pair sn mn -> case d of { Pair sd md -> let p = btoint_acc mn 0# 1# in let q = btoint_acc md 0# 1# in Pair (Pair 0# (bfromint (isqrt (*# p q)))) (Pair 0# (bfromint q)) } } }")
  lines.push("brmax = \\ a b -> case brge a b of { 1# -> a; __DEFAULT -> b }")
  lines.push("brmin = \\ a b -> case brle a b of { 1# -> a; __DEFAULT -> b }")
  lines.push("brtofixed = \\ a -> case a of { Pair n d -> case n of { Pair sn mn -> case d of { Pair sd md -> let nv = btoint_acc mn 0# 1# in let dv = btoint_acc md 0# 1# in let q = quotInt# (*# nv 4096#) dv in let sq = -# q (*# 2# (*# (xor# sn sd) q)) in +# sq -2147483648# } } }")
  lines.push("brfromfixed = \\ f -> Pair (bifromint (-# f -2147483648#)) (Pair 0# (bfromint 4096#))")
  lines.push("brexp = \\ x -> brfromfixed (Coronet_fexp (brtofixed x))")
  lines.push("brexpm1 = \\ x -> brfromfixed (Coronet_fexpm1 (brtofixed x))")
  lines.push("brlog = \\ x -> brfromfixed (Coronet_flog (brtofixed x))")
  lines.push("brlog1p = \\ x -> brfromfixed (Coronet_flog1p (brtofixed x))")
  lines.push("brsin = \\ x -> brfromfixed (Coronet_fsin (brtofixed x))")
  lines.push("brcos = \\ x -> brfromfixed (Coronet_fcos (brtofixed x))")
  lines.push("brtan = \\ x -> brfromfixed (Coronet_ftan (brtofixed x))")
  lines.push("brasin = \\ x -> brfromfixed (Coronet_fasin (brtofixed x))")
  lines.push("bracos = \\ x -> brfromfixed (Coronet_facos (brtofixed x))")
  lines.push("bratan = \\ x -> brfromfixed (Coronet_fatan (brtofixed x))")
  lines.push("brsinh = \\ x -> brfromfixed (Coronet_fsinh (brtofixed x))")
  lines.push("brcosh = \\ x -> brfromfixed (Coronet_fcosh (brtofixed x))")
  lines.push("brtanh = \\ x -> brfromfixed (Coronet_ftanh (brtofixed x))")
  lines.push("brasinh = \\ x -> brfromfixed (Coronet_fasinh (brtofixed x))")
  lines.push("bracosh = \\ x -> brfromfixed (Coronet_facosh (brtofixed x))")
  lines.push("bratanh = \\ x -> brfromfixed (Coronet_fatanh (brtofixed x))")
  lines.push("brpow = \\ x y -> brfromfixed (Coronet_fpow (brtofixed x) (brtofixed y))")
  lines.push("brfmadd = \\ a b c -> brfromfixed (Coronet_ffmadd (brtofixed a) (brtofixed b) (brtofixed c))")
  lines.push("brfmsub = \\ a b c -> brfromfixed (Coronet_ffmsub (brtofixed a) (brtofixed b) (brtofixed c))")
  lines.push("brfnmadd = \\ a b c -> brfromfixed (Coronet_ffnmadd (brtofixed a) (brtofixed b) (brtofixed c))")
  lines.push("brfnmsub = \\ a b c -> brfromfixed (Coronet_ffnmsub (brtofixed a) (brtofixed b) (brtofixed c))")
  lines.push("brdecode = \\ a -> Pair (-# a -2147483648#) -12#")
  lines.push("brdecode2 = \\ a -> Tuple4 0# (-# a -2147483648#) -12# (case ltInt# a -2147483648# of { 1# -> 1#; __DEFAULT -> 0# })")
  lines.push("brdecode64 = \\ a -> Pair (-# a -2147483648#) -12#")
  lines.push("end Rec }")
  let mut out = ""
  for line in lines {
    out = out + line + "\n"
  }
  out
}

fn usage() -> Unit {
  println("Usage: coronet-opt <input.core> -o <output.core> [--target hvm3|hvm2]")
  println("  Rewrites CoreLite for the semantic plugin prelude.")
  println("  hvm3: software Q4.12 float; hvm2: pass-through (native F24).")
  println("  --bigint: include the base-1000 arbitrary-precision integer prelude.")
  println("  --bigrat: exact arbitrary-precision rational floats (implies --bigint).")
  println("  --mid: run the shared CAF/rebuild/inline middle-end pass.")
  println("  --sched: sequential cooperative fork/yield scheduler (no true parallelism).")
}

async fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    return
  }
  let mut input = ""
  let mut output = ""
  let mut target = "hvm3"
  let mut bigint = false
  let mut bigrat = false
  let mut use_mid = false
  let mut use_sched = false
  let mut i = 1
  while i < args.length() {
    let a = args[i]
    if a == "-o" && i + 1 < args.length() {
      output = args[i + 1]
      i = i + 2
    } else if a == "--target" && i + 1 < args.length() {
      target = args[i + 1]
      i = i + 2
    } else if a == "--bigint" {
      bigint = true
      i = i + 1
    } else if a == "--bigrat" {
      bigrat = true
      i = i + 1
    } else if a == "--mid" {
      use_mid = true
      i = i + 1
    } else if a == "--sched" {
      use_sched = true
      i = i + 1
    } else if input == "" {
      input = a
      i = i + 1
    } else {
      i = i + 1
    }
  }
  if input == "" {
    usage()
    return
  }
  let src = @fs.read_text(input)
  let prog = match @syntax.parse_core(src) {
    Ok(p) => p
    Err(e) => {
      println("parse error: " + e)
      return
    }
  }
  let prog = if use_mid { @mid.optimize(prog, @mid.MidStats::new()) } else { prog }
  let gc = gc_prims(prog)
  if gc.length() > 0 {
    println("coronet-opt: GC/weak/compact primops need a tracing heap and are not supported:")
    for name in gc { println("  " + name) }
    println("HVM has no heap roots, so weak pointers/finalizers cannot be made correct in a .core transform.")
    return
  }
  if target == "hvm3" {
    let unknown = unknown_float_ops(prog)
    if unknown.length() > 0 {
      println("coronet-opt: unsupported float primops for HVM3:")
      for name in unknown { println("  " + name) }
      println("Add them to cmd/opt/main.mbt's float prelude; refusing to emit a silent zero.")
      return
    }
  }
  let rewritten0 = if bigrat {
    rewrite_program_br(prog)
  } else if target == "hvm3" {
    rewrite_program(prog)
  } else {
    prog
  }
  let rewritten1 = if use_sched { rewrite_program_sched(rewritten0) } else { rewritten0 }
  let rewritten = if target == "hvm3" { rewrite_program_arrays(rewritten1) } else { rewritten1 }
  let body = rewritten.to_string()
  let text = if target == "hvm3" {
    (if bigrat { bigrat_prelude() } else { prelude() + (if bigint { bigint_prelude() } else { "" }) }) + "\n" + body + "\n"
  } else {
    (if bigrat { bigrat_prelude() } else if bigint { bigint_prelude() } else { "" }) + body + "\n"
  }
  if output == "" {
    println(text)
  } else {
    @fs.write_text(output, text)
  }
}
