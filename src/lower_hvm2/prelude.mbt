///| Builtin runtime net definitions for HVM2

// ----------------------------------------------------------------------------
// Builtin Primitives & Scott Constructor Generation
// ----------------------------------------------------------------------------

fn LowerCtx::add_builtin_prims(self : LowerCtx) -> Unit {
  // @prim_add = (a (b ret)) & a ~ $([+] $(b ret))
  // Build an F24 value from a rational literal without a float-literal parser
  // hook: cast both integers to F24, then divide. Small literals stay exact
  // enough for F24, and the value is a real F24 from here on.
  self.add_def("float_ratio", Net::{
    root: Con(Var("n"), Con(Var("d"), Var("ret"))),
    redexes: [
      { fst: Var("n"), snd: Opr(OpSym("[f24]"), Var("n_f")) },
      { fst: Var("d"), snd: Opr(OpSym("[f24]"), Var("d_f")) },
      { fst: Var("n_f"), snd: Opr(OpSym("[/]"), Opr(Var("d_f"), Var("ret"))) },
    ],
  })
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

  // @prim_and = (a (b ret)) & a ~ $([&] $(b ret))
  self.add_def("prim_and", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[&]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @prim_or = (a (b ret)) & a ~ $([|] $(b ret))
  self.add_def("prim_or", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[|]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @prim_xor = (a (b ret)) & a ~ $([^] $(b ret))
  self.add_def("prim_xor", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[^]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @prim_shl = (a (b ret)) & a ~ $([<<] $(b ret))
  self.add_def("prim_shl", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[<<]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @prim_shr = (a (b ret)) & a ~ $([>>] $(b ret))
  self.add_def("prim_shr", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[>>]"), Opr(Var("b"), Var("ret"))) },
    ],
  })

  // @I_hash = (x x)
  self.add_def("I_hash", Net::{
    root: Con(Var("x"), Var("x")),
    redexes: [],
  })

  // Runtime error fallbacks
  self.add_def("divZeroError", Net::{ root: Num(0), redexes: [] })
  self.add_def("overflowError", Net::{ root: Num(0), redexes: [] })

  // Word32 addition dictionary method fallback: @_fNumWord32__c = (dict (a (b ret))) & a ~ $([+] $(b ret))
  self.add_def("_fNumWord32__c", Net::{
    root: Con(Era, Con(Var("a"), Con(Var("b"), Var("ret")))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[+]"), Opr(Var("b"), Var("ret"))) }
    ]
  })

  // Signed 24-bit arithmetic and comparison primitives
  self.add_def("slt", Net::{
    root: Con(Var("x"), Con(Var("y"), Var("ret"))),
    redexes: [
      { fst: Var("x"), snd: Opr(OpSym("[>>]"), Opr(Num(23), Var("sx"))) },
      { fst: Var("y"), snd: Opr(OpSym("[>>]"), Opr(Num(23), Var("sy"))) },
      { fst: Var("sx"), snd: Opr(OpSym("[!]"), Opr(Var("sy"), Var("diff_sign"))) },
      {
        fst: Var("diff_sign"),
        snd: Swi(
          Con(Ref("slt_same"), Ref("slt_diff")),
          Con(Var("x"), Con(Var("y"), Con(Var("sx"), Var("ret"))))
        ),
      },
    ],
  })
  self.add_def("slt_same", Net::{
    root: Con(Var("x"), Con(Var("y"), Con(Era, Var("ret")))),
    redexes: [
      { fst: Var("x"), snd: Opr(OpSym("[<]"), Opr(Var("y"), Var("ret"))) },
    ],
  })
  self.add_def("slt_diff", Net::{
    root: Con(Era, Con(Era, Con(Era, Con(Var("sx"), Var("ret"))))),
    redexes: [
      { fst: Var("sx"), snd: Var("ret") },
    ],
  })

  self.add_def("sra", Net::{
    root: Con(Var("x"), Con(Var("y"), Var("ret"))),
    redexes: [
      { fst: Var("x"), snd: Opr(OpSym("[>>]"), Opr(Num(23), Var("sx"))) },
      {
        fst: Var("sx"),
        snd: Swi(
          Con(Ref("sra_pos"), Ref("sra_neg")),
          Con(Var("x"), Con(Var("y"), Var("ret")))
        ),
      },
    ],
  })
  self.add_def("sra_pos", Net::{
    root: Con(Var("x"), Con(Var("y"), Var("ret"))),
    redexes: [
      { fst: Var("x"), snd: Opr(OpSym("[>>]"), Opr(Var("y"), Var("ret"))) },
    ],
  })
  self.add_def("sra_neg", Net::{
    root: Con(Era, Con(Var("x"), Con(Var("y"), Var("ret")))),
    redexes: [
      { fst: Var("x"), snd: Opr(OpSym("[>>]"), Opr(Var("y"), Var("shr_x"))) },
      { fst: Num(16777215), snd: Opr(OpSym("[>>]"), Opr(Var("y"), Var("shr_mask"))) },
      { fst: Num(16777215), snd: Opr(OpSym("[^]"), Opr(Var("shr_mask"), Var("sign_fill"))) },
      { fst: Var("shr_x"), snd: Opr(OpSym("[|]"), Opr(Var("sign_fill"), Var("ret"))) },
    ],
  })

  self.add_def("abs24", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [
      { fst: Var("x"), snd: Opr(OpSym("[>>]"), Opr(Num(23), Var("sx"))) },
      { fst: Var("sx"), snd: Swi(Con(Ref("id24"), Ref("neg24")), Con(Var("x"), Var("ret"))) },
    ],
  })
  self.add_def("id24", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [{ fst: Var("x"), snd: Var("ret") }],
  })
  self.add_def("neg24", Net::{
    root: Con(Era, Con(Var("x"), Var("ret"))),
    redexes: [{ fst: Num(0), snd: Opr(OpSym("[-]"), Opr(Var("x"), Var("ret"))) }],
  })

  self.add_def("sdiv", Net::{
    root: Con(Var("x"), Con(Var("y"), Var("ret"))),
    redexes: [
      { fst: Var("x"), snd: Opr(OpSym("[>>]"), Opr(Num(23), Var("sx"))) },
      { fst: Var("y"), snd: Opr(OpSym("[>>]"), Opr(Num(23), Var("sy"))) },
      { fst: Var("sx"), snd: Opr(OpSym("[^]"), Opr(Var("sy"), Var("sign"))) },
      { fst: Ref("abs24"), snd: Con(Var("x"), Var("ax")) },
      { fst: Ref("abs24"), snd: Con(Var("y"), Var("ay")) },
      { fst: Var("ax"), snd: Opr(OpSym("[/]"), Opr(Var("ay"), Var("q"))) },
      { fst: Var("sign"), snd: Swi(Con(Ref("id24"), Ref("neg24")), Con(Var("q"), Var("ret"))) },
    ],
  })

  self.add_def("srem", Net::{
    root: Con(Var("x"), Con(Var("y"), Var("ret"))),
    redexes: [
      { fst: Var("x"), snd: Opr(OpSym("[>>]"), Opr(Num(23), Var("sx"))) },
      { fst: Ref("abs24"), snd: Con(Var("x"), Var("ax")) },
      { fst: Ref("abs24"), snd: Con(Var("y"), Var("ay")) },
      { fst: Var("ax"), snd: Opr(OpSym("[%]"), Opr(Var("ay"), Var("r"))) },
      { fst: Var("sx"), snd: Swi(Con(Ref("id24"), Ref("neg24")), Con(Var("r"), Var("ret"))) },
    ],
  })

  // @add64 = (a (b ret))
  self.add_def("add64", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Con(Var("a_hi"), Var("a_lo")) },
      { fst: Var("b"), snd: Con(Var("b_hi"), Var("b_lo")) },
      { fst: Var("a_lo"), snd: Opr(OpSym("[+]"), Opr(Var("b_lo"), Var("sum_lo"))) },
      { fst: Var("sum_lo"), snd: Opr(OpSym("[<]"), Opr(Var("a_lo"), Var("carry"))) },
      { fst: Var("a_hi"), snd: Opr(OpSym("[+]"), Opr(Var("b_hi"), Var("sum_hi"))) },
      { fst: Var("sum_hi"), snd: Opr(OpSym("[+]"), Opr(Var("carry"), Var("res_hi"))) },
      { fst: Var("ret"), snd: Con(Var("res_hi"), Var("sum_lo")) },
    ],
  })

  // @sub64 = (a (b ret))
  self.add_def("sub64", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Con(Var("a_hi"), Var("a_lo")) },
      { fst: Var("b"), snd: Con(Var("b_hi"), Var("b_lo")) },
      { fst: Var("a_lo"), snd: Opr(OpSym("[-]"), Opr(Var("b_lo"), Var("diff_lo"))) },
      { fst: Var("a_lo"), snd: Opr(OpSym("[<]"), Opr(Var("b_lo"), Var("borrow"))) },
      { fst: Var("a_hi"), snd: Opr(OpSym("[-]"), Opr(Var("b_hi"), Var("diff_hi"))) },
      { fst: Var("diff_hi"), snd: Opr(OpSym("[-]"), Opr(Var("borrow"), Var("res_hi"))) },
      { fst: Var("ret"), snd: Con(Var("res_hi"), Var("diff_lo")) },
    ],
  })

  // @mul64 = (a (b ret))
  self.add_def("mul64", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Con(Var("a_hi"), Var("a_lo")) },
      { fst: Var("b"), snd: Con(Var("b_hi"), Var("b_lo")) },
      { fst: Var("a_hi"), snd: Opr(OpSym("[*]"), Opr(Var("b_lo"), Var("hi_term1"))) },
      { fst: Var("a_lo"), snd: Opr(OpSym("[*]"), Opr(Var("b_hi"), Var("hi_term2"))) },
      { fst: Var("hi_term1"), snd: Opr(OpSym("[+]"), Opr(Var("hi_term2"), Var("hi_terms"))) },
      { fst: Var("a_lo"), snd: Opr(OpSym("[>>]"), Opr(Num(12), Var("a_hi12"))) },
      { fst: Var("a_lo"), snd: Opr(OpSym("[&]"), Opr(Num(4095), Var("a_lo12"))) },
      { fst: Var("b_lo"), snd: Opr(OpSym("[>>]"), Opr(Num(12), Var("b_hi12"))) },
      { fst: Var("b_lo"), snd: Opr(OpSym("[&]"), Opr(Num(4095), Var("b_lo12"))) },
      { fst: Var("a_lo12"), snd: Opr(OpSym("[*]"), Opr(Var("b_lo12"), Var("p0"))) },
      { fst: Var("a_hi12"), snd: Opr(OpSym("[*]"), Opr(Var("b_lo12"), Var("p1a"))) },
      { fst: Var("a_lo12"), snd: Opr(OpSym("[*]"), Opr(Var("b_hi12"), Var("p1b"))) },
      { fst: Var("a_hi12"), snd: Opr(OpSym("[*]"), Opr(Var("b_hi12"), Var("p2"))) },
      { fst: Var("p0"), snd: Opr(OpSym("[>>]"), Opr(Num(12), Var("p0_hi"))) },
      { fst: Var("p0"), snd: Opr(OpSym("[&]"), Opr(Num(4095), Var("p0_lo"))) },
      { fst: Var("p1a"), snd: Opr(OpSym("[&]"), Opr(Num(4095), Var("p1a_lo"))) },
      { fst: Var("p1a"), snd: Opr(OpSym("[>>]"), Opr(Num(12), Var("p1a_hi"))) },
      { fst: Var("p1b"), snd: Opr(OpSym("[&]"), Opr(Num(4095), Var("p1b_lo"))) },
      { fst: Var("p1b"), snd: Opr(OpSym("[>>]"), Opr(Num(12), Var("p1b_hi"))) },
      { fst: Var("p0_hi"), snd: Opr(OpSym("[+]"), Opr(Var("p1a_lo"), Var("mid_part1"))) },
      { fst: Var("mid_part1"), snd: Opr(OpSym("[+]"), Opr(Var("p1b_lo"), Var("mid_lo"))) },
      { fst: Var("mid_lo"), snd: Opr(OpSym("[>>]"), Opr(Num(12), Var("mid_carry"))) },
      { fst: Var("mid_lo"), snd: Opr(OpSym("[&]"), Opr(Num(4095), Var("mid_bits"))) },
      { fst: Var("mid_bits"), snd: Opr(OpSym("[<<]"), Opr(Num(12), Var("mid_shifted"))) },
      { fst: Var("p0_lo"), snd: Opr(OpSym("[|]"), Opr(Var("mid_shifted"), Var("res_lo"))) },
      { fst: Var("p2"), snd: Opr(OpSym("[+]"), Opr(Var("p1a_hi"), Var("carry_part1"))) },
      { fst: Var("carry_part1"), snd: Opr(OpSym("[+]"), Opr(Var("p1b_hi"), Var("carry_part2"))) },
      { fst: Var("carry_part2"), snd: Opr(OpSym("[+]"), Opr(Var("mid_carry"), Var("carry_to_hi"))) },
      { fst: Var("carry_to_hi"), snd: Opr(OpSym("[+]"), Opr(Var("hi_terms"), Var("res_hi"))) },
      { fst: Var("ret"), snd: Con(Var("res_hi"), Var("res_lo")) },
    ],
  })

  // Raytracer scaled integer square root: @isqrt1000
  self.add_def("div1000", Net::{
    root: Con(Var("n"), Con(Var("x"), Var("ret"))),
    redexes: [
      { fst: Var("n"), snd: Opr(OpSym("[%]"), Opr(Var("x"), Var("r"))) },
      { fst: Var("n"), snd: Opr(OpSym("[/]"), Opr(Var("x"), Var("q"))) },
      { fst: Var("r"), snd: Opr(OpSym("[*]"), Opr(Num(125), Var("t"))) },
      { fst: Var("t"), snd: Opr(OpSym("[/]"), Opr(Var("x"), Var("qt"))) },
      { fst: Var("t"), snd: Opr(OpSym("[%]"), Opr(Var("x"), Var("rt"))) },
      { fst: Var("qt"), snd: Opr(OpSym("[*]"), Opr(Num(8), Var("qt8"))) },
      { fst: Var("rt"), snd: Opr(OpSym("[*]"), Opr(Num(8), Var("rt8"))) },
      { fst: Var("rt8"), snd: Opr(OpSym("[/]"), Opr(Var("x"), Var("rem_rt"))) },
      { fst: Var("qt8"), snd: Opr(OpSym("[+]"), Opr(Var("rem_rt"), Var("rem_part"))) },
      { fst: Var("q"), snd: Opr(OpSym("[*]"), Opr(Num(1000), Var("q1000"))) },
      { fst: Var("q1000"), snd: Opr(OpSym("[+]"), Opr(Var("rem_part"), Var("ret"))) },
    ],
  })

  self.add_def("isqrt1000_step", Net::{
    root: Con(Var("n"), Con(Var("x"), Var("ret"))),
    redexes: [
      { fst: Ref("div1000"), snd: Con(Var("n"), Con(Var("x"), Var("div_res"))) },
      { fst: Var("x"), snd: Opr(OpSym("[+]"), Opr(Var("div_res"), Var("sum"))) },
      { fst: Var("sum"), snd: Opr(OpSym("[>>]"), Opr(Num(1), Var("nxt"))) },
      { fst: Ref("slt"), snd: Con(Var("nxt"), Con(Var("x"), Var("is_less"))) },
      {
        fst: Var("is_less"),
        snd: Swi(Con(Ref("isqrt1000_done"), Ref("isqrt1000_loop")), Con(Var("n"), Con(Var("nxt"), Con(Var("x"), Var("ret"))))),
      },
    ],
  })

  self.add_def("isqrt1000_done", Net::{
    root: Con(Era, Con(Era, Con(Var("x"), Var("ret")))),
    redexes: [{ fst: Var("x"), snd: Var("ret") }],
  })

  self.add_def("isqrt1000_loop", Net::{
    root: Con(Era, Con(Var("n"), Con(Var("nxt"), Con(Era, Var("ret"))))),
    redexes: [{ fst: Ref("isqrt1000_step"), snd: Con(Var("n"), Con(Var("nxt"), Var("ret"))) }],
  })

  self.add_def("isqrt1000", Net::{
    root: Con(Var("n"), Var("ret")),
    redexes: [
      { fst: Ref("slt"), snd: Con(Num(0), Con(Var("n"), Var("is_pos"))) },
      { fst: Var("is_pos"), snd: Swi(Con(Ref("isqrt1000_zero"), Ref("isqrt1000_pos")), Con(Var("n"), Var("ret"))) },
    ],
  })

  self.add_def("isqrt1000_zero", Net::{
    root: Con(Era, Con(Era, Var("ret"))),
    redexes: [{ fst: Num(0), snd: Var("ret") }],
  })

  self.add_def("isqrt1000_pos", Net::{
    root: Con(Era, Con(Var("n"), Var("ret"))),
    redexes: [
      { fst: Ref("isqrt"), snd: Con(Var("n"), Var("sqrt_n")) },
      { fst: Var("sqrt_n"), snd: Opr(OpSym("[*]"), Opr(Num(32), Var("s32"))) },
      { fst: Var("s32"), snd: Opr(OpSym("[+]"), Opr(Num(32), Var("x0"))) },
      { fst: Ref("isqrt1000_step"), snd: Con(Var("n"), Con(Var("x0"), Var("ret"))) },
    ],
  })

  self.add_def("isqrt", Net::{
    root: Con(Var("n"), Var("ret")),
    redexes: [
      { fst: Ref("slt"), snd: Con(Num(0), Con(Var("n"), Var("is_pos"))) },
      { fst: Var("is_pos"), snd: Swi(Con(Ref("isqrt_zero"), Ref("isqrt_pos")), Con(Var("n"), Var("ret"))) },
    ],
  })

  self.add_def("isqrt_zero", Net::{
    root: Con(Era, Con(Era, Var("ret"))),
    redexes: [{ fst: Num(0), snd: Var("ret") }],
  })

  self.add_def("isqrt_pos", Net::{
    root: Con(Era, Con(Var("n"), Var("ret"))),
    redexes: [
      { fst: Var("n"), snd: Opr(OpSym("[>>]"), Opr(Num(1), Var("half_n"))) },
      { fst: Var("half_n"), snd: Opr(OpSym("[+]"), Opr(Num(1), Var("x0"))) },
      { fst: Ref("isqrt_step"), snd: Con(Var("x0"), Con(Var("n"), Var("ret"))) },
    ],
  })

  self.add_def("isqrt_step", Net::{
    root: Con(Var("x"), Con(Var("n"), Var("ret"))),
    redexes: [
      { fst: Var("n"), snd: Opr(OpSym("[/]"), Opr(Var("x"), Var("div_res"))) },
      { fst: Var("x"), snd: Opr(OpSym("[+]"), Opr(Var("div_res"), Var("sum"))) },
      { fst: Var("sum"), snd: Opr(OpSym("[>>]"), Opr(Num(1), Var("nxt"))) },
      { fst: Ref("slt"), snd: Con(Var("nxt"), Con(Var("x"), Var("is_less"))) },
      {
        fst: Var("is_less"),
        snd: Swi(Con(Ref("isqrt_done"), Ref("isqrt_loop")), Con(Var("n"), Con(Var("nxt"), Con(Var("x"), Var("ret"))))),
      },
    ],
  })

  self.add_def("isqrt_done", Net::{
    root: Con(Era, Con(Era, Con(Var("x"), Var("ret")))),
    redexes: [{ fst: Var("x"), snd: Var("ret") }],
  })

  self.add_def("isqrt_loop", Net::{
    root: Con(Era, Con(Var("n"), Con(Var("nxt"), Con(Era, Var("ret"))))),
    redexes: [{ fst: Ref("isqrt_step"), snd: Con(Var("nxt"), Con(Var("n"), Var("ret"))) }],
  })

  // Raytracer modular arithmetic modulo 10^9 + 7: (59, 10144263) in radix 2^24
  self.add_def("add_mod", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Con(Var("a_hi"), Var("a_lo")) },
      { fst: Var("b"), snd: Con(Var("b_hi"), Var("b_lo")) },
      { fst: Var("a_lo"), snd: Opr(OpSym("[+]"), Opr(Var("b_lo"), Var("sum_lo"))) },
      { fst: Var("sum_lo"), snd: Opr(OpSym("[<]"), Opr(Var("a_lo"), Var("carry"))) },
      { fst: Var("a_hi"), snd: Opr(OpSym("[+]"), Opr(Var("b_hi"), Var("sum_hi1"))) },
      { fst: Var("sum_hi1"), snd: Opr(OpSym("[+]"), Opr(Var("carry"), Var("sum_hi"))) },
      { fst: Ref("ge_mod"), snd: Con(Var("sum_hi"), Con(Var("sum_lo"), Var("is_ge"))) },
      {
        fst: Var("is_ge"),
        snd: Swi(Con(Ref("sub_mod_no"), Ref("sub_mod_yes")), Con(Var("sum_hi"), Con(Var("sum_lo"), Var("ret")))),
      },
    ],
  })

  self.add_def("sub_mod_no", Net::{
    root: Con(Var("hi"), Con(Var("lo"), Var("ret"))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("hi"), Var("lo")) }],
  })

  self.add_def("sub_mod_yes", Net::{
    root: Con(Era, Con(Var("hi"), Con(Var("lo"), Var("ret")))),
    redexes: [
      { fst: Var("lo"), snd: Opr(OpSym("[<]"), Opr(Num(10144263), Var("borrow"))) },
      { fst: Var("lo"), snd: Opr(OpSym("[-]"), Opr(Num(10144263), Var("res_lo"))) },
      { fst: Var("hi"), snd: Opr(OpSym("[-]"), Opr(Num(59), Var("diff_hi"))) },
      { fst: Var("diff_hi"), snd: Opr(OpSym("[-]"), Opr(Var("borrow"), Var("res_hi"))) },
      { fst: Var("ret"), snd: Con(Var("res_hi"), Var("res_lo")) },
    ],
  })

  self.add_def("ge_mod", Net::{
    root: Con(Var("hi"), Con(Var("lo"), Var("ret"))),
    redexes: [
      { fst: Var("hi"), snd: Opr(OpSym("[<]"), Opr(Num(59), Var("lt59"))) },
      {
        fst: Var("lt59"),
        snd: Swi(Con(Ref("check_gt59"), Ref("ret_zero")), Con(Var("hi"), Con(Var("lo"), Var("ret")))),
      },
    ],
  })

  self.add_def("ret_zero", Net::{
    root: Con(Era, Con(Era, Con(Era, Var("ret")))),
    redexes: [{ fst: Num(0), snd: Var("ret") }],
  })

  // reallyUnsafePtrEquality# a b = 0#. Pointer identity is not observable in a
  // pure net, and GHC only promises that True implies equality, so False is
  // always sound. Programs keep working; some identity fast paths just stop
  // short-circuiting.
  self.add_def("reallyUnsafePtrEquality_hash", Net::{
    root: Con(Era, Con(Era, Var("ret"))),
    redexes: [{ fst: Num(0), snd: Var("ret") }],
  })

  self.add_def("check_gt59", Net::{
    root: Con(Var("hi"), Con(Var("lo"), Var("ret"))),
    redexes: [
      { fst: Num(59), snd: Opr(OpSym("[<]"), Opr(Var("hi"), Var("gt59"))) },
      { fst: Var("gt59"), snd: Swi(Con(Ref("check_lo"), Ref("ret_one")), Con(Var("lo"), Var("ret"))) },
    ],
  })

  self.add_def("ret_one", Net::{
    root: Con(Era, Con(Era, Var("ret"))),
    redexes: [{ fst: Num(1), snd: Var("ret") }],
  })

  self.add_def("check_lo", Net::{
    root: Con(Var("lo"), Var("ret")),
    redexes: [
      { fst: Num(10144262), snd: Opr(OpSym("[<]"), Opr(Var("lo"), Var("ret"))) },
    ],
  })

  self.add_def("mul31_mod", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [
      { fst: Ref("add_mod"), snd: Con(Var("x"), Con(Var("x"), Var("y2"))) },
      { fst: Ref("add_mod"), snd: Con(Var("y2"), Con(Var("y2"), Var("y4"))) },
      { fst: Ref("add_mod"), snd: Con(Var("y4"), Con(Var("y4"), Var("y8"))) },
      { fst: Ref("add_mod"), snd: Con(Var("y8"), Con(Var("y8"), Var("y16"))) },
      { fst: Ref("add_mod"), snd: Con(Var("y2"), Con(Var("x"), Var("t1"))) },
      { fst: Ref("add_mod"), snd: Con(Var("y4"), Con(Var("t1"), Var("t2"))) },
      { fst: Ref("add_mod"), snd: Con(Var("y8"), Con(Var("t2"), Var("t3"))) },
      { fst: Ref("add_mod"), snd: Con(Var("y16"), Con(Var("t3"), Var("ret"))) },
    ],
  })

  // High signed product *H#
  self.add_def("prim_mul_hi", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[>>]"), Opr(Num(23), Var("sx"))) },
      { fst: Var("b"), snd: Opr(OpSym("[>>]"), Opr(Num(23), Var("sy"))) },
      { fst: Ref("mul64"), snd: Con(Con(Num(0), Var("a")), Con(Con(Num(0), Var("b")), Con(Var("hi"), Era))) },
      { fst: Var("sx"), snd: Swi(Con(Ref("mul_hi_sx0"), Ref("mul_hi_sx1")), Con(Var("b"), Con(Var("hi"), Var("hi1")))) },
      { fst: Var("sy"), snd: Swi(Con(Ref("mul_hi_sy0"), Ref("mul_hi_sy1")), Con(Var("a"), Con(Var("hi1"), Var("ret")))) },
    ],
  })
  self.add_def("mul_hi_sx0", Net::{
    root: Con(Era, Con(Var("hi"), Var("ret"))),
    redexes: [{ fst: Var("hi"), snd: Var("ret") }],
  })
  self.add_def("mul_hi_sx1", Net::{
    root: Con(Var("b"), Con(Var("hi"), Var("ret"))),
    redexes: [{ fst: Var("hi"), snd: Opr(OpSym("[-]"), Opr(Var("b"), Var("ret"))) }],
  })
  self.add_def("mul_hi_sy0", Net::{
    root: Con(Era, Con(Var("hi"), Var("ret"))),
    redexes: [{ fst: Var("hi"), snd: Var("ret") }],
  })
  self.add_def("mul_hi_sy1", Net::{
    root: Con(Var("a"), Con(Var("hi"), Var("ret"))),
    redexes: [{ fst: Var("hi"), snd: Opr(OpSym("[-]"), Opr(Var("a"), Var("ret"))) }],
  })

  // Narrowing primitives
  self.add_def("narrow8Word", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [
      { fst: Var("x"), snd: Opr(OpSym("[&]"), Opr(Num(255), Var("ret"))) },
    ],
  })
  self.add_def("narrow16Word", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [
      { fst: Var("x"), snd: Opr(OpSym("[&]"), Opr(Num(65535), Var("ret"))) },
    ],
  })
  self.add_def("narrow8Int", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [
      { fst: Var("x"), snd: Opr(OpSym("[&]"), Opr(Num(255), Var("b8"))) },
      { fst: Var("b8"), snd: Opr(OpSym("[>>]"), Opr(Num(7), Var("s8"))) },
      { fst: Var("s8"), snd: Swi(Con(Ref("narrow_pos"), Ref("narrow8_neg")), Con(Var("b8"), Var("ret"))) },
    ],
  })
  self.add_def("narrow_pos", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [{ fst: Var("x"), snd: Var("ret") }],
  })
  self.add_def("narrow8_neg", Net::{
    root: Con(Era, Con(Var("x"), Var("ret"))),
    redexes: [{ fst: Var("x"), snd: Opr(OpSym("[|]"), Opr(Num(16776960), Var("ret"))) }],
  })
  self.add_def("narrow16Int", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [
      { fst: Var("x"), snd: Opr(OpSym("[&]"), Opr(Num(65535), Var("b16"))) },
      { fst: Var("b16"), snd: Opr(OpSym("[>>]"), Opr(Num(15), Var("s16"))) },
      { fst: Var("s16"), snd: Swi(Con(Ref("narrow_pos"), Ref("narrow16_neg")), Con(Var("b16"), Var("ret"))) },
    ],
  })
  self.add_def("narrow16_neg", Net::{
    root: Con(Era, Con(Var("x"), Var("ret"))),
    redexes: [{ fst: Var("x"), snd: Opr(OpSym("[|]"), Opr(Num(16711680), Var("ret"))) }],
  })

  // Width-independent helpers for primops that produce tuples or scan bits.
  // These are real nets, so a Core program that reaches them does not link to
  // an undefined reference.
  self.add_def("indexWord8OffAddr", Net::{
    root: Con(Var("ptr"), Con(Var("off"), Var("ret"))),
    redexes: [
      { fst: Ref("readWord8OffAddr"), snd: Con(Var("ptr"), Con(Var("off"), Con(Num(0), Var("pair")))) },
      { fst: Var("pair"), snd: Con(Era, Var("ret")) },
    ],
  })
  self.add_def("plusWord2", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Dup(Var("a_p"), Var("a_c")), snd: Var("a") },
      { fst: Var("a_p"), snd: Opr(OpSym("[+]"), Opr(Var("b"), Var("sum"))) },
      { fst: Dup(Var("sum_p"), Var("sum_c")), snd: Var("sum") },
      { fst: Var("sum_c"), snd: Opr(OpSym("[<]"), Opr(Var("a_c"), Var("carry"))) },
      { fst: Var("ret"), snd: Con(Var("sum_p"), Var("carry")) },
    ],
  })
  self.add_def("timesWord2", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Dup(Var("a_lo"), Var("a_hi")), snd: Var("a") },
      { fst: Dup(Var("b_lo"), Var("b_hi")), snd: Var("b") },
      { fst: Var("a_lo"), snd: Opr(OpSym("[*]"), Opr(Var("b_lo"), Var("low"))) },
      { fst: Ref("prim_mul_hi"), snd: Con(Var("a_hi"), Con(Var("b_hi"), Var("high"))) },
      { fst: Var("ret"), snd: Con(Var("high"), Var("low")) },
    ],
  })
  self.add_def("quotRemWord2", Net::{
    root: Con(Era, Con(Var("a"), Con(Var("b"), Var("ret")))),
    redexes: [{ fst: Ref("quotRemInt"), snd: Con(Var("a"), Con(Var("b"), Var("ret"))) }],
  })
  self.add_def("addIntC", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Dup(Var("a_p"), Var("a_c")), snd: Var("a") },
      { fst: Var("a_p"), snd: Opr(OpSym("[+]"), Opr(Var("b"), Var("sum"))) },
      { fst: Dup(Var("sum_p"), Var("sum_c")), snd: Var("sum") },
      { fst: Var("sum_c"), snd: Opr(OpSym("[<]"), Opr(Var("a_c"), Var("carry"))) },
      { fst: Var("ret"), snd: Con(Var("sum_p"), Var("carry")) },
    ],
  })
  self.add_def("subIntC", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Dup(Var("a_p"), Var("a_c")), snd: Var("a") },
      { fst: Dup(Var("b_p"), Var("b_c")), snd: Var("b") },
      { fst: Var("a_p"), snd: Opr(OpSym("[-]"), Opr(Var("b_p"), Var("diff"))) },
      { fst: Var("a_c"), snd: Opr(OpSym("[<]"), Opr(Var("b_c"), Var("borrow"))) },
      { fst: Var("ret"), snd: Con(Var("diff"), Var("borrow")) },
    ],
  })
  self.add_def("mulIntMayOflo", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Ref("prim_mul_hi"), snd: Con(Var("a"), Con(Var("b"), Var("high"))) },
      { fst: Var("high"), snd: Opr(OpSym("[!]"), Opr(Num(0), Var("ret"))) },
    ],
  })
  // SWAR popcount over the 24-bit value domain. This is branch-free, so it
  // does not depend on the evaluator's numeric-switch calling convention.
  self.add_def("popCnt", Net::{
    root: Con(Var("n"), Var("ret")),
    redexes: [
      { fst: Dup(Var("x0a"), Var("x0b")), snd: Var("n") },
      { fst: Var("x0a"), snd: Opr(OpSym("[>>]"), Opr(Num(1), Var("shr1"))) },
      { fst: Var("shr1"), snd: Opr(OpSym("[&]"), Opr(Num(5592405), Var("m1"))) },
      { fst: Var("x0b"), snd: Opr(OpSym("[-]"), Opr(Var("m1"), Var("x1"))) },
      { fst: Dup(Var("x1a"), Var("x1b")), snd: Var("x1") },
      { fst: Var("x1a"), snd: Opr(OpSym("[&]"), Opr(Num(3355443), Var("a2"))) },
      { fst: Var("x1b"), snd: Opr(OpSym("[>>]"), Opr(Num(2), Var("shr2"))) },
      { fst: Var("shr2"), snd: Opr(OpSym("[&]"), Opr(Num(3355443), Var("b2"))) },
      { fst: Var("a2"), snd: Opr(OpSym("[+]"), Opr(Var("b2"), Var("x2"))) },
      { fst: Dup(Var("x2a"), Var("x2b")), snd: Var("x2") },
      { fst: Var("x2a"), snd: Opr(OpSym("[>>]"), Opr(Num(4), Var("shr4"))) },
      { fst: Var("x2b"), snd: Opr(OpSym("[+]"), Opr(Var("shr4"), Var("s4"))) },
      { fst: Var("s4"), snd: Opr(OpSym("[&]"), Opr(Num(986895), Var("x3"))) },
      { fst: Var("x3"), snd: Opr(OpSym("[*]"), Opr(Num(65793), Var("prod"))) },
      { fst: Var("prod"), snd: Opr(OpSym("[>>]"), Opr(Num(16), Var("ret"))) },
    ],
  })
  self.add_def("cloneArray", Net::{
    root: Con(Var("arr"), Con(Var("s"), Var("ret"))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Var("arr")) }],
  })
  self.add_def("freezeArray", Net::{ root: Ref("cloneArray"), redexes: [] })
  self.add_def("thawArray", Net::{ root: Ref("cloneArray"), redexes: [] })
  self.add_def("shrinkArray", Net::{
    root: Con(Era, Con(Era, Con(Var("s"), Var("ret")))),
    redexes: [{ fst: Var("ret"), snd: Var("s") }],
  })
  self.add_def("isPinned", Net::{
    root: Con(Era, Num(0)),
    redexes: [],
  })
  self.add_def("waitState", Net::{ root: Con(Var("s"), Var("s")), redexes: [] })
  self.add_def("sparkInfo", Net::{
    root: Con(Var("s"), Var("ret")),
    redexes: [
      { fst: Dup(Var("s1"), Var("s2")), snd: Var("s") },
      { fst: Var("ret"), snd: Con(Var("s1"), Num(0)) },
    ],
  })
  self.add_def("threadLabel", Net::{
    root: Con(Era, Con(Era, Con(Var("s"), Var("s")))),
    redexes: [],
  })
  self.add_def("threadStatus", Net::{ root: Con(Era, Num(0)), redexes: [] })
  self.add_def("copyAddrToAddr", Net::{
    root: Con(Era, Con(Era, Con(Era, Con(Var("s"), Var("s"))))),
    redexes: [],
  })
  self.add_def("copyAddrToByteArray", Net::{
    root: Con(Era, Con(Era, Con(Era, Con(Era, Con(Var("s"), Var("s")))))),
    redexes: [],
  })
  self.add_def("copyByteArrayToAddr", Net::{
    root: Con(Era, Con(Era, Con(Era, Con(Era, Con(Var("s"), Var("s")))))),
    redexes: [],
  })
  self.add_def("setAddrRange", Net::{
    root: Con(Era, Con(Era, Con(Era, Con(Var("s"), Var("s"))))),
    redexes: [],
  })
  self.add_def("compareByteArrays", Net::{
    root: Con(Era, Con(Era, Num(0))),
    redexes: [],
  })
  self.add_def("opaque", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })

  self.add_def("prim_max", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Dup(Var("a1"), Var("a2")), snd: Var("a") },
      { fst: Dup(Var("b1"), Var("b2")), snd: Var("b") },
      { fst: Ref("slt"), snd: Con(Var("b1"), Con(Var("a1"), Var("cond"))) },
      { fst: Var("cond"), snd: Swi(Con(Var("b2"), Var("a2")), Var("ret")) },
    ],
  })
  self.add_def("prim_min", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Dup(Var("a1"), Var("a2")), snd: Var("a") },
      { fst: Dup(Var("b1"), Var("b2")), snd: Var("b") },
      { fst: Ref("slt"), snd: Con(Var("a1"), Con(Var("b1"), Var("cond"))) },
      { fst: Var("cond"), snd: Swi(Con(Var("b2"), Var("a2")), Var("ret")) },
    ],
  })
  self.add_def("fmadd", Net::{
    root: Con(Var("a"), Con(Var("b"), Con(Var("c"), Var("ret")))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[*]"), Opr(Var("b"), Var("p"))) },
      { fst: Var("p"), snd: Opr(OpSym("[+]"), Opr(Var("c"), Var("ret"))) },
    ],
  })
  self.add_def("fmsub", Net::{
    root: Con(Var("a"), Con(Var("b"), Con(Var("c"), Var("ret")))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[*]"), Opr(Var("b"), Var("p"))) },
      { fst: Var("p"), snd: Opr(OpSym("[-]"), Opr(Var("c"), Var("ret"))) },
    ],
  })
  self.add_def("fnmadd", Net::{
    root: Con(Var("a"), Con(Var("b"), Con(Var("c"), Var("ret")))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[*]"), Opr(Var("b"), Var("p"))) },
      { fst: Var("c"), snd: Opr(OpSym("[-]"), Opr(Var("p"), Var("ret"))) },
    ],
  })
  self.add_def("fnmsub", Net::{
    root: Con(Var("a"), Con(Var("b"), Con(Var("c"), Var("ret")))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[*]"), Opr(Var("b"), Var("p"))) },
      { fst: Var("p"), snd: Opr(OpSym("[+]"), Opr(Var("c"), Var("sum"))) },
      { fst: Num(0), snd: Opr(OpSym("[-]"), Opr(Var("sum"), Var("ret"))) },
    ],
  })
  self.add_def("prim_pow", Net::{
    root: Con(Var("b"), Con(Var("e"), Var("ret"))),
    redexes: [
      { fst: Ref("pow_loop"), snd: Con(Var("b"), Con(Var("e"), Con(Num(1), Var("ret")))) },
    ],
  })
  self.add_def("pow_loop", Net::{
    root: Con(Var("b"), Con(Var("e"), Con(Var("acc"), Var("ret")))),
    redexes: [
      { fst: Var("e"), snd: Swi(Con(Ref("pow_zero"), Ref("pow_step")), Con(Var("b"), Con(Var("acc"), Var("ret")))) },
    ],
  })
  self.add_def("pow_zero", Net::{
    root: Con(Era, Con(Var("acc"), Var("ret"))),
    redexes: [{ fst: Var("acc"), snd: Var("ret") }],
  })
  self.add_def("pow_step", Net::{
    root: Con(Var("pred"), Con(Var("b"), Con(Var("acc"), Var("ret")))),
    redexes: [
      { fst: Dup(Var("b1"), Var("b2")), snd: Var("b") },
      { fst: Var("acc"), snd: Opr(OpSym("[*]"), Opr(Var("b1"), Var("acc2"))) },
      { fst: Ref("pow_loop"), snd: Con(Var("b2"), Con(Var("pred"), Con(Var("acc2"), Var("ret")))) },
    ],
  })
  self.add_def("decodeFloat_Int", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [{ fst: Var("ret"), snd: Con(Var("x"), Num(0)) }],
  })
  self.add_def("prim_sin", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_cos", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_tan", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_asin", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_acos", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_atan", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_sinh", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_cosh", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_tanh", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_asinh", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_acosh", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_atanh", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_exp", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_log", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_expm1", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("prim_log1p", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("clz", Net::{
    root: Con(Var("n"), Var("ret")),
    redexes: [
      { fst: Ref("clz_step"), snd: Con(Var("n"), Con(Num(24), Var("ret"))) },
    ],
  })
  self.add_def("clz_step", Net::{
    root: Con(Var("n"), Con(Var("count"), Var("ret"))),
    redexes: [
      { fst: Dup(Var("n1"), Var("n2")), snd: Var("n") },
      { fst: Var("n1"), snd: Swi(Con(Ref("clz_done"), Ref("clz_nonzero")), Con(Var("n2"), Con(Var("count"), Var("ret")))) },
    ],
  })
  self.add_def("clz_done", Net::{
    root: Con(Era, Con(Var("count"), Var("ret"))),
    redexes: [{ fst: Var("count"), snd: Var("ret") }],
  })
  self.add_def("clz_nonzero", Net::{
    root: Con(Era, Con(Var("n"), Con(Var("count"), Var("ret")))),
    redexes: [
      { fst: Var("n"), snd: Opr(OpSym("[>>]"), Opr(Num(1), Var("n_shr"))) },
      { fst: Var("count"), snd: Opr(OpSym("[-]"), Opr(Num(1), Var("c_dec"))) },
      { fst: Ref("clz_step"), snd: Con(Var("n_shr"), Con(Var("c_dec"), Var("ret"))) },
    ],
  })
  self.add_def("ctz", Net::{
    root: Con(Var("n"), Var("ret")),
    redexes: [
      { fst: Dup(Var("n1"), Var("n2")), snd: Var("n") },
      { fst: Num(0), snd: Opr(OpSym("[-]"), Opr(Var("n1"), Var("neg_n"))) },
      { fst: Var("n2"), snd: Opr(OpSym("[&]"), Opr(Var("neg_n"), Var("lsb"))) },
      { fst: Var("lsb"), snd: Opr(OpSym("[-]"), Opr(Num(1), Var("mask"))) },
      { fst: Ref("popCnt"), snd: Con(Var("mask"), Var("ret")) },
    ],
  })
  self.add_def("byteSwap", Net::{
    root: Con(Var("n"), Var("ret")),
    redexes: [
      { fst: Dup(Var("n1"), Var("n_rest")), snd: Var("n") },
      { fst: Dup(Var("n2"), Var("n3")), snd: Var("n_rest") },
      { fst: Var("n1"), snd: Opr(OpSym("[>>]"), Opr(Num(16), Var("b0"))) },
      { fst: Var("n2"), snd: Opr(OpSym("[&]"), Opr(Num(65280), Var("b1"))) },
      { fst: Var("n3"), snd: Opr(OpSym("[&]"), Opr(Num(255), Var("b2_raw"))) },
      { fst: Var("b2_raw"), snd: Opr(OpSym("[<<]"), Opr(Num(16), Var("b2"))) },
      { fst: Var("b0"), snd: Opr(OpSym("[|]"), Opr(Var("b1"), Var("mid"))) },
      { fst: Var("mid"), snd: Opr(OpSym("[|]"), Opr(Var("b2"), Var("ret"))) },
    ],
  })
  self.add_def("bitReverse", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("pdep", Net::{ root: Con(Var("src"), Con(Var("mask"), Var("src"))), redexes: [] })
  self.add_def("pext", Net::{ root: Con(Var("src"), Con(Var("mask"), Var("src"))), redexes: [] })
  self.add_def("casArray", Net::{
    root: Con(Var("arr"), Con(Var("idx"), Con(Var("old_v"), Con(Var("new_v"), Con(Var("s"), Var("ret")))))),
    redexes: [
      { fst: Ref("state_get"), snd: Con(Var("s"), Con(Var("arr"), Var("got"))) },
      { fst: Var("got"), snd: Con(Var("s1"), Var("actual")) },
      { fst: Ref("state_put"), snd: Con(Var("s1"), Con(Var("arr"), Con(Var("new_v"), Var("s2")))) },
      { fst: Var("ret"), snd: Con(Var("s2"), Var("actual")) },
    ],
  })
  self.add_def("casAddr", Net::{
    root: Con(Era, Con(Var("old_v"), Con(Var("new_v"), Con(Var("s"), Var("ret"))))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Var("old_v")) }],
  })
  self.add_def("exchangeAddr", Net::{
    root: Con(Era, Con(Var("new_v"), Con(Var("s"), Var("ret")))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Var("new_v")) }],
  })
  self.add_def("fetchOpIntArray", Net::{
    root: Con(Var("arr"), Con(Var("idx"), Con(Var("val"), Con(Var("s"), Var("ret"))))),
    redexes: [
      { fst: Ref("state_get"), snd: Con(Var("s"), Con(Var("arr"), Var("got"))) },
      { fst: Var("got"), snd: Con(Var("s1"), Var("old")) },
      { fst: Dup(Var("old1"), Var("old2")), snd: Var("old") },
      { fst: Var("old1"), snd: Opr(OpSym("[+]"), Opr(Var("val"), Var("new_v"))) },
      { fst: Ref("state_put"), snd: Con(Var("s1"), Con(Var("arr"), Con(Var("new_v"), Var("s2")))) },
      { fst: Var("ret"), snd: Con(Var("s2"), Var("old2")) },
    ],
  })
  self.add_def("fetchOpWordAddr", Net::{
    root: Con(Era, Con(Var("val"), Con(Var("s"), Var("ret")))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Var("val")) }],
  })

  // String / CString primitives
  self.add_def("unpackCString", Net::{
    root: Con(Var("s"), Var("s")),
    redexes: [],
  })
  self.add_def("unpackCStringUtf8", Net::{
    root: Con(Var("s"), Var("s")),
    redexes: [],
  })

  // MutVar#/TVar# without runtime cells. State# is a persistent value:
  //   S = (next-id, entries, flag, exception)
  // entries is a tagged association list: (0, *) is empty, (1, id, val, tail)
  // is a binding. A write replaces the first binding or prepends one, so the
  // list stays proportional to the number of live variables. STM rollback is
  // just dropping the new S; no undo log or runtime support is needed.
  self.add_def("state_empty", Net::{
    root: Con(Num(0), Con(Con(Num(0), Era), Con(Num(0), Num(0)))),
    redexes: [],
  })

  // Splits S and rebuilds it unchanged; `ret` is the reconstructed state.
  self.add_def("state_keep", Net::{
    root: Con(Var("s"), Var("ret")),
    redexes: [
      { fst: Var("s"), snd: Con(Var("next"), Con(Var("ents"), Con(Var("flag"), Var("exc")))) },
      { fst: Var("ret"), snd: Con(Var("next"), Con(Var("ents"), Con(Var("flag"), Var("exc")))) },
    ],
  })

  self.add_def("state_flag", Net::{
    root: Con(Var("s"), Var("ret")),
    redexes: [
      { fst: Var("s"), snd: Con(Era, Con(Era, Con(Var("flag"), Era))) },
      { fst: Var("ret"), snd: Var("flag") },
    ],
  })
  self.add_def("state_exc", Net::{
    root: Con(Var("s"), Var("ret")),
    redexes: [
      { fst: Var("s"), snd: Con(Era, Con(Era, Con(Era, Var("exc")))) },
      { fst: Var("ret"), snd: Var("exc") },
    ],
  })

  // Looks up an id in the association list. Missing ids read as 0.
  self.add_def("state_get", Net::{
    root: Con(Var("s"), Con(Var("id"), Var("ret"))),
    redexes: [
      { fst: Var("s"), snd: Con(Var("next"), Con(Var("ents"), Con(Var("flag"), Var("exc")))) },
      { fst: Ref("cell_list_get"), snd: Con(Var("ents"), Con(Var("id"), Var("val"))) },
      { fst: Var("ret"), snd: Con(Con(Var("next"), Con(Var("ents"), Con(Var("flag"), Var("exc")))), Var("val")) },
    ],
  })
  self.add_def("cell_list_get", Net::{
    root: Con(Var("ents"), Con(Var("id"), Var("ret"))),
    redexes: [
      { fst: Var("ents"), snd: Con(Var("tag"), Var("rest")) },
      {
        fst: Var("tag"),
        snd: Swi(
          Con(Ref("cell_get_nil"), Ref("cell_get_cons")),
          Con(Var("rest"), Con(Var("id"), Var("ret"))),
        ),
      },
    ],
  })
  self.add_def("cell_get_nil", Net::{
    root: Con(Era, Con(Era, Num(0))),
    redexes: [],
  })
  self.add_def("cell_get_cons", Net::{
    root: Con(Era, Con(Var("rest"), Con(Var("id"), Var("ret")))),
    redexes: [
      { fst: Var("rest"), snd: Con(Var("entry_id"), Con(Var("val"), Var("tail"))) },
      { fst: Dup(Var("id_cmp"), Var("id_next")), snd: Var("id") },
      { fst: Var("entry_id"), snd: Opr(OpSym("[=]"), Opr(Var("id_cmp"), Var("cmp"))) },
      {
        fst: Var("cmp"),
        snd: Swi(
          // [=] is 1 on equality, so 0 takes miss and nonzero takes hit.
          Con(Ref("cell_get_miss"), Ref("cell_get_hit")),
          Con(Var("val"), Con(Var("tail"), Con(Var("id_next"), Var("ret")))),
        ),
      },
    ],
  })
  self.add_def("cell_get_hit", Net::{
    root: Con(Era, Con(Var("val"), Con(Era, Con(Era, Var("ret"))))),
    redexes: [{ fst: Var("val"), snd: Var("ret") }],
  })
  self.add_def("cell_get_miss", Net::{
    root: Con(Era, Con(Var("tail"), Con(Var("id_next"), Var("ret")))),
    redexes: [
      { fst: Ref("cell_list_get"), snd: Con(Var("tail"), Con(Var("id_next"), Var("ret"))) },
    ],
  })

  // Replaces id's binding, or prepends one when absent.
  self.add_def("state_put", Net::{
    root: Con(Var("s"), Con(Var("id"), Con(Var("val"), Var("ret")))),
    redexes: [
      { fst: Var("s"), snd: Con(Var("next"), Con(Var("ents"), Con(Var("flag"), Var("exc")))) },
      { fst: Ref("cell_list_put"), snd: Con(Var("ents"), Con(Var("id"), Con(Var("val"), Var("ents2")))) },
      { fst: Var("ret"), snd: Con(Var("next"), Con(Var("ents2"), Con(Var("flag"), Var("exc")))) },
    ],
  })
  self.add_def("cell_list_put", Net::{
    root: Con(Var("ents"), Con(Var("id"), Con(Var("val"), Var("ret")))),
    redexes: [
      { fst: Var("ents"), snd: Con(Var("tag"), Var("rest")) },
      {
        fst: Var("tag"),
        snd: Swi(
          Con(Ref("cell_put_nil"), Ref("cell_put_cons")),
          Con(Var("rest"), Con(Var("id"), Con(Var("val"), Var("ret")))),
        ),
      },
    ],
  })
  self.add_def("cell_put_nil", Net::{
    root: Con(Era, Con(Var("id"), Con(Var("val"), Var("ret")))),
    redexes: [
      { fst: Var("ret"), snd: Con(Num(1), Con(Var("id"), Con(Var("val"), Num(0)))) },
    ],
  })
  self.add_def("cell_put_cons", Net::{
    root: Con(Era, Con(Var("rest"), Con(Var("id"), Con(Var("val"), Var("ret"))))),
    redexes: [
      { fst: Var("rest"), snd: Con(Var("entry_id"), Con(Var("old_val"), Var("tail"))) },
      { fst: Dup(Var("id_cmp"), Var("id_miss")), snd: Var("id") },
      { fst: Var("entry_id"), snd: Opr(OpSym("[=]"), Opr(Var("id_cmp"), Var("cmp"))) },
      {
        fst: Var("cmp"),
        snd: Swi(
          Con(Ref("cell_put_miss"), Ref("cell_put_hit")),
          Con(Var("entry_id"), Con(Var("old_val"), Con(Var("tail"), Con(Var("id_miss"), Con(Var("val"), Var("ret")))))),
        ),
      },
    ],
  })
  self.add_def("cell_put_hit", Net::{
    root: Con(Era, Con(Var("entry_id"), Con(Era, Con(Var("tail"), Con(Era, Con(Var("val"), Var("ret"))))))),
    redexes: [
      { fst: Var("ret"), snd: Con(Num(1), Con(Var("entry_id"), Con(Var("val"), Var("tail")))) },
    ],
  })
  self.add_def("cell_put_miss", Net::{
    root: Con(Var("entry_id"), Con(Var("old_val"), Con(Var("tail"), Con(Var("id"), Con(Var("val"), Var("ret")))))),
    redexes: [
      { fst: Ref("cell_list_put"), snd: Con(Var("tail"), Con(Var("id"), Con(Var("val"), Var("tail2")))) },
      { fst: Var("ret"), snd: Con(Num(1), Con(Var("entry_id"), Con(Var("old_val"), Var("tail2")))) },
    ],
  })

  self.add_def("newMutVar", Net::{
    root: Con(Var("val"), Con(Var("s"), Var("ret"))),
    redexes: [
      { fst: Var("s"), snd: Con(Var("next"), Con(Var("ents"), Con(Var("flag"), Var("exc")))) },
      { fst: Dup(Var("next_id"), Var("next_inc")), snd: Var("next") },
      { fst: Var("next_inc"), snd: Opr(OpSym("[+]"), Opr(Num(1), Var("next2"))) },
      {
        fst: Var("ret"),
        snd: Con(
          Con(Var("next2"), Con(Con(Num(1), Con(Var("next_id"), Con(Var("val"), Var("ents")))), Con(Var("flag"), Var("exc")))),
          Var("next_id"),
        ),
      },
    ],
  })
  self.add_def("readMutVar", Net::{
    root: Con(Var("mv"), Con(Var("s"), Var("ret"))),
    redexes: [
      { fst: Ref("state_get"), snd: Con(Var("s"), Con(Var("mv"), Var("ret"))) },
    ],
  })
  self.add_def("writeMutVar", Net::{
    root: Con(Var("mv"), Con(Var("val"), Con(Var("s"), Var("ret")))),
    redexes: [
      { fst: Ref("state_put"), snd: Con(Var("s"), Con(Var("mv"), Con(Var("val"), Var("ret")))) },
    ],
  })
  self.add_def("newTVar", Net::{ root: Ref("newMutVar"), redexes: [] })
  self.add_def("readTVar", Net::{ root: Ref("readMutVar"), redexes: [] })
  self.add_def("writeTVar", Net::{ root: Ref("writeMutVar"), redexes: [] })
  self.add_def("readTVarIO", Net::{ root: Ref("readMutVar"), redexes: [] })

  // STM flags: 0 = success, 1 = retry, 2 = exception. Rollback is dropping
  // the action's returned state and reusing the caller's persistent snapshot.
  self.add_def("retry", Net::{
    root: Con(Var("s"), Var("ret")),
    redexes: [
      { fst: Var("s"), snd: Con(Var("next"), Con(Var("ents"), Con(Era, Var("exc")))) },
      { fst: Var("ret"), snd: Con(Con(Var("next"), Con(Var("ents"), Con(Num(1), Var("exc")))), Num(0)) },
    ],
  })
  self.add_def("atomically", Net::{
    root: Con(Var("action"), Con(Var("s"), Var("ret"))),
    redexes: [
      { fst: Var("action"), snd: Con(Var("s"), Var("act_ret")) },
      { fst: Var("act_ret"), snd: Con(Var("s_after"), Var("val")) },
      { fst: Ref("state_flag"), snd: Con(Var("s_after"), Var("flag")) },
      {
        fst: Var("flag"),
        snd: Swi(
          Con(Ref("atom_ok"), Ref("atom_retry")),
          Con(Var("s_after"), Con(Var("val"), Con(Var("s"), Var("ret")))),
        ),
      },
    ],
  })
  self.add_def("atom_ok", Net::{
    root: Con(Var("s"), Con(Var("val"), Con(Era, Var("ret")))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Var("val")) }],
  })
  self.add_def("atom_retry", Net::{
    root: Con(Era, Con(Era, Con(Era, Con(Var("s0"), Var("ret"))))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s0"), Ref("stuck")) }],
  })
  self.add_def("catchRetry", Net::{
    root: Con(Var("action"), Con(Var("handler"), Con(Var("s"), Var("ret")))),
    redexes: [
      { fst: Var("action"), snd: Con(Var("s"), Var("act_ret")) },
      { fst: Var("act_ret"), snd: Con(Var("s_after"), Var("val")) },
      { fst: Ref("state_flag"), snd: Con(Var("s_after"), Var("flag")) },
      {
        fst: Var("flag"),
        snd: Swi(
          Con(Ref("crt_done"), Ref("crt_alt")),
          Con(Var("s_after"), Con(Var("val"), Con(Var("handler"), Con(Var("s"), Var("ret"))))),
        ),
      },
    ],
  })
  self.add_def("crt_done", Net::{
    root: Con(Var("s"), Con(Var("val"), Con(Era, Con(Era, Var("ret"))))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Var("val")) }],
  })
  self.add_def("crt_alt", Net::{
    root: Con(Era, Con(Era, Con(Era, Con(Var("handler"), Con(Var("s0"), Var("ret")))))),
    redexes: [
      { fst: Var("handler"), snd: Con(Var("s0"), Var("ret")) },
    ],
  })
  self.add_def("catchSTM", Net::{
    root: Con(Var("action"), Con(Var("handler"), Con(Var("s"), Var("ret")))),
    redexes: [
      { fst: Var("action"), snd: Con(Var("s"), Var("act_ret")) },
      { fst: Var("act_ret"), snd: Con(Var("s_after"), Var("val")) },
      { fst: Ref("state_flag"), snd: Con(Var("s_after"), Var("flag")) },
      {
        fst: Var("flag"),
        snd: Swi(
          Con(Ref("cstm_done"), Ref("cstm_nonzero")),
          Con(Var("s_after"), Con(Var("val"), Con(Var("handler"), Con(Var("s"), Var("ret"))))),
        ),
      },
    ],
  })
  self.add_def("cstm_done", Net::{
    root: Con(Var("s"), Con(Var("val"), Con(Era, Con(Era, Var("ret"))))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Var("val")) }],
  })
  self.add_def("cstm_nonzero", Net::{
    root: Con(Var("pred"), Con(Var("s_after"), Con(Var("val"), Con(Var("handler"), Con(Var("s0"), Var("ret")))))),
    redexes: [
      {
        fst: Var("pred"),
        snd: Swi(
          Con(Ref("cstm_retry"), Ref("cstm_handle")),
          Con(Var("s_after"), Con(Var("val"), Con(Var("handler"), Con(Var("s0"), Var("ret"))))),
        ),
      },
    ],
  })
  self.add_def("cstm_retry", Net::{
    root: Con(Var("s_after"), Con(Era, Con(Era, Con(Var("s0"), Var("ret"))))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s0"), Ref("stuck")) }],
  })
  self.add_def("cstm_handle", Net::{
    root: Con(Era, Con(Var("s_after"), Con(Era, Con(Var("handler"), Con(Var("s0"), Var("ret")))))),
    redexes: [
      { fst: Ref("state_exc"), snd: Con(Var("s_after"), Var("exc")) },
      { fst: Var("handler"), snd: Con(Var("exc"), Con(Var("s0"), Var("ret"))) },
    ],
  })
  self.add_def("catch", Net::{ root: Ref("catchSTM"), redexes: [] })

  self.add_def("raiseIO", Net::{
    root: Con(Var("e"), Con(Var("s"), Var("ret"))),
    redexes: [
      { fst: Var("s"), snd: Con(Var("next"), Con(Var("ents"), Con(Era, Era))) },
      { fst: Var("ret"), snd: Con(Con(Var("next"), Con(Var("ents"), Con(Num(2), Var("e")))), Var("e")) },
    ],
  })
  self.add_def("stuck", Net::{ root: Num(0), redexes: [] })
  self.add_def("raise", Net::{ root: Con(Era, Ref("stuck")), redexes: [] })


  // Raise and error primitives (raiseIO is defined above with cell heap)

  // Concurrency, MVar and Thread primitives
  self.add_def("writeWord8OffAddr", Net::{
    root: Con(Era, Con(Era, Con(Era, Con(Var("s"), Var("ret"))))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Num(0)) }],
  })
  self.add_def("setByteArray", Net::{
    root: Con(Era, Con(Era, Con(Era, Con(Era, Con(Var("s"), Var("ret")))))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Num(0)) }],
  })
  // MVars are ordinary cells containing a boxed value. There is no scheduler,
  // so this models the single-threaded protocol; it must not be read as real
  // concurrency. The box is (1, value) for full and (0, 0) for empty.
  self.add_def("newMVar", Net::{
    root: Con(Var("val"), Con(Var("s"), Var("ret"))),
    redexes: [
      {
        fst: Ref("newMutVar"),
        snd: Con(Con(Num(1), Var("val")), Con(Var("s"), Var("ret"))),
      },
    ],
  })
  self.add_def("takeMVar", Net::{
    root: Con(Var("mv"), Con(Var("s"), Var("ret"))),
    redexes: [
      { fst: Ref("state_get"), snd: Con(Var("s"), Con(Var("mv"), Var("got"))) },
      { fst: Var("got"), snd: Con(Var("s1"), Con(Era, Var("val"))) },
      { fst: Ref("state_put"), snd: Con(Var("s1"), Con(Var("mv"), Con(Con(Num(0), Num(0)), Var("s2")))) },
      { fst: Var("ret"), snd: Con(Var("s2"), Var("val")) },
    ],
  })
  self.add_def("tryTakeMVar", Net::{
    root: Con(Var("mv"), Con(Var("s"), Var("ret"))),
    redexes: [
      { fst: Ref("state_get"), snd: Con(Var("s"), Con(Var("mv"), Var("got"))) },
      { fst: Var("got"), snd: Con(Var("s1"), Con(Era, Var("val"))) },
      { fst: Ref("state_put"), snd: Con(Var("s1"), Con(Var("mv"), Con(Con(Num(0), Num(0)), Var("s2")))) },
      { fst: Var("ret"), snd: Con(Var("s2"), Con(Num(1), Var("val"))) },
    ],
  })
  self.add_def("putMVar", Net::{
    root: Con(Var("mv"), Con(Var("val"), Con(Var("s"), Var("ret")))),
    redexes: [
      { fst: Ref("state_put"), snd: Con(Var("s"), Con(Var("mv"), Con(Con(Num(1), Var("val")), Var("ret")))) },
    ],
  })
  self.add_def("tryPutMVar", Net::{
    root: Con(Var("mv"), Con(Var("val"), Con(Var("s"), Var("ret")))),
    redexes: [
      { fst: Ref("state_put"), snd: Con(Var("s"), Con(Var("mv"), Con(Con(Num(1), Var("val")), Var("s2")))) },
      { fst: Var("ret"), snd: Con(Var("s2"), Num(1)) },
    ],
  })
  self.add_def("readMVar", Net::{
    root: Con(Var("mv"), Con(Var("s"), Var("ret"))),
    redexes: [
      { fst: Ref("state_get"), snd: Con(Var("s"), Con(Var("mv"), Var("got"))) },
      { fst: Var("got"), snd: Con(Var("s1"), Con(Era, Var("val"))) },
      { fst: Var("ret"), snd: Con(Var("s1"), Var("val")) },
    ],
  })
  self.add_def("tryReadMVar", Net::{
    root: Con(Var("mv"), Con(Var("s"), Var("ret"))),
    redexes: [
      { fst: Ref("state_get"), snd: Con(Var("s"), Con(Var("mv"), Var("got"))) },
      { fst: Var("got"), snd: Con(Var("s1"), Con(Era, Var("val"))) },
      { fst: Var("ret"), snd: Con(Var("s1"), Con(Num(1), Var("val"))) },
    ],
  })
  self.add_def("isEmptyMVar", Net::{
    root: Con(Era, Con(Var("s"), Var("ret"))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Num(0)) }],
  })
  // fork# starts a real parallel reduction of the action. HVM schedules the
  // spawned redex alongside the parent, so pure work runs concurrently. The
  // action gets a disjoint id range and its own persistent snapshot; shared
  // mutation is intentionally not visible across the fork boundary.
  self.add_def("fork", Net::{
    root: Con(Var("act"), Con(Var("s"), Var("ret"))),
    redexes: [
      { fst: Var("s"), snd: Con(Var("next"), Con(Var("ents"), Con(Var("flag"), Var("exc")))) },
      { fst: Dup(Var("tid"), Var("next_r")), snd: Var("next") },
      { fst: Var("next_r"), snd: Opr(OpSym("[+]"), Opr(Num(1), Var("child_next"))) },
      { fst: Dup(Var("ents_p"), Var("ents_c")), snd: Var("ents") },
      { fst: Dup(Var("flag_p"), Var("flag_c")), snd: Var("flag") },
      { fst: Dup(Var("exc_p"), Var("exc_c")), snd: Var("exc") },
      { fst: Var("act"), snd: Con(Con(Var("child_next"), Con(Var("ents_c"), Con(Var("flag_c"), Var("exc_c")))), Var("child_ret")) },
      { fst: Var("child_ret"), snd: Era },
      { fst: Var("ret"), snd: Con(Con(Var("child_next"), Con(Var("ents_p"), Con(Var("flag_p"), Var("exc_p")))), Var("tid")) },
    ],
  })
  self.add_def("killThread", Net::{
    root: Con(Era, Con(Var("s"), Var("s"))),
    redexes: [],
  })
  self.add_def("forkOn", Net::{ root: Ref("fork"), redexes: [] })
  self.add_def("yield", Net::{
    root: Con(Var("s"), Var("s")),
    redexes: [],
  })
  self.add_def("myThreadId", Net::{
    root: Con(Var("s"), Var("ret")),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Num(0)) }],
  })
  self.add_def("spark", Net::{
    root: Con(Var("a"), Con(Var("s"), Var("ret"))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Var("a")) }],
  })
  // error msg = a value. There is no exception channel; see docs/real_world_gaps.md.
  self.add_def("error", Net::{
    root: Con(Era, Var("ret")),
    redexes: [{ fst: Num(0), snd: Var("ret") }],
  })
  // isTrue# x = (x /= 0#): GHC's tag-to-Bool test.
  self.add_def("isTrue", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [{ fst: Var("x"), snd: Opr(OpSym("[!]"), Opr(Num(0), Var("ret"))) }],
  })
  // (&&) a b = a b False, (||) a b = a True b, with the Scott Bool encoding.
  self.add_def("logical_and", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [{ fst: Var("a"), snd: Con(Var("b"), Con(Ref("False"), Var("ret"))) }],
  })
  self.add_def("logical_or", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [{ fst: Var("a"), snd: Con(Ref("True"), Con(Var("b"), Var("ret"))) }],
  })
  // lazy x = x. GHC uses it to hide a value from strictness analysis; the net
  // encoding has no forcing to suppress, so it is the identity wire.
  self.add_def("lazy", Net::{ root: Con(Var("x"), Var("x")), redexes: [] })
  self.add_def("seq", Net::{
    root: Con(Era, Con(Var("b"), Con(Var("s"), Var("ret")))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Var("b")) }],
  })
  self.add_def("negateInt", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [{ fst: Num(0), snd: Opr(OpSym("[-]"), Opr(Var("x"), Var("ret"))) }],
  })
  self.add_def("quotRemInt", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Var("a"), snd: Opr(OpSym("[/]"), Opr(Var("b"), Var("q"))) },
      { fst: Var("a"), snd: Opr(OpSym("[%]"), Opr(Var("b"), Var("r"))) },
      { fst: Var("ret"), snd: Con(Var("q"), Var("r")) },
    ],
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
    ("and", "prim_and"),
    ("or", "prim_or"),
    ("xor", "prim_xor"),
    ("shl", "prim_shl"),
    ("shr", "prim_shr"),
    ("quotWord", "prim_div"),
    ("remWord", "prim_rem"),
    ("eqWord", "prim_eq"),
    ("neWord", "prim_neq"),
    ("ltWord", "prim_lt"),
    ("gtWord", "prim_gt"),
    ("leWord", "prim_lte"),
    ("geWord", "prim_gte"),
    ("readWord8Array", "readByteArray"),
    ("writeWord8Array", "writeByteArray"),
    ("indexIntArray", "indexWord8Array"),
    ("unpackCStringUtf8", "unpackCString"),
  ]
  for a in aliases {
    if !self.is_top_level(a.0) {
      self.add_def(a.0, Net::{ root: Ref(a.1), redexes: [] })
    }
  }
}

