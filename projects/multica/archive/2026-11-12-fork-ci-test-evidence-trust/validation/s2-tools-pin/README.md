# Slice 2 证据 — 单一 tools pin（TC-CBE-003）

> change：`2026-11-12-fork-ci-test-evidence-trust`｜执行时间：2026-11-12 本地｜Node v24.15.0｜Windows
> 本切片不创建容器、不连接数据库、不读取任何凭据值。

## 产出物

| 文件 | 性质 |
|---|---|
| `.github/aifirst-tools-pin` | 新增，单行 40 位 hex：`e52b8081f159d581bf62f82447c76f818fc52426` |
| `scripts/aifi45-disposable/tools-pin.mjs` | 新增，`read` / `check` 两个子命令 + 导出 `parsePin`、`REQUIRED_FILES` |
| `scripts/aifi45-disposable/tools-pin.test.mjs` | 新增，15 项测试 |
| `.github/workflows/ci.yml` | 上游文件，`transitions-contract-check` 内最小改动，两处标 `# AIFIRST:` |

必需文件清单取自真实消费者，不是臆造路径：

- `skills/shared/crctl/scripts/lib/execution-control-protocol.mjs` ← `server/internal/governance/crosslang_test/interop_test.go:391`
- `skills/shared/crctl/scripts/test/fixtures/control-vectors.json` ← `crosslang_test/shared_vectors_test.go:22`、`execution_control_protocol_test.go:336`
- `skills/shared/crctl/scripts/crctl.mjs` ← `CRCTL_MJS` 消费者（`execution_authorization_test.go:612` 等）

## 命令与结果

| 命令 | 退出码 | tests | pass | fail | skipped | 文件 |
|---|---|---|---|---|---|---|
| `node --test --test-reporter=tap scripts/aifi45-disposable/tools-pin.test.mjs` | 0 | 15 | 15 | 0 | 0 | `tc-cbe-003.tap` |
| `node --test --test-reporter=tap "scripts/aifi45-disposable/*.test.mjs"`（全量回归） | 0 | 75 | 75 | 0 | 0 | `regression-directory.tap` |
| `node scripts/aifi45-disposable/tools-pin.mjs check --pin .github/aifirst-tools-pin --tools ../tools` | 0 | — | — | — | — | `real-tools-check.txt` |
| `generate-transitions.mjs --tools ../tools --check` | 0 | — | — | — | — | `generators-at-pin.txt` |
| `generate-gate-nodes.mjs --tools ../tools --check` | 0 | — | — | — | — | `generators-at-pin.txt` |

生成器输出原文：

```
transitions consistency OK: 54 transitions (tools@e52b808)
four registry snapshots and gate nodes consistent (tools working tree, BASE e52b808)
```

这证实 design.md 的事实断言「单一 pin 推进到 e52b808 不会破坏 transitions 检查」。

## RED

实现前运行 → `ERR_MODULE_NOT_FOUND`（`tools-pin.mjs` 不存在），退出码 1。

## 变异验证：ci.yml 字面 ref 检查不是空检查

把 `ref: ${{ steps.tools-pin.outputs.ref }}` 临时改回字面
`ref: 9e41ad74ce631459bc007a29c3d0cdaaa1e49e75`，重跑：退出码 **1**，
`TC-CBE-003 ci.yml carries no literal tools commit` 变红并给出精确行号
（`mutation-literal-ref.tap`）：

```
AssertionError: literal 40 hex refs must be gone:
[{"line":"          ref: 9e41ad74ce631459bc007a29c3d0cdaaa1e49e75","number":135}]
```

恢复后 15/15 通过，`grep -cE "[0-9a-f]{40}" .github/workflows/ci.yml` = **0**。

该检查按 AGENTS 工程纪律逐行解析：`readFileSync` → `replaceAll("\r\n","\n")` →
`split(/\r?\n/)`；文件为空或解析不出多行即 `throw`（硬失败），不静默当作"无字面 ref"通过。

## 拒绝分支覆盖（check 不是空检查）

- `parsePin` 拒绝：空串、单换行、非 hex、39 位、41 位、大写 hex、两行、尾部空行、
  前导空格/Tab、尾随空格、行尾注释、40 个 `g`。接受：裸 40 hex、`\n` 结尾、`\r\n` 结尾。
- `check` 对三个必需文件**逐个单独缺失**各有一项测试，断言退出非 0 且输出同时含 pin 与该缺失文件全路径。
- 检出目录为空 → 三个文件名全部打印。
- pin 非法时 `check` 先失败，不去看检出目录。
- pin 文件不存在 → `read` 非 0 退出。

## 接线正确性（本地等价验证，非真实 CI）

- `ci.yml` 经 YAML 解析成功，17 个 job；`transitions-contract-check` 步骤顺序为：
  Require credential → Checkout → Setup Node.js → **Read the single tools pin** →
  Checkout tools（`ref: ${{ steps.tools-pin.outputs.ref }}`）→ **Check the tools pin integrity** →
  verify transitions → verify gate nodes。
- 读取步骤 `id: tools-pin` 与 ref 表达式一致。
- 本地模拟该 run 块：`GITHUB_OUTPUT` 得到 `ref=e52b8081f159d581bf62f82447c76f818fc52426`。

## 实现期发现并修复的自身缺陷

`tools-pin.mjs` 初版在模块顶层无条件执行 CLI，被测试 `import` 时即跑 `main()`，
把 `process.exitCode` 置 1 并打印 usage，导致 15 项断言全过但文件级退出码为 1。
已加 main-module 守卫（`import.meta.url === pathToFileURL(resolve(process.argv[1])).href`）。
**这是真实缺陷而非测试写法问题**：任何导入该模块的调用方都会被污染。

## 未满足的前置与未验证项（如实记录，不 skip、不报绿）

1. **pin 目标提交尚未推送。** tools 本地 HEAD = `e52b8081f159d581bf62f82447c76f818fc52426`，
   `origin/main` = `f774ffb30770659cab31dcd72a413d872a78e4da`。U1 = α 要求 pin 指向 e52b808，
   而 pin 必须是 origin 上存在的提交。**推送前真实 CI 的 tools 检出必然失败**，
   因此「CI 的 tools 相关测试」当前状态为**未验证**，不是通过。
   推送 tools 属设计级单独授权，执行前须逐项列出提交与范围；本切片未推送任何内容。
2. **`generate-gate-nodes --check` 读的是 tools 工作树**（其输出自述 "tools working tree"），
   而 tools 工作树有 5 个他人未提交改动（`AGENTS.md`、`CUSTOM.md`、
   `skills/shared/crctl/scripts/lib/merge-effects.mjs`、
   `.../test/golden/crctl-detail/workspace-inspect.json`、`.../test/merge-effects.test.mjs`）
   与未跟踪 `.crctl/`。这些文件都不是 gate-node / registry 合同源，故结论不受影响，
   但严格说该 PASS 不是"纯 committed 修订"的验证。`generate-transitions` 自述 `tools@e52b808`。
   未清理、未混入这些改动。
3. **未执行真实 CI run**（TC-CBE-005 属 manual，依赖推送）。
4. **未执行 `make test`**（U5 排除）。

## 与 slices.md 的口径澄清（非设计偏离）

`slices.md` 的 S2 写「`ci.yml` 两处 ref 改为读 pin」。核实后：`ci.yml` 当前**只有 1 处**
tools 检出（`transitions-contract-check`）。design.md 决策 3 所说的第二个消费者
`backend-tests` 的 tools 检出**尚不存在**，由 Slice 13 新建并读同一个 pin。
因此 S2 改 1 处 ref + 新增 1 步完整性检查；「两个消费者共用一个 pin」在 S13 完成后才成立。
SC-CBE-003 的「ci.yml 中不再出现 tools 的字面 commit」已在本切片达成并可验证。