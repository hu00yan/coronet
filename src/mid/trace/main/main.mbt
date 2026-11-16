///|Stage-level timing for the Coronet front/middle/back pipeline.
///|
///|Usage: coronet-trace <file.core> [--target hvm2|hvm3] [--repeat N] [--no-prune] [--emit path]
///
/// The shipping CLI measures nothing, and wall-clock timing of the whole
/// binary cannot split parse from middle-end from lowering. This tool runs the
/// same pipeline as `cmd/main` on one input, repeats it, and reports the
/// minimum time per stage. It is a measurement instrument only: it links
/// against the real `@syntax`, `@mid`, `@lower_hvm2`, `@lower_hvm3`, so a number
/// it prints is the number the compiler spends.
///
/// Usage:
///   coronet-trace <file.core> [--target hvm2|hvm3] [--repeat N] [--no-prune]
///
/// Output is one JSON object on stdout.

///|
struct StageTimings {
  read : Double
  parse : Double
  link : Double
  mid : Double
  lower : Double
  prune : Double
}

///|
fn StageTimings::min_with(self : StageTimings, other : StageTimings) -> StageTimings {
  {
    read: min_double(self.read, other.read),
    parse: min_double(self.parse, other.parse),
    link: min_double(self.link, other.link),
    mid: min_double(self.mid, other.mid),
    lower: min_double(self.lower, other.lower),
    prune: min_double(self.prune, other.prune),
  }
}

///|
fn StageTimings::total(self : StageTimings) -> Double {
  self.read + self.parse + self.link + self.mid + self.lower + self.prune
}

///|
fn parse_int_default(text : String, fallback : Int) -> Int {
  let mut value = 0
  let mut digits = 0
  for i in 0..<text.length() {
    let c = text.code_unit_at(i).to_int()
    if c >= 48 && c <= 57 {
      value = value * 10 + (c - 48)
      digits = digits + 1
    } else {
      return fallback
    }
  }
  if digits == 0 {
    fallback
  } else {
    value
  }
}

///|
fn min_double(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|The same post-lowering pass sequence `cmd/main` applies.
fn prune_generated(code : String, enabled : Bool) -> String {
  if enabled {
    let pruned = @mid.prune_book_text(code, ["main"])
    let merged = @mid.merge_alpha_duplicate_defs(pruned)
    @mid.prune_book_text(merged, ["main"])
  } else {
    code
  }
}

///|
fn elapsed_us(start : @bench.Timestamp) -> Double {
  @bench.monotonic_clock_end(start) / 1000.0 // ns -> us
}

///|
fn count_defs(code : String) -> Int {
  @mid.book_def_names(code).length()
}

///|
async fn main {
  let args = @env.args()
  let mut input = ""
  let mut target = "hvm2"
  let mut repeat = 3
  let mut prune = true
  let mut emit = ""
  let mut i = 1
  while i < args.length() {
    let a = args[i]
    if a == "--target" && i + 1 < args.length() {
      target = args[i + 1]
      i = i + 1
    } else if a == "--repeat" && i + 1 < args.length() {
      repeat = parse_int_default(args[i + 1], 3)
      i = i + 1
    } else if a == "--emit" && i + 1 < args.length() {
      emit = args[i + 1]
      i = i + 1
    } else if a == "--no-prune" {
      prune = false
    } else {
      input = a
    }
    i = i + 1
  }
  if input == "" {
    println("usage: coronet-trace <file.core> [--target hvm2|hvm3] [--repeat N] [--no-prune] [--emit path]")
    @env.exit(2)
  }
  if !@fs.exists(input) {
    println("no such input: \{input}")
    @env.exit(2)
  }

  // One warm-up round so first-touch allocation does not land in the minimum.
  let mut best : StageTimings? = None
  let mut last_bytes = 0
  let mut last_defs = 0
  for _round in 0..=repeat {
    let s0 = @bench.monotonic_clock_start()
    let content = @fs.read_text(input)
    let read_us = elapsed_us(s0)
    let s1 = @bench.monotonic_clock_start()
    let parsed = match @syntax.parse_core(content) {
      Ok(p) => p
      Err(e) => {
        println("parse error: \{e}")
        @env.exit(1)
        return
      }
    }
    let parse_us = elapsed_us(s1)
    let s2 = @bench.monotonic_clock_start()
    let linked = @syntax.link_programs([parsed])
    let link_us = elapsed_us(s2)
    let s3 = @bench.monotonic_clock_start()
    let stats = @mid.MidStats::new()
    let program = @mid.optimize(linked, stats)
    let mid_us = elapsed_us(s3)
    let s4 = @bench.monotonic_clock_start()
    let lowered = match target {
      "hvm3" => @lower_hvm3.lower(program)
      _ => @lower_hvm2.lower(program)
    }
    let lower_us = elapsed_us(s4)
    let s5 = @bench.monotonic_clock_start()
    let code = prune_generated(lowered, prune)
    let prune_us = elapsed_us(s5)
    let timings = StageTimings::{
      read: read_us,
      parse: parse_us,
      link: link_us,
      mid: mid_us,
      lower: lower_us,
      prune: prune_us,
    }
    last_bytes = code.length()
    last_defs = count_defs(code)
    // `--emit` lets the harness prove the instrument and the shipping CLI
    // produce the same book, not merely the same length.
    if emit != "" {
      @fs.write_text(emit, code)
    }
    best = match best {
      None => Some(timings)
      Some(prev) => Some(prev.min_with(timings))
    }
  }
  let t = best.unwrap()
  let buf = StringBuilder()
  buf.write_string("{\"input\": \"" + input + "\", \"target\": \"" + target + "\"")
  buf.write_string(", \"repeat\": " + repeat.to_string())
  buf.write_string(", \"read_us\": " + t.read.to_string())
  buf.write_string(", \"parse_us\": " + t.parse.to_string())
  buf.write_string(", \"link_us\": " + t.link.to_string())
  buf.write_string(", \"mid_us\": " + t.mid.to_string())
  buf.write_string(", \"lower_us\": " + t.lower.to_string())
  buf.write_string(", \"prune_us\": " + t.prune.to_string())
  buf.write_string(", \"total_us\": " + t.total().to_string())
  buf.write_string(", \"out_bytes\": " + last_bytes.to_string())
  buf.write_string(", \"out_defs\": " + last_defs.to_string())
  buf.write_string("}")
  println(buf.to_string())
}
