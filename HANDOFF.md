# Coronet — 交接文档（HANDOFF）

> 写于 2026-11-15（收工终版）。前序工作由 DeepAI Code 线程的指挥官 + 两个子代理完成 R1 设计轮并超预期推进到 R2/R3 实现与验证。本项目现移交给新代理（Antigravity）继续。
> **阅读顺序：本文 → `docs/TARGETS.md`（两后端规格）→ `frontend/README.md`（CoreLite 规格）→ `tests/e2e/README.md`（验证方法）→ `docs/experiments/INDEX.md`（语义实验素材）。**

## 1. 项目定位

**Coronet** = **Cor**e → interaction **net**s。把 GHC Core 编译到 **HVM2 和 HVM3**（Interaction Combinators / Interaction Calculus），验证 Haskell 能否获得隐式自动并行执行能力。

背景共识：
- GHC Core 是最高杠杆切入点：纯函数、不可变数据、ADT、高阶、惰性，与 Interaction Nets 契合；复用 GHC 前端，Core 之后接 Coronet，不重写 GHC。
- HVM2（Rust，并行 Interaction Net evaluator，含 C/CUDA 后端）与 HVM3（Haskell+C，Interaction Calculus，编译原生 C，性能好但无 GPU 后端）**IR 不兼容，各写 lowering**。
- 自动并行只对有足够独立 rewrite 的程序有效，不消除串行依赖——基准要如实测。

## 2. 已定决策

| 决策 | 结论 | 理由 |
|---|---|---|
| 项目名 | `coronet` | Core → interaction nets |
| 实现语言 | **MoonBit** | 三候选中唯一有工具链；性能好 |
| 输入 | **CoreLite**：GHC Core `-ddump-simpl` 纯子集（见 `frontend/README.md` 的 EBNF） | 手写 `.core` 测试 + 可直连 GHC 插件/提取脚本 |
| 范围（P1） | Int/Bool、ADT、case、高阶、递归、let/letrec；不做 IO/ST/FFI/coercion/tick | 三阶段计划第一阶段 |
| 双后端 | `src/lower_hvm2`（→ HVM2 Book 文本）+ `src/lower_hvm3`（→ Interaction Calculus） | IR 不兼容 |
| 测试 | e2e 三方对照：GHC(runghc) vs HVM2 vs HVM3 输出逐位一致（`tests/e2e/verify.py`） | 不依赖 GHC 也能闭环；且已实装 GHC 对照 |
| 阶段计划 | P1 子集跑通 → P2 并行验证+基准 → P3 完整惰性 + GHC 生态对接 | 用户三阶段计划 |

## 3. 目录地图（~/mycode/coronet/，git 仓库，5+1 commits）

```
HANDOFF.md              ← 本文
docs/
├── TARGETS.md          ← HVM2/HVM3 两后端完整规格：CLI、文法、AST、lowering 模式、Colab GPU 桥
├── experiments/        ← 语义实验素材（中断顾问的遗产，见其 INDEX.md；含惰性/共享核心实验）
frontend/
├── README.md           ← CoreLite 规格（EBNF）+ Core 提取管线说明
├── CoronetPlugin.hs    ← GHC 原生插件（提取 Core）
└── extract_core.sh     ← ghc -ddump-simpl 提取/清洗脚本
src/
├── syntax/             ← CoreLite parser（ast.mbt, parse.mbt）
├── lower_hvm2/         ← Core IR → HVM2
└── lower_hvm3/         ← Core IR → HVM3 IC
cmd/main/               ← CLI（bin/coronet 为已构建二进制）
tests/
├── fixtures/hs/        ← 01-08 Haskell 原题（arith/fib/adt/higher_order/tree/lazy_stream/nqueens/mergesort）
├── fixtures/core/      ← 对应 CoreLite 输入
├── samples/hvm2|hvm3/  ← 手写参考样例
└── e2e/                ← verify.py 三方对照 + 性能计时；报告在 _build/e2e/report.md
scripts/                ← run_hvm2.sh / run_hvm3.sh / run_colab_gpu.sh（远程 Colab GPU 桥）/ colab_runner.py
vendor/HVM2, HVM3       ← 参考仓库克隆（均已构建：HVM2 target/release/hvm；HVM3 dist-newstyle）
.build-logs/            ← ghc / hvm2 / hvm3 构建日志
```

## 4. 环境事实（实测 2026-11-15）

- MoonBit `moon 0.1.20261104` ✅；Rust/cargo 1.98 ✅（HVM2 已构建）
- **GHC 9.14.1 + cabal 3.18 已由 brew 安装** ✅，`runghc` 可用（e2e 对照用）；HVM3 已构建（cabal，见 .build-logs/hvm3.log）
- Python 3.15、Node 26 ✅；GitHub 可达 ✅；本机 macOS Apple Silicon 无 NVIDIA GPU → GPU 走 `scripts/run_colab_gpu.sh`（Colab T4/L4/A100）
- HVM2 CLI：`vendor/HVM2/target/release/hvm run|run-c|run-cu|gen-c|gen-cu <file.hvm>`

## 5. 交接前实测状态（2026-11-15 收工前跑的）

- **单元测试：32/32 全绿**（`moon test`）
- **e2e 三方对照：5/8 PASS**，输出与 GHC 逐位一致：
  - ✅ 01_arith（48）、02_fib（55）、03_adt（42）、04_higher_order（24）、05_tree（92）——HVM2/HVM3 双后端均对
  - ❌ **06_lazy_stream（GHC=55）**：HVM2 执行失败(exit 101)；HVM3 输出 `invalid:app-w32(1)`
  - ❌ **07_nqueens（GHC=92）**：双后端执行失败
  - ❌ **08_mergesort（GHC=481054039）**：双后端执行失败
- 三个失败全是**惰性/共享语义**硬骨头（惰性流、惰性下的剪枝搜索、惰性排序），与 `docs/experiments/` 中顾问最后攻关的问题完全一致。**这是交接后的第一战场。**

## 6. 已完成

1. 项目命名、目录、MoonBit 工程、git 仓库。
2. HVM2/HVM3 文法与 CLI 考证（docs/TARGETS.md），两运行时构建并跑通冒烟。
3. CoreLite 规格 + parser + 双后端 lowering + CLI，全管线贯通。
4. e2e 验证体系（GHC 对照 + 计时）+ 8 组 fixture（含 nqueens/mergesort 基准素材）。
5. 超纲交付：GHC 原生插件（frontend/CoronetPlugin.hs）、Colab GPU 远程执行桥。
6. 语义实验素材库（docs/experiments/，约 100 个 HVM2 探针）。

## 7. 未完成 / 待办（建议顺序）

1. **修复三个惰性失败 fixture**（06_lazy_stream / 07_nqueens / 08_mergesort）：
   从 `docs/experiments/hvmx/laz1.hvm`、`share1.hvm` 与 `test_lazy*/test_whnf*` 系列入手，定位是求值顺序、共享被 DUP 破坏还是 WHNF 提取问题；以 e2e 逐位一致为验收。
2. **补写语义备忘录**（`docs/experiments/SEMANTICS-MEMO.md`）：把实验结论落纸——共享编码（REF-thunk vs DUP vs 显式 thunk）、WHNF 强制、ADT 编码在代码里的实际选择及其语义依据。
3. **P2 并行基准**：fib/parallel map/tree reduction/merge sort/N-Queens 多核 speedup（HVM2 `run` vs `run-c` vs GHC -N），GPU 走 Colab 桥；指标：单线程时间/多核 speedup/内存/归约数。07/08 fixture 已是基准素材。
4. **P3 远期**：完整惰性语义（无穷结构、递归共享）、GHC 插件管线产品化、IO Effect Boundary。

## 8. 未决问题（需人拍板）

- 三个惰性失败的修法：改 lowering 编码（保惰性但可能损并行度）vs 语义限定（文档声明 CoreLite 子集内哪些惰性模式不支持）——建议先诊断再选。
- HVM3 的 `invalid:app-w32(1)` 是 lowering 的 bug 还是 HVM3 运行时限制，需单独定位。
- GPU 基准是否走 Colab 桥（当前唯一路径）。

## 9. 参考资料

- https://github.com/HigherOrderCO/HVM2 / HVM3（本地克隆见 vendor/，均已构建）
- `docs/TARGETS.md`：两后端文法/节点/交互规则（带出处）
- `docs/experiments/INDEX.md`：实验族谱与给接手者的三条建议
- GHC Core：GHC 用户指南 "Core language"；`-ddump-simpl` 输出格式
