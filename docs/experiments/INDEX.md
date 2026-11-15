# 语义实验素材（中断的顾问轮遗产）

> 2026-11-15，语义映射顾问（MiMo 2.6 Pro）在验证 HVM2/HVM3 编码约定时被收工中断，**备忘录没来得及写**。此目录是它的全部实验原始素材，保留作证据，供接手者反推出结论、补写语义备忘录。

**顾问最后已知进度**（终止前自述）：
> "HVM2 的编码约定已实证确认。现在验证惰性/共享语义（问题 1 的核心）…"

即：HVM2 的 ADT/Scott 编码、模式匹配、数值节点等**已实证**；**惰性与共享语义尚在验证中**。这正对应 e2e 中失败的三个 fixture（06_lazy_stream / 07_nqueens / 08_mergesort）——它们是当前语义边界的最前线。

## 目录内容

| 内容 | 说明 |
|---|---|
| `*.hvm`（约 91 个，文件名带序号后缀的是迭代版本，数字越大越新） | HVM2 编码实证实验：每个文件是一个最小化探针 |
| `hvmx/` | **惰性/共享核心实验**：`laz1.hvm`（`konst 1 loop` 惰性能否不坠入死循环）、`share1.hvm`（DUP 节点过共享是否保持一致）、t1-t6 系列 |
| `coronet-probe/` | 最早的基础探针：dup/id/if/pair/swi 节点行为、C 后端对照（含 `id.c`/`id_c`） |
| `hvm2_paper.txt` | 下载的 HVM2 论文文本（可重取，arXiv） |

## 实验族谱（按文件名前缀）

- `test_add*` `test_sub` `test_mul` `test_lte` `test_cmp` `test_arith_clean*`：数值节点/算术
- `test_fib*`（cond/cond2-4/gen/run/run2）：递归 + 条件（SWI/MAT）编码迭代
- `test_scott*`（clean/fold_ref1-3/generic/int/list/raw/tree/pure/universal）：Scott 编码 ADT 的多种方案对比
- `test_ho*`（clean/clean2-5/closure）：高阶函数/闭包编码迭代
- `test_lazy*` `test_stream*` `test_magic_stream*`（1-5）`test_whnf*` `test_spine` `test_main_force`：**惰性/WHNF/流**——与失败 fixture 直接相关，优先读
- `test_official_map` `test_official_fold*` `test_map_only` `test_map_fold_42`：map/fold 翻译
- `test_swi*` `test_if` `test_dup_def` `test_ref` `test_alias*` `test_triple` `test_unused` `test_name` `test_double` `test_full_tree` `test_tag_map`：节点行为杂项
- `01-08` 编号文件、`gen_*`：与 `tests/samples/hvm2/` 对应的样例副本

## 给接手者的建议

1. 先读 `hvmx/laz1.hvm`、`hvmx/share1.hvm` 和 `test_lazy*/test_whnf*` 系列，对照 `vendor/HVM2` 的归约语义，回答：Core 的 call-by-need 共享（`let x=e in (x,x)` 只算一次）在当前 `src/lower_hvm2` 的编码下是否成立？
2. 用这些实验复现/定位 e2e 三个失败 fixture 的根因（惰性求值顺序？共享被 DUP 复制破坏？无穷/惰性流的 WHNF 提取？）。
3. 结论补写到本目录 `SEMANTICS-MEMO.md`（这是原顾问的未竟交付）。
