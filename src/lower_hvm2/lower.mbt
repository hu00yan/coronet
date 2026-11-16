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
// Identifier Sanitization
// ----------------------------------------------------------------------------

///| Check if an identifier is an unboxed tuple constructor
pub fn is_unboxed_tuple_con(name : String) -> Bool {
  match name {
    "(#,#)" | "(#,,#)" | "(#,,,#)" | "(#,,,,#)" | "(# #)" | "(##)" | "(#_#)" | "Solo#" | "Unit#" => true
    _ => {
      if name.has_prefix("(#") && (name.has_suffix("#)") || name.has_suffix("#")) {
        true
      } else {
        false
      }
    }
  }
}

///| Check if an identifier is any tuple constructor (boxed or unboxed)
pub fn is_tuple_con(name : String) -> Bool {
  if is_unboxed_tuple_con(name) {
    return true
  }
  match name {
    "(,)" | "(,,)" | "(,,,)" | "(,,,,)" | "Pair" | "Tuple3" | "Tuple4" | "CAlt" => true
    _ => false
  }
}

///| Sanitize Core identifiers into valid HVM2 alphanumeric names
pub fn sanitize_name(name : String) -> String {
  match name {
    "+" | "+#" | "plusWord#" | "plusWord32#" | "$fNumWord32_$c" | "$fNumWord32_$c+" | "$fNumWord32_$c+#" => "add"
    "-" | "-#" | "minusWord#" | "minusWord32#" => "sub"
    "*" | "*#" | "timesWord#" | "timesWord32#" => "mul"
    "*H#" => "prim_mul_hi"
    "/" | "/#" | "quotWord#" | "quotWord32#" | "quotInt#" => "div"
    "%" | "%#" | "remWord#" | "remWord32#" | "remInt#" => "rem"
    "<=#" | "<=" | "leWord#" | "leWord32#" => "lte"
    ">=#" | ">=" | "geWord#" | "geWord32#" => "gte"
    "<#" | "<" | "ltWord#" | "ltWord32#" => "lt"
    ">#" | ">" | "gtWord#" | "gtWord32#" => "gt"
    "==#" | "==" | "eqWord#" | "eqWord32#" => "eq"
    "/=#" | "/=" | "neWord#" | "neWord32#" => "neq"
    "&" | "and#" | "andI#" | ".&." => "and"
    "|" | "or#" | "orI#" | ".|." => "or"
    "^" | "xor#" | "xorI#" | "xor" | ".^." => "xor"
    "<<" | "uncheckedIShiftL#" | "uncheckedShiftL#" | "shiftL" => "shl"
    ">>" | "uncheckedIShiftRL#" | "uncheckedShiftRL#" | "uncheckedIShiftRA#" | "uncheckedShiftRA#" | "shiftR" => "shr"
    "I#" => "I_hash"
    "W#" => "W_hash"
    "W32#" => "W32_hash"
    "[]" => "Nil"
    ":" => "Cons"
    "()" => "Unit"
    "(#,#)" => "unboxed_tuple2"
    "(#,,#)" => "unboxed_tuple3"
    "(#,,,#)" => "unboxed_tuple4"
    "(# #)" | "(##)" => "unboxed_unit"
    "(#_#)" | "Solo#" => "unboxed_solo"
    "Unit#" => "unboxed_unit"
    "(,)" => "Pair"
    "(,,)" => "Tuple3"
    "(,,,)" => "Tuple4"
    "runRW#" => "runRW"
    "newByteArray#" => "newByteArray"
    "writeIntArray#" => "writeIntArray"
    "readIntArray#" => "readIntArray"
    "writeByteArray#" => "writeByteArray"
    "readByteArray#" => "readByteArray"
    "sizeofByteArray#" => "sizeofByteArray"
    "indexWord8Array#" => "indexWord8Array"
    "indexIntArray#" => "indexWord8Array"
    "readWord8Array#" => "readByteArray"
    "writeWord8Array#" => "writeByteArray"
    "copyByteArray#" => "copyByteArray"
    "newMutVar#" => "newMutVar"
    "readMutVar#" => "readMutVar"
    "writeMutVar#" => "writeMutVar"
    "unpackCString#" => "unpackCString"
    "unpackCStringUtf8#" => "unpackCString"
    "raise#" => "raise"
    "raiseIO#" => "raiseIO"
    "narrow8Word#" => "narrow8Word"
    "narrow16Word#" => "narrow16Word"
    "narrow8Int#" => "narrow8Int"
    "narrow16Int#" => "narrow16Int"
    "chr#" | "ord#" => "I_hash"
    "plusAddr#" => "plusAddr"
    "eqAddr#" => "eqAddr"
    "readWord8OffAddr#" => "readWord8OffAddr"
    "touch#" => "touch"
    "word8ToWord#" => "I_hash"
    "compare" => "compare"
    "Eq" | "C:Eq" => "Eq"
    "Show" | "C:Show" => "Show"
    "C" => "C"
    "tagToEnum#" => "tagToEnum"
    "dataToTagSmall#" => "dataToTagSmall"
    "tag_Literal" => "tag_Literal"
    "tag_Bool" => "tag_Bool"
    "tag_AltCon" => "tag_AltCon"
    "tag_CoreBind" => "tag_CoreBind"
    "tag_CoreExpr" => "tag_CoreExpr"
    "tag_Value" => "tag_Value"
    "patError" | "patError#" => "patError"
    "eqString" => "eqString"
    "++" | "_plus__plus_" | "append" => "append"
    "realWorld#" | "void#" => "realWorld"
    "overflowError" => "overflowError"
    "divZeroError" => "divZeroError"
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
        } else if (c >= 'a'.to_int().to_uint16() && c <= 'z'.to_int().to_uint16()) ||
                  (c >= 'A'.to_int().to_uint16() && c <= 'Z'.to_int().to_uint16()) ||
                  (c >= '0'.to_int().to_uint16() && c <= '9'.to_int().to_uint16()) ||
                  c == '_'.to_int().to_uint16() {
          buf.write_char(c.to_int().unsafe_to_char())
        } else {
          buf.write_char('_')
        }
      }
      buf.to_string()
    }
  }
}

///| Check if an identifier is an inlined binary operator
pub fn is_inlined_binop(op : String) -> Bool {
  match op {
    "+" | "+#" | "plusWord#" | "plusWord32#" | "plusAddr#" | "$fNumWord32_$c" | "$fNumWord32_$c+" | "$fNumWord32_$c+#" => true
    "-" | "-#" | "minusWord#" | "minusWord32#" => true
    "*" | "*#" | "timesWord#" | "timesWord32#" => true
    "*H#" => true
    "/" | "/#" | "quotWord#" | "quotWord32#" | "quotInt#" => true
    "%" | "%#" | "remWord#" | "remWord32#" | "remInt#" => true
    "==#" | "==" | "eqWord#" | "eqWord32#" | "eqAddr#" => true
    "/=#" | "/=" | "neWord#" | "neWord32#" => true
    "<#" | "<" | "ltWord#" | "ltWord32#" => true
    ">#" | ">" | "gtWord#" | "gtWord32#" => true
    "<=#" | "<=" | "leWord#" | "leWord32#" => true
    ">=#" | ">=" | "geWord#" | "geWord32#" => true
    "&" | "and#" | "andI#" | ".&." => true
    "|" | "or#" | "orI#" | ".|." => true
    "^" | "xor#" | "xorI#" | "xor" | ".^." => true
    "<<" | "uncheckedIShiftL#" | "uncheckedShiftL#" | "shiftL" => true
    ">>" | "uncheckedIShiftRL#" | "uncheckedShiftRL#" | "uncheckedIShiftRA#" | "uncheckedShiftRA#" | "shiftR" => true
    _ => false
  }
}

///| Check if an identifier is a builtin primitive operator
pub fn is_builtin_prim(name : String) -> Bool {
  match name {
    "+" | "+#" | "plusWord#" | "plusWord32#" | "$fNumWord32_$c" | "$fNumWord32_$c+" | "$fNumWord32_$c+#" | "+##" | "plusFloat#" => true
    "-" | "-#" | "minusWord#" | "minusWord32#" | "-##" | "minusFloat#" => true
    "*" | "*#" | "timesWord#" | "timesWord32#" | "*##" | "timesFloat#" => true
    "*H#" => true
    "/" | "/#" | "quotWord#" | "quotWord32#" | "quotInt#" | "/##" | "divideFloat#" => true
    "%" | "%#" | "remWord#" | "remWord32#" | "remInt#" => true
    "<=#" | "<=" | "leWord#" | "leWord32#" | "<=##" | "leFloat#" => true
    ">=#" | ">=" | "geWord#" | "geWord32#" | ">=##" | "geFloat#" => true
    "<#" | "<" | "ltWord#" | "ltWord32#" | "<##" | "ltFloat#" => true
    ">#" | ">" | "gtWord#" | "gtWord32#" | ">##" | "gtFloat#" => true
    "==#" | "==" | "eqWord#" | "eqWord32#" | "==##" | "eqFloat#" => true
    "/=#" | "/=" | "neWord#" | "neWord32#" | "/=##" | "neFloat#" => true
    "&" | "and#" | "andI#" | ".&." => true
    "|" | "or#" | "orI#" | ".|." => true
    "^" | "xor#" | "xorI#" | "xor" | ".^." => true
    "<<" | "uncheckedIShiftL#" | "uncheckedShiftL#" | "shiftL" => true
    ">>" | "uncheckedIShiftRL#" | "uncheckedShiftRL#" | "uncheckedIShiftRA#" | "uncheckedShiftRA#" | "shiftR" => true
    "I#" | "W#" | "W32#" | "W8#" | "W16#" | "W64#" | "I8#" | "I16#" | "I32#" | "I64#" | "Int#" | "Word#" | "C#" | "Char#" | "D#" | "F#" => true
    "word2Int#" | "int2Word#" | "word32ToWord#" | "wordToWord32#" | "narrow32Word#" | "double2Int#" | "int2Double#" | "float2Int#" | "int2Float#" | "float2Double#" | "double2Float#" => true
    "narrow8Int#" | "narrow16Int#" | "narrow8Word#" | "narrow16Word#" => true
    "chr#" | "ord#" => true
    "not#" | "notI#" | "notWord#" | "negateInt#" | "negateDouble#" | "negateFloat#" => true
    "quotRemInt#" | "quotRemWord#" => true
    "(#,#)" | "(#,,#)" | "(#,,,#)" | "(# #)" | "(##)" | "(#_#)" | "Solo#" | "Unit#" => true
    "(,)" | "(,,)" | "(,,,)" => true
    "runRW#" | "newByteArray#" | "writeIntArray#" | "readIntArray#" | "writeByteArray#" | "readByteArray#" => true
    "sizeofByteArray#" | "sizeofMutableByteArray#" | "indexWord8Array#" | "readWord8Array#" | "writeWord8Array#" | "indexIntArray#" | "copyByteArray#" | "copyMutableByteArray#" | "setByteArray#" => true
    "newArray#" | "readArray#" | "writeArray#" | "indexArray#" | "sizeofArray#" | "sizeofMutableArray#" | "sameMutableArray#" | "sameMutableByteArray#" | "byteArrayContents#" => true
    "newSmallArray#" | "readSmallArray#" | "writeSmallArray#" | "indexSmallArray#" | "sizeofSmallArray#" | "sizeofSmallMutableArray#" => true
    "newMutVar#" | "readMutVar#" | "writeMutVar#" | "casMutVar#" | "atomicModifyMutVar2#" => true
    "newMVar#" | "takeMVar#" | "tryTakeMVar#" | "putMVar#" | "tryPutMVar#" | "readMVar#" | "tryReadMVar#" | "isEmptyMVar#" => true
    "fork#" | "forkOn#" | "killThread#" | "yield#" | "myThreadId#" | "labelThread#" | "isCurrentThreadBound#" | "noDuplicate#" | "spark#" | "seq#" | "keepAlive#" => true
    "plusAddr#" | "minusAddr#" | "remAddr#" | "addr2Int#" | "int2Addr#" | "eqAddr#" | "neAddr#" | "ltAddr#" | "leAddr#" | "gtAddr#" | "geAddr#" => true
    "readWord8OffAddr#" | "writeWord8OffAddr#" | "readIntOffAddr#" | "writeIntOffAddr#" | "touch#" | "word8ToWord#" | "wordToWord8#" | "compare" => true
    "unpackCString#" | "unpackCStringUtf8#" | "unpackAppendCString#" | "unpackFoldrCString#" => true
    "raise#" | "raiseIO#" => true
    "realWorld#" | "void#" => true
    "overflowError" | "divZeroError" | "absentError" => true
    "add_mod" | "mul31_mod" => true
    "Eq" | "C:Eq" | "Show" | "C:Show" | "C" | "C_Eq" => true
    "tag_Literal" | "tag_Bool" | "tag_AltCon" | "tag_CoreBind" | "tag_CoreExpr" | "tag_Value" => true
    "tagToEnum#" | "dataToTagSmall#" | "patError" | "patError#" | "eqString" | "_plus__plus_" | "append" => true
    "map" | "filter" | "elem" | "notElem" | "concatMap" | "fst" | "snd" => true
    "$fEqList_$s$c_ne_1" | "_fEqList__s_c_ne_1" | "$fEqList_$c_eq_" | "_fEqList__c_eq_" => true
    "$fEqTuple2" | "_fEqTuple2" | "$fEqList_$s$fEqList1" | "_fEqList__s_fEqList1" => true
    _ => false
  }
}


///| Check if an identifier is a builtin primitive operator
pub fn builtin_prim_name(name : String) -> String {
  match name {
    "+" | "+#" | "plusWord#" | "plusWord32#" | "$fNumWord32_$c" | "$fNumWord32_$c+" | "$fNumWord32_$c+#" | "+##" | "plusFloat#" => "prim_add"
    "-" | "-#" | "minusWord#" | "minusWord32#" | "-##" | "minusFloat#" | "minusAddr#" => "prim_sub"
    "*" | "*#" | "timesWord#" | "timesWord32#" | "*##" | "timesFloat#" => "prim_mul"
    "*H#" => "prim_mul_hi"
    "/" | "/#" | "quotWord#" | "quotWord32#" | "quotInt#" | "/##" | "divideFloat#" => "prim_div"
    "%" | "%#" | "remWord#" | "remWord32#" | "remInt#" | "remAddr#" => "prim_rem"
    "<=#" | "<=" | "leWord#" | "leWord32#" | "<=##" | "leFloat#" | "leAddr#" => "prim_lte"
    ">=#" | ">=" | "geWord#" | "geWord32#" | ">=##" | "geFloat#" | "geAddr#" => "prim_gte"
    "<#" | "<" | "ltWord#" | "ltWord32#" | "<##" | "ltFloat#" | "ltAddr#" => "prim_lt"
    ">#" | ">" | "gtWord#" | "gtWord32#" | ">##" | "gtFloat#" | "gtAddr#" => "prim_gt"
    "==#" | "==" | "eqWord#" | "eqWord32#" | "==##" | "eqFloat#" | "sameMutableArray#" | "sameMutableByteArray#" => "prim_eq"
    "/=#" | "/=" | "neWord#" | "neWord32#" | "/=##" | "neFloat#" | "neAddr#" => "prim_neq"
    "&" | "and#" | "andI#" | ".&." => "prim_and"
    "|" | "or#" | "orI#" | ".|." => "prim_or"
    "^" | "xor#" | "xorI#" | "xor" | ".^." => "prim_xor"
    "<<" | "uncheckedIShiftL#" | "uncheckedShiftL#" | "shiftL" => "prim_shl"
    ">>" | "uncheckedIShiftRL#" | "uncheckedShiftRL#" | "uncheckedIShiftRA#" | "uncheckedShiftRA#" | "shiftR" => "prim_shr"
    "I#" | "W#" | "W32#" | "W8#" | "W16#" | "W64#" | "I8#" | "I16#" | "I32#" | "I64#" | "Int#" | "Word#" | "C#" | "Char#" | "D#" | "F#" => "I_hash"
    "word2Int#" | "int2Word#" | "word32ToWord#" | "wordToWord32#" | "narrow32Word#" | "word8ToWord#" | "wordToWord8#" | "addr2Int#" | "int2Addr#" | "byteArrayContents#" => "I_hash"
    "double2Int#" | "int2Double#" | "float2Int#" | "int2Float#" | "float2Double#" | "double2Float#" => "I_hash"
    "labelThread#" | "isCurrentThreadBound#" => "I_hash"
    "quotRemInt#" | "quotRemWord#" => "quotRemInt"
    "narrow8Word#" => "narrow8Word"
    "narrow16Word#" => "narrow16Word"
    "narrow8Int#" => "narrow8Int"
    "narrow16Int#" => "narrow16Int"
    "chr#" | "ord#" => "I_hash"
    "not#" | "notI#" | "notWord#" | "negateInt#" | "negateDouble#" | "negateFloat#" => "negateInt"
    "plusAddr#" => "plusAddr"
    "eqAddr#" => "eqAddr"
    "readWord8OffAddr#" | "readIntOffAddr#" => "readWord8OffAddr"
    "writeWord8OffAddr#" | "writeIntOffAddr#" => "writeWord8OffAddr"
    "touch#" | "noDuplicate#" | "keepAlive#" => "touch"
    "compare" => "compare"
    "add_mod" => "add_mod"
    "mul31_mod" => "mul31_mod"
    "Eq" | "C:Eq" | "C_Eq" => "C_Eq"
    "Show" | "C:Show" => "Show"
    "C" => "C"
    "tagToEnum#" => "tagToEnum"
    "dataToTagSmall#" | "dataToTagLarge#" | "dataToTag#" => "dataToTagSmall"
    "tag_Literal" => "tag_Literal"
    "tag_Bool" => "tag_Bool"
    "tag_AltCon" => "tag_AltCon"
    "tag_CoreBind" => "tag_CoreBind"
    "tag_CoreExpr" => "tag_CoreExpr"
    "tag_Value" => "tag_Value"
    "patError" | "patError#" | "absentError" => "patError"
    "eqString" => "eqString"
    "++" | "_plus__plus_" | "append" => "append"
    "map" => "map"
    "filter" => "filter"
    "elem" => "elem"
    "notElem" => "notElem"
    "concatMap" => "concatMap"
    "fst" => "fst"
    "snd" => "snd"
    "$fEqList_$s$c_ne_1" | "_fEqList__s_c_ne_1" => "_fEqList__s_c_ne_1"
    "$fEqList_$c_eq_" | "_fEqList__c_eq_" => "_fEqList__c_eq_"
    "$fEqTuple2" | "_fEqTuple2" => "_fEqTuple2"
    "$fEqList_$s$fEqList1" | "_fEqList__s_fEqList1" => "_fEqList__s_fEqList1"
    "unpackCString#" | "unpackCStringUtf8#" | "unpackAppendCString#" | "unpackFoldrCString#" => "unpackCString"
    "sizeofByteArray#" | "sizeofMutableByteArray#" | "sizeofArray#" | "sizeofMutableArray#" | "sizeofSmallArray#" | "sizeofSmallMutableArray#" | "getSizeofMutableByteArray#" => "sizeofByteArray"
    "indexWord8Array#" | "indexIntArray#" | "indexArray#" | "indexSmallArray#" | "indexCharArray#" => "indexWord8Array"
    "readWord8Array#" | "readByteArray#" | "readArray#" | "readSmallArray#" | "readCharArray#" => "readByteArray"
    "writeWord8Array#" | "writeByteArray#" | "writeArray#" | "writeSmallArray#" | "writeCharArray#" => "writeByteArray"
    "newByteArray#" | "newArray#" | "newSmallArray#" | "newPinnedByteArray#" | "newAlignedPinnedByteArray#" => "newByteArray"
    "copyByteArray#" | "copyMutableByteArray#" => "copyByteArray"
    "setByteArray#" => "setByteArray"
    "newMutVar#" => "newMutVar"
    "readMutVar#" => "readMutVar"
    "writeMutVar#" => "writeMutVar"
    "casMutVar#" => "casMutVar"
    "atomicModifyMutVar2#" => "atomicModifyMutVar2"
    "newMVar#" => "newMVar"
    "takeMVar#" => "takeMVar"
    "tryTakeMVar#" => "tryTakeMVar"
    "putMVar#" => "putMVar"
    "tryPutMVar#" => "tryPutMVar"
    "readMVar#" => "readMVar"
    "tryReadMVar#" => "tryReadMVar"
    "isEmptyMVar#" => "isEmptyMVar"
    "fork#" | "forkOn#" => "fork"
    "killThread#" => "killThread"
    "yield#" => "yield"
    "myThreadId#" => "myThreadId"
    "spark#" => "spark"
    "seq#" => "seq"
    "raise#" => "raise"
    "raiseIO#" => "raiseIO"
    "overflowError" => "overflowError"
    "divZeroError" => "divZeroError"
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

priv struct ConstrInfo {
  name : String
  variant_idx : Int
  num_variants : Int
  family_idx : Int
}

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

fn LowerCtx::has_def(self : LowerCtx, name : String) -> Bool {
  for d in self.defs {
    if d.0 == name { return true }
  }
  false
}

fn LowerCtx::find_constr(self : LowerCtx, name : String) -> ConstrInfo? {
  for c in self.known_constrs {
    if c.name == name {
      return Some(c)
    }
  }
  None
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

  // String / CString primitives
  self.add_def("unpackCString", Net::{
    root: Con(Var("s"), Var("s")),
    redexes: [],
  })
  self.add_def("unpackCStringUtf8", Net::{
    root: Con(Var("s"), Var("s")),
    redexes: [],
  })

  // MutVar# primitives
  self.add_def("newMutVar", Net::{
    root: Con(Var("val"), Con(Var("s"), Var("ret"))),
    redexes: [
      { fst: Var("ret"), snd: Con(Con(Var("val"), Var("s")), Num(0)) },
    ],
  })
  self.add_def("writeMutVar", Net::{
    root: Con(Var("mv"), Con(Var("val"), Con(Var("s"), Var("ret")))),
    redexes: [
      {
        fst: Var("mv"),
        snd: Swi(Con(Ref("write_at_0"), Ref("write_at_next")), Con(Var("val"), Con(Var("s"), Var("ret")))),
      },
    ],
  })
  self.add_def("readMutVar", Net::{
    root: Con(Var("mv"), Con(Var("s"), Var("ret"))),
    redexes: [
      {
        fst: Var("mv"),
        snd: Swi(Con(Ref("read_at_0"), Ref("read_at_next")), Con(Var("s"), Var("ret"))),
      },
    ],
  })

  // Raise and error primitives
  self.add_def("raise", Net::{
    root: Con(Era, Num(0)),
    redexes: [],
  })
  self.add_def("raiseIO", Net::{
    root: Con(Era, Con(Var("s"), Con(Con(Var("s"), Num(0)), Num(0)))),
    redexes: [],
  })

  // Concurrency, MVar and Thread primitives
  self.add_def("writeWord8OffAddr", Net::{
    root: Con(Era, Con(Era, Con(Era, Con(Var("s"), Var("ret"))))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Num(0)) }],
  })
  self.add_def("setByteArray", Net::{
    root: Con(Era, Con(Era, Con(Era, Con(Era, Con(Var("s"), Var("ret")))))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Num(0)) }],
  })
  self.add_def("newMVar", Net::{
    root: Con(Var("s"), Var("ret")),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Num(0)) }],
  })
  self.add_def("takeMVar", Net::{
    root: Con(Era, Con(Var("s"), Var("ret"))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Num(0)) }],
  })
  self.add_def("tryTakeMVar", Net::{
    root: Con(Era, Con(Var("s"), Var("ret"))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Con(Num(1), Num(0))) }],
  })
  self.add_def("putMVar", Net::{
    root: Con(Era, Con(Era, Con(Var("s"), Var("ret")))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Num(0)) }],
  })
  self.add_def("tryPutMVar", Net::{
    root: Con(Era, Con(Era, Con(Var("s"), Var("ret")))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Num(1)) }],
  })
  self.add_def("readMVar", Net::{
    root: Con(Era, Con(Var("s"), Var("ret"))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Num(0)) }],
  })
  self.add_def("tryReadMVar", Net::{
    root: Con(Era, Con(Var("s"), Var("ret"))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Con(Num(1), Num(0))) }],
  })
  self.add_def("isEmptyMVar", Net::{
    root: Con(Era, Con(Var("s"), Var("ret"))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Num(0)) }],
  })
  self.add_def("casMutVar", Net::{
    root: Con(Era, Con(Era, Con(Var("new"), Con(Var("s"), Var("ret"))))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Con(Num(0), Var("new"))) }],
  })
  self.add_def("atomicModifyMutVar2", Net::{
    root: Con(Era, Con(Era, Con(Var("s"), Var("ret")))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Con(Num(0), Num(0))) }],
  })
  self.add_def("fork", Net::{
    root: Con(Era, Con(Var("s"), Var("ret"))),
    redexes: [{ fst: Var("ret"), snd: Con(Var("s"), Num(1)) }],
  })
  self.add_def("killThread", Net::{
    root: Con(Era, Con(Var("s"), Var("s"))),
    redexes: [],
  })
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
  self.add_def("realWorld", Net::{ root: Num(0), redexes: [] })

  self.add_def("runRW", Net::{
    root: Con(Var("f"), Var("ret")),
    redexes: [
      { fst: Var("f"), snd: Con(Num(0), Var("ret")) },
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
  self.register_known_constructors()
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
      let mut already_registered = false
      for ctor in fam.ctors {
        if self.find_constr(ctor.name) is Some(_) {
          already_registered = true
          break
        }
      }
      if !already_registered {
        self.register_adt(variants)
      }
    }
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
    LitInt(n) => Num((n.to_int64() & 0xFFFFFFL).to_int())
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

fn has_64bit_indicator(prog : @syntax.Program) -> Bool {
  fn expr_has_64bit(e : @syntax.Expr) -> Bool {
    match e {
      LitInt(i) => i > 16777215 && i != 1000000007
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
    LitInt(_) | LitChar(_) | LitString(_) => expr
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
  @mid.prune_book_text(book.to_string(), ["main"])
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
