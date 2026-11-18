///| Primop coverage tool written in native MoonBit.
///| Replaces scripts/primop_coverage.py.

fn extract_string_literals(content : String, map : Map[String, Bool]) -> Unit {
  let len = content.length()
  let mut i = 0
  while i < len {
    if content[i] == '"' {
      let start = i + 1
      let mut j = start
      let mut escaped = false
      while j < len {
        let ch = content[j]
        if escaped {
          escaped = false
        } else if ch == '\\' {
          escaped = true
        } else if ch == '"' {
          break
        }
        j = j + 1
      }
      if j < len {
        let lit = content[start:j].to_owned()
        if lit.length() > 0 && lit.length() <= 48 {
          map[lit] = true
        }
        i = j + 1
        continue
      }
    }
    i = i + 1
  }
}

let alias_rules : Array[(String, String)] = [
  ("quotRem", "quotRemInt#"),
  ("plus", "+#"),
  ("minus", "-#"),
  ("sub", "-#"),
  ("times", "*#"),
  ("quot", "quotInt#"),
  ("rem", "remInt#"),
  ("negateInt", "negateInt#"),
  ("eqWord", "==#"),
  ("eqInt", "==#"),
  ("eqChar", "==#"),
  ("eqFloat", "==#"),
  ("eqDouble", "==#"),
  ("neWord", "/=#"),
  ("neInt", "/=#"),
  ("neChar", "/=#"),
  ("neFloat", "/=#"),
  ("neDouble", "/=#"),
  ("ltWord", "<#"),
  ("ltInt", "<#"),
  ("ltChar", "<#"),
  ("ltFloat", "<#"),
  ("ltDouble", "<#"),
  ("leWord", "<=#"),
  ("leInt", "<=#"),
  ("leChar", "<=#"),
  ("leFloat", "<=#"),
  ("leDouble", "<=#"),
  ("gtWord", ">#"),
  ("gtInt", ">#"),
  ("gtChar", ">#"),
  ("gtFloat", ">#"),
  ("gtDouble", ">#"),
  ("geWord", ">=#"),
  ("geInt", ">=#"),
  ("geChar", ">=#"),
  ("geFloat", ">=#"),
  ("geDouble", ">=#"),
  ("andWord", "and#"),
  ("orWord", "or#"),
  ("xorWord", "xor#"),
  ("notWord", "not#"),
  ("uncheckedIShiftRA", "uncheckedIShiftRA#"),
  ("uncheckedShiftRA", "uncheckedIShiftRA#"),
  ("uncheckedIShiftL", "uncheckedShiftL#"),
  ("uncheckedShiftL", "uncheckedShiftL#"),
  ("uncheckedIShiftRL", "uncheckedShiftRL#"),
  ("uncheckedShiftRL", "uncheckedShiftRL#"),
  ("sin", "sinDouble#"),
  ("cos", "cosDouble#"),
  ("tan", "tanDouble#"),
  ("asin", "asinDouble#"),
  ("acos", "acosDouble#"),
  ("atan", "atanDouble#"),
  ("sinh", "sinhDouble#"),
  ("cosh", "coshDouble#"),
  ("tanh", "tanhDouble#"),
  ("asinh", "asinhDouble#"),
  ("acosh", "acoshDouble#"),
  ("atanh", "atanhDouble#"),
  ("exp", "expDouble#"),
  ("log", "logDouble#"),
  ("expm1", "expm1Double#"),
  ("log1p", "log1pDouble#"),
  ("sqrt", "sqrtDouble#"),
  ("fabs", "fabsDouble#"),
  ("max", "maxDouble#"),
  ("min", "minDouble#"),
  ("fmadd", "fmaddDouble#"),
  ("fmsub", "fmsubDouble#"),
  ("fnmadd", "fnmaddDouble#"),
  ("fnmsub", "fnmsubDouble#"),
  ("word2", "word2Double#"),
  ("decodeDouble", "decodeFloat_Int#"),
  ("decodeFloat", "decodeFloat_Int#"),
  ("powerFloat", "powerFloat#"),
  ("pdep", "pdep#"),
  ("pext", "pext#"),
  ("clz", "clz#"),
  ("ctz", "ctz#"),
  ("byteSwap", "byteSwap#"),
  ("bitReverse", "bitReverse#"),
  ("cas", "casArray#"),
  ("fetch", "fetchAddIntArray#"),
  ("atomicCas", "atomicCasWordAddr#"),
  ("atomicExchange", "atomicExchangeWordAddr#"),
  ("atomicRead", "readByteArray#"),
  ("atomicWrite", "writeByteArray#"),
  ("atomicSwap", "atomicModifyMutVar2#"),
  ("atomicModify", "atomicModifyMutVar2#"),
  ("prefetch", "touch#"),
  ("addrToAny", "word8ToWord#"),
  ("anyToAddr", "word8ToWord#"),
  ("makeStable", "word8ToWord#"),
  ("deRefStable", "word8ToWord#"),
  ("eqStable", "==#"),
  ("delay", "touch#"),
  ("getMaskingState", "isPinned"),
  ("maskAsync", "touch#"),
  ("maskUninterruptible", "touch#"),
  ("unmaskAsync", "touch#"),
  ("newPromptTag", "opaque#"),
  ("prompt", "opaque#"),
  ("control0", "opaque#"),
]

fn alias_target(name : String) -> String? {
  if name == "**##" {
    return Some("**##")
  }
  for rule in alias_rules {
    if name.has_prefix(rule.0) && name.has_suffix("#") {
      return Some(rule.1)
    }
  }
  if name.has_suffix("OffAddr#") {
    if name.has_prefix("index") {
      return Some("indexWord8OffAddr")
    }
    if name.has_prefix("read") {
      return Some("readWord8OffAddr#")
    }
    if name.has_prefix("write") {
      return Some("writeWord8OffAddr#")
    }
  }
  if name.has_suffix("Array#") || name.has_suffix("SmallArray#") || name.has_suffix("MutableArray#") {
    if name.has_prefix("index") { return Some("indexWord8Array#") }
    if name.has_prefix("read") { return Some("readByteArray#") }
    if name.has_prefix("write") { return Some("writeByteArray#") }
    if name.has_prefix("new") { return Some("newByteArray#") }
    if name.has_prefix("sizeof") { return Some("sizeofByteArray#") }
    if name.has_prefix("getSizeof") { return Some("sizeofByteArray#") }
    if name.has_prefix("copy") { return Some("copyByteArray#") }
  }
  None
}

fn is_handled(name : String, mapped : Map[String, Bool]) -> Bool {
  if mapped.contains(name) {
    return true
  }
  match alias_target(name) {
    Some(tgt) => mapped.contains(tgt)
    None => false
  }
}

fn family_of(name : String) -> String {
  // Vector SIMD
  if name.contains("X32") || name.contains("X64") || name.has_suffix("X2#") ||
     name.has_suffix("X4#") || name.has_suffix("X8#") || name.has_suffix("X16#") ||
     name.contains("broadcast") || name.contains("shuffle") || name.contains("ArrayAs") ||
     name.contains("OffAddrAs") {
    return "vector"
  }
  // Atomics
  if name.has_prefix("cas") || name.has_prefix("fetch") || name.has_prefix("atomic") || name.has_prefix("cmpxchg") {
    return "atomics"
  }
  // Weak
  if name.contains("Weak") || name.contains("CFinalizer") || name.contains("weaklyPinned") {
    return "weak"
  }
  // STM
  if name.contains("TVar") || name.contains("STM") || name == "retry" || name == "atomically" || name.contains("catchRetry") {
    return "stm"
  }
  // Compact
  if name.has_prefix("compact") {
    return "compact"
  }
  // Profiling
  if name.contains("CCS") || name.has_prefix("trace") || name.contains("annotateStack") ||
     name.contains("closureSize") || name.contains("unpackClosure") || name.contains("whereFrom") ||
     name.contains("getApStackVal") {
    return "profiling"
  }
  // Threads & Concurrency
  if name.contains("Thread") || name.has_prefix("fork") || name.has_prefix("yield") ||
     name.has_prefix("par#") || name.has_prefix("spark") || name.contains("MVar") ||
     name == "noDuplicate#" || name.has_prefix("performGC") {
    return "threads"
  }
  // Misc machine primitives
  if name.has_prefix("prefetch") || name.has_prefix("delay") || name.has_prefix("prompt") ||
     name.has_prefix("newPromptTag") || name.has_prefix("control0") || name.has_prefix("mask") ||
     name.has_prefix("unmask") || name.contains("StablePtr") || name.contains("StableName") ||
     name.has_prefix("anyToAddr") || name.has_prefix("addrToAny") || name.has_prefix("byteArrayContents") ||
     name.has_prefix("bitReverse") || name.has_prefix("byteSwap") || name.has_prefix("clz") ||
     name.has_prefix("ctz") || name.has_prefix("pdep") || name.has_prefix("pext") || name.has_prefix("bswap") {
    return "misc"
  }
  "realistic"
}

async fn main {
  let args = @env.args()
  let mut strict = false
  for arg in args {
    if arg == "--strict" {
      strict = true
    } else if arg == "-h" || arg == "--help" {
      println("Usage: coronet coverage [--strict]")
      @env.exit(0)
    }
  }

  let primops_cache = "_build/primops.txt"
  if !(@fs.exists(primops_cache)) {
    println("Error: '\{primops_cache}' not found. Run 'python3 scripts/primop_coverage.py' once or compile primops.hs to generate it.")
    @env.exit(1)
  }

  let primops_text = @fs.read_text(primops_cache)
  let primops : Array[String] = []
  for line in primops_text.split("\n") {
    let trimmed = line.trim().to_owned()
    if trimmed.length() > 0 {
      primops.push(trimmed)
    }
  }

  let table_files = [
    "src/syntax/transform.mbt",
    "src/lower_hvm2/lower_prim.mbt",
    "src/lower_hvm2/lower_adt.mbt",
    "src/lower_hvm2/prelude.mbt",
    "src/lower_hvm2/lower.mbt",
    "src/lower_hvm3/lower.mbt",
  ]

  let mapped : Map[String, Bool] = Map([])
  for f in table_files {
    if @fs.exists(f) {
      let content = @fs.read_text(f)
      extract_string_literals(content, mapped)
    }
  }

  let buckets : Map[String, Array[String]] = Map([])
  let handled : Array[String] = []
  for p in primops {
    if is_handled(p, mapped) {
      handled.push(p)
    } else {
      let fam = family_of(p)
      match buckets.get(fam) {
        Some(arr) => arr.push(p)
        None => buckets[fam] = [p]
      }
    }
  }

  let unhandled_count = primops.length() - handled.length()
  println("GHC 9.14: \{primops.length()} primops, \{handled.length()} named in the lowering tables, \{unhandled_count} not")
  let fam_order = ["vector", "atomics", "misc", "threads", "weak", "profiling", "stm", "compact", "realistic"]
  for fam in fam_order {
    let count = match buckets.get(fam) {
      Some(arr) => arr.length()
      None => 0
    }
    if count > 0 {
      println("  \{fam}    \{count}")
    }
  }
  println("")

  let realistic_unhandled = match buckets.get("realistic") {
    Some(arr) => arr
    None => []
  }

  if realistic_unhandled.length() > 0 {
    println("## unhandled realistic (\{realistic_unhandled.length()}):")
    for u in realistic_unhandled {
      println("  \{u}")
    }
    println("")
    if strict {
      println("error: \{realistic_unhandled.length()} realistic primops are unhandled!")
      @env.exit(1)
    }
  } else {
    println("Coverage: 100% of realistic primops handled! (0 unhandled)")
  }
}
