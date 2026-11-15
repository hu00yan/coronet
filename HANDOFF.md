# Coronet — 交接文档（HANDOFF）

> 写于 2026-11-15。前序工作由 DeepAI Code 线程的指挥官 + 两个子代理（DeepSeek V4.1 工人、MiMo 2.6 Pro 顾问）完成 R1（设计轮）。本项目现移交给新代理（Antigravity）继续。**先读本文，再读 DESIGN.md 和 docs/semantics-memo.md。**

## 1. 项目定位

**Coronet** = **Cor**e → interaction **net**s。把 GHC Core 编译到 **HVM2 和 HVM3**（Interaction Combinators / Interaction Calculus 执行模型），验证成熟函数式语言（Haskell）能否获得隐式自动并行执行能力。

背景共识（来自用户与前序讨论）：
- GHC Core 是合适的切入点：纯函数、不可变数据、ADT、高阶函数、惰性求值，与 Interaction Nets 高度契合。
- 目标是"替代执行后端"，不是重写 GHC：复用 GHC 前端/类型检查/优化，Core 之后接 Coronet。
- HVM2（Rust，并行 Interaction Net evaluator，含 C/CUDA 后端）与 HVM3（Haskell+C，Interaction Calculus runtime，编译到原生 C，性能更好但无 GPU 后端）**IR 不兼容，各写一个 lowering**。
- 自动并行只对有足够独立 rewrite 的程序有效，不消除算法串行依赖——基准测试要如实验证。

## 2. 已定决策（不要推翻，除非有压倒性理由）

| 决策 | 结论 | 理由 |
|---|---|---|
| 项目名 | `coronet` | Core → interaction nets |
| 实现语言 | **MoonBit**（`moon 0.1.20261104` 已装） | OCaml/Haskell 本机没有；MoonBit 工具链现成、性能好 |
| Phase 1 输入 | **CoreLite**：严格对齐 GHC Core `-ddump-simpl` 文本输出的子集 | 测试用手写 `.core` 文件；将来可直连 ghc dump，不用重做前端 |
| Phase 1 范围 | Int/Bool、ADT、case、高阶函数、递归、let/letrec；**不做** IO/ST/FFI/coercion/tick/join point | 用户定的三阶段计划第一阶段 |
| 双后端 | HVM2 文本格式 + HVM3 Interaction Calculus，各写 lowering | 两者 IR 不同，不假设兼容 |
| 测试策略 | MoonBit 写 call-by-need 参考解释器（oracle）+ golden tests：同一批 .core 在 oracle / HVM2 / HVM3 三方结果一致 | 不依赖 GHC 也能闭环验证语义正确性 |
| 阶段计划 | P1 纯函数子集双后端跑通 → P2 自动并行验证+基准（fib / parallel map / tree reduction / merge sort / N-Queens；指标：单线程时间、多核 speedup、内存、归约数）→ P3 完整惰性语义 + GHC 生态对接 | 用户三阶段计划 |

## 3. 目录状态（~/mycode/coronet/）

```
coronet/
├── HANDOFF.md          ← 本文
├── DESIGN.md           ← 工人1（DeepSeek）的设计文档，收尾中；含 CoreLite 文法、
│                          Core→IC 映射表、惰性策略、双后端差异、测试计划
├── docs/
│   └── semantics-memo.md ← 顾问（MiMo 2.6 Pro）的语义映射备忘录，收尾中；含
│                            共享/WHNF/letrec 编码方案与 5 个手工翻译示例
├── vendor/
│   ├── HVM2/           ← shallow clone（HEAD 6542760…，2026-11-15）
│   └── HVM3/           ← shallow clone（HEAD fba2e9c…，2026-11-15）
└── .build-logs/        ← 工人1 的构建探测日志（可删）
```

注：两份收尾文档可能在交接时刻刚落盘或仍在写；若 DESIGN.md / semantics-memo.md 缺失或标注"未完成"，以其 HANDOFF NOTES 一节和本文第 5/6 节为准。

## 4. 环境事实（实测，2026-11-15）

- **MoonBit**：`moon 0.1.20261104` ✅（唯一可用的三候选语言工具链）
- **Rust**：cargo/rustc 1.98 ✅（可构建 HVM2）
- **GHC/OCaml**：❌ 未装。HVM3 是 Haskell 实现，构建它需要 GHC：`brew install ghc`（Homebrew 7.0.12 在）或 ghcup。交接时可能正在安装，`command -v ghc` 先查。
- Python 3.15、Node 26、git 2.54 ✅；GitHub 网络可达 ✅
- HVM2 构建：`cargo build --release`；HVM3 构建方式见其 repo（README/Makefile/.cabal）。
- /tmp 下有前序探测残留（`coronet-probe/`、`hvmx/`、`hvm3_build.log`），可清理。

## 5. 已完成

1. 需求分析与三阶段路线确定。
2. 环境侦察（工具链、网络、vendor 克隆）。
3. R1 设计轮启动并收尾：DESIGN.md（后端文法考证 + 映射设计）、语义备忘录（惰性共享→IC 的编码方案 + 5 个手工翻译示例，可直接当 golden test 参考答案）。
4. 项目命名、目录、MoonBit 脚手架方案。

## 6. 未完成 / 待办（建议顺序）

1. **读完 DESIGN.md + semantics-memo.md 后拍板**：共享编码方案（REF-thunk vs SUP/DUP vs 显式 thunk 包）、ADT 编码（Scott vs 原生 CON/MAT）——两份文档可能给出不同推荐，需裁决一个写进实现。
2. **R2 实现**（建议拆 4 线并行，文件所有权分开，AST 接口先定死）：
   - `syntax/`：CoreLite parser（AST + 解析）
   - `lower_hvm2/`：Core IR → HVM2 文本
   - `lower_hvm3/`：Core IR → HVM3 Interaction Calculus
   - `ref_interp/` + `tests/`：call-by-need oracle + golden tests
   - `cli/`：`coronet build foo.core --target hvm2|hvm3`
3. **R3 验证**：三方（oracle/HVM2/HVM3）结果一致性；构建 HVM3 并验证其 C 编译模式。
4. **R4 并行基准**：fib、parallel map、tree reduction、merge sort、N-Queens；对照 GHC 与 HVM2 多核/CUDA、HVM3 原生 C。
5. **P3 远期**：完整惰性语义（无穷结构、blackholing 等价物）、GHC `-ddump-simpl` 直连、（可选）Effect Boundary 处理 IO。

## 7. 未决问题（需人拍板）

- CoreLite 文法边界：GHC Core dump 的 coercion/cast/tick 如何处理（擦除？报错？）——DESIGN.md 有清单。
- 共享语义方案的最终选择（见第 6.1 条）。
- HVM3 若构建困难：是否允许 P1 只验证 HVM2、HVM3 后端仅做"文本发射 + 静态对照"。

## 8. 参考资料

- https://github.com/HigherOrderCO/HVM2 （vendor/HVM2/ 有本地克隆）
- https://github.com/HigherOrderCO/HVM3 （vendor/HVM3/ 有本地克隆）
- GHC Core：GHC 用户指南 "Core language" 章节；`-ddump-simpl` 输出格式
- 前序讨论的关键共识：Haskell Core 是最高杠杆入口；HVM2 定位为通用编译后端；自动并行收益依赖程序结构，需实测。
