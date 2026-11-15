///| Coronet CLI entrypoint

///|
struct CliArgs {
  input_file : String
  target : String
  output_file : String?
}

///|
fn print_usage() -> Unit {
  let usage = (
    #|Coronet: GHC Core -> HVM2/3 Compiler
    #|
    #|Usage: coronet <input.core> --target <hvm2|hvm3> [-o <output_file>]
    #|
    #|Arguments:
    #|  <input.core>           Input CoreLite source file
    #|
    #|Options:
    #|  --target <hvm2|hvm3>   Target backend: hvm2 (Interaction Nets) or hvm3 (Interaction Calculus)
    #|  -o, --output <file>    Output destination file (default: stdout)
    #|  -h, --help             Show this help message and exit
  )
  println(usage)
}

///|
fn parse_cli_args(args : Array[String]) -> CliArgs {
  let mut input_file : String? = None
  let mut target : String? = None
  let mut output_file : String? = None
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if arg == "-h" || arg == "--help" {
      print_usage()
      @env.exit(0)
    } else if arg == "--target" {
      i = i + 1
      if i >= args.length() {
        println("Error: --target requires an argument ('hvm2' or 'hvm3')")
        print_usage()
        @env.exit(1)
      }
      target = Some(args[i])
    } else if arg.has_prefix("--target=") {
      target = Some(arg[9:].to_owned())
    } else if arg == "-o" || arg == "--output" {
      i = i + 1
      if i >= args.length() {
        println("Error: -o/--output requires a filename argument")
        print_usage()
        @env.exit(1)
      }
      output_file = Some(args[i])
    } else if arg.has_prefix("-o=") {
      output_file = Some(arg[3:].to_owned())
    } else if arg.has_prefix("--output=") {
      output_file = Some(arg[9:].to_owned())
    } else if arg.has_prefix("-") {
      println("Error: Unknown option '\{arg}'")
      print_usage()
      @env.exit(1)
    } else {
      match input_file {
        None => input_file = Some(arg)
        Some(_) => {
          println("Error: Unexpected extra argument '\{arg}'")
          print_usage()
          @env.exit(1)
        }
      }
    }
    i = i + 1
  }

  let in_file = match input_file {
    Some(f) => f
    None => {
      println("Error: Missing input .core file")
      print_usage()
      @env.exit(1)
    }
  }

  let tgt = match target {
    Some(t) => {
      if t != "hvm2" && t != "hvm3" {
        println("Error: Invalid target '\{t}'. Must be 'hvm2' or 'hvm3'.")
        print_usage()
        @env.exit(1)
      }
      t
    }
    None => {
      println("Error: Missing --target option ('hvm2' or 'hvm3')")
      print_usage()
      @env.exit(1)
    }
  }

  { input_file: in_file, target: tgt, output_file }
}

///|
async fn main {
  let args = @env.args()
  let cli = parse_cli_args(args)

  if !(@fs.exists(cli.input_file)) {
    println("Error: Input file '\{cli.input_file}' not found.")
    @env.exit(1)
  }

  let content = @fs.read_text(cli.input_file)
  let program = match @syntax.parse_core(content) {
    Ok(prog) => prog
    Err(err) => {
      println("Parse error in '\{cli.input_file}': \{err}")
      @env.exit(1)
    }
  }

  let generated_code = match cli.target {
    "hvm2" => @lower_hvm2.lower(program)
    "hvm3" => @lower_hvm3.lower(program)
    _ => {
      println("Error: Unsupported target '\{cli.target}'")
      @env.exit(1)
    }
  }

  match cli.output_file {
    Some(out_path) => @fs.write_text(out_path, generated_code)
    None => println(generated_code)
  }
}
