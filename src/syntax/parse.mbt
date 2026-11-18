///| CoreLite Lexer and Parser for Coronet compiler.

///| Tokens for CoreLite.
#derive(Eq)
pub enum Token {
  Ident(String)
  IntLit(Int)
  FloatLit(Double)
  CharLit(Char)
  StringLit(String)
  TypeVar(String)
  KwLet
  KwIn
  KwCase
  KwOf
  KwRec
  KwEnd
  KwDefault
  Equal
  Backslash
  Arrow
  LParen
  RParen
  LBrace
  RBrace
  LBracket
  RBracket
  Semicolon
  DoubleColon
  Comma
  Underscore
  LUnboxedTuple
  RUnboxedTuple
  EOF
}

pub extend Token with Eq::{not_equal, equal}

///|
pub impl Show for Token with output(self, logger) {
  match self {
    Ident(s) => logger.write_string("Ident(\{s})")
    IntLit(n) => logger.write_string("IntLit(\{n})")
    FloatLit(d) => logger.write_string("FloatLit(\{d})")
    CharLit(c) => logger.write_string("CharLit(\{c})")
    StringLit(s) => logger.write_string("StringLit(\{s})")
    TypeVar(s) => logger.write_string("TypeVar(@\{s})")
    KwLet => logger.write_string("let")
    KwIn => logger.write_string("in")
    KwCase => logger.write_string("case")
    KwOf => logger.write_string("of")
    KwRec => logger.write_string("Rec")
    KwEnd => logger.write_string("end")
    KwDefault => logger.write_string("__DEFAULT")
    Equal => logger.write_string("=")
    Backslash => logger.write_string("\\")
    Arrow => logger.write_string("->")
    LParen => logger.write_string("(")
    RParen => logger.write_string(")")
    LBrace => logger.write_string("{")
    RBrace => logger.write_string("}")
    LBracket => logger.write_string("[")
    RBracket => logger.write_string("]")
    Semicolon => logger.write_string(";")
    DoubleColon => logger.write_string("::")
    Comma => logger.write_string(",")
    Underscore => logger.write_string("_")
    LUnboxedTuple => logger.write_string("(#")
    RUnboxedTuple => logger.write_string("#)")
    EOF => logger.write_string("<EOF>")
  }
}

pub extend Token with Show::{to_string, output}

///| Extract the unqualified base name from a qualified symbol (e.g. Math_Fib_fib -> fib).
pub fn get_unqualified_name(name : String) -> String {
  let mut last_idx = -1
  for i in 0..<name.length() {
    let c = name[i].to_int().unsafe_to_char()
    if c == '.' || c == '_' {
      last_idx = i
    }
  }
  if last_idx >= 0 && last_idx + 1 < name.length() {
    name[last_idx + 1 : name.length()].to_owned()
  } else {
    name
  }
}

///| Check if an identifier is a constructor name.
pub fn is_constructor_name(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  let first_char = name[0].to_int().unsafe_to_char()
  if (first_char >= 'a' && first_char <= 'z') || first_char == '$' || first_char == '_' {
    return false
  }
  let unqual = get_unqualified_name(name)
  if unqual.length() > 0 {
    let first = unqual[0].to_int().unsafe_to_char()
    if (first >= 'A' && first <= 'Z') || first == ':' || first == '(' || first == '[' {
      return true
    }
    if first == '\'' && unqual.length() > 1 {
      let second = unqual[1].to_int().unsafe_to_char()
      return second >= 'A' && second <= 'Z'
    }
    return false
  }
  false
}

fn is_ident(tok : Token) -> Bool {
  match tok {
    Ident(_) => true
    _ => false
  }
}

fn ident_name(tok : Token) -> String {
  match tok {
    Ident(s) => s
    _ => ""
  }
}

fn is_op_char(c : Char) -> Bool {
  c == '+' || c == '-' || c == '*' || c == '/' || c == '<' || c == '>' || c == '=' ||
  c == '&' || c == '|' || c == '!' || c == '?' || c == '%' || c == '^' || c == '~' ||
  c == ':' || c == '\\'
}

///| Symbol characters GHC emits inside an occurrence name.
///| `Data.Map.Internal.!?` reaches CoreLite as `Data_Map_Internal_!?`, so an
///| alphanumeric identifier may continue with a symbol run. `-` and `>` are
///| excluded so `\x` followed by `->` still lexes as an arrow.
fn is_ident_symbol_char(c : Char) -> Bool {
  c == '!' || c == '?' || c == ':' || c == '\\' || c == '*' || c == '#' || c == '$' ||
  c == '%' || c == '^' || c == '~' || c == '&' || c == '|' || c == '/' || c == '.'
}

// ----------------------------------------------------------------------------
// Lexer
// ----------------------------------------------------------------------------

priv struct Lexer {
  src : String
  mut pos : Int
}

fn Lexer::new(src : String) -> Lexer {
  { src, pos: 0 }
}

fn Lexer::char_at(self : Lexer, pos : Int) -> Char {
  self.src[pos].to_int().unsafe_to_char()
}

///| Control-character names the Haskell Report allows inside escapes.
fn named_escape_code(name : String) -> Int {
  match name {
    "NUL" => 0
    "SOH" => 1
    "STX" => 2
    "ETX" => 3
    "EOT" => 4
    "ENQ" => 5
    "ACK" => 6
    "BEL" => 7
    "BS" => 8
    "HT" => 9
    "LF" => 10
    "VT" => 11
    "FF" => 12
    "CR" => 13
    "SO" => 14
    "SI" => 15
    "DLE" => 16
    "DC1" => 17
    "DC2" => 18
    "DC3" => 19
    "DC4" => 20
    "NAK" => 21
    "SYN" => 22
    "ETB" => 23
    "CAN" => 24
    "EM" => 25
    "SUB" => 26
    "ESC" => 27
    "FS" => 28
    "GS" => 29
    "RS" => 30
    "US" => 31
    "SP" => 32
    "DEL" => 127
    _ => -1
  }
}

///| Decode the escape after a backslash; self.pos sits on its first
///| character. Named escapes match their longest table prefix so a dump
///| like \ESC[ does not swallow the following character. A trailing \& gap
///| and caret (\^X) and numeric (\o..\d) forms are consumed the same way.
fn Lexer::lex_escape(self : Lexer) -> Char {
  let c = self.char_at(self.pos)
  self.pos = self.pos + 1
  let ch = match c {
    '&' => return self.lex_escape()
    'n' => '\n'
    't' => '\t'
    'r' => '\r'
    'a' => '\u{07}'
    'b' => '\u{08}'
    'f' => '\u{0c}'
    'v' => '\u{0b}'
    '"' => '"'
    '\'' => '\''
    '\\' => '\\'
    '^' => {
      if self.pos < self.src.length() {
        let code = self.char_at(self.pos).to_int() ^ 0x40
        self.pos = self.pos + 1
        Char::from_int(code)
      } else {
        '^'
      }
    }
    'o' | 'x' | '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' => {
      let radix = if c == 'o' { 8 } else if c == 'x' { 16 } else { 10 }
      let mut n = 0
      while self.pos < self.src.length() {
        let d = self.char_at(self.pos)
        let v = if d >= '0' && d <= '9' {
          d.to_int() - '0'.to_int()
        } else if d >= 'a' && d <= 'f' && radix == 16 {
          d.to_int() - 'a'.to_int() + 10
        } else if d >= 'A' && d <= 'F' && radix == 16 {
          d.to_int() - 'A'.to_int() + 10
        } else {
          break
        }
        if v >= radix {
          break
        }
        n = n * radix + v
        self.pos = self.pos + 1
      }
      if self.pos < self.src.length() && self.char_at(self.pos) == '&' {
        self.pos = self.pos + 1
      }
      Char::from_int(n)
    }
    other if other >= 'A' && other <= 'Z' => {
      let start = self.pos - 1
      while self.pos < self.src.length() {
        let d = self.char_at(self.pos)
        if (d >= 'A' && d <= 'Z') || (d >= 'a' && d <= 'z') {
          self.pos = self.pos + 1
        } else {
          break
        }
      }
      let run = self.src[start:self.pos].to_owned()
      let mut matched : Char = other
      let mut matched_end = start + 1
      for i in 1..=run.length() {
        let code = named_escape_code(run.substring(start=0, end=i))
        if code >= 0 {
          matched = Char::from_int(code)
          matched_end = start + i
        }
      }
      self.pos = matched_end
      if self.pos < self.src.length() && self.char_at(self.pos) == '&' {
        self.pos = self.pos + 1
      }
      matched
    }
    other => other
  }
  ch
}

fn Lexer::starts_with(self : Lexer, prefix : String) -> Bool {
  let len = prefix.length()
  if self.pos + len > self.src.length() {
    return false
  }
  for i in 0..<len {
    if self.src[self.pos + i] != prefix[i] {
      return false
    }
  }
  true
}

fn Lexer::skip_whitespace_and_comments(self : Lexer) -> Unit {
  while self.pos < self.src.length() {
    let c = self.char_at(self.pos)
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      self.pos = self.pos + 1
      continue
    }
    // Line comment: --
    if c == '-' && self.pos + 1 < self.src.length() && self.char_at(self.pos + 1) == '-' {
      if self.pos + 2 < self.src.length() && self.char_at(self.pos + 2) == '#' {
        break
      }
      while self.pos < self.src.length() && self.char_at(self.pos) != '\n' {
        self.pos = self.pos + 1
      }
      continue
    }
    // Block comment: {- ... -}
    if c == '{' && self.pos + 1 < self.src.length() && self.char_at(self.pos + 1) == '-' {
      self.pos = self.pos + 2
      let mut depth = 1
      while self.pos < self.src.length() && depth > 0 {
        if self.src[self.pos] == '{' && self.pos + 1 < self.src.length() && self.char_at(self.pos + 1) == '-' {
          depth = depth + 1
          self.pos = self.pos + 2
        } else if self.src[self.pos] == '-' && self.pos + 1 < self.src.length() && self.char_at(self.pos + 1) == '}' {
          depth = depth - 1
          self.pos = self.pos + 2
        } else {
          self.pos = self.pos + 1
        }
      }
      continue
    }
    // GHC dump banners: === ... ===
    if c == '=' && self.pos + 2 < self.src.length() && self.char_at(self.pos + 1) == '=' && self.char_at(self.pos + 2) == '=' {
      while self.pos < self.src.length() && self.char_at(self.pos) != '\n' {
        self.pos = self.pos + 1
      }
      continue
    }
    // GHC dump banner: [1 of ...
    if self.starts_with("[1 of") {
      while self.pos < self.src.length() && self.char_at(self.pos) != '\n' {
        self.pos = self.pos + 1
      }
      continue
    }
    // GHC dump banner: Result size ...
    if self.starts_with("Result size") {
      while self.pos < self.src.length() && self.char_at(self.pos) != '\n' {
        self.pos = self.pos + 1
      }
      continue
    }
    // GHC dump banner: = {terms: ...
    if self.starts_with("= {terms") || self.starts_with("{terms:") {
      while self.pos < self.src.length() && self.char_at(self.pos) != '\n' {
        self.pos = self.pos + 1
      }
      continue
    }
    // GHC module header: module ... where
    if self.starts_with("module ") {
      while self.pos < self.src.length() && self.char_at(self.pos) != '\n' {
        self.pos = self.pos + 1
      }
      continue
    }
    break
  }
}

fn parse_double_str(s : String) -> Double {
  let mut i = 0
  let mut neg = false
  if i < s.length() && s[i] == '-' {
    neg = true
    i = i + 1
  }
  let mut int_val : Double = 0.0
  while i < s.length() && s[i] >= '0' && s[i] <= '9' {
    let digit = s[i].to_int() - '0'.to_int()
    int_val = int_val * 10.0 + digit.to_double()
    i = i + 1
  }
  let mut frac_val : Double = 0.0
  let mut divisor : Double = 1.0
  if i < s.length() && s[i] == '.' {
    i = i + 1
    while i < s.length() && s[i] >= '0' && s[i] <= '9' {
      let digit = s[i].to_int() - '0'.to_int()
      divisor = divisor * 10.0
      frac_val = frac_val + digit.to_double() / divisor
      i = i + 1
    }
  }
  let mut res = int_val + frac_val
  if i < s.length() && (s[i] == 'e' || s[i] == 'E') {
    i = i + 1
    let mut exp_neg = false
    if i < s.length() && s[i] == '-' {
      exp_neg = true
      i = i + 1
    } else if i < s.length() && s[i] == '+' {
      i = i + 1
    }
    let mut exp : Int = 0
    while i < s.length() && s[i] >= '0' && s[i] <= '9' {
      exp = exp * 10 + (s[i].to_int() - '0'.to_int())
      i = i + 1
    }
    let mut factor : Double = 1.0
    for _ in 0..<exp {
      factor = factor * 10.0
    }
    if exp_neg {
      res = res / factor
    } else {
      res = res * factor
    }
  }
  if neg { -res } else { res }
}

fn Lexer::next_token(self : Lexer) -> Result[Token, String] {
  self.skip_whitespace_and_comments()
  if self.pos >= self.src.length() {
    return Ok(Token::EOF)
  }

  // Multi-char tokens
  if self.starts_with("->") {
    self.pos = self.pos + 2
    return Ok(Token::Arrow)
  }
  if self.starts_with("::") {
    self.pos = self.pos + 2
    return Ok(Token::DoubleColon)
  }
  if self.starts_with("[]") {
    self.pos = self.pos + 2
    return Ok(Token::Ident("[]"))
  }
  if self.starts_with("#)") {
    self.pos = self.pos + 2
    return Ok(Token::RUnboxedTuple)
  }
  if self.starts_with("(#") {
    if self.starts_with("(##)") {
      self.pos = self.pos + 4
      return Ok(Token::Ident("(##)"))
    }
    if self.starts_with("(# #)") {
      self.pos = self.pos + 5
      return Ok(Token::Ident("(##)"))
    }
    if self.pos + 2 < self.src.length() && self.char_at(self.pos + 2) == ',' {
      let mut i = self.pos + 2
      while i < self.src.length() && self.char_at(i) == ',' {
        i = i + 1
      }
      if i + 1 < self.src.length() && self.char_at(i) == '#' && self.char_at(i + 1) == ')' {
        let tup_con = self.src[self.pos : i + 2].to_owned()
        self.pos = i + 2
        return Ok(Token::Ident(tup_con))
      }
    }
    self.pos = self.pos + 2
    return Ok(Token::LUnboxedTuple)
  }
  // Check parenthesized operator or tuple constructor: (op) or (,) or (:)
  if self.char_at(self.pos) == '(' {
    if self.starts_with("(:)") {
      self.pos = self.pos + 3
      return Ok(Token::Ident("(:)"))
    }
    if self.pos + 1 < self.src.length() && self.char_at(self.pos + 1) == ',' {
      let mut i = self.pos + 1
      while i < self.src.length() && self.char_at(i) == ',' {
        i = i + 1
      }
      if i < self.src.length() && self.char_at(i) == ')' {
        let tuple_str = self.src[self.pos : i + 1].to_owned()
        self.pos = i + 1
        return Ok(Token::Ident(tuple_str))
      }
    }
    let next_c = if self.pos + 1 < self.src.length() { self.char_at(self.pos + 1) } else { ' ' }
    if is_op_char(next_c) || next_c == '.' {
      let mut i = self.pos + 1
      while i < self.src.length() && (is_op_char(self.char_at(i)) || self.char_at(i) == '#' || self.char_at(i) == '.') {
        i = i + 1
      }
      if i < self.src.length() && self.char_at(i) == ')' {
        let op_str = self.src[self.pos + 1 : i].to_owned()
        self.pos = i + 1
        return Ok(Token::Ident(op_str))
      }
    }
  }
  // Coercion cast: `cast` <co:...>
  if self.starts_with("`cast`") {
    self.pos = self.pos + 6
    self.skip_whitespace_and_comments()
    if self.pos < self.src.length() && self.char_at(self.pos) == '<' {
      let mut d = 1
      self.pos = self.pos + 1
      while self.pos < self.src.length() && d > 0 {
        if self.char_at(self.pos) == '<' { d = d + 1 }
        else if self.char_at(self.pos) == '>' { d = d - 1 }
        self.pos = self.pos + 1
      }
    }
    return self.next_token()
  }

  let c = self.char_at(self.pos)

  // Symbols
  if c == '\\' || c == 'λ' {
    self.pos = self.pos + 1
    return Ok(Token::Backslash)
  }
  if c == '(' {
    self.pos = self.pos + 1
    return Ok(Token::LParen)
  }
  if c == ')' {
    self.pos = self.pos + 1
    return Ok(Token::RParen)
  }
  if c == '{' {
    self.pos = self.pos + 1
    return Ok(Token::LBrace)
  }
  if c == '}' {
    self.pos = self.pos + 1
    return Ok(Token::RBrace)
  }
  if c == '[' {
    self.pos = self.pos + 1
    return Ok(Token::LBracket)
  }
  if c == ']' {
    self.pos = self.pos + 1
    return Ok(Token::RBracket)
  }
  if c == ';' {
    self.pos = self.pos + 1
    return Ok(Token::Semicolon)
  }
  if c == ',' {
    self.pos = self.pos + 1
    return Ok(Token::Comma)
  }
  if c == ':' {
    if self.pos + 1 < self.src.length() && self.char_at(self.pos + 1) == ':' {
      self.pos = self.pos + 2
      return Ok(Token::DoubleColon)
    }
    // `:` alone is the list cons, but GHC also emits symbolic constructors and
    // operators that start with it (`:=>`, `:+`). The operator branch below
    // lexes the whole run, so a bare colon still comes out as ":".
  }

  // Type abstraction / application starting with @
  if c == '@' {
    self.pos = self.pos + 1
    if self.pos < self.src.length() && self.char_at(self.pos) == '(' {
      let start = self.pos
      let mut depth = 1
      self.pos = self.pos + 1
      while self.pos < self.src.length() && depth > 0 {
        if self.char_at(self.pos) == '(' { depth = depth + 1 }
        else if self.char_at(self.pos) == ')' { depth = depth - 1 }
        self.pos = self.pos + 1
      }
      let content = self.src[start:self.pos].to_owned()
      return Ok(Token::TypeVar(content))
    }
    let start = self.pos
    while self.pos < self.src.length() {
      let ch = self.char_at(self.pos)
      if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '\'' || ch == '$' || ch == '*' || ch == '#' {
        self.pos = self.pos + 1
      } else {
        break
      }
    }
    let name = self.src[start:self.pos].to_owned()
    return Ok(Token::TypeVar(name))
  }

  // String literal "..."
  if c == '"' {
    self.pos = self.pos + 1
    let buf = StringBuilder()
    while self.pos < self.src.length() && self.char_at(self.pos) != '"' {
      let ch = self.char_at(self.pos)
      if ch == '\\' {
        self.pos = self.pos + 1
        if self.pos >= self.src.length() {
          break
        }
        buf.write_char(self.lex_escape())
        continue
      }
      buf.write_char(ch)
      self.pos = self.pos + 1
    }
    if self.pos < self.src.length() && self.char_at(self.pos) == '"' {
      self.pos = self.pos + 1
    }
    while self.pos < self.src.length() && self.char_at(self.pos) == '#' {
      self.pos = self.pos + 1
    }
    return Ok(Token::StringLit(buf.to_string()))
  }

  // Char literal '...' or promoted constructor 'Nil
  if c == '\'' {
    if self.pos + 1 < self.src.length() && self.char_at(self.pos + 1) >= 'A' && self.char_at(self.pos + 1) <= 'Z' {
      let start = self.pos
      self.pos = self.pos + 2
      while self.pos < self.src.length() {
        let ch = self.char_at(self.pos)
        if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '\'' || ch == '$' || ch == '#' {
          self.pos = self.pos + 1
        } else {
          break
        }
      }
      let name = self.src[start:self.pos].to_owned()
      return Ok(Token::Ident(name))
    }
    self.pos = self.pos + 1
    let mut ch = ' '
    if self.pos < self.src.length() {
      if self.char_at(self.pos) == '\\' {
        self.pos = self.pos + 1
        if self.pos < self.src.length() {
          ch = self.lex_escape()
        }
      } else {
        ch = self.char_at(self.pos)
        self.pos = self.pos + 1
      }
    }
    if self.pos < self.src.length() && self.char_at(self.pos) == '\'' {
      self.pos = self.pos + 1
    }
    if self.pos < self.src.length() && self.char_at(self.pos) == '#' {
      self.pos = self.pos + 1
    }
    return Ok(Token::CharLit(ch))
  }

  // Numeric literal (positive or negative, decimal, hex, or float)
  let is_negative = c == '-' && self.pos + 1 < self.src.length() && (
    (self.char_at(self.pos + 1) >= '0' && self.char_at(self.pos + 1) <= '9') ||
    (self.char_at(self.pos + 1) == '.' && self.pos + 2 < self.src.length() && self.char_at(self.pos + 2) >= '0' && self.char_at(self.pos + 2) <= '9')
  )
  if (c >= '0' && c <= '9') || is_negative {
    let start_pos = self.pos
    if is_negative {
      self.pos = self.pos + 1
    }
    // Check for hex: 0x or 0X
    let is_hex = self.pos + 1 < self.src.length() && self.char_at(self.pos) == '0' && (self.char_at(self.pos + 1) == 'x' || self.char_at(self.pos + 1) == 'X')
    if is_hex {
      self.pos = self.pos + 2
      let mut n : Int64 = 0L
      while self.pos < self.src.length() {
        let ch = self.char_at(self.pos)
        if ch >= '0' && ch <= '9' {
          n = (n << 4) | (ch.to_int() - '0'.to_int()).to_int64()
          self.pos = self.pos + 1
        } else if ch >= 'a' && ch <= 'f' {
          n = (n << 4) | (ch.to_int() - 'a'.to_int() + 10).to_int64()
          self.pos = self.pos + 1
        } else if ch >= 'A' && ch <= 'F' {
          n = (n << 4) | (ch.to_int() - 'A'.to_int() + 10).to_int64()
          self.pos = self.pos + 1
        } else {
          break
        }
      }
      if is_negative {
        n = -n
      }
      // Consume any hash suffix: #, ##, #Word32, #Word64, etc.
      while self.pos < self.src.length() && self.char_at(self.pos) == '#' {
        self.pos = self.pos + 1
        while self.pos < self.src.length() {
          let ch = self.char_at(self.pos)
          if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '#' {
            self.pos = self.pos + 1
          } else {
            break
          }
        }
      }
      return Ok(Token::IntLit(n.to_int()))
    }

    // Decimal digits
    let digits_start = self.pos
    while self.pos < self.src.length() && self.char_at(self.pos) >= '0' && self.char_at(self.pos) <= '9' {
      self.pos = self.pos + 1
    }

    // Check for float dot
    let mut is_float = false
    if self.pos < self.src.length() && self.char_at(self.pos) == '.' && self.pos + 1 < self.src.length() && self.char_at(self.pos + 1) >= '0' && self.char_at(self.pos + 1) <= '9' {
      is_float = true
      self.pos = self.pos + 1
      while self.pos < self.src.length() && self.char_at(self.pos) >= '0' && self.char_at(self.pos) <= '9' {
        self.pos = self.pos + 1
      }
      if self.pos < self.src.length() && (self.char_at(self.pos) == 'e' || self.char_at(self.pos) == 'E') {
        self.pos = self.pos + 1
        if self.pos < self.src.length() && (self.char_at(self.pos) == '+' || self.char_at(self.pos) == '-') {
          self.pos = self.pos + 1
        }
        while self.pos < self.src.length() && self.char_at(self.pos) >= '0' && self.char_at(self.pos) <= '9' {
          self.pos = self.pos + 1
        }
      }
    }

    let raw_num_str = self.src[start_pos:self.pos].to_owned()

    // Consume any hash suffix: #, ##, #Word32, #Word64, etc.
    while self.pos < self.src.length() && self.char_at(self.pos) == '#' {
      self.pos = self.pos + 1
      while self.pos < self.src.length() {
        let ch = self.char_at(self.pos)
        if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '#' {
          self.pos = self.pos + 1
        } else {
          break
        }
      }
    }

    if is_float {
      let d = parse_double_str(raw_num_str)
      return Ok(Token::FloatLit(d))
    }

    // Decimal integer using Int64
    let mut n : Int64 = 0L
    for i in digits_start..<self.pos {
      let ch = self.char_at(i)
      if ch >= '0' && ch <= '9' {
        let digit = (ch.to_int() - '0'.to_int()).to_int64()
        n = n * 10L + digit
      } else {
        break
      }
    }
    if is_negative {
      n = -n
    }
    let val : Int = if n == -9223372036854775808L {
      -2147483648
    } else {
      n.to_int()
    }
    return Ok(Token::IntLit(val))
  }

  // Underscore '_'
  if c == '_' {
    let next_ch = if self.pos + 1 < self.src.length() { self.char_at(self.pos + 1) } else { ' ' }
    let is_ident_next = (next_ch >= 'a' && next_ch <= 'z') || (next_ch >= 'A' && next_ch <= 'Z') || (next_ch >= '0' && next_ch <= '9') || next_ch == '_'
    if !is_ident_next {
      self.pos = self.pos + 1
      return Ok(Token::Underscore)
    }
  }

  // Equal '='
  if c == '=' {
    let next_ch = if self.pos + 1 < self.src.length() { self.char_at(self.pos + 1) } else { ' ' }
    if next_ch != '=' && next_ch != '#' {
      self.pos = self.pos + 1
      return Ok(Token::Equal)
    }
  }

  // Dot operators: .&., .|., .^., etc., and the bare `.` operator name.
  if c == '.' && !(self.pos + 1 < self.src.length() && is_op_char(self.char_at(self.pos + 1))) {
    self.pos = self.pos + 1
    return Ok(Token::Ident("."))
  }
  if c == '.' && self.pos + 1 < self.src.length() && is_op_char(self.char_at(self.pos + 1)) {
    let start = self.pos
    while self.pos < self.src.length() {
      let ch = self.char_at(self.pos)
      if is_op_char(ch) || ch == '.' || ch == '#' {
        self.pos = self.pos + 1
      } else {
        break
      }
    }
    let op = self.src[start:self.pos].to_owned()
    return Ok(Token::Ident(op))
  }

  // Operator primops like *H#
  if self.starts_with("*H#") {
    self.pos = self.pos + 3
    return Ok(Token::Ident("*H#"))
  }

  // Operators: +, -, *, /, <, >, ==, etc.
  if is_op_char(c) {
    let start = self.pos
    while self.pos < self.src.length() {
      let ch = self.char_at(self.pos)
      if is_op_char(ch) || ch == '#' {
        self.pos = self.pos + 1
      } else {
        break
      }
    }
    let op = self.src[start:self.pos].to_owned()
    return Ok(Token::Ident(op))
  }

  // Identifiers and keywords starting with [a-zA-Z$_]
  if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '$' || c == '_' {
    let start = self.pos
    while self.pos < self.src.length() {
      let ch = self.char_at(self.pos)
      if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '\'' || ch == '$' || is_ident_symbol_char(ch) {
        self.pos = self.pos + 1
      } else {
        break
      }
    }
    let word = self.src[start:self.pos].to_owned()
    if word == "let" { return Ok(Token::KwLet) }
    if word == "in" { return Ok(Token::KwIn) }
    if word == "case" { return Ok(Token::KwCase) }
    if word == "of" { return Ok(Token::KwOf) }
    if word == "Rec" || word == "rec" { return Ok(Token::KwRec) }
    if word == "end" { return Ok(Token::KwEnd) }
    if word == "__DEFAULT" { return Ok(Token::KwDefault) }
    if word == "cast" {
      self.skip_whitespace_and_comments()
      if self.pos < self.src.length() && self.char_at(self.pos) == '<' {
        let mut d = 1
        self.pos = self.pos + 1
        while self.pos < self.src.length() && d > 0 {
          if self.char_at(self.pos) == '<' { d = d + 1 }
          else if self.char_at(self.pos) == '>' { d = d - 1 }
          self.pos = self.pos + 1
        }
      }
      return self.next_token()
    }
    return Ok(Token::Ident(word))
  }

  let unrec = c
  self.pos = self.pos + 1
  Err("Unrecognized character in CoreLite: \{unrec}")
}

fn Lexer::tokenize(self : Lexer) -> Result[Array[Token], String] {
  let tokens : Array[Token] = []
  while true {
    match self.next_token() {
      Ok(Token::EOF) => {
        tokens.push(Token::EOF)
        break
      }
      Ok(tok) => tokens.push(tok)
      Err(e) => return Err(e)
    }
  }
  Ok(tokens)
}

// ----------------------------------------------------------------------------
// Parser
// ----------------------------------------------------------------------------

priv struct Parser {
  tokens : Array[Token]
  mut pos : Int
}

fn Parser::new(tokens : Array[Token]) -> Parser {
  { tokens, pos: 0 }
}

fn Parser::peek(self : Parser) -> Token {
  if self.pos < self.tokens.length() {
    self.tokens[self.pos]
  } else {
    Token::EOF
  }
}

fn Parser::peek_at(self : Parser, offset : Int) -> Token {
  let idx = self.pos + offset
  if idx < self.tokens.length() {
    self.tokens[idx]
  } else {
    Token::EOF
  }
}

fn Parser::next(self : Parser) -> Token {
  let tok = self.peek()
  if self.pos < self.tokens.length() {
    self.pos = self.pos + 1
  }
  tok
}

fn Parser::match_token(self : Parser, expected : Token) -> Bool {
  if self.peek() == expected {
    self.pos = self.pos + 1
    true
  } else {
    false
  }
}

fn Parser::skip_type_signature(self : Parser) -> Unit {
  while self.peek() != Token::EOF {
    if is_ident(self.peek()) && (self.peek_at(1) == Token::Equal || self.peek_at(1) == Token::DoubleColon) {
      break
    }
    if self.peek() == Token::KwRec {
      break
    }
    let _ = self.next()
  }
}

fn Parser::parse_program_internal(self : Parser) -> Result[Program, String] {
  let binds : Array[Bind] = []
  while self.peek() != Token::EOF {
    if self.match_token(Token::Semicolon) {
      continue
    }
    if self.peek() == Token::KwRec {
      let b = match self.parse_rec_bind() {
        Ok(b) => b
        Err(e) => return Err(e)
      }
      binds.push(b)
      continue
    }
    if is_ident(self.peek()) && self.peek_at(1) == Token::DoubleColon {
      let _ = self.next()
      let _ = self.next()
      self.skip_type_signature()
      continue
    }
    if is_ident(self.peek()) && self.peek_at(1) == Token::Equal {
      let name = ident_name(self.next())
      let _ = self.next()
      let expr = match self.parse_expr() {
        Ok(e) => e
        Err(e) => return Err(e)
      }
      binds.push(Bind::NonRec(name, expr))
      let _ = self.match_token(Token::Semicolon)
      continue
    }
    if self.match_token(Token::LBrace) || self.match_token(Token::RBrace) {
      continue
    }
    let tok = self.next()
    return Err("Unexpected token at top level: \{tok}")
  }
  Ok(Program::new(binds))
}

fn Parser::parse_rec_bind(self : Parser) -> Result[Bind, String] {
  let _ = self.next()
  if !self.match_token(Token::LBrace) {
    return Err("Expected '{' after 'Rec'")
  }
  let pairs : Array[(String, Expr)] = []
  while self.peek() != Token::RBrace && self.peek() != Token::KwEnd && self.peek() != Token::EOF {
    if self.match_token(Token::Semicolon) {
      continue
    }
    if is_ident(self.peek()) && self.peek_at(1) == Token::DoubleColon {
      let _ = self.next()
      let _ = self.next()
      self.skip_type_signature()
      continue
    }
    let name = match self.peek() {
      Token::Ident(n) => {
        let _ = self.next()
        n
      }
      _ => return Err("Expected identifier in Rec block, got: \{self.peek()}")
    }
    if !self.match_token(Token::Equal) {
      return Err("Expected '=' in Rec binding for \{name}")
    }
    let expr = match self.parse_expr() {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    pairs.push((name, expr))
    let _ = self.match_token(Token::Semicolon)
  }
  if self.match_token(Token::KwEnd) {
    let _ = self.match_token(Token::KwRec)
  }
  if !self.match_token(Token::RBrace) {
    return Err("Expected '}' closing Rec block")
  }
  Ok(Bind::Rec(pairs))
}

fn Parser::parse_expr(self : Parser) -> Result[Expr, String] {
  match self.peek() {
    Token::Backslash => self.parse_lam()
    Token::KwLet => self.parse_let()
    Token::KwCase => self.parse_case()
    _ => self.parse_app()
  }
}

fn Parser::parse_lam(self : Parser) -> Result[Expr, String] {
  let _ = self.next()
  let params : Array[String] = []
  while self.peek() != Token::Arrow && self.peek() != Token::EOF {
    match self.peek() {
      Token::TypeVar(_) => {
        let _ = self.next()
      }
      Token::LParen => {
        let _ = self.next()
        if self.match_token(Token::RParen) {
          params.push("_")
        } else {
          match self.peek() {
            Token::Ident(p) => {
              let _ = self.next()
              params.push(p)
              if self.match_token(Token::DoubleColon) {
                let mut depth = 1
                while self.peek() != Token::EOF && depth > 0 {
                  if self.peek() == Token::LParen { depth = depth + 1 }
                  else if self.peek() == Token::RParen { depth = depth - 1 }
                  let _ = self.next()
                }
              } else if self.peek() == Token::Comma {
                while self.match_token(Token::Comma) {
                  match self.peek() {
                    Token::Ident(q) => {
                      let _ = self.next()
                      params.push(q)
                    }
                    Token::Underscore => {
                      let _ = self.next()
                      params.push("_")
                    }
                    _ => ()
                  }
                }
                let _ = self.match_token(Token::RParen)
              } else {
                let _ = self.match_token(Token::RParen)
              }
            }
            Token::Underscore => {
              let _ = self.next()
              params.push("_")
              if self.match_token(Token::DoubleColon) {
                let mut depth = 1
                while self.peek() != Token::EOF && depth > 0 {
                  if self.peek() == Token::LParen { depth = depth + 1 }
                  else if self.peek() == Token::RParen { depth = depth - 1 }
                  let _ = self.next()
                }
              } else {
                let _ = self.match_token(Token::RParen)
              }
            }
            _ => return Err("Expected identifier inside parenthesized lambda parameter")
          }
        }
      }
      Token::Underscore => {
        let _ = self.next()
        params.push("_")
      }
      Token::LUnboxedTuple => {
        let _ = self.next()
        let vars : Array[String] = []
        while self.peek() != Token::RUnboxedTuple && self.peek() != Token::EOF {
          if self.match_token(Token::Comma) { continue }
          match self.next() {
            Token::Ident(p) => vars.push(p)
            Token::Underscore => vars.push("_")
            _ => ()
          }
        }
        let _ = self.match_token(Token::RUnboxedTuple)
        for v in vars {
          params.push(v)
        }
      }
      Token::Ident(p) => {
        let _ = self.next()
        params.push(p)
      }
      _ => return Err("Unexpected token in lambda parameter list: \{self.peek()}")
    }
  }
  if !self.match_token(Token::Arrow) {
    return Err("Expected '->' after lambda parameters")
  }
  let body = match self.parse_expr() {
    Ok(e) => e
    Err(e) => return Err(e)
  }
  Ok(Expr::lams(params, body))
}

fn Parser::parse_let(self : Parser) -> Result[Expr, String] {
  let _ = self.next()
  if self.peek() == Token::KwRec {
    let bind = match self.parse_rec_bind() {
      Ok(b) => b
      Err(e) => return Err(e)
    }
    if !self.match_token(Token::KwIn) {
      return Err("Expected 'in' after let Rec")
    }
    let body = match self.parse_expr() {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    return Ok(Expr::Let(bind, body))
  }
  if self.match_token(Token::LBrace) {
    let pairs : Array[(String, Expr)] = []
    let mut is_rec = false
    if self.match_token(Token::KwRec) {
      is_rec = true
    }
    while self.peek() != Token::RBrace && self.peek() != Token::EOF {
      if self.match_token(Token::Semicolon) { continue }
      let name = match self.next() {
        Token::Ident(n) => n
        _ => return Err("Expected identifier in let block")
      }
      if !self.match_token(Token::Equal) {
        return Err("Expected '=' in let binding")
      }
      let val = match self.parse_expr() {
        Ok(e) => e
        Err(e) => return Err(e)
      }
      pairs.push((name, val))
      let _ = self.match_token(Token::Semicolon)
    }
    if !self.match_token(Token::RBrace) {
      return Err("Expected '}' closing let block")
    }
    if !self.match_token(Token::KwIn) {
      return Err("Expected 'in' after let block")
    }
    let body = match self.parse_expr() {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    if is_rec || pairs.length() > 1 {
      return Ok(Expr::Let(Bind::Rec(pairs), body))
    } else if pairs.length() == 1 {
      return Ok(Expr::Let(Bind::NonRec(pairs[0].0, pairs[0].1), body))
    } else {
      return Ok(body)
    }
  }
  let name = match self.next() {
    Token::Ident(n) => n
    _ => return Err("Expected identifier after 'let'")
  }
  if !self.match_token(Token::Equal) {
    return Err("Expected '=' after let identifier \{name}")
  }
  let val = match self.parse_expr() {
    Ok(e) => e
    Err(e) => return Err(e)
  }
  if !self.match_token(Token::KwIn) {
    return Err("Expected 'in' after let binding")
  }
  let body = match self.parse_expr() {
    Ok(e) => e
    Err(e) => return Err(e)
  }
  Ok(Expr::Let(Bind::NonRec(name, val), body))
}

fn Parser::parse_case(self : Parser) -> Result[Expr, String] {
  let _ = self.next()
  let scrutinee = match self.parse_app() {
    Ok(e) => e
    Err(e) => return Err(e)
  }
  if !self.match_token(Token::KwOf) {
    return Err("Expected 'of' in case expression")
  }
  let mut binder = ""
  if is_ident(self.peek()) && self.peek() != Token::KwDefault && !is_constructor_name(ident_name(self.peek())) && self.peek_at(1) == Token::LBrace {
    binder = ident_name(self.next())
  }
  if !self.match_token(Token::LBrace) {
    return Err("Expected '{' starting case alternatives")
  }
  let alts : Array[Alt] = []
  while self.peek() != Token::RBrace && self.peek() != Token::EOF {
    if self.match_token(Token::Semicolon) { continue }
    let alt = match self.parse_alt() {
      Ok(a) => a
      Err(e) => return Err(e)
    }
    alts.push(alt)
    let _ = self.match_token(Token::Semicolon)
  }
  if !self.match_token(Token::RBrace) {
    return Err("Expected '}' closing case alternatives")
  }
  Ok(Expr::Case(scrutinee, binder, alts))
}

fn Parser::parse_alt(self : Parser) -> Result[Alt, String] {
  let pat = match self.peek() {
    Token::KwDefault => {
      let _ = self.next()
      Pat::Default(None)
    }
    Token::Underscore => {
      let _ = self.next()
      Pat::Default(None)
    }
    Token::IntLit(n) => {
      let _ = self.next()
      Pat::Lit(n)
    }
    Token::CharLit(c) => {
      let _ = self.next()
      Pat::Lit(c.to_int())
    }
    Token::FloatLit(d) => {
      let _ = self.next()
      Pat::Lit(d.to_int())
    }
    Token::LUnboxedTuple => {
      let _ = self.next()
      let vars : Array[String] = []
      while self.peek() != Token::RUnboxedTuple && self.peek() != Token::EOF {
        if self.match_token(Token::Comma) { continue }
        match self.next() {
          Token::Ident(name) => vars.push(name)
          Token::Underscore => vars.push("_")
          tok => return Err("Expected variable name in unboxed tuple pattern, got \{tok}")
        }
      }
      if !self.match_token(Token::RUnboxedTuple) {
        return Err("Expected '#)' closing unboxed tuple pattern")
      }
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
      Pat::Data(cname, vars)
    }
    Token::LParen => {
      let _ = self.next()
      if self.match_token(Token::RParen) {
        Pat::Data("()", [])
      } else {
        let vars : Array[String] = []
        while self.peek() != Token::RParen && self.peek() != Token::EOF {
          if self.match_token(Token::Comma) { continue }
          match self.next() {
            Token::Ident(name) => vars.push(name)
            Token::Underscore => vars.push("_")
            tok => return Err("Expected variable in tuple pattern, got \{tok}")
          }
        }
        if !self.match_token(Token::RParen) {
          return Err("Expected ')' closing tuple pattern")
        }
        let buf = StringBuilder()
        buf.write_string("(")
        for _ in 1..<vars.length() {
          buf.write_string(",")
        }
        buf.write_string(")")
        Pat::Data(buf.to_string(), vars)
      }
    }
    Token::Ident(name) => {
      if is_constructor_name(name) {
        let _ = self.next()
        let vars : Array[String] = []
        while is_ident(self.peek()) && self.peek() != Token::Arrow && self.peek() != Token::EOF {
          vars.push(ident_name(self.next()))
        }
        Pat::Data(name, vars)
      } else {
        let _ = self.next()
        if self.peek() == Token::Arrow {
          Pat::Default(Some(name))
        } else {
          Pat::Data(name, [])
        }
      }
    }
    _ => return Err("Unexpected token in case pattern: \{self.peek()}")
  }
  if !self.match_token(Token::Arrow) {
    return Err("Expected '->' after case pattern")
  }
  let expr = match self.parse_expr() {
    Ok(e) => e
    Err(e) => return Err(e)
  }
  Ok(Alt::new(pat, expr))
}

fn Parser::can_start_atom(self : Parser) -> Bool {
  match self.peek() {
    Token::IntLit(_) => true
    Token::FloatLit(_) => true
    Token::CharLit(_) => true
    Token::StringLit(_) => true
    Token::Ident(_) => {
      if self.peek_at(1) == Token::Equal || self.peek_at(1) == Token::DoubleColon {
        return false
      }
      true
    }
    Token::TypeVar(_) => true
    Token::LParen => true
    Token::LUnboxedTuple => true
    Token::LBracket => true
    _ => false
  }
}

fn Parser::parse_app(self : Parser) -> Result[Expr, String] {
  while self.peek() is Token::TypeVar(_) {
    let _ = self.next()
  }
  let mut head = match self.parse_atom() {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  while self.can_start_atom() {
    if self.peek() is Token::TypeVar(_) {
      let _ = self.next()
      continue
    }
    let arg = match self.parse_atom() {
      Ok(a) => a
      Err(e) => return Err(e)
    }
    match head {
      Constr(_, args) => args.push(arg)
      _ => head = App(head, arg)
    }
  }
  Ok(head)
}

fn Parser::parse_atom(self : Parser) -> Result[Expr, String] {
  match self.peek() {
    Token::IntLit(n) => {
      let _ = self.next()
      Ok(Expr::LitInt(n))
    }
    Token::FloatLit(d) => {
      let _ = self.next()
      Ok(Expr::LitFloat(d))
    }
    Token::CharLit(c) => {
      let _ = self.next()
      Ok(Expr::LitChar(c))
    }
    Token::StringLit(s) => {
      let _ = self.next()
      Ok(Expr::LitString(s))
    }
    Token::Ident(name) => {
      let _ = self.next()
      if is_constructor_name(name) {
        Ok(Expr::Constr(name, []))
      } else {
        Ok(Expr::Var(name))
      }
    }
    Token::LUnboxedTuple => {
      let _ = self.next()
      let elements : Array[Expr] = []
      while self.peek() != Token::RUnboxedTuple && self.peek() != Token::EOF {
        if self.match_token(Token::Comma) { continue }
        let elem = match self.parse_expr() {
          Ok(e) => e
          Err(e) => return Err(e)
        }
        elements.push(elem)
      }
      if !self.match_token(Token::RUnboxedTuple) {
        return Err("Expected '#)' closing unboxed tuple expression")
      }
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
      Ok(Expr::Constr(cname, elements))
    }
    Token::LParen => {
      let _ = self.next()
      if self.match_token(Token::RParen) {
        return Ok(Expr::Constr("()", []))
      }
      let first_expr = match self.parse_expr() {
        Ok(e) => e
        Err(e) => return Err(e)
      }
      if self.peek() == Token::Comma {
        let elements = [first_expr]
        while self.match_token(Token::Comma) {
          let elem = match self.parse_expr() {
            Ok(e) => e
            Err(e) => return Err(e)
          }
          elements.push(elem)
        }
        if !self.match_token(Token::RParen) {
          return Err("Expected ')' closing tuple expression")
        }
        let buf = StringBuilder()
        buf.write_string("(")
        for _ in 1..<elements.length() {
          buf.write_string(",")
        }
        buf.write_string(")")
        return Ok(Expr::Constr(buf.to_string(), elements))
      }
      if !self.match_token(Token::RParen) {
        return Err("Expected ')' closing parenthesized expression")
      }
      Ok(first_expr)
    }
    Token::LBracket => {
      let _ = self.next()
      let elements : Array[Expr] = []
      while self.peek() != Token::RBracket && self.peek() != Token::EOF {
        if self.match_token(Token::Comma) { continue }
        let elem = match self.parse_expr() {
          Ok(e) => e
          Err(e) => return Err(e)
        }
        elements.push(elem)
        let _ = self.match_token(Token::Comma)
      }
      if !self.match_token(Token::RBracket) {
        return Err("Expected ']' closing list literal")
      }
      let mut res = Expr::Constr("[]", [])
      for i = elements.length() - 1; i >= 0; i = i - 1 {
        res = Expr::Constr(":", [elements[i], res])
      }
      Ok(res)
    }
    _ => Err("Expected atomic expression, got: \{self.peek()}")
  }
}

// ----------------------------------------------------------------------------
// Public API
// ----------------------------------------------------------------------------

///| Parse a full CoreLite program.
pub fn parse_program(input : String) -> Result[Program, String] {
  let lexer = Lexer::new(input)
  let tokens = match lexer.tokenize() {
    Ok(toks) => toks
    Err(e) => return Err(e)
  }
  let parser = Parser::new(tokens)
  parser.parse_program_internal()
}

///| Alias for parse_program.
pub fn parse_core(input : String) -> Result[Program, String] {
  parse_program(input)
}

///| Parse a single CoreLite expression.
pub fn parse_expr(input : String) -> Result[Expr, String] {
  let lexer = Lexer::new(input)
  let tokens = match lexer.tokenize() {
    Ok(toks) => toks
    Err(e) => return Err(e)
  }
  let parser = Parser::new(tokens)
  parser.parse_expr()
}
