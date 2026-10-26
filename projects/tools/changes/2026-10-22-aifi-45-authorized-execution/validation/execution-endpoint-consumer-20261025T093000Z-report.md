# T 侧消费：`crctl` 认 per-run 端点（增量 4）

## 背景

前一片把 `MULTICA_EXECUTION_BINDING_ENDPOINT` 注入了 run 环境，但 `crctl` **不认识**它——端点在产品里没有消费者，等于接好线没通电。这一片补上消费者。

## 改动（tools 仓）

**`skills/shared/crctl/scripts/lib/execution-binding.mjs`**

- 新增 `fetchExecutionBindingOverHTTP(endpoint, challenge, options)`：
  - 只接受 `http://127.0.0.1…`（拒绝 `https`、非回环主机名、非 URL）；
  - POST body **恰好一个键** `{"challenge": …}`；
  - 超时默认 15s（与 stdio 路径一致），失败 → `EXECUTION_BINDING_UNAVAILABLE`；
  - 非 2xx → `EXECUTION_BINDING_UNAVAILABLE`；空体或 >128KiB → `EXECUTION_BINDING_INVALID`；
  - **故意不拆 `{"envelope":…}` 外壳**：外壳必须一路走到下游 schema 检查然后失败，而不是被"好心"剥开。
- `requestExecutionBinding` 按环境变量选传输：有 `MULTICA_EXECUTION_BINDING_ENDPOINT` 走 HTTP，否则走原 stdio（**stdin TTY 守卫只在 stdio 分支生效**）。验签、字段集、challenge 绑定、`EXECUTION_CONSUMPTION_REQUIRED` 收尾**全部不变**。

**`skills/shared/crctl/scripts/crctl.mjs`**

- `authorization-bind` 的入口门从"必须 `--binding-stdio`"改为"`--binding-stdio` **或** 环境里有端点"。拒绝仍然是拒绝：两条都没有时照旧 `EXECUTION_BINDING_REQUIRED`。

## 证据

新测试 `skills/shared/crctl/scripts/test/execution-binding-endpoint.test.mjs`（真实 `node:http` 本机服务，无 mock）：

| 用例 | 断言 |
|---|---|
| `posts only the challenge and accepts the bare proof document` | body 键集合 == `['challenge']`；接受裸证明文档 |
| `does not unwrap a wrapped response` | 外壳原样返回、`schema` 不是 `execution-binding/v1` |
| `a refused response is never a proof` | 409 → `EXECUTION_BINDING_UNAVAILABLE`，不返回任何 proof |
| `only a loopback http endpoint is accepted` | `https`、`10.0.0.7`、`localhost`、非 URL 全拒 |
| `a stalled endpoint times out instead of hanging the run` | 不响应 → 超时后报错，不挂死 |
| `a timed-out attempt is retried with the same challenge` | 第一次不响应 → **第二次携带完全相同的 challenge 字节**并成功 |
| `a 5xx is retried but a 4xx is not` | 503 → 重试一次；403 → **只发一次**（4xx 是终态） |
| `an oversized body is refused` | >128KiB → `EXECUTION_BINDING_INVALID` |

- **8/8 PASS**；
- **RED 探针 A**（body 多带 `operation`、响应里剥外壳）→ **4 PASS / 2 FAIL**；
- **RED 探针 B**（重试时重新生成 nonce）→ **6 PASS / 2 FAIL**（“同 challenge 重试”被判死）；
- 既有 `execution-authorization.test.mjs` **160/160 PASS**。

## 一个与本片无关的既有失败（如实记录）

全量 `node --test skills/shared/crctl/scripts/test/*.test.mjs`：**1058 tests / 1056 pass / 1 fail / 1 skip**，失败是
`crctl.test.mjs → CR-2026-030 TASK-01：owner-set 恢复失败 → OWNER_COMMIT_ROLLBACK_FAILED（AC-15）`。

已做隔离验证：

1. 该用例正文**不含**任何 `binding-stdio` / `authorization-bind` / `MULTICA_EXECUTION_BINDING_ENDPOINT`；
2. 把本片两个文件 `git stash -u` 后单跑该文件 → **仍然失败**（298/299）；
3. `git worktree add /tmp/tools-head HEAD`（干净 HEAD）→ **299/299 通过**。

⇒ 失败来自工作区**其它未提交改动**或环境，**不是本片**。但它必须在 C1–C7 全量门禁前解决，已作为待办列出，不得当作通过。

## 边界（不得外推）

- 端点**仍未认证调用方**（URL 是 bearer 能力，同 UID 可读环境）——本片只让 T 会用，不构成隔离。
- 消费/准入**仍关闭**：`authorization-bind` 验完证明后仍以 `EXECUTION_CONSUMPTION_REQUIRED` 退出，不写 receipt、不改 CR 事实。
- 不签 activation、隔离执行域、全局 C1。
