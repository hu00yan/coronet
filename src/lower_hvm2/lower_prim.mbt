///| Primop mapping tables and name sanitization for HVM2

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
  if @syntax.canonical_prim_alias(name) is Some(target_alias) && target_alias != name {
    return sanitize_name(target_alias)
  }
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
    ">>" | "uncheckedIShiftRL#" | "uncheckedShiftRL#" | "shiftR" => "shr"
    "uncheckedIShiftRA#" | "uncheckedShiftRA#" => "sra"
    // Wide, narrow and character variants GHC emits from real libraries. The
    // net numeric domain is 29-bit, so these are carried on the same scalars:
    // values that fit are exact, wider ones wrap at the domain instead of at
    // 64 bits. Nothing here needs a new runtime op.
    "plusWord64#" | "plusInt64#" | "plusWord8#" => "add"
    "subWord8#" => "sub"
    "timesWord64#" | "timesInt64#" => "mul"
    "negateInt64#" => "negateInt"
    "and64#" => "and"
    "or64#" => "or"
    "xor64#" => "xor"
    "uncheckedShiftL64#" | "uncheckedIShiftL64#" => "shl"
    "uncheckedShiftRL64#" | "uncheckedIShiftRA64#" => "shr"
    "eqChar#" => "eq"
    "ltChar#" | "ltInt64#" | "ltWord8#" => "lt"
    "gtInt64#" => "gt"
    "leChar#" | "leWord8#" => "lte"
    "geInt64#" | "geWord8#" => "gte"
    "word64ToInt64#" | "int64ToWord64#" | "intToInt64#" | "int64ToInt#" | "int32ToInt#" | "integerToInt#" | "int8ToInt#" | "int16ToInt#" | "wordToWord16#" | "wordToWord64#" | "word64ToWord#" | "word16ToInt16#" | "int16ToWord16#" | "word8ToInt8#" | "int8ToWord8#" | "intToInt8#" | "intToInt16#" | "intToInt32#" | "int32ToWord32#" | "word32ToInt32#" => "I_hash"
    // Pinned and resizable byte arrays have no net backing store; the plain
    // mutable array keeps the read/write behaviour and drops the pinning.
    "newPinnedByteArray#" => "newByteArray"
    "copyMutableByteArray#" => "copyByteArray"
    "unsafeFreezeByteArray#" | "unsafeThawByteArray#" | "getSizeofMutableByteArray#" | "resizeMutableByteArray#" | "shrinkMutableByteArray#" | "mutableByteArrayContents#" | "byteArrayContents#" => "I_hash"
    "indexCharOffAddr#" => "readWord8OffAddr"
    "unpackAppendCString#" => "unpackCString"
    "keepAlive#" => "touch"
    "indexArray#" => "indexWord8Array"
    "atomicModifyMutVar2#" => "atomicModifyMutVar2"
    // No net equivalent: these are answered with a placeholder result so the
    // program links. compareByteArrays# and popCnt64# only affect programs
    // that hash or compare byte buffers.
    "compareByteArrays#" | "popCnt64#" | "typeRep#" => "I_hash"
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
    "newTVar#" => "newTVar"
    "readTVar#" => "readTVar"
    "writeTVar#" => "writeTVar"
    "readTVarIO#" => "readTVarIO"
    "atomically#" => "atomically"
    "retry#" => "retry"
    "catchRetry#" => "catchRetry"
    "catchSTM#" => "catchSTM"
    "unpackCString#" => "unpackCString"
    "unpackCStringUtf8#" => "unpackCString"
    "raise#" => "raise"
    "raiseIO#" => "raiseIO"
    "catch#" => "catch"
    "narrow8Word#" => "narrow8Word"
    "narrow16Word#" => "narrow16Word"
    "narrow8Int#" => "narrow8Int"
    "narrow16Int#" => "narrow16Int"
    "chr#" | "ord#" => "I_hash"
    "plusAddr#" => "plusAddr"
    "minusAddr#" => "sub"
    "remAddr#" => "rem"
    "eqAddr#" => "eqAddr"
    "neAddr#" => "neq"
    "ltAddr#" => "lt"
    "leAddr#" => "lte"
    "gtAddr#" => "gt"
    "geAddr#" => "gte"
    "addr2Int#" | "int2Addr#" => "I_hash"
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
    "&&" | "and" => "logical_and"
    "||" | "or" => "logical_or"
    "isTrue#" | "isTrue" => "isTrue"
    "++" | "_plus__plus_" | "append" => "append"
    "realWorld#" | "void#" => "realWorld"
    "overflowError" => "overflowError"
    "divZeroError" => "divZeroError"
    "word2Double#" | "word2Float#" => "I_hash"
    "fabsDouble#" | "fabsFloat#" => "abs24"
    "sqrtDouble#" | "sqrtFloat#" => "isqrt"
    "maxDouble#" | "maxFloat#" => "prim_max"
    "minDouble#" | "minFloat#" => "prim_min"
    "fmaddDouble#" | "fmaddFloat#" => "fmadd"
    "fmsubDouble#" | "fmsubFloat#" => "fmsub"
    "fnmaddDouble#" | "fnmaddFloat#" => "fnmadd"
    "fnmsubDouble#" | "fnmsubFloat#" => "fnmsub"
    "**##" | "powerFloat#" => "prim_pow"
    "decodeDouble_2Int#" | "decodeDouble_Int64#" | "decodeFloat_Int#" => "decodeFloat_Int"
    "sinDouble#" | "sinFloat#" => "prim_sin"
    "cosDouble#" | "cosFloat#" => "prim_cos"
    "tanDouble#" | "tanFloat#" => "prim_tan"
    "asinDouble#" | "asinFloat#" => "prim_asin"
    "acosDouble#" | "acosFloat#" => "prim_acos"
    "atanDouble#" | "atanFloat#" => "prim_atan"
    "sinhDouble#" | "sinhFloat#" => "prim_sinh"
    "coshDouble#" | "coshFloat#" => "prim_cosh"
    "tanhDouble#" | "tanhFloat#" => "prim_tanh"
    "asinhDouble#" | "asinhFloat#" => "prim_asinh"
    "acoshDouble#" | "acoshFloat#" => "prim_acosh"
    "atanhDouble#" | "atanhFloat#" => "prim_atanh"
    "expDouble#" | "expFloat#" => "prim_exp"
    "logDouble#" | "logFloat#" => "prim_log"
    "expm1Double#" | "expm1Float#" => "prim_expm1"
    "log1pDouble#" | "log1pFloat#" => "prim_log1p"
    "clz#" | "clz8#" | "clz16#" | "clz32#" | "clz64#" => "clz"
    "ctz#" | "ctz8#" | "ctz16#" | "ctz32#" | "ctz64#" => "ctz"
    "byteSwap#" | "byteSwap16#" | "byteSwap32#" | "byteSwap64#" => "byteSwap"
    "bitReverse#" | "bitReverse8#" | "bitReverse16#" | "bitReverse32#" | "bitReverse64#" => "bitReverse"
    "pdep#" | "pdep8#" | "pdep16#" | "pdep32#" | "pdep64#" => "pdep"
    "pext#" | "pext8#" | "pext16#" | "pext32#" | "pext64#" => "pext"
    "casArray#" | "casSmallArray#" | "casIntArray#" | "casInt8Array#" | "casInt16Array#" | "casInt32Array#" | "casInt64Array#" => "casArray"
    "atomicCasAddrAddr#" | "atomicCasWord16Addr#" | "atomicCasWord32Addr#" | "atomicCasWord64Addr#" | "atomicCasWord8Addr#" | "atomicCasWordAddr#" => "casAddr"
    "atomicExchangeAddrAddr#" | "atomicExchangeWordAddr#" => "exchangeAddr"
    "atomicModifyMutVar_#" | "atomicSwapMutVar#" => "atomicModifyMutVar2"
    "atomicReadIntArray#" => "readByteArray"
    "atomicWriteIntArray#" => "writeByteArray"
    "atomicReadWordAddr#" => "readWord8OffAddr"
    "atomicWriteWordAddr#" => "writeWord8OffAddr"
    "fetchAddIntArray#" | "fetchSubIntArray#" | "fetchAndIntArray#" | "fetchOrIntArray#" | "fetchXorIntArray#" | "fetchNandIntArray#" => "fetchOpIntArray"
    "fetchAddWordAddr#" | "fetchSubWordAddr#" | "fetchAndWordAddr#" | "fetchOrWordAddr#" | "fetchXorWordAddr#" | "fetchNandWordAddr#" => "fetchOpWordAddr"
    "addrToAny#" | "anyToAddr#" | "makeStableName#" | "makeStablePtr#" | "deRefStablePtr#" => "I_hash"
    "eqStablePtr#" => "prim_eq"
    "delay#" => "waitState"
    "getMaskingState#" => "isPinned"
    "maskAsyncExceptions#" | "maskUninterruptible#" | "unmaskAsyncExceptions#" | "prompt#" | "control0#" | "newPromptTag#" => "opaque"
    "prefetchAddr0#" | "prefetchAddr1#" | "prefetchAddr2#" | "prefetchAddr3#" |
    "prefetchByteArray0#" | "prefetchByteArray1#" | "prefetchByteArray2#" | "prefetchByteArray3#" |
    "prefetchMutableByteArray0#" | "prefetchMutableByteArray1#" | "prefetchMutableByteArray2#" | "prefetchMutableByteArray3#" |
    "prefetchValue0#" | "prefetchValue1#" | "prefetchValue2#" | "prefetchValue3#" => "touch"
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

///| Primitives whose application is the crash value and whose arguments are
///| therefore never evaluated.
pub fn is_crash_prim(name : String) -> Bool {
  match name {
    "error" | "errorWithoutStackTrace" | "undefined" | "patError" | "patError#" |
    "absentError" | "raise#" | "raiseIO#" => true
    _ => false
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
    "plusWord64#" | "plusInt64#" | "plusWord8#" | "minusInt64#" | "subWord8#" => true
    "timesWord64#" | "timesInt64#" | "negateInt64#" | "not64#" => true
    "and64#" | "or64#" | "xor64#" => true
    "uncheckedShiftL64#" | "uncheckedIShiftL64#" | "uncheckedShiftRL64#" | "uncheckedIShiftRA64#" => true
    "eqChar#" | "ltChar#" | "gtChar#" | "leChar#" | "geChar#" | "neChar#" => true
    "ltInt64#" | "gtInt64#" | "geInt64#" | "ltWord8#" | "leWord8#" | "geWord8#" | "gtWord8#" | "eqWord8#" => true
    _ => false
  }
}

///| Check if an identifier is a builtin primitive operator
pub fn is_builtin_prim(name : String) -> Bool {
  if @syntax.canonical_prim_alias(name) is Some(_) {
    return true
  }
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
    "word64ToInt64#" | "int64ToWord64#" | "intToInt64#" | "int64ToInt#" | "int32ToInt#" | "integerToInt#" => true
    "int8ToInt#" | "int16ToInt#" | "wordToWord16#" | "wordToWord64#" | "word64ToWord#" => true
    "word16ToInt16#" | "int16ToWord16#" | "word8ToInt8#" | "int8ToWord8#" => true
    "intToInt8#" | "intToInt16#" | "intToInt32#" | "int32ToWord32#" | "word32ToInt32#" => true
    "newPinnedByteArray#" | "unsafeFreezeByteArray#" | "unsafeThawByteArray#" => true
    "getSizeofMutableByteArray#" | "resizeMutableByteArray#" | "shrinkMutableByteArray#" | "byteArrayContents#" | "mutableByteArrayContents#" => true
    "indexCharOffAddr#" | "unpackAppendCString#" | "indexArray#" => true
    "compareByteArrays#" | "popCnt64#" | "typeRep#" | "catch#" | "atomicModifyMutVar2#" => true
    "narrow8Int#" | "narrow16Int#" | "narrow8Word#" | "narrow16Word#" => true
    "chr#" | "ord#" => true
    "not#" | "notI#" | "notWord#" | "negateInt#" | "negateDouble#" | "negateFloat#" => true
    "quotRemInt#" | "quotRemWord#" => true
    "(#,#)" | "(#,,#)" | "(#,,,#)" | "(# #)" | "(##)" | "(#_#)" | "Solo#" | "Unit#" => true
    "(,)" | "(,,)" | "(,,,)" => true
    "runRW#" | "newByteArray#" | "writeIntArray#" | "readIntArray#" | "writeByteArray#" | "readByteArray#" => true
    "sizeofByteArray#" | "sizeofMutableByteArray#" | "indexWord8Array#" | "readWord8Array#" | "writeWord8Array#" | "indexIntArray#" | "copyByteArray#" | "copyMutableByteArray#" | "setByteArray#" => true
    "newArray#" | "readArray#" | "writeArray#" | "sizeofArray#" | "sizeofMutableArray#" | "sameMutableArray#" | "sameMutableByteArray#" => true
    "newSmallArray#" | "readSmallArray#" | "writeSmallArray#" | "indexSmallArray#" | "sizeofSmallArray#" | "sizeofSmallMutableArray#" => true
    "newMutVar#" | "readMutVar#" | "writeMutVar#" | "casMutVar#" => true
    "word2Double#" | "word2Float#" => true
    "fabsDouble#" | "fabsFloat#" => true
    "sqrtDouble#" | "sqrtFloat#" => true
    "maxDouble#" | "maxFloat#" | "minDouble#" | "minFloat#" => true
    "fmaddDouble#" | "fmaddFloat#" | "fmsubDouble#" | "fmsubFloat#" | "fnmaddDouble#" | "fnmaddFloat#" | "fnmsubDouble#" | "fnmsubFloat#" => true
    "**##" | "powerFloat#" => true
    "decodeDouble_2Int#" | "decodeDouble_Int64#" | "decodeFloat_Int#" => true
    "sinDouble#" | "sinFloat#" | "cosDouble#" | "cosFloat#" | "tanDouble#" | "tanFloat#" => true
    "asinDouble#" | "asinFloat#" | "acosDouble#" | "acosFloat#" | "atanDouble#" | "atanFloat#" => true
    "sinhDouble#" | "sinhFloat#" | "coshDouble#" | "coshFloat#" | "tanhDouble#" | "tanhFloat#" => true
    "asinhDouble#" | "asinhFloat#" | "acoshDouble#" | "acoshFloat#" | "atanhDouble#" | "atanhFloat#" => true
    "expDouble#" | "expFloat#" | "logDouble#" | "logFloat#" | "expm1Double#" | "expm1Float#" | "log1pDouble#" | "log1pFloat#" => true
    "clz#" | "clz8#" | "clz16#" | "clz32#" | "clz64#" => true
    "ctz#" | "ctz8#" | "ctz16#" | "ctz32#" | "ctz64#" => true
    "byteSwap#" | "byteSwap16#" | "byteSwap32#" | "byteSwap64#" => true
    "bitReverse#" | "bitReverse8#" | "bitReverse16#" | "bitReverse32#" | "bitReverse64#" => true
    "pdep#" | "pdep8#" | "pdep16#" | "pdep32#" | "pdep64#" => true
    "pext#" | "pext8#" | "pext16#" | "pext32#" | "pext64#" => true
    "casArray#" | "casSmallArray#" | "casIntArray#" | "casInt8Array#" | "casInt16Array#" | "casInt32Array#" | "casInt64Array#" => true
    "atomicCasAddrAddr#" | "atomicCasWord16Addr#" | "atomicCasWord32Addr#" | "atomicCasWord64Addr#" | "atomicCasWord8Addr#" | "atomicCasWordAddr#" => true
    "atomicExchangeAddrAddr#" | "atomicExchangeWordAddr#" => true
    "atomicModifyMutVar_#" | "atomicSwapMutVar#" => true
    "atomicReadIntArray#" | "atomicWriteIntArray#" | "atomicReadWordAddr#" | "atomicWriteWordAddr#" => true
    "fetchAddIntArray#" | "fetchSubIntArray#" | "fetchAndIntArray#" | "fetchOrIntArray#" | "fetchXorIntArray#" | "fetchNandIntArray#" => true
    "fetchAddWordAddr#" | "fetchSubWordAddr#" | "fetchAndWordAddr#" | "fetchOrWordAddr#" | "fetchXorWordAddr#" | "fetchNandWordAddr#" => true
    "addrToAny#" | "anyToAddr#" | "makeStableName#" | "makeStablePtr#" | "deRefStablePtr#" | "eqStablePtr#" | "delay#" => true
    "getMaskingState#" | "maskAsyncExceptions#" | "maskUninterruptible#" | "unmaskAsyncExceptions#" | "prompt#" | "control0#" | "newPromptTag#" => true
    "prefetchAddr0#" | "prefetchAddr1#" | "prefetchAddr2#" | "prefetchAddr3#" |
    "prefetchByteArray0#" | "prefetchByteArray1#" | "prefetchByteArray2#" | "prefetchByteArray3#" |
    "prefetchMutableByteArray0#" | "prefetchMutableByteArray1#" | "prefetchMutableByteArray2#" | "prefetchMutableByteArray3#" |
    "prefetchValue0#" | "prefetchValue1#" | "prefetchValue2#" | "prefetchValue3#" => true
    "newTVar#" | "readTVar#" | "writeTVar#" | "readTVarIO#" | "atomically#" | "retry#" | "catchRetry#" | "catchSTM#" => true
    "newMVar#" | "takeMVar#" | "tryTakeMVar#" | "putMVar#" | "tryPutMVar#" | "readMVar#" | "tryReadMVar#" | "isEmptyMVar#" => true
    "fork#" | "forkOn#" | "killThread#" | "yield#" | "myThreadId#" | "labelThread#" | "isCurrentThreadBound#" | "noDuplicate#" | "spark#" | "seq#" | "keepAlive#" => true
    "plusAddr#" | "minusAddr#" | "remAddr#" | "addr2Int#" | "int2Addr#" | "eqAddr#" | "neAddr#" | "ltAddr#" | "leAddr#" | "gtAddr#" | "geAddr#" => true
    "readWord8OffAddr#" | "writeWord8OffAddr#" | "readIntOffAddr#" | "writeIntOffAddr#" | "touch#" | "word8ToWord#" | "wordToWord8#" | "compare" => true
    "unpackCString#" | "unpackCStringUtf8#" | "unpackFoldrCString#" => true
    "raise#" | "raiseIO#" => true
    "realWorld#" | "void#" => true
    "overflowError" | "divZeroError" | "absentError" => true
    "add_mod" | "mul31_mod" => true
    "Eq" | "C:Eq" | "Show" | "C:Show" | "C" | "C_Eq" => true
    "tag_Literal" | "tag_Bool" | "tag_AltCon" | "tag_CoreBind" | "tag_CoreExpr" | "tag_Value" => true
    "tagToEnum#" | "dataToTagSmall#" | "patError" | "patError#" | "eqString" | "_plus__plus_" | "append" => true
    "reallyUnsafePtrEquality#" | "reallyUnsafePtrEquality" => true
    "lazy" => true
    "error" | "errorWithoutStackTrace" | "undefined" => true
    "&&" | "||" | "isTrue#" | "isTrue" => true
    "map" | "filter" | "elem" | "notElem" | "concatMap" | "fst" | "snd" => true
    "$fEqList_$s$c_ne_1" | "_fEqList__s_c_ne_1" | "$fEqList_$c_eq_" | "_fEqList__c_eq_" => true
    "$fEqTuple2" | "_fEqTuple2" | "$fEqList_$s$fEqList1" | "_fEqList__s_fEqList1" => true
    _ => false
  }
}


///| Check if an identifier is a builtin primitive operator
pub fn builtin_prim_name(name : String) -> String {
  if @syntax.canonical_prim_alias(name) is Some(target_alias) && target_alias != name {
    return builtin_prim_name(target_alias)
  }
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
    ">>" | "uncheckedIShiftRL#" | "uncheckedShiftRL#" | "shiftR" => "prim_shr"
    "uncheckedIShiftRA#" | "uncheckedShiftRA#" => "sra"
    "plusWord64#" | "plusInt64#" | "plusWord8#" => "prim_add"
    "minusInt64#" | "subWord8#" => "prim_sub"
    "timesWord64#" | "timesInt64#" => "prim_mul"
    "negateInt64#" | "not64#" => "negateInt"
    "and64#" => "prim_and"
    "or64#" => "prim_or"
    "xor64#" => "prim_xor"
    "uncheckedShiftL64#" | "uncheckedIShiftL64#" => "prim_shl"
    "uncheckedShiftRL64#" | "uncheckedIShiftRA64#" => "prim_shr"
    "eqChar#" | "eqWord8#" => "prim_eq"
    "ltChar#" | "ltInt64#" | "ltWord8#" => "prim_lt"
    "gtInt64#" | "gtWord8#" => "prim_gt"
    "leChar#" | "leWord8#" => "prim_lte"
    "geInt64#" | "geWord8#" => "prim_gte"
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
    "compareByteArrays#" | "popCnt64#" | "typeRep#" => "I_hash"
    "newMutVar#" => "newMutVar"
    "readMutVar#" => "readMutVar"
    "writeMutVar#" => "writeMutVar"
    "newTVar#" => "newTVar"
    "readTVar#" => "readTVar"
    "writeTVar#" => "writeTVar"
    "readTVarIO#" => "readTVarIO"
    "atomically#" => "atomically"
    "retry#" => "retry"
    "catchRetry#" => "catchRetry"
    "catchSTM#" => "catchSTM"
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
    "catch#" => "catch"
    "overflowError" => "overflowError"
    "divZeroError" => "divZeroError"
    "word2Double#" | "word2Float#" => "I_hash"
    "fabsDouble#" | "fabsFloat#" => "abs24"
    "sqrtDouble#" | "sqrtFloat#" => "isqrt"
    "maxDouble#" | "maxFloat#" => "prim_max"
    "minDouble#" | "minFloat#" => "prim_min"
    "fmaddDouble#" | "fmaddFloat#" => "fmadd"
    "fmsubDouble#" | "fmsubFloat#" => "fmsub"
    "fnmaddDouble#" | "fnmaddFloat#" => "fnmadd"
    "fnmsubDouble#" | "fnmsubFloat#" => "fnmsub"
    "**##" | "powerFloat#" => "prim_pow"
    "decodeDouble_2Int#" | "decodeDouble_Int64#" | "decodeFloat_Int#" => "decodeFloat_Int"
    "sinDouble#" | "sinFloat#" => "prim_sin"
    "cosDouble#" | "cosFloat#" => "prim_cos"
    "tanDouble#" | "tanFloat#" => "prim_tan"
    "asinDouble#" | "asinFloat#" => "prim_asin"
    "acosDouble#" | "acosFloat#" => "prim_acos"
    "atanDouble#" | "atanFloat#" => "prim_atan"
    "sinhDouble#" | "sinhFloat#" => "prim_sinh"
    "coshDouble#" | "coshFloat#" => "prim_cosh"
    "tanhDouble#" | "tanhFloat#" => "prim_tanh"
    "asinhDouble#" | "asinhFloat#" => "prim_asinh"
    "acoshDouble#" | "acoshFloat#" => "prim_acosh"
    "atanhDouble#" | "atanhFloat#" => "prim_atanh"
    "expDouble#" | "expFloat#" => "prim_exp"
    "logDouble#" | "logFloat#" => "prim_log"
    "expm1Double#" | "expm1Float#" => "prim_expm1"
    "log1pDouble#" | "log1pFloat#" => "prim_log1p"
    "clz#" | "clz8#" | "clz16#" | "clz32#" | "clz64#" => "clz"
    "ctz#" | "ctz8#" | "ctz16#" | "ctz32#" | "ctz64#" => "ctz"
    "byteSwap#" | "byteSwap16#" | "byteSwap32#" | "byteSwap64#" => "byteSwap"
    "bitReverse#" | "bitReverse8#" | "bitReverse16#" | "bitReverse32#" | "bitReverse64#" => "bitReverse"
    "pdep#" | "pdep8#" | "pdep16#" | "pdep32#" | "pdep64#" => "pdep"
    "pext#" | "pext8#" | "pext16#" | "pext32#" | "pext64#" => "pext"
    "casArray#" | "casSmallArray#" | "casIntArray#" | "casInt8Array#" | "casInt16Array#" | "casInt32Array#" | "casInt64Array#" => "casArray"
    "atomicCasAddrAddr#" | "atomicCasWord16Addr#" | "atomicCasWord32Addr#" | "atomicCasWord64Addr#" | "atomicCasWord8Addr#" | "atomicCasWordAddr#" => "casAddr"
    "atomicExchangeAddrAddr#" | "atomicExchangeWordAddr#" => "exchangeAddr"
    "atomicModifyMutVar_#" | "atomicSwapMutVar#" => "atomicModifyMutVar2"
    "atomicReadIntArray#" => "readByteArray"
    "atomicWriteIntArray#" => "writeByteArray"
    "atomicReadWordAddr#" => "readWord8OffAddr"
    "atomicWriteWordAddr#" => "writeWord8OffAddr"
    "fetchAddIntArray#" | "fetchSubIntArray#" | "fetchAndIntArray#" | "fetchOrIntArray#" | "fetchXorIntArray#" | "fetchNandIntArray#" => "fetchOpIntArray"
    "fetchAddWordAddr#" | "fetchSubWordAddr#" | "fetchAndWordAddr#" | "fetchOrWordAddr#" | "fetchXorWordAddr#" | "fetchNandWordAddr#" => "fetchOpWordAddr"
    "addrToAny#" | "anyToAddr#" | "makeStableName#" | "makeStablePtr#" | "deRefStablePtr#" => "I_hash"
    "eqStablePtr#" => "prim_eq"
    "delay#" => "waitState"
    "getMaskingState#" => "isPinned"
    "maskAsyncExceptions#" | "maskUninterruptible#" | "unmaskAsyncExceptions#" | "prompt#" | "control0#" | "newPromptTag#" => "opaque"
    "prefetchAddr0#" | "prefetchAddr1#" | "prefetchAddr2#" | "prefetchAddr3#" |
    "prefetchByteArray0#" | "prefetchByteArray1#" | "prefetchByteArray2#" | "prefetchByteArray3#" |
    "prefetchMutableByteArray0#" | "prefetchMutableByteArray1#" | "prefetchMutableByteArray2#" | "prefetchMutableByteArray3#" |
    "prefetchValue0#" | "prefetchValue1#" | "prefetchValue2#" | "prefetchValue3#" => "touch"
    _ => sanitize_name(name)
  }
}

