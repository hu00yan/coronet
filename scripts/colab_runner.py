#!/usr/bin/env python3
"""
scripts/colab_runner.py - Automated Colab GPU Execution Bridge for HVM2 / CUDA

This tool compiles and executes HVM2 programs on remote Google Colab GPU instances:
1. Accepts an HVM2 (.hvm) program or a standalone CUDA (.cu) file.
2. If given .hvm, generates standalone CUDA code via `vendor/HVM2/target/release/hvm gen-cu`.
3. Automatically patches shared memory size for Tesla T4 GPU (48 KB LNet).
4. Packages and transmits the workload to a Google Colab GPU VM using the `colab` CLI.
5. Remotely compiles with `nvcc -O3` and executes the binary on the GPU.
6. Streams results (Result, ITRS, TIME, MIPS) back to local stdout.
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Dict, Any, Optional, Tuple

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DEFAULT_HVM2_BIN = REPO_ROOT / "vendor" / "HVM2" / "target" / "release" / "hvm"
COLAB_CLI = Path(os.environ.get("COLAB_CLI_PATH", "/Users/huyan00/.local/bin/colab"))


def find_colab_cli() -> Path:
    if COLAB_CLI.exists() and os.access(COLAB_CLI, os.X_OK):
        return COLAB_CLI
    # Try PATH
    import shutil
    p = shutil.which("colab")
    if p:
        return Path(p)
    raise FileNotFoundError(
        "Colab CLI not found. Expected at /Users/huyan00/.local/bin/colab or in PATH."
    )


def find_hvm2_bin() -> Path:
    custom = os.environ.get("HVM2_BIN")
    if custom and Path(custom).exists():
        return Path(custom)
    if DEFAULT_HVM2_BIN.exists() and os.access(DEFAULT_HVM2_BIN, os.X_OK):
        return DEFAULT_HVM2_BIN
    local_bin = REPO_ROOT / "vendor" / "HVM2" / "hvm"
    if local_bin.exists() and os.access(local_bin, os.X_OK):
        return local_bin
    raise FileNotFoundError(
        f"HVM2 executable not found at {DEFAULT_HVM2_BIN} or {local_bin}. Build HVM2 with cargo build --release."
    )


def generate_cuda_from_hvm(hvm_file: Path) -> str:
    hvm2_bin = find_hvm2_bin()
    cmd = [str(hvm2_bin), "gen-cu", str(hvm_file)]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        raise RuntimeError(
            f"Failed to generate CUDA code from {hvm_file} (exit code {res.returncode}):\n{res.stderr}"
        )
    return res.stdout


def adapt_cuda_for_gpu(cu_source: str, gpu: str) -> str:
    """Adapts HVM2 CUDA source code to target GPU architecture limits.

    T4 has 64 KB max shared memory per block. HVM2 default uses 96 KB (0x2000 * 8 + 0x2000 * 4),
    which causes `cudaErrorInvalidValue` on T4. Adjusting to 0x1000 uses 48 KB, running cleanly.
    """
    if gpu.upper() == "T4":
        cu_source = cu_source.replace(
            "const u32 L_NODE_LEN = 0x2000;",
            "const u32 L_NODE_LEN = 0x1000;",
        )
        cu_source = cu_source.replace(
            "const u32 L_VARS_LEN = 0x2000;",
            "const u32 L_VARS_LEN = 0x1000;",
        )
    return cu_source


def build_remote_python_script(cu_source: str, nvcc_opt: str = "-O3") -> str:
    b64_payload = base64.b64encode(cu_source.encode("utf-8")).decode("ascii")

    script = f'''# Remote Colab GPU Execution Script
import base64
import os
import subprocess
import sys
import time

CU_PAYLOAD = "{b64_payload}"

def main():
    cu_source = base64.b64decode(CU_PAYLOAD)
    work_dir = "/tmp/hvm_colab_run"
    os.makedirs(work_dir, exist_ok=True)
    cu_path = os.path.join(work_dir, "kernel.cu")
    bin_path = os.path.join(work_dir, "kernel_bin")

    with open(cu_path, "wb") as f:
        f.write(cu_source)

    print("[colab-gpu] Compiling HVM2 CUDA kernel with nvcc {nvcc_opt}...", flush=True)
    t0 = time.time()
    compile_cmd = ["nvcc", "{nvcc_opt}", "-w", cu_path, "-o", bin_path]
    comp = subprocess.run(compile_cmd, capture_output=True, text=True)
    t_compile = time.time() - t0

    if comp.returncode != 0:
        print(f"[colab-gpu] Compilation FAILED (exit code {{comp.returncode}}):", file=sys.stderr, flush=True)
        print(comp.stderr, file=sys.stderr, flush=True)
        sys.exit(comp.returncode)

    print(f"[colab-gpu] Compilation succeeded in {{t_compile:.2f}}s", flush=True)
    print("[colab-gpu] Executing on GPU...", flush=True)

    t1 = time.time()
    run = subprocess.run([bin_path], capture_output=True, text=True)
    t_run = time.time() - t1

    print(f"[colab-gpu] Execution finished in {{t_run:.3f}}s, exit code: {{run.returncode}}", flush=True)
    if run.stdout:
        print(run.stdout, end="", flush=True)
    if run.stderr:
        print(f"[colab-gpu-stderr] {{run.stderr}}", flush=True)

    sys.exit(run.returncode)

if __name__ == "__main__":
    main()
'''
    return script


def parse_hvm2_gpu_output(output: str) -> Dict[str, Any]:
    res: Dict[str, Any] = {
        "result": None,
        "itrs": None,
        "time": None,
        "mips": None,
        "leak": None,
        "raw": output,
    }
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("Result:"):
            raw_res = line[len("Result:") :].strip()
            res["result"] = raw_res
            m = re.match(r"^\(?\s*(\d+)\s+(\d+)\s*\)?$", raw_res)
            if m:
                hi = int(m.group(1))
                lo = int(m.group(2))
                res["decoded_result"] = (hi << 24) + lo
        elif line.startswith("- ITRS:"):
            try:
                res["itrs"] = int(line[len("- ITRS:") :].strip())
            except ValueError:
                pass
        elif line.startswith("- TIME:"):
            res["time"] = line[len("- TIME:") :].strip()
        elif line.startswith("- MIPS:"):
            try:
                res["mips"] = float(line[len("- MIPS:") :].strip())
            except ValueError:
                pass
        elif line.startswith("- LEAK:"):
            try:
                res["leak"] = int(line[len("- LEAK:") :].strip())
            except ValueError:
                pass
    return res


def run_on_colab(
    cu_source: str,
    gpu: str = "T4",
    timeout: int = 300,
    nvcc_opt: str = "-O3",
    keep_session: bool = False,
) -> Tuple[int, str, str]:
    colab_bin = find_colab_cli()
    cu_adapted = adapt_cuda_for_gpu(cu_source, gpu)
    remote_script = build_remote_python_script(cu_adapted, nvcc_opt=nvcc_opt)

    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as tf:
        tf.write(remote_script)
        temp_script_path = tf.name

    try:
        cmd = [
            str(colab_bin),
            "run",
            "--gpu",
            gpu,
            "--timeout",
            str(timeout),
        ]
        if keep_session:
            cmd.append("--keep")
        cmd.append(temp_script_path)

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        stdout, stderr = proc.communicate()
        return proc.returncode, stdout, stderr
    finally:
        if os.path.exists(temp_script_path):
            try:
                os.remove(temp_script_path)
            except OSError:
                pass


def main():
    parser = argparse.ArgumentParser(
        description="Run HVM2 / CUDA programs on remote Google Colab GPU"
    )
    parser.add_argument(
        "input_file",
        type=Path,
        help="Path to HVM2 file (.hvm) or CUDA file (.cu)",
    )
    parser.add_argument(
        "--gpu",
        default="T4",
        help="Colab GPU variant (default: T4). Supported: T4, L4, A100",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help="Timeout in seconds for remote execution (default: 300)",
    )
    parser.add_argument(
        "--nvcc-opt",
        default="-O3",
        help="nvcc optimization flag (default: -O3)",
    )
    parser.add_argument(
        "--keep",
        action="store_true",
        help="Keep remote Colab session active after execution",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output parsed metrics as JSON",
    )

    args = parser.parse_args()

    if not args.input_file.exists():
        print(f"Error: input file '{args.input_file}' not found.", file=sys.stderr)
        sys.exit(1)

    # 1. Obtain CUDA source
    if args.input_file.suffix.lower() == ".cu":
        print(f"--> Reading CUDA source from {args.input_file}...")
        cu_source = args.input_file.read_text(encoding="utf-8")
    else:
        print(f"--> Generating CUDA code from {args.input_file} via HVM2...")
        cu_source = generate_cuda_from_hvm(args.input_file)

    # 2. Run on Colab GPU
    print(f"--> Dispatching to Google Colab ({args.gpu} GPU)...")
    t0 = time.time()
    code, stdout, stderr = run_on_colab(
        cu_source,
        gpu=args.gpu,
        timeout=args.timeout,
        nvcc_opt=args.nvcc_opt,
        keep_session=args.keep,
    )
    elapsed = time.time() - t0

    if code != 0:
        print(f"DEBUG: colab run returned {code}", file=sys.stderr)
        print(f"DEBUG stdout:\n{stdout}", file=sys.stderr)
        print(f"DEBUG stderr:\n{stderr}", file=sys.stderr)

    # 3. Filter and stream stdout
    # Remove colab CLI update chatter if present for clean reporting
    filtered_lines = []
    for line in stdout.splitlines():
        if line.startswith("[colab] A new version of Colab CLI"):
            continue
        if line.startswith("[colab] Run 'colab update'") or line.startswith("[colab] To silence"):
            continue
        filtered_lines.append(line)
    clean_stdout = "\n".join(filtered_lines).strip()

    # 3. Parse output
    parsed = parse_hvm2_gpu_output(clean_stdout)
    parsed["elapsed_wall_s"] = elapsed
    parsed["returncode"] = code

    # 4. Filter and stream stdout
    if clean_stdout:
        print(clean_stdout)
        if parsed.get("decoded_result") is not None:
            print(f"Decoded Result: {parsed['decoded_result']}")

    if stderr.strip():
        # Only print relevant stderr (exclude standard colab info)
        err_lines = [l for l in stderr.splitlines() if not l.startswith("[colab]")]
        if err_lines:
            print("\n".join(err_lines), file=sys.stderr)

    if args.json:
        print(json.dumps(parsed, indent=2))

    sys.exit(code)


if __name__ == "__main__":
    main()
