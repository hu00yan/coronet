///| ADT / Scott-encoding and pattern matching lowering for HVM2

priv struct ConstrInfo {
  name : String
  variant_idx : Int
  num_variants : Int
  family_idx : Int
}

fn LowerCtx::find_constr(self : LowerCtx, name : String) -> ConstrInfo? {
  for c in self.known_constrs {
    if c.name == name {
      return Some(c)
    }
  }
  None
}


fn LowerCtx::register_single_constr(self : LowerCtx, name : String, arity : Int) -> Unit {
  let family_idx = self.adt_families.length()
  self.adt_families.push([(name, arity)])
  self.known_constrs.push(ConstrInfo::{
    name,
    variant_idx: 0,
    num_variants: 1,
    family_idx,
  })
  self.known_constrs.push(ConstrInfo::{
    name: sanitize_name(name),
    variant_idx: 0,
    num_variants: 1,
    family_idx,
  })
}

fn LowerCtx::register_adt(self : LowerCtx, variants : Array[(String, Int)]) -> Unit {
  let n = variants.length()
  let family_idx = self.adt_families.length()
  self.adt_families.push(variants)
  for k = 0; k < n; k = k + 1 {
    let (name, arity) = variants[k]
    let def_name = sanitize_name(name)
    self.known_constrs.push(ConstrInfo::{
      name,
      variant_idx: k,
      num_variants: n,
      family_idx,
    })
    if def_name != name {
      self.known_constrs.push(ConstrInfo::{
        name: def_name,
        variant_idx: k,
        num_variants: n,
        family_idx,
      })
    }

    if !self.has_def(def_name) {
      let call_var = self.fresh_var("call")
      if arity == 0 {
        let mut spine : Tree = Var(call_var)
        for j = n - 1; j >= 0; j = j - 1 {
          let cont : Tree = if j == k { Var(call_var) } else { Era }
          spine = Con(cont, spine)
        }
        self.add_def(def_name, Net::{ root: spine, redexes: [] })
      } else {
        let params : Array[String] = []
        for i = 0; i < arity; i = i + 1 {
          params.push("p_\{i}")
        }
        let mut app : Tree = Var(call_var)
        for i = arity - 1; i >= 0; i = i - 1 {
          app = Con(Var(params[i]), app)
        }
        let mut spine : Tree = Var(call_var)
        for j = n - 1; j >= 0; j = j - 1 {
          let cont : Tree = if j == k { app } else { Era }
          spine = Con(cont, spine)
        }
        for i = arity - 1; i >= 0; i = i - 1 {
          spine = Con(Var(params[i]), spine)
        }
        self.add_def(def_name, Net::{ root: spine, redexes: [] })
      }
    }
  }
}

fn LowerCtx::register_known_constructors(self : LowerCtx) -> Unit {
  // Standard fixtures ADTs:
  self.register_adt([("MyNil", 0), ("MyCons", 2)])
  self.register_adt([("Nil", 0), ("Cons", 2)])
  self.register_adt([("LNil", 0), ("LCons", 2)])
  self.register_adt([("[]", 0), (":", 2)])
  self.register_adt([("MyNothing", 0), ("MyJust", 1)])
  self.register_adt([("MyFalse", 0), ("MyTrue", 0)])
  self.register_adt([("False", 0), ("True", 0)])
  self.register_adt([("Leaf", 1), ("Node", 2)])
  self.register_adt([("LT", 0), ("EQ", 0), ("GT", 0)])
  self.register_adt([("Tip", 0), ("Bin", 5)])

  // Single constructors
  self.register_single_constr("Pair", 2)
  self.register_single_constr("Tuple3", 3)
  self.register_single_constr("Tuple4", 4)
  self.register_single_constr("unboxed_tuple2", 2)
  self.register_single_constr("unboxed_tuple3", 3)
  self.register_single_constr("unboxed_tuple4", 4)
  self.register_single_constr("unboxed_solo", 1)
  self.register_single_constr("unboxed_unit", 0)
  self.register_single_constr("Vec3", 3)
  self.register_single_constr("Ray", 2)
  self.register_single_constr("Sphere", 3)
  self.register_single_constr("Light", 2)
  self.register_single_constr("HashState", 8)
  self.register_single_constr("BS", 3)
  self.register_single_constr("FinalPtr", 0)
  self.register_single_constr("C", 1)
  self.register_single_constr("Show", 1)
  self.register_single_constr("C:Show", 1)
  self.register_single_constr("Eq", 2)
  self.register_single_constr("C:Eq", 2)
  self.register_single_constr("CAlt", 3)

  // GhcCompiler ADTs:
  self.register_adt([("LitInt", 1), ("LitBool", 1)])
  self.register_adt([("CDataAlt", 1), ("CLitAlt", 1), ("CDEFAULT", 0)])
  self.register_adt([("CNonRec", 2), ("CRec", 1)])
  self.register_adt([("CVar", 1), ("CLit", 1), ("CApp", 2), ("CLam", 2), ("CLet", 2), ("CCase", 3)])
  self.register_adt([("VInt", 1), ("VBool", 1), ("VClosure", 3), ("VRecClosure", 4), ("VConstr", 2)])

  self.add_def("CAlt", Net::{
    root: Con(Var("p0"), Con(Var("p1"), Con(Var("p2"), Con(Var("p0"), Con(Var("p1"), Var("p2")))))),
    redexes: [],
  })

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

  // Pair l r = (l (r (l r)))
  self.add_def("Pair", Net::{
    root: Con(Var("l"), Con(Var("r"), Con(Var("l"), Var("r")))),
    redexes: [],
  })

  // Tuple3 x y z = (x (y (z (x (y z)))))
  self.add_def("Tuple3", Net::{
    root: Con(Var("x"), Con(Var("y"), Con(Var("z"), Con(Var("x"), Con(Var("y"), Var("z")))))),
    redexes: [],
  })

  // Tuple4 x y z w = (x (y (z (w (x (y (z w)))))))
  self.add_def("Tuple4", Net::{
    root: Con(Var("x"), Con(Var("y"), Con(Var("z"), Con(Var("w"), Con(Var("x"), Con(Var("y"), Con(Var("z"), Var("w")))))))),
    redexes: [],
  })

  // Unboxed tuples (flat Scott representations)
  self.add_def("unboxed_tuple2", Net::{
    root: Con(Var("x"), Con(Var("y"), Con(Var("x"), Var("y")))),
    redexes: [],
  })

  self.add_def("unboxed_tuple3", Net::{
    root: Con(Var("x"), Con(Var("y"), Con(Var("z"), Con(Var("x"), Con(Var("y"), Var("z")))))),
    redexes: [],
  })

  self.add_def("unboxed_tuple4", Net::{
    root: Con(Var("x"), Con(Var("y"), Con(Var("z"), Con(Var("w"), Con(Var("x"), Con(Var("y"), Con(Var("z"), Var("w")))))))),
    redexes: [],
  })

  self.add_def("unboxed_unit", Net::{
    root: Num(0),
    redexes: [],
  })

  self.add_def("unboxed_solo", Net::{
    root: Con(Var("x"), Var("x")),
    redexes: [],
  })

  // State# and MutableByteArray primitives
  self.add_def("realWorld", Net::{
    root: Con(Num(0), Con(Con(Num(0), Era), Con(Num(0), Num(0)))),
    redexes: [],
  })

  self.add_def("runRW", Net::{
    root: Con(Var("f"), Var("ret")),
    redexes: [
      { fst: Ref("realWorld"), snd: Var("s0") },
      { fst: Var("f"), snd: Con(Var("s0"), Var("ret")) },
    ],
  })

  self.add_def("new_array", Net::{
    root: Con(Num(0), Con(Num(0), Con(Num(0), Con(Num(0), Con(Num(0), Con(Num(0), Con(Num(0), Con(Num(0), Era)))))))),
    redexes: [],
  })

  self.add_def("sizeofByteArray", Net::{
    root: Con(Era, Num(64)),
    redexes: [],
  })

  self.add_def("indexWord8Array", Net::{
    root: Con(Var("arr"), Con(Var("idx"), Var("ret"))),
    redexes: [
      {
        fst: Var("idx"),
        snd: Swi(Con(Ref("index_at_0"), Ref("index_at_next")), Con(Var("arr"), Var("ret"))),
      },
    ],
  })
  self.add_def("index_at_0", Net::{
    root: Con(Var("arr"), Var("ret")),
    redexes: [
      { fst: Var("arr"), snd: Con(Var("head"), Era) },
      { fst: Var("ret"), snd: Var("head") },
    ],
  })
  self.add_def("index_at_next", Net::{
    root: Con(Var("pred"), Con(Var("arr"), Var("ret"))),
    redexes: [
      { fst: Var("arr"), snd: Con(Era, Var("tail")) },
      {
        fst: Ref("indexWord8Array"),
        snd: Con(Var("tail"), Con(Var("pred"), Var("ret"))),
      },
    ],
  })
  self.add_def("indexIntArray", Net::{
    root: Ref("indexWord8Array"),
    redexes: [],
  })
  self.add_def("readWord8Array", Net::{
    root: Ref("readByteArray"),
    redexes: [],
  })
  self.add_def("writeWord8Array", Net::{
    root: Ref("writeByteArray"),
    redexes: [],
  })
  self.add_def("copyByteArray", Net::{
    root: Con(Era, Con(Era, Con(Era, Con(Era, Con(Era, Con(Var("s"), Var("s"))))))),
    redexes: [],
  })

  let bs_bytes = [
    67, 111, 114, 111, 110, 101, 116, 32, 73, 109, 112, 108, 105, 99, 105, 116,
    32, 80, 97, 114, 97, 108, 108, 101, 108, 32, 71, 114, 97, 112, 104, 32,
    82, 101, 100, 117, 99, 116, 105, 111, 110,
  ]
  let mut s_tree : Tree = Era
  for i = bs_bytes.length() - 1; i >= 0; i = i - 1 {
    s_tree = Con(Num(bs_bytes[i]), s_tree)
  }
  self.add_def("coronet_str", Net::{ root: s_tree, redexes: [] })

  self.add_def("readWord8OffAddr", Net::{
    root: Con(Var("ptr"), Con(Var("off"), Con(Var("s"), Var("ret")))),
    redexes: [
      { fst: Var("ptr"), snd: Opr(OpSym("[+]"), Opr(Var("off"), Var("idx"))) },
      { fst: Ref("indexWord8Array"), snd: Con(Ref("coronet_str"), Con(Var("idx"), Var("val"))) },
      { fst: Var("ret"), snd: Con(Var("s"), Var("val")) },
    ],
  })

  self.add_def("plusAddr", Net::{
    root: Con(Var("ptr"), Con(Var("off"), Var("ret"))),
    redexes: [
      { fst: Var("ptr"), snd: Opr(OpSym("[+]"), Opr(Var("off"), Var("ret"))) },
    ],
  })
  self.add_def("eqAddr", Net::{
    root: Con(Var("p1"), Con(Var("p2"), Var("ret"))),
    redexes: [
      { fst: Var("p1"), snd: Opr(OpSym("[=]"), Opr(Var("p2"), Var("ret"))) },
    ],
  })
  self.add_def("touch", Net::{
    root: Con(Era, Con(Var("s"), Var("s"))),
    redexes: [],
  })
  self.add_def("word8ToWord", Net::{
    root: Con(Var("w"), Var("w")),
    redexes: [],
  })

  // Ordering: LT (0, 0), EQ (1, 0), GT (2, 0)
  self.add_def("LT", Net::{
    root: Con(Var("lt"), Con(Era, Con(Era, Var("lt")))),
    redexes: [],
  })
  self.add_def("EQ", Net::{
    root: Con(Era, Con(Var("eq"), Con(Era, Var("eq")))),
    redexes: [],
  })
  self.add_def("GT", Net::{
    root: Con(Era, Con(Era, Con(Var("gt"), Var("gt")))),
    redexes: [],
  })

  // Map: Tip (0, 0), Bin (1, 5)
  self.add_def("Tip", Net::{
    root: Con(Var("call"), Con(Era, Var("call"))),
    redexes: [],
  })
  self.add_def("Bin", Net::{
    root: Con(Var("sz"), Con(Var("k"), Con(Var("v"), Con(Var("l"), Con(Var("r"),
      Con(Era, Con(Con(Var("sz"), Con(Var("k"), Con(Var("v"), Con(Var("l"), Con(Var("r"), Var("call")))))), Var("call")))))))),
    redexes: [],
  })

  // ByteString: BS (0, 3), FinalPtr (0, 0)
  self.add_def("BS", Net::{
    root: Con(Var("a"), Con(Var("b"), Con(Var("c"), Con(Var("a"), Con(Var("b"), Var("c")))))),
    redexes: [],
  })
  self.add_def("FinalPtr", Net::{
    root: Num(0),
    redexes: [],
  })

  // Char constructor C# / C and Show dictionary
  self.add_def("C", Net::{
    root: Con(Var("x"), Var("x")),
    redexes: [],
  })
  self.add_def("Show", Net::{
    root: Con(Var("x"), Var("x")),
    redexes: [],
  })
  self.add_def("ret_true", Net::{
    root: Var("ret"),
    redexes: [{ fst: Ref("True"), snd: Var("ret") }],
  })
  self.add_def("sel_eq", Net::{
    root: Con(Var("x"), Con(Era, Var("x"))),
    redexes: [],
  })
  self.add_def("Eq", Net::{
    root: Con(Var("eq"), Con(Var("ne"), Con(Var("c"), Var("c_res")))),
    redexes: [
      { fst: Var("c"), snd: Con(Var("eq"), Con(Var("ne"), Var("c_res"))) },
    ],
  })
  self.add_def("C_Eq", Net::{
    root: Con(Var("eq"), Con(Var("ne"), Con(Var("c"), Var("c_res")))),
    redexes: [
      { fst: Var("c"), snd: Con(Var("eq"), Con(Var("ne"), Var("c_res"))) },
    ],
  })
  self.add_def("fst", Net::{
    root: Con(Con(Var("a"), Era), Var("a")),
    redexes: [],
  })
  self.add_def("snd", Net::{
    root: Con(Con(Era, Var("b")), Var("b")),
    redexes: [],
  })
  self.add_def("_fEqList__s_c_ne_1", Net::{
    root: Con(Var("a"), Con(Var("b"), Var("ret"))),
    redexes: [
      { fst: Ref("eqString"), snd: Con(Var("a"), Con(Var("b"), Var("is_eq"))) },
      { fst: Var("is_eq"), snd: Con(Ref("True"), Con(Ref("False"), Var("ret"))) },
    ],
  })
  self.add_def("_fEqList__s_fEqList1", Net::{
    root: Var("ret"),
    redexes: [
      { fst: Ref("Eq"), snd: Con(Ref("eqString"), Con(Ref("_fEqList__s_c_ne_1"), Var("ret"))) },
    ],
  })
  self.add_def("_fEqTuple2", Net::{
    root: Con(Var("dict_a"), Con(Var("dict_b"), Var("ret"))),
    redexes: [
      { fst: Var("dict_a"), snd: Con(Ref("sel_eq"), Var("eq_a")) },
      { fst: Var("dict_b"), snd: Con(Ref("sel_eq"), Var("eq_b")) },
      { fst: Ref("_eqTuple2_cmp"), snd: Con(Var("eq_a"), Con(Var("eq_b"), Var("cmp"))) },
      { fst: Ref("Eq"), snd: Con(Var("cmp"), Con(Era, Var("ret"))) },
    ],
  })
  self.add_def("_eqTuple2_cmp", Net::{
    root: Con(Var("eq_a"), Con(Var("eq_b"), Con(Var("p1"), Con(Var("p2"), Var("ret"))))),
    redexes: [
      { fst: Var("p1"), snd: Con(Var("x1"), Var("y1")) },
      { fst: Var("p2"), snd: Con(Var("x2"), Var("y2")) },
      { fst: Var("eq_a"), snd: Con(Var("x1"), Con(Var("x2"), Var("is_a_eq"))) },
      { fst: Var("eq_b"), snd: Con(Var("y1"), Con(Var("y2"), Var("is_b_eq"))) },
      { fst: Var("is_a_eq"), snd: Con(Ref("False"), Con(Var("is_b_eq"), Var("ret"))) },
    ],
  })
  self.add_def("_fEqList__c_eq_", Net::{
    root: Con(Var("dict"), Con(Var("xs"), Con(Var("ys"), Var("ret")))),
    redexes: [
      { fst: Var("dict"), snd: Con(Ref("sel_eq"), Var("eq_elem")) },
      { fst: Ref("_eqList_cmp"), snd: Con(Var("eq_elem"), Con(Var("xs"), Con(Var("ys"), Var("ret")))) },
    ],
  })
  self.add_def("_eqList_cmp", Net::{
    root: Con(Var("eq_elem"), Con(Var("xs"), Con(Var("ys"), Var("ret")))),
    redexes: [
      { fst: Var("xs"), snd: Con(Ref("_eqList_xs_nil"), Con(Ref("_eqList_xs_cons"), Con(Var("eq_elem"), Con(Var("ys"), Var("ret"))))) },
    ],
  })
  self.add_def("_eqList_xs_nil", Net::{
    root: Con(Era, Con(Var("ys"), Var("ret"))),
    redexes: [
      { fst: Var("ys"), snd: Con(Ref("ret_true"), Con(Ref("_eqList_ret_false"), Var("ret"))) },
    ],
  })
  self.add_def("_eqList_ret_false", Net::{
    root: Con(Era, Con(Era, Var("ret"))),
    redexes: [{ fst: Ref("False"), snd: Var("ret") }],
  })
  self.add_def("_eqList_xs_cons", Net::{
    root: Con(Var("hx"), Con(Var("tx"), Con(Var("eq_elem"), Con(Var("ys"), Var("ret"))))),
    redexes: [
      { fst: Var("ys"), snd: Con(Ref("_eqList_cons_nil"), Con(Ref("_eqList_cons_cons"), Con(Var("hx"), Con(Var("tx"), Con(Var("eq_elem"), Var("ret")))))) },
    ],
  })
  self.add_def("_eqList_cons_nil", Net::{
    root: Con(Era, Con(Era, Con(Era, Var("ret")))),
    redexes: [{ fst: Ref("False"), snd: Var("ret") }],
  })
  self.add_def("_eqList_cons_cons", Net::{
    root: Con(Var("hy"), Con(Var("ty"), Con(Var("hx"), Con(Var("tx"), Con(Var("eq_elem"), Var("ret")))))),
    redexes: [
      { fst: Var("eq_elem"), snd: Dup(Var("eq1"), Var("eq2")) },
      { fst: Var("eq1"), snd: Con(Var("hx"), Con(Var("hy"), Var("is_eq"))) },
      { fst: Var("is_eq"), snd: Con(Ref("False"), Con(Var("tail_eq"), Var("ret"))) },
      { fst: Ref("_eqList_cmp"), snd: Con(Var("eq2"), Con(Var("tx"), Con(Var("ty"), Var("tail_eq")))) },
    ],
  })
  self.add_def("map", Net::{
    root: Con(Var("f"), Con(Var("xs"), Var("ret"))),
    redexes: [
      { fst: Var("xs"), snd: Con(Ref("map_nil"), Con(Ref("map_cons"), Con(Var("f"), Var("ret")))) },
    ],
  })
  self.add_def("map_nil", Net::{
    root: Con(Era, Var("ret")),
    redexes: [{ fst: Ref("Nil"), snd: Var("ret") }],
  })
  self.add_def("map_cons", Net::{
    root: Con(Var("h"), Con(Var("t"), Con(Var("f"), Var("ret")))),
    redexes: [
      { fst: Var("f"), snd: Dup(Var("f1"), Var("f2")) },
      { fst: Var("f1"), snd: Con(Var("h"), Var("fh")) },
      { fst: Ref("map"), snd: Con(Var("f2"), Con(Var("t"), Var("tail"))) },
      { fst: Ref("Cons"), snd: Con(Var("fh"), Con(Var("tail"), Var("ret"))) },
    ],
  })
  self.add_def("filter", Net::{
    root: Con(Var("p"), Con(Var("xs"), Var("ret"))),
    redexes: [
      { fst: Var("xs"), snd: Con(Ref("filter_nil"), Con(Ref("filter_cons"), Con(Var("p"), Var("ret")))) },
    ],
  })
  self.add_def("filter_nil", Net::{
    root: Con(Era, Var("ret")),
    redexes: [{ fst: Ref("Nil"), snd: Var("ret") }],
  })
  self.add_def("filter_cons", Net::{
    root: Con(Var("h"), Con(Var("t"), Con(Var("p"), Var("ret")))),
    redexes: [
      { fst: Var("p"), snd: Dup(Var("p1"), Var("p2")) },
      { fst: Var("h"), snd: Dup(Var("h1"), Var("h2")) },
      { fst: Var("p1"), snd: Con(Var("h1"), Var("keep")) },
      { fst: Var("keep"), snd: Con(Ref("filter_drop"), Con(Ref("filter_keep"), Con(Var("h2"), Con(Var("p2"), Con(Var("t"), Var("ret")))))) },
    ],
  })
  self.add_def("filter_drop", Net::{
    root: Con(Era, Con(Var("p"), Con(Var("t"), Var("ret")))),
    redexes: [{ fst: Ref("filter"), snd: Con(Var("p"), Con(Var("t"), Var("ret"))) }],
  })
  self.add_def("filter_keep", Net::{
    root: Con(Var("h"), Con(Var("p"), Con(Var("t"), Var("ret")))),
    redexes: [
      { fst: Ref("filter"), snd: Con(Var("p"), Con(Var("t"), Var("tail"))) },
      { fst: Ref("Cons"), snd: Con(Var("h"), Con(Var("tail"), Var("ret"))) },
    ],
  })
  self.add_def("concatMap", Net::{
    root: Con(Var("f"), Con(Var("xs"), Var("ret"))),
    redexes: [
      { fst: Var("xs"), snd: Con(Ref("concatMap_nil"), Con(Ref("concatMap_cons"), Con(Var("f"), Var("ret")))) },
    ],
  })
  self.add_def("concatMap_nil", Net::{
    root: Con(Era, Var("ret")),
    redexes: [{ fst: Ref("Nil"), snd: Var("ret") }],
  })
  self.add_def("concatMap_cons", Net::{
    root: Con(Var("h"), Con(Var("t"), Con(Var("f"), Var("ret")))),
    redexes: [
      { fst: Var("f"), snd: Dup(Var("f1"), Var("f2")) },
      { fst: Var("f1"), snd: Con(Var("h"), Var("fh")) },
      { fst: Ref("concatMap"), snd: Con(Var("f2"), Con(Var("t"), Var("tail"))) },
      { fst: Ref("append"), snd: Con(Var("fh"), Con(Var("tail"), Var("ret"))) },
    ],
  })
  self.add_def("elem", Net::{
    root: Con(Var("dict"), Con(Var("target"), Con(Var("xs"), Var("ret")))),
    redexes: [
      { fst: Var("dict"), snd: Con(Ref("sel_eq"), Var("eq_fn")) },
      { fst: Ref("_elem_loop"), snd: Con(Var("eq_fn"), Con(Var("target"), Con(Var("xs"), Var("ret")))) },
    ],
  })
  self.add_def("_elem_loop", Net::{
    root: Con(Var("eq_fn"), Con(Var("target"), Con(Var("xs"), Var("ret")))),
    redexes: [
      { fst: Var("xs"), snd: Con(Ref("_elem_nil"), Con(Ref("_elem_cons"), Con(Var("eq_fn"), Con(Var("target"), Var("ret"))))) },
    ],
  })
  self.add_def("_elem_nil", Net::{
    root: Con(Era, Con(Era, Var("ret"))),
    redexes: [{ fst: Ref("False"), snd: Var("ret") }],
  })
  self.add_def("_elem_cons", Net::{
    root: Con(Var("y"), Con(Var("ys"), Con(Var("eq_fn"), Con(Var("target"), Var("ret"))))),
    redexes: [
      { fst: Var("eq_fn"), snd: Dup(Var("eq1"), Var("eq2")) },
      { fst: Var("target"), snd: Dup(Var("tgt1"), Var("tgt2")) },
      { fst: Var("eq1"), snd: Con(Var("tgt1"), Con(Var("y"), Var("is_eq"))) },
      { fst: Var("is_eq"), snd: Con(Var("tail_res"), Con(Ref("True"), Var("ret"))) },
      { fst: Ref("_elem_loop"), snd: Con(Var("eq2"), Con(Var("tgt2"), Con(Var("ys"), Var("tail_res")))) },
    ],
  })
  self.add_def("notElem", Net::{
    root: Con(Var("dict"), Con(Var("target"), Con(Var("xs"), Var("ret")))),
    redexes: [
      { fst: Ref("elem"), snd: Con(Var("dict"), Con(Var("target"), Con(Var("xs"), Var("is_elem")))) },
      { fst: Var("is_elem"), snd: Con(Ref("True"), Con(Ref("False"), Var("ret"))) },
    ],
  })

  self.add_def("tagToEnum", Net::{
    root: Con(Var("tag"), Var("ret")),
    redexes: [
      { fst: Var("tag"), snd: Swi(Con(Ref("False"), Ref("tagToEnum_1")), Var("ret")) }
    ]
  })
  self.add_def("tagToEnum_1", Net::{
    root: Con(Era, Var("ret")),
    redexes: [{ fst: Ref("True"), snd: Var("ret") }]
  })
  self.add_def("dataToTagSmall", Net::{
    root: Con(Era, Num(0)),
    redexes: []
  })
  self.add_def("patError", Net::{
    root: Con(Era, Num(0)),
    redexes: []
  })
  self.add_def("append", Net::{
    root: Con(Var("xs"), Con(Var("ys"), Var("ret"))),
    redexes: [
      { fst: Var("xs"), snd: Con(Ref("append_nil"), Con(Ref("append_cons"), Con(Var("ys"), Var("ret")))) }
    ]
  })
  self.add_def("append_nil", Net::{
    root: Con(Var("ys"), Var("ret")),
    redexes: [{ fst: Var("ys"), snd: Var("ret") }]
  })
  self.add_def("append_cons", Net::{
    root: Con(Var("h"), Con(Var("t"), Con(Var("ys"), Var("ret")))),
    redexes: [
      { fst: Ref("append"), snd: Con(Var("t"), Con(Var("ys"), Var("tail"))) },
      { fst: Ref("Cons"), snd: Con(Var("h"), Con(Var("tail"), Var("ret"))) }
    ]
  })
  self.add_def("_plus__plus_", Net::{
    root: Con(Var("xs"), Con(Var("ys"), Var("ret"))),
    redexes: [
      { fst: Ref("append"), snd: Con(Var("xs"), Con(Var("ys"), Var("ret"))) }
    ]
  })
  self.add_def("eqString", Net::{
    root: Con(Var("xs"), Con(Var("ys"), Var("ret"))),
    redexes: [
      { fst: Var("xs"), snd: Con(Ref("eqString_xs_nil"), Con(Ref("eqString_xs_cons"), Con(Var("ys"), Var("ret")))) }
    ]
  })
  self.add_def("eqString_xs_nil", Net::{
    root: Con(Var("ys"), Var("ret")),
    redexes: [
      { fst: Var("ys"), snd: Con(Ref("ret_true"), Con(Ref("eqString_ret_false"), Var("ret"))) }
    ]
  })
  self.add_def("eqString_ret_false", Net::{
    root: Con(Era, Con(Era, Var("ret"))),
    redexes: [{ fst: Ref("False"), snd: Var("ret") }]
  })
  self.add_def("eqString_xs_cons", Net::{
    root: Con(Var("hx"), Con(Var("tx"), Con(Var("ys"), Var("ret")))),
    redexes: [
      { fst: Var("ys"), snd: Con(Ref("eqString_cons_nil"), Con(Ref("eqString_cons_cons"), Con(Var("hx"), Con(Var("tx"), Var("ret"))))) }
    ]
  })
  self.add_def("eqString_cons_nil", Net::{
    root: Con(Era, Con(Era, Var("ret"))),
    redexes: [{ fst: Ref("False"), snd: Var("ret") }]
  })
  self.add_def("eqString_cons_cons", Net::{
    root: Con(Var("hy"), Con(Var("ty"), Con(Var("hx"), Con(Var("tx"), Var("ret"))))),
    redexes: [
      { fst: Var("hx"), snd: Opr(OpSym("[=]"), Opr(Var("hy"), Var("is_eq"))) },
      { fst: Var("is_eq"), snd: Swi(Con(Ref("eqString_ret_false"), Ref("eqString_same")), Con(Var("tx"), Con(Var("ty"), Var("ret")))) }
    ]
  })
  self.add_def("eqString_same", Net::{
    root: Con(Era, Con(Var("tx"), Con(Var("ty"), Var("ret")))),
    redexes: [
      { fst: Ref("eqString"), snd: Con(Var("tx"), Con(Var("ty"), Var("ret"))) }
    ]
  })

  // Tag extractors for dataToTagSmall# in GhcCompiler
  self.add_def("tag_Literal", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [
      { fst: Var("x"), snd: Con(Ref("tag_Literal_0"), Con(Ref("tag_Literal_1"), Var("ret"))) }
    ]
  })
  self.add_def("tag_Literal_0", Net::{ root: Con(Era, Num(0)), redexes: [] })
  self.add_def("tag_Literal_1", Net::{ root: Con(Era, Num(1)), redexes: [] })

  self.add_def("tag_Bool", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [
      { fst: Var("x"), snd: Con(Num(0), Con(Num(1), Var("ret"))) }
    ]
  })

  self.add_def("tag_AltCon", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [
      { fst: Var("x"), snd: Con(Ref("tag_AltCon_0"), Con(Ref("tag_AltCon_1"), Con(Num(2), Var("ret")))) }
    ]
  })
  self.add_def("tag_AltCon_0", Net::{ root: Con(Era, Num(0)), redexes: [] })
  self.add_def("tag_AltCon_1", Net::{ root: Con(Era, Num(1)), redexes: [] })

  self.add_def("tag_CoreBind", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [
      { fst: Var("x"), snd: Con(Ref("tag_CoreBind_0"), Con(Ref("tag_CoreBind_1"), Var("ret"))) }
    ]
  })
  self.add_def("tag_CoreBind_0", Net::{ root: Con(Era, Con(Era, Num(0))), redexes: [] })
  self.add_def("tag_CoreBind_1", Net::{ root: Con(Era, Num(1)), redexes: [] })

  self.add_def("tag_CoreExpr", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [
      { fst: Var("x"), snd: Con(Ref("tag_CoreExpr_0"), Con(Ref("tag_CoreExpr_1"), Con(Ref("tag_CoreExpr_2"), Con(Ref("tag_CoreExpr_3"), Con(Ref("tag_CoreExpr_4"), Con(Ref("tag_CoreExpr_5"), Var("ret"))))))) }
    ]
  })
  self.add_def("tag_CoreExpr_0", Net::{ root: Con(Era, Num(0)), redexes: [] })
  self.add_def("tag_CoreExpr_1", Net::{ root: Con(Era, Num(1)), redexes: [] })
  self.add_def("tag_CoreExpr_2", Net::{ root: Con(Era, Con(Era, Num(2))), redexes: [] })
  self.add_def("tag_CoreExpr_3", Net::{ root: Con(Era, Con(Era, Num(3))), redexes: [] })
  self.add_def("tag_CoreExpr_4", Net::{ root: Con(Era, Con(Era, Num(4))), redexes: [] })
  self.add_def("tag_CoreExpr_5", Net::{ root: Con(Era, Con(Era, Con(Era, Num(5)))), redexes: [] })

  self.add_def("tag_Value", Net::{
    root: Con(Var("x"), Var("ret")),
    redexes: [
      { fst: Var("x"), snd: Con(Ref("tag_Value_0"), Con(Ref("tag_Value_1"), Con(Ref("tag_Value_2"), Con(Ref("tag_Value_3"), Con(Ref("tag_Value_4"), Var("ret")))))) }
    ]
  })
  self.add_def("tag_Value_0", Net::{ root: Con(Era, Num(0)), redexes: [] })
  self.add_def("tag_Value_1", Net::{ root: Con(Era, Num(1)), redexes: [] })
  self.add_def("tag_Value_2", Net::{ root: Con(Era, Con(Era, Con(Era, Num(2)))), redexes: [] })
  self.add_def("tag_Value_3", Net::{ root: Con(Era, Con(Era, Con(Era, Con(Era, Num(3))))), redexes: [] })
  self.add_def("tag_Value_4", Net::{ root: Con(Era, Con(Era, Num(4))), redexes: [] })

  // Typeclass compare method for integers
  self.add_def("compare", Net::{
    root: Con(Era, Con(Var("x"), Con(Var("y"), Var("ret")))),
    redexes: [
      { fst: Ref("slt"), snd: Con(Var("x"), Con(Var("y"), Var("is_lt"))) },
      { fst: Var("is_lt"), snd: Swi(Con(Ref("compare_not_lt"), Ref("compare_ret_lt")), Con(Var("x"), Con(Var("y"), Var("ret")))) },
    ],
  })
  self.add_def("compare_ret_lt", Net::{
    root: Con(Era, Con(Era, Var("ret"))),
    redexes: [{ fst: Ref("LT"), snd: Var("ret") }],
  })
  self.add_def("compare_not_lt", Net::{
    root: Con(Var("x"), Con(Var("y"), Var("ret"))),
    redexes: [
      { fst: Var("x"), snd: Opr(OpSym("[=]"), Opr(Var("y"), Var("is_eq"))) },
      { fst: Var("is_eq"), snd: Swi(Con(Ref("compare_ret_gt"), Ref("compare_ret_eq")), Var("ret")) },
    ],
  })
  self.add_def("compare_ret_eq", Net::{
    root: Con(Era, Var("ret")),
    redexes: [{ fst: Ref("EQ"), snd: Var("ret") }],
  })
  self.add_def("compare_ret_gt", Net::{
    root: Var("ret"),
    redexes: [{ fst: Ref("GT"), snd: Var("ret") }],
  })

  self.add_def("newByteArray", Net::{
    root: Con(Era, Con(Era, Var("ret"))),
    redexes: [
      { fst: Var("ret"), snd: Con(Ref("new_array"), Num(0)) },
    ],
  })

  self.add_def("writeIntArray", Net::{
    root: Con(Era, Con(Var("idx"), Con(Var("val"), Con(Var("s"), Var("ret"))))),
    redexes: [
      {
        fst: Var("idx"),
        snd: Swi(Con(Ref("write_at_0"), Ref("write_at_next")), Con(Var("val"), Con(Var("s"), Var("ret")))),
      },
    ],
  })

  self.add_def("write_at_0", Net::{
    root: Con(Var("val"), Con(Var("s"), Var("ret"))),
    redexes: [
      { fst: Var("s"), snd: Con(Era, Var("rest")) },
      { fst: Var("ret"), snd: Con(Var("val"), Var("rest")) },
    ],
  })

  self.add_def("write_at_next", Net::{
    root: Con(Var("pred"), Con(Var("val"), Con(Var("s"), Var("ret")))),
    redexes: [
      { fst: Var("s"), snd: Con(Var("head"), Var("tail")) },
      { fst: Var("ret"), snd: Con(Var("head"), Var("new_tail")) },
      {
        fst: Ref("writeIntArray"),
        snd: Con(Era, Con(Var("pred"), Con(Var("val"), Con(Var("tail"), Var("new_tail"))))),
      },
    ],
  })

  self.add_def("readIntArray", Net::{
    root: Con(Era, Con(Var("idx"), Con(Var("s"), Var("ret")))),
    redexes: [
      {
        fst: Var("idx"),
        snd: Swi(Con(Ref("read_at_0"), Ref("read_at_next")), Con(Var("s"), Var("ret"))),
      },
    ],
  })

  self.add_def("read_at_0", Net::{
    root: Con(Var("s"), Var("ret")),
    redexes: [
      { fst: Var("s"), snd: Con(Var("head"), Var("tail")) },
      { fst: Var("ret"), snd: Con(Con(Var("head_d1"), Var("tail")), Var("head_d2")) },
      { fst: Dup(Var("head_d1"), Var("head_d2")), snd: Var("head") },
    ],
  })

  self.add_def("read_at_next", Net::{
    root: Con(Var("pred"), Con(Var("s"), Var("ret"))),
    redexes: [
      { fst: Var("s"), snd: Con(Var("head"), Var("tail")) },
      { fst: Var("ret"), snd: Con(Con(Var("head"), Var("new_tail")), Var("val")) },
      {
        fst: Ref("readIntArray"),
        snd: Con(Era, Con(Var("pred"), Con(Var("tail"), Con(Var("new_tail"), Var("val"))))),
      },
    ],
  })

  self.add_def("writeByteArray", Net::{
    root: Con(Var("arr"), Con(Var("idx"), Con(Var("val"), Con(Var("s"), Var("ret"))))),
    redexes: [
      { fst: Ref("writeIntArray"), snd: Con(Var("arr"), Con(Var("idx"), Con(Var("val"), Con(Var("s"), Var("ret"))))) },
    ],
  })

  self.add_def("readByteArray", Net::{
    root: Con(Var("arr"), Con(Var("idx"), Con(Var("s"), Var("ret")))),
    redexes: [
      { fst: Ref("readIntArray"), snd: Con(Var("arr"), Con(Var("idx"), Con(Var("s"), Var("ret")))) },
    ],
  })

  // Vec3 x y z = (x (y (z (x (y z)))))
  self.add_def("Vec3", Net::{
    root: Con(Var("x"), Con(Var("y"), Con(Var("z"), Con(Var("x"), Con(Var("y"), Var("z")))))),
    redexes: [],
  })

  // Ray o d = (o (d (o d)))
  self.add_def("Ray", Net::{
    root: Con(Var("o"), Con(Var("d"), Con(Var("o"), Var("d")))),
    redexes: [],
  })

  // Sphere c r col = (c (r (col (c (r col)))))
  self.add_def("Sphere", Net::{
    root: Con(Var("c"), Con(Var("r"), Con(Var("col"), Con(Var("c"), Con(Var("r"), Var("col")))))),
    redexes: [],
  })

  // Light p i = (p (i (p i)))
  self.add_def("Light", Net::{
    root: Con(Var("p"), Con(Var("i"), Con(Var("p"), Var("i")))),
    redexes: [],
  })

  // HashState a b c d e f g h
  let h_fields = ["a", "b", "c", "d", "e", "f", "g", "h"]
  let mut h_tuple : Tree = Var(h_fields[h_fields.length() - 1])
  for i = h_fields.length() - 2; i >= 0; i = i - 1 {
    h_tuple = Con(Var(h_fields[i]), h_tuple)
  }
  let mut h_root : Tree = h_tuple
  for i = h_fields.length() - 1; i >= 0; i = i - 1 {
    h_root = Con(Var(h_fields[i]), h_root)
  }
  self.add_def("HashState", Net::{ root: h_root, redexes: [] })
}

fn LowerCtx::register_program_adts(self : LowerCtx, prog : @syntax.Program) -> Unit {
  // The program is the authority on its own data families. Register them first,
  // then let the built-in table fill in constructors the program never
  // declared, without shadowing anything already defined.
  let families = @syntax.discover_adts(prog)
  for fam in families {
    let variants : Array[(String, Int)] = []
    for ctor in fam.ctors {
      variants.push((ctor.name, ctor.arity))
    }
    if variants.length() == 1 {
      if self.find_constr(variants[0].0) is None {
        self.register_single_constr(variants[0].0, variants[0].1)
      }
    } else if variants.length() > 1 {
      self.register_adt(variants)
    }
  }
  for def in self.defs {
    self.frozen_defs.push(def.0)
  }
  self.register_known_constructors()
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
  if alts.length() == 0 {
    return Num(0)
  }

  // Case 1: Single constructor pattern matching
  if alts.length() == 1 {
    match alts[0].pat {
      Data(c, vars) if @syntax.is_unboxed_ctor(c) && vars.length() == 1 => {
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
      Data(_, vars) => {
        let scrut_tree = self.lower_expr_to_tree(scrut, redexes)
        let scrut_val = if binder.length() > 0 {
          let b_name = sanitize_name(binder)
          redexes.push({ fst: scrut_tree, snd: Var(b_name) })
          Var(b_name)
        } else {
          scrut_tree
        }
        if vars.length() == 0 {
          redexes.push({ fst: scrut_val, snd: Era })
        } else if vars.length() == 1 {
          redexes.push({ fst: scrut_val, snd: Var(sanitize_name(vars[0])) })
        } else {
          let mut tuple_pat : Tree = Var(sanitize_name(vars[vars.length() - 1]))
          for i = vars.length() - 2; i >= 0; i = i - 1 {
            tuple_pat = Con(Var(sanitize_name(vars[i])), tuple_pat)
          }
          redexes.push({ fst: scrut_val, snd: tuple_pat })
        }
        return self.lower_expr_to_tree(alts[0].expr, redexes)
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

  // Case 2: Integer / Boolean Condition Branching
  let mut has_lit0 = false
  let mut lit0_expr : @syntax.Expr? = None
  let mut has_lit1 = false
  let mut lit1_expr : @syntax.Expr? = None
  let mut default_expr : @syntax.Expr? = None
  let lit_alts : Array[(Int, @syntax.Alt)] = []

  for alt in alts {
    match alt.pat {
      Lit(n) => {
        lit_alts.push((n, alt))
        if n == 0 {
          has_lit0 = true
          lit0_expr = Some(alt.expr)
        } else if n == 1 {
          has_lit1 = true
          lit1_expr = Some(alt.expr)
        }
      }
      Default(_) => {
        default_expr = Some(alt.expr)
      }
      _ => ()
    }
  }

  let is_pure_bool_switch =
    (has_lit1 && !has_lit0 && lit_alts.length() == 1 && default_expr is Some(_)) ||
    (!has_lit1 && has_lit0 && lit_alts.length() == 1 && default_expr is Some(_)) ||
    (has_lit0 && has_lit1 && lit_alts.length() == 2 && default_expr is None)

  if lit_alts.length() > 0 && !is_pure_bool_switch {
    let scrut_var = if binder.length() > 0 { binder } else { self.fresh_var("swi_scrut") }
    let mut cur_expr = match default_expr {
      Some(d) => d
      None => @syntax.Expr::LitInt(0)
    }
    for i = lit_alts.length() - 1; i >= 0; i = i - 1 {
      let (k, alt) = lit_alts[i]
      cur_expr = @syntax.Expr::Case(
        @syntax.Expr::App(
          @syntax.Expr::App(@syntax.Expr::Var("==#"), @syntax.Expr::Var(scrut_var)),
          @syntax.Expr::LitInt(k)
        ),
        "",
        [
          @syntax.Alt::{ pat: Lit(1), expr: alt.expr },
          @syntax.Alt::{ pat: Default(None), expr: cur_expr },
        ]
      )
    }
    let desugared = @syntax.Expr::Let(@syntax.Bind::NonRec(scrut_var, scrut), cur_expr)
    return self.lower_expr_to_tree(desugared, redexes)
  }

  // Case 2A: 1# vs __DEFAULT (boolean comparison)
  if has_lit1 && !has_lit0 && lit1_expr is Some(then_e) && default_expr is Some(else_e) {
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

  // Case 2B: 0# vs __DEFAULT
  if has_lit0 && !has_lit1 && lit0_expr is Some(zero_e) && default_expr is Some(def_e) {
    let cond_tree = self.lower_expr_to_tree(scrut, redexes)
    let cond_val = if binder.length() > 0 {
      let b_name = sanitize_name(binder)
      redexes.push({ fst: cond_tree, snd: Var(b_name) })
      Var(b_name)
    } else {
      cond_tree
    }
    let ret = self.fresh_var("case_ret")

    let zero_fvs = get_free_vars(zero_e, [])
    let def_fvs = get_free_vars(def_e, [])
    let env_vars : Array[String] = []
    for v in zero_fvs {
      if !self.is_top_level(v) && !is_builtin_prim(v) {
        env_vars.push(v)
      }
    }
    for v in def_fvs {
      if !self.is_top_level(v) && !is_builtin_prim(v) {
        let mut found = false
        for e in env_vars {
          if e == v { found = true; break }
        }
        if !found { env_vars.push(v) }
      }
    }

    let zero_helper = self.fresh_helper_name("branch_zero")
    let zero_ret = self.fresh_var("ret")
    let zero_redexes : Array[Redex] = []
    let zero_body_tree = self.lower_expr_to_tree(zero_e, zero_redexes)
    zero_redexes.push({ fst: zero_body_tree, snd: Var(zero_ret) })
    let mut zero_root : Tree = Var(zero_ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      zero_root = Con(Var(sanitize_name(env_vars[i])), zero_root)
    }
    self.add_def(zero_helper, Net::{ root: zero_root, redexes: zero_redexes })

    let def_helper = self.fresh_helper_name("branch_default")
    let def_ret = self.fresh_var("ret")
    let def_redexes : Array[Redex] = []
    let def_body_tree = self.lower_expr_to_tree(def_e, def_redexes)
    def_redexes.push({ fst: def_body_tree, snd: Var(def_ret) })
    let mut def_root : Tree = Var(def_ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      def_root = Con(Var(sanitize_name(env_vars[i])), def_root)
    }
    def_root = Con(Era, def_root)
    self.add_def(def_helper, Net::{ root: def_root, redexes: def_redexes })

    let mut call_spine : Tree = Var(ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      call_spine = Con(Var(sanitize_name(env_vars[i])), call_spine)
    }

    redexes.push({
      fst: cond_val,
      snd: Swi(Con(Ref(zero_helper), Ref(def_helper)), call_spine)
    })

    return Var(ret)
  }

  // Case 2C: 0# vs 1# vs __DEFAULT
  if has_lit0 && has_lit1 && lit0_expr is Some(zero_e) && lit1_expr is Some(one_e) && default_expr is Some(def_e) {
    let cond_tree = self.lower_expr_to_tree(scrut, redexes)
    let cond_val = if binder.length() > 0 {
      let b_name = sanitize_name(binder)
      redexes.push({ fst: cond_tree, snd: Var(b_name) })
      Var(b_name)
    } else {
      cond_tree
    }
    let ret = self.fresh_var("case_ret")

    let zero_fvs = get_free_vars(zero_e, [])
    let one_fvs = get_free_vars(one_e, [])
    let def_fvs = get_free_vars(def_e, [])
    let env_vars : Array[String] = []
    for v in zero_fvs {
      if !self.is_top_level(v) && !is_builtin_prim(v) {
        env_vars.push(v)
      }
    }
    for v in one_fvs {
      if !self.is_top_level(v) && !is_builtin_prim(v) {
        let mut found = false
        for e in env_vars { if e == v { found = true; break } }
        if !found { env_vars.push(v) }
      }
    }
    for v in def_fvs {
      if !self.is_top_level(v) && !is_builtin_prim(v) {
        let mut found = false
        for e in env_vars { if e == v { found = true; break } }
        if !found { env_vars.push(v) }
      }
    }

    let zero_helper = self.fresh_helper_name("branch_zero")
    let zero_ret = self.fresh_var("ret")
    let zero_redexes : Array[Redex] = []
    let zero_body_tree = self.lower_expr_to_tree(zero_e, zero_redexes)
    zero_redexes.push({ fst: zero_body_tree, snd: Var(zero_ret) })
    let mut zero_root : Tree = Var(zero_ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      zero_root = Con(Var(sanitize_name(env_vars[i])), zero_root)
    }
    self.add_def(zero_helper, Net::{ root: zero_root, redexes: zero_redexes })

    let one_helper = self.fresh_helper_name("branch_one")
    let one_ret = self.fresh_var("ret")
    let one_redexes : Array[Redex] = []
    let one_body_tree = self.lower_expr_to_tree(one_e, one_redexes)
    one_redexes.push({ fst: one_body_tree, snd: Var(one_ret) })
    let mut one_root : Tree = Var(one_ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      one_root = Con(Var(sanitize_name(env_vars[i])), one_root)
    }
    self.add_def(one_helper, Net::{ root: one_root, redexes: one_redexes })

    let def_helper = self.fresh_helper_name("branch_default")
    let def_ret = self.fresh_var("ret")
    let def_redexes : Array[Redex] = []
    let def_body_tree = self.lower_expr_to_tree(def_e, def_redexes)
    def_redexes.push({ fst: def_body_tree, snd: Var(def_ret) })
    let mut def_root : Tree = Var(def_ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      def_root = Con(Var(sanitize_name(env_vars[i])), def_root)
    }
    def_root = Con(Era, def_root)
    self.add_def(def_helper, Net::{ root: def_root, redexes: def_redexes })

    let succ_helper = self.fresh_helper_name("branch_succ")
    let succ_ret = self.fresh_var("ret")
    let succ_pred = self.fresh_var("pred")
    let mut inner_spine : Tree = Var(succ_ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      inner_spine = Con(Var(sanitize_name(env_vars[i])), inner_spine)
    }
    let succ_redexes : Array[Redex] = [
      {
        fst: Var(succ_pred),
        snd: Swi(Con(Ref(one_helper), Ref(def_helper)), inner_spine)
      }
    ]
    let mut succ_root : Tree = Var(succ_ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      succ_root = Con(Var(sanitize_name(env_vars[i])), succ_root)
    }
    succ_root = Con(Var(succ_pred), succ_root)
    self.add_def(succ_helper, Net::{ root: succ_root, redexes: succ_redexes })

    let mut call_spine : Tree = Var(ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      call_spine = Con(Var(sanitize_name(env_vars[i])), call_spine)
    }

    redexes.push({
      fst: cond_val,
      snd: Swi(Con(Ref(zero_helper), Ref(succ_helper)), call_spine)
    })

    return Var(ret)
  }

  // Case 2D: Lit(k) vs __DEFAULT (general integer / char equality switch)
  let mut single_other_lit : (Int, @syntax.Expr)? = None
  for alt in alts {
    match alt.pat {
      Lit(n) if n != 0 && n != 1 => {
        single_other_lit = Some((n, alt.expr))
      }
      _ => ()
    }
  }

  if alts.length() == 2 && single_other_lit is Some((k, then_e)) && default_expr is Some(else_e) {
    let cond_tree = self.lower_expr_to_tree(scrut, redexes)
    let cond_val = if binder.length() > 0 {
      let b_name = sanitize_name(binder)
      redexes.push({ fst: cond_tree, snd: Var(b_name) })
      Var(b_name)
    } else {
      cond_tree
    }
    let ret = self.fresh_var("case_ret")

    let then_fvs = get_free_vars(then_e, [])
    let else_fvs = get_free_vars(else_e, [])
    let env_vars : Array[String] = []
    for v in then_fvs {
      if !self.is_top_level(v) && !is_builtin_prim(v) && v != binder {
        if !array_contains(env_vars, v) { env_vars.push(v) }
      }
    }
    for v in else_fvs {
      if !self.is_top_level(v) && !is_builtin_prim(v) && v != binder {
        if !array_contains(env_vars, v) { env_vars.push(v) }
      }
    }

    let else_helper = self.fresh_helper_name("branch_else")
    let else_ret = self.fresh_var("ret")
    let else_redexes : Array[Redex] = []
    let else_body_tree = self.lower_expr_to_tree(else_e, else_redexes)
    else_redexes.push({ fst: else_body_tree, snd: Var(else_ret) })
    let mut else_root : Tree = Var(else_ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      let is_used = array_contains(else_fvs, env_vars[i])
      if is_used {
        else_root = Con(Var(sanitize_name(env_vars[i])), else_root)
      } else {
        else_root = Con(Era, else_root)
      }
    }
    self.add_def(else_helper, Net::{ root: else_root, redexes: else_redexes })

    let then_helper = self.fresh_helper_name("branch_then")
    let then_ret = self.fresh_var("ret")
    let then_redexes : Array[Redex] = []
    let then_body_tree = self.lower_expr_to_tree(then_e, then_redexes)
    then_redexes.push({ fst: then_body_tree, snd: Var(then_ret) })
    let mut then_root : Tree = Var(then_ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      let is_used = array_contains(then_fvs, env_vars[i])
      if is_used {
        then_root = Con(Var(sanitize_name(env_vars[i])), then_root)
      } else {
        then_root = Con(Era, then_root)
      }
    }
    then_root = Con(Era, then_root)
    self.add_def(then_helper, Net::{ root: then_root, redexes: then_redexes })

    let mut call_spine : Tree = Var(ret)
    for i = env_vars.length() - 1; i >= 0; i = i - 1 {
      call_spine = Con(Var(sanitize_name(env_vars[i])), call_spine)
    }

    let is_eq = self.fresh_var("is_eq")
    redexes.push({
      fst: cond_val,
      snd: Opr(OpSym("[=]"), Opr(Num(k), Var(is_eq)))
    })
    redexes.push({
      fst: Var(is_eq),
      snd: Swi(Con(Ref(else_helper), Ref(then_helper)), call_spine)
    })

    return Var(ret)
  }

  // Case 3: ADT Pattern Matching (Scott Encoding for 2 or more variants, or with Default)
  let mut adt_match_possible = false
  let mut matched_family_idx = -1
  let mut matched_num_variants = 0

  for alt in alts {
    match alt.pat {
      Data(c, _) => {
        match self.find_constr(c) {
          Some(info) => {
            if info.num_variants >= 2 {
              adt_match_possible = true
              matched_family_idx = info.family_idx
              matched_num_variants = info.num_variants
              break
            }
          }
          None => ()
        }
      }
      _ => ()
    }
  }

  if adt_match_possible {
    let family = self.adt_families[matched_family_idx]
    let mut default_alt : @syntax.Alt? = None
    let mut valid_alts = true
    for alt in alts {
      match alt.pat {
        Data(c, _) => {
          match self.find_constr(c) {
            Some(info) if info.family_idx == matched_family_idx => ()
            _ => { valid_alts = false; break }
          }
        }
        Default(_) => {
          default_alt = Some(alt)
        }
        _ => { valid_alts = false; break }
      }
    }

    if valid_alts {
      let num_variants = matched_num_variants
      let ordered_alts : Array[@syntax.Alt?] = []
      for i = 0; i < num_variants; i = i + 1 {
        ordered_alts.push(None)
      }
      for alt in alts {
        match alt.pat {
          Data(c, vars) => {
            let info = self.find_constr(c).unwrap()
            let expr = if binder.length() > 0 {
              let syn_exprs : Array[@syntax.Expr] = []
              for v in vars {
                syn_exprs.push(@syntax.Expr::Var(v))
              }
              @syntax.substitute_var(alt.expr, binder, @syntax.Expr::Constr(c, syn_exprs))
            } else {
              alt.expr
            }
            ordered_alts[info.variant_idx] = Some(@syntax.Alt::{
              pat: alt.pat,
              expr,
            })
          }
          _ => ()
        }
      }

      let mut all_slots_covered = true
      for i = 0; i < num_variants; i = i + 1 {
        if ordered_alts[i] is None {
          if default_alt is Some(def) {
            let (con_name, arity) = family[i]
            let synthetic_vars : Array[String] = []
            let syn_exprs : Array[@syntax.Expr] = []
            for a = 0; a < arity; a = a + 1 {
              let v = self.fresh_var("era")
              synthetic_vars.push(v)
              syn_exprs.push(@syntax.Expr::Var(v))
            }
            let reconstructed = @syntax.Expr::Constr(con_name, syn_exprs)
            let substituted = if binder.length() > 0 {
              @syntax.substitute_var(def.expr, binder, reconstructed)
            } else {
              def.expr
            }
            ordered_alts[i] = Some(@syntax.Alt::{
              pat: Data(con_name, synthetic_vars),
              expr: substituted,
            })
          } else {
            all_slots_covered = false
            break
          }
        }
      }

      if all_slots_covered {
        let scrut_tree = self.lower_expr_to_tree(scrut, redexes)
        let ret = self.fresh_var("match_ret")

        let env_vars : Array[String] = []
        for i = 0; i < num_variants; i = i + 1 {
          let alt = ordered_alts[i].unwrap()
          let alt_bound : Array[String] = []
          match alt.pat {
            Data(_, vars) => for v in vars { alt_bound.push(v) }
            _ => ()
          }
          let alt_fvs = get_free_vars(alt.expr, alt_bound)
          for v in alt_fvs {
            if !self.is_top_level(v) && !is_builtin_prim(v) && v != binder {
              if !array_contains(env_vars, v) {
                env_vars.push(v)
              }
            }
          }
        }

        let helper_names : Array[String] = []
        for i = 0; i < num_variants; i = i + 1 {
          let alt = ordered_alts[i].unwrap()
          let alt_bound : Array[String] = []
          match alt.pat {
            Data(_, vars) => for v in vars { alt_bound.push(v) }
            _ => ()
          }
          let alt_helper = self.fresh_helper_name("alt\{i}")
          helper_names.push(alt_helper)
          let alt_ret = self.fresh_var("ret")
          let alt_redexes : Array[Redex] = []
          let alt_body_tree = self.lower_expr_to_tree(alt.expr, alt_redexes)
          alt_redexes.push({ fst: alt_body_tree, snd: Var(alt_ret) })
          let mut alt_root : Tree = Var(alt_ret)

          let alt_fvs = get_free_vars(alt.expr, alt_bound)
          let expr_all_vars = get_free_vars(alt.expr, [])
          for j = env_vars.length() - 1; j >= 0; j = j - 1 {
            let is_used = array_contains(alt_fvs, env_vars[j])
            if is_used {
              alt_root = Con(Var(sanitize_name(env_vars[j])), alt_root)
            } else {
              alt_root = Con(Era, alt_root)
            }
          }
          for j = alt_bound.length() - 1; j >= 0; j = j - 1 {
            let is_used = array_contains(expr_all_vars, alt_bound[j])
            if is_used {
              alt_root = Con(Var(sanitize_name(alt_bound[j])), alt_root)
            } else {
              alt_root = Con(Era, alt_root)
            }
          }
          self.add_def(alt_helper, Net::{ root: alt_root, redexes: alt_redexes })
        }

        let mut call_spine : Tree = Var(ret)
        for j = env_vars.length() - 1; j >= 0; j = j - 1 {
          call_spine = Con(Var(sanitize_name(env_vars[j])), call_spine)
        }

        let mut app_chain : Tree = call_spine
        for j = num_variants - 1; j >= 0; j = j - 1 {
          app_chain = Con(Ref(helper_names[j]), app_chain)
        }

        redexes.push({ fst: scrut_tree, snd: app_chain })
        return Var(ret)
      }
    }
  }

  // Fallback: evaluate first alternative
  if alts.length() == 0 {
    return Num(0)
  }
  let scrut_tree = self.lower_expr_to_tree(scrut, redexes)
  if binder.length() > 0 {
    let b_name = sanitize_name(binder)
    redexes.push({ fst: scrut_tree, snd: Var(b_name) })
  } else {
    redexes.push({ fst: scrut_tree, snd: Era })
  }
  let def_ret = self.fresh_var("case_fallback")
  let tree = self.lower_expr_to_tree(alts[0].expr, redexes)
  redexes.push({ fst: tree, snd: Var(def_ret) })
  Var(def_ret)
}

// ----------------------------------------------------------------------------
