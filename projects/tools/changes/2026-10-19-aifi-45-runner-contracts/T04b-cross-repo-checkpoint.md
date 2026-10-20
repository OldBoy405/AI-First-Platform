# T04b 跨仓同源核对检查点（S4.3）

**change**：`2026-10-19-aifi-45-runner-contracts`（tools 侧）
**切片**：T04b（任务 4.3）——与 multica 编译/解析同源核对，记录检查点
**核对时间**：2026-10-20
**核对人**：Main（executor）

---

## 1. 核对范围与判据

任务 4.3 原文：「与 multica 编译/解析同源核对，记录检查点；**禁止半套启用、把 checkout 更新当线上已生效**。」

据此设三项判据：

| # | 判据 | 方法 |
|---|---|---|
| C1 | tools 侧四阶段 canonical 合同与 multica 编译产物 digest 一致 | `emit-registry.mjs` 逐 pipeline 导出 digest，与 multica `*_registry_gen.go` 内嵌 digest 比对 |
| C2 | multica 侧解析（gate nodes / registry 快照）可 off tools 现树重建 | `generate-gate-nodes.mjs --check` |
| C3 | 不把 checkout 更新当线上已生效 | 核对 `agents/_index.yml` 的「已合并 ≠ 已部署」声明与部署校验口（由 TC-T-PROMPT-002 固化） |

---

## 2. C1：四阶段 canonical digest 逐项比对

命令（cwd = tools 仓）：

```bash
cd pipeline-templates
for p in requirement-authoring architecture-design code-implementation feature-writeback; do
  node emit-registry.mjs --pipeline $p
done
```

| pipeline | tools 现树导出 digest | multica pin digest | 结果 |
|---|---|---|---|
| requirement-authoring | `f839d28c30ce2dc0eec709589f742abac1f45db96771d80a3ef3ef66a45ea32c` | `f839d28c…a45ea32c` | ✅ 一致 |
| architecture-design | `11970fe3aec6013ff88117eda212617fec4b395e45c52057d157fd8112f2aeb5` | `11970fe3…12f2aeb5` | ✅ 一致 |
| code-implementation | `ee6461ff376646dba36f64d57dfd4482c1e6f6532e049ce6547350b1c7175a88` | `ee6461ff…c7175a88` | ✅ 一致 |
| feature-writeback | `6a63a222146eb018564cd0487e8b1ab5352f832fd3d972f6c065ff7010c01108` | `6a63a222…f0c01108` | ✅ 一致 |

**结论**：四阶段编译合同内容**零漂移**。

> 注：digest 是 canonical 规范化后的 registry body 摘要，**不是** pipeline-templates 原始文件字节的 sha256。直接对 `*.pipeline.json` 求 sha256 会得到不同值（已实测：`574e0fee…` / `9208a3f7…` / `304ec236…` / `11fc7f0e…`），那是预期的，不是漂移。

---

## 3. C2：multica 侧解析重建核对

### 3.1 实测发现的运行陷阱（必须记录）

```bash
cd multica
node server/internal/governance/gen/generate-gate-nodes.mjs --check
# → exit 1: requirement_registry_gen.go differs ...
```

**根因不是合同漂移**，而是两件事叠加：

1. **默认 toolsDir 解析到 multica 仓内的空壳 `tools/`**。脚本默认值为
   `path.resolve(__dirname, '..','..','..','..','..','tools')`，即
   `multica/tools/`——该目录是早前 Windows 文件锁导致删不掉的残留（已 `.gitignore`，AGENTS.md 有记载），**当前为空**。
   不显式传 `--tools` 时脚本读到的是空目录，结论不可信。
2. **provenance 注释里的 BASE SHA 已随 tools HEAD 前进**。

正确调用必须显式指向 sibling tools 仓：

```bash
node server/internal/governance/gen/generate-gate-nodes.mjs --check \
  --tools "C:/Users/GOBAO/Downloads/AI/tools"
```

### 3.2 显式 --tools 后的 drift 性质

仍报 exit 1。重新生成并与提交版逐行比对（CRLF 归一后 diff），**唯一差异是第 4 行 provenance 注释**：

```diff
- // Source: tools working tree (BASE 2bfa3ad04c523a2ec065b9b6cffa93fb859ca6f4); requirement-authoring sha256:f839d28c…a45ea32c
+ // Source: tools working tree (BASE 1fa6059ad169be8289dcd4305aec3f413a1d1907); requirement-authoring sha256:f839d28c…a45ea32c
```

- digest 完全相同 → **编译合同内容零漂移**。
- 差异仅在 BASE 指针：tools HEAD 已从 `2bfa3ad`（AIFI-45 T01–T03 冻结）前进到 `1fa6059`（R5 lint 精度修复）。
- 已核实 `1fa6059` 只改 `lint-prompts.mjs` 与其测试，**未触碰** `pipeline-templates/`、`agents/`、`skills/`：
  ```bash
  git diff --name-only 2bfa3ad 1fa6059 -- pipeline-templates/ agents/ skills/
  # → 仅 lint-prompts.mjs 与 lint-prompts.test.mjs
  ```

**结论**：C2 的「内容同源」成立；BASE 指针对齐属**既定延期项**（tools CI pin 在提交后对齐），不是本次引入的漂移。

### 3.3 核对过程的副作用与还原

为取得 diff，曾在 multica 仓执行过一次**非 --check 的重新生成**，改动了 4 个 `*_gen.go` 的 provenance 行。已全部还原：

```bash
git checkout -- server/internal/governance/{code,gate_nodes,writeback}_registry_gen.go
cp /tmp/rrg.bak server/internal/governance/requirement_registry_gen.go
git status --porcelain   # → 空
```

multica 仓当前干净，HEAD 仍为 `0d6b4e9f9`。

---

## 4. C3：不把 checkout 更新当线上已生效

由 `TC-T-PROMPT-002`（`contract-scan.test.mjs`）固化为回归断言：

- `agents/_index.yml` 必须声明本目录是**唯一编辑源**；
- 必须保留「**已合并 ≠ 已部署**」校验口（`check-deployed.mjs` 逐字节校验）；
- 必须区分「源文件」与「平台部署产物」，平台侧不手工编辑；
- 索引 ≡ 目录枚举（无孤儿 `.md`），五个 Runner 责任 Agent 必须全部 `active` 登记。

---

## 5. 半套启用风险评估

任务明确「禁止半套启用」。当前状态评估：

| 侧 | 状态 | 是否半套 |
|---|---|---|
| multica（M00–M53） | 四阶段 Runner、ack 纯送达、周期恢复、派发全部落码并验收 | 完整 |
| tools（S0–S3 + T04） | 合同冻结、lint、T04 去接力与 approve 边界已落码 | 完整 |

两侧对侧改动（tools 去 Agent 评论接力 ↔ multica ack 纯送达 + Runner 派发）**均已落码**，不存在「只做一半」的启用面。

**未执行项（明确不在本切片范围）**：
- 真实 CR 验证（由用户单独执行）；
- 生产库旧续接存量处置（按 `ACK-006-legacy-continuation-drill.md` 演练文档执行）；
- 部署（由用户自行完成）。

---

## 6. 检查点结论

| 判据 | 结果 |
|---|---|
| C1 四阶段 digest 一致 | ✅ 通过（4/4） |
| C2 multica 解析可重建 | ✅ 内容同源通过；BASE 指针对齐为既定延期项 |
| C3 不把 checkout 当线上生效 | ✅ 由 TC-T-PROMPT-002 固化 |

**T04b 通过。** 遗留两项跟进——**项 1 已于本次完成，项 2 仍开放**：

1. ~~tools 提交后对齐 multica 四个 `*_gen.go` 的 BASE provenance 指针~~ → **已完成**。
   - tools 提交 `9e41ad7`（T04a/T04b/T04c + T05）；multica 提交 `5a913605b`。
   - `ci.yml` 的 tools checkout `ref:` 由 `9d0a6a7` 前移至 `9e41ad7`；以该 revision 重跑生成器再生 5 份生成物（`gate_nodes_gen` / `requirement_registry_gen` / `code_registry_gen` / `writeback_registry_gen` / `transitions_gen`）。
   - 四份 body digest 不变（`f839d28c`/`11970fe3`/`ee6461ff`/`6a63a222`）——即编译合同内容零漂移，仅 provenance 行的 BASE 更新。
   - 验证（含用 `ci.yml` 真实 ref 检出后模拟 CI）：
     ```text
     generate-transitions.mjs --tools <pin> --check  → exit 0
     generate-gate-nodes.mjs  --tools <pin> --check  → exit 0
     go build ./...                                  → exit 0
     ```
   - 已按 AGENTS.md #10 在 `CUSTOM.md` 登记为 **#153**（M3 节头由「7 行」改为「8 行」）。
2. `generate-gate-nodes.mjs` 默认 `toolsDir` 解析到 multica 仓内的**空壳 `tools/`**，不显式传 `--tools` 时会读到空目录而结论不可信。**仍开放**：建议后续对空壳做 fail-fast。

### 6.1 本次核对附带发现的 CI 设计摩擦（建议另立 CR）

`--check` 把 provenance SHA 纳入**整文件比对**，因此**tools 任何提交都必须同步 bump multica pin 并重新生成**，否则 CI 红。这把「合同内容一致性」与「provenance 记录」耦合在一起。

- 实际影响：tools 的 `1fa6059`（仅改 lint 脚本文本）也足以让 multica CI 红——尽管编译合同一字未变。
- 对照：`generate-transitions.mjs --check` **不**比对 provenance，故在两种 pin 下都绿，反而掩盖了 gate-nodes 侧的失配。两个生成器的口径不一致本身就是风险。
- 建议（需另立 CR，本切片不做）：内容不一致才红，provenance 仅作记录（或单独校验“pin 是否等于 BASE”）。
