///| Coronet CLI entrypoint

///|
struct CliArgs {
  input_files : Array[String]
  target : String
  output_file : String?
  lto : Bool
}

///|
fn print_usage() -> Unit {
  let usage = (
    #|Coronet: GHC Core -> HVM2/3/GPU/Metal/CUDA/HIP Parallel Compiler
    #|
    #|Usage: coronet <input.core ...> --target <hvm2|hvm3|gpu|metal|cuda|hip> [-o <output_file>]
    #|       coronet <input.core ...> [--gpu|--metal|--cuda|--hip] [-o <output_file>]
    #|
    #|Arguments:
    #|  <input.core ...>             One or more input CoreLite source files to compile and link
    #|
    #|Options:
    #|  --target <backend>           Target backend:
    #|                                 hvm2  (Interaction Nets CPU)
    #|                                 hvm3  (Interaction Calculus CPU)
    #|                                 gpu   (HVM2 CUDA / Colab GPU)
    #|                                 metal (Apple Silicon Metal GPU)
    #|                                 cuda  (NVIDIA CUDA GPU)
    #|                                 hip   (AMD HIP GPU)
    #|  --gpu                        Shortcut for --target gpu
    #|  --metal                      Shortcut for --target metal
    #|  --cuda                       Shortcut for --target cuda
    #|  --hip                        Shortcut for --target hip
    #|  -o, --output <file>          Output destination file (default: stdout / execute)
    #|  -h, --help                   Show this help message and exit
  )
  println(usage)
}

///|
fn parse_cli_args(args : Array[String]) -> CliArgs {
  let input_files : Array[String] = []
  let mut target : String? = None
  let mut output_file : String? = None
  let mut lto = true
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if arg == "-h" || arg == "--help" {
      print_usage()
      @env.exit(0)
    } else if arg == "--gpu" {
      target = Some("gpu")
    } else if arg == "--metal" {
      target = Some("metal")
    } else if arg == "--cuda" {
      target = Some("cuda")
    } else if arg == "--hip" {
      target = Some("hip")
    } else if arg == "--lto" {
      lto = true
    } else if arg == "--no-lto" {
      lto = false
    } else if arg == "--target" {
      i = i + 1
      if i >= args.length() {
        println("Error: --target requires an argument ('hvm2', 'hvm3', 'gpu', 'metal', 'cuda', 'hip')")
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
      input_files.push(arg)
    }
    i = i + 1
  }

  if input_files.is_empty() {
    println("Error: Missing input .core file")
    print_usage()
    @env.exit(1)
  }

  let tgt = match target {
    Some(t) => {
      if t != "hvm2" && t != "hvm3" && t != "gpu" && t != "metal" && t != "cuda" && t != "hip" {
        println("Error: Invalid target '\{t}'. Must be 'hvm2', 'hvm3', 'gpu', 'metal', 'cuda', or 'hip'.")
        print_usage()
        @env.exit(1)
      }
      t
    }
    None => {
      println("Error: Missing --target option ('hvm2', 'hvm3', 'gpu', 'metal', 'cuda', or 'hip')")
      print_usage()
      @env.exit(1)
    }
  }

  { input_files, target: tgt, output_file, lto }
}

///|
async fn handle_metal_target(program : @syntax.Program, output_file : String?) -> Unit {
  let hvm2_code = @lower_hvm2.lower(program)
  let tmp_dir = "_build/metal"
  if !(@fs.exists(tmp_dir)) {
    let _ = @process.run("mkdir", ["-p", tmp_dir][:])
  }
  let tmp_hvm = "_build/metal/temp.hvm"
  @fs.write_text(tmp_hvm, hvm2_code)

  match output_file {
    Some(out_path) => {
      @fs.write_text(out_path, hvm2_code)
    }
    None => {
      if @fs.exists("bin/coronet_metal") {
        let runner = @process.run(
          "bin/coronet_metal",
          [][:],
          stdout=Inherit,
          stderr=Inherit,
        )
        if runner.exit_code != 0 {
          @env.exit(runner.exit_code)
        }
      } else {
        println(hvm2_code)
      }
    }
  }
}

///|
async fn handle_gpu_target(program : @syntax.Program, output_file : String?) -> Unit {
  let hvm2_code = @lower_hvm2.lower(program)
  let tmp_dir = "_build/gpu"
  if !(@fs.exists(tmp_dir)) {
    let _ = @process.run("mkdir", ["-p", tmp_dir][:])
  }
  let tmp_hvm = "_build/gpu/temp.hvm"
  let tmp_cu = "_build/gpu/temp.cu"
  @fs.write_text(tmp_hvm, hvm2_code)

  let hvm_bin = if @fs.exists("vendor/HVM2/target/release/hvm") {
    "vendor/HVM2/target/release/hvm"
  } else {
    "hvm"
  }

  // Generate CUDA code via hvm gen-cu
  let mut cu_code = ""
  try {
    let gen_res = @process.run(
      hvm_bin,
      ["gen-cu", tmp_hvm][:],
      stdout=Collect,
      stderr=Collect,
    )
    if gen_res.exit_code != 0 {
      println("Warning: 'hvm gen-cu' exited with code \{gen_res.exit_code}")
    }
    cu_code = gen_res.stdout_text()
  } catch {
    _ => ()
  }
  if cu_code.length() > 0 {
    @fs.write_text(tmp_cu, cu_code)
  }

  match output_file {
    Some(out_path) => {
      if out_path.has_suffix(".cu") {
        if cu_code.length() > 0 {
          @fs.write_text(out_path, cu_code)
        } else {
          println("Error: failed to generate CUDA code")
          @env.exit(1)
        }
      } else {
        @fs.write_text(out_path, hvm2_code)
      }
    }
    None => {
      // Check if scripts/run_colab_gpu.sh is available
      if @fs.exists("scripts/run_colab_gpu.sh") {
        let runner = @process.run(
          "bash",
          ["scripts/run_colab_gpu.sh", tmp_hvm][:],
          stdout=Inherit,
          stderr=Inherit,
        )
        if runner.exit_code != 0 {
          @env.exit(runner.exit_code)
        }
      } else if cu_code.length() > 0 {
        println(cu_code)
      } else {
        println(hvm2_code)
      }
    }
  }
}

///|
async fn main {
  let args = @env.args()
  let cli = parse_cli_args(args)

  let programs : Array[@syntax.Program] = []
  for input_file in cli.input_files {
    if !(@fs.exists(input_file)) {
      println("Error: Input file '\{input_file}' not found.")
      @env.exit(1)
    }

    let content = @fs.read_text(input_file)
    match @syntax.parse_core(content) {
      Ok(prog) => programs.push(prog)
      Err(err) => {
        println("Parse error in '\{input_file}': \{err}")
        @env.exit(1)
      }
    }
  }

  let program = if cli.lto {
    @syntax.link_programs_lto(programs, ["main", "result"])
  } else {
    @syntax.link_programs(programs)
  }

  if cli.target == "gpu" || cli.target == "cuda" || cli.target == "hip" {
    handle_gpu_target(program, cli.output_file)
    return
  }

  if cli.target == "metal" {
    handle_metal_target(program, cli.output_file)
    return
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
