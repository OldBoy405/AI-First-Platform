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

### 3.1 toolsDir 解析（2026-10-20 更正）

**原记录有误，此处更正**：曾记「默认 toolsDir 解析到 multica 仓内的空壳 `tools/`」，系层数算错。实际脚本位于
`multica/server/internal/governance/gen`，默认
`path.resolve(__dirname,'..','..','..','..','..','tools')` 上跳 5 层后**正确指向 sibling `AI/tools`**，不是 `multica/tools`。

- 默认路径正确，**不强制** `--tools`；显式 `--tools` 仍可用（本次核对沿用它固定 revision）。
- **不**额外修改路径逻辑，**不**新增空壳 fail-fast：目标文件缺失时，既有读取路径本身就会失败。
- 原「不显式传 `--tools` 会读到空目录、结论不可信」的结论随之**撤销**。

本次实测（`--check`）仍报 exit 1，但**根因不是合同漂移，也不是路径**，而是 provenance 注释里的 BASE SHA 已随 tools HEAD 前进（见 §3.2）。当时使用显式 `--tools` 仅用于明确来源目录：

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

**结论**：C2 的「内容同源」成立（digest 相同）。BASE 行不同只是 provenance 记录差异，**不是内容漂移**；`--check` 对 BASE 敏感的行为已按 §7 归一化处理。

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
| C2 multica 解析可重建 | ✅ 内容同源通过；provenance BASE 差异按 §7 归一化，不属内容漂移 |
| C3 不把 checkout 当线上生效 | ✅ 由 TC-T-PROMPT-002 固化 |

**T04b 通过。** 两项跟进：**项 1 已完成；项 2 已撤销（原结论有误）**：

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
2. ~~`generate-gate-nodes.mjs` 默认 `toolsDir` 解析到 multica 仓内的**空壳 `tools/`**，不显式传 `--tools` 时会读到空目录而结论不可信；建议后续对空壳做 fail-fast。~~ → **撤销（原结论有误）**：默认路径上跳 5 层正确指向 sibling `AI/tools`，无需强制 `--tools`，不额外改路径逻辑、不加 fail-fast；文件缺失时既有读取会失败。详见 §3.1 更正。

### 6.1 关于「`--check` 与 provenance」的更正

原记「tools 任何提交都必须 bump multica pin，否则 CI 红」为**过度断言**，撤销。核实后：

- multica CI 使用**固定 tools pin**（`ci.yml` 的 `ref:`），**不因** tools 仓出现新提交而自动变红；pin 只在合同升级时前移。
- 真实误报场景：本地用**内容相同但 Git HEAD 不同**的 tools checkout 跑 `--check`，生成物 provenance 的 BASE 行不同，仅 BASE SHA 差异即导致失败。这不是内容漂移，更不是 CI 必然变红。
- 历史事实保留：`9d0a6a7`（旧 pin）确实无法复现新 registry 的**内容漂移**（raw pipeline fields 随 `2bfa3ad` 变化，exit=2）；`5a913605b` 的 pin 修复（前移至 `9e41ad7` 并再生生成物）仍为真。
- 旁证：`generate-transitions.mjs --check` 本就不比对 provenance。
- 原建议「另立 CR 解耦内容一致性与 provenance」**撤销**：不另开 CR/STDD，改由下述最小修补处理（§7）。

---

## 7. 更正的落地方式（最小代码修补）

本次按普通维护完成生成器、回归测试及历史记录纠错，**未**新增 flag/config/模块，**未**另开 CR/STDD：

- `--check` 比较前归一化行尾（CRLF/LF）。
- 仅忽略来源注释中的 BASE：40 位 SHA 或 `unavailable`。
- **保留**来源行的 pipeline digest 与全部生成正文的比较——内容漂移仍会报红。
- 生成（非 `--check`）时仍记录真实 BASE，provenance 不丢失。
- multica CI 的 tools pin 保持不变，仅在合同升级时前移。

验证：新增 BASE-only 回归在修补前真实失败；修补后 `TestMDispatch005Generator` 与 `TestMDispatch005` 共 38 RUN / 38 PASS / 0 FAIL / 0 SKIP，native exit 0。默认路径与显式 `--tools` 的 gate `--check`、默认路径的 transitions `--check` 均 exit 0；CI pin 和生成物未改。证据位于 OS Temp 的 `aifi45-generator-base-check/`。

本项属普通维护与历史记录纠错，不构成 STDD 切片。
