# 交付记录 — 2026-10-22-aifi-45-authorized-execution（multica 侧）

> 本页只记录交付事实与关联，不含批准或验收结论。Gate 1/2/3 的确认以 `.stdd.yaml` 为准。

## 业务仓提交（先）

| 仓 | commit | 内容 |
|---|---|---|
| multica | `37fba41ed` | 一次性库入口修正（角色标记、nonce、skip 判失败）、真实入口选择并入 `selections.json`、NTF 恢复断言非空、CUSTOM #309/#302/#310 校正与 M30 登记 |
| multica | `26f6c5b0a` | M005 读侧接缝、一次性 DB pin、v2 准入夹具（本次之前的最后一次业务提交） |

## 记录提交（后）

| commit | 内容 |
|---|---|
| 本文件所在记录提交 | 归档本 change + 合并 `specs/{attention-routing,authorized-runner}`（message 带 `business=37fba41ed`）|

## 本轮取得的可执行证据

- 一次性 PostgreSQL（自建 pgvector 容器，tmpfs、仅 127.0.0.1）：`scripts/aifi45-disposable/run-selection.mjs` 整组 **11 个选择 / 207 PASS / 0 FAIL / 0 skip**；容器按 ID 删除、label 回读 0。
- `go build ./...`、`go vet`（governance、daemon、cmd/server、service）退出 0；`stdd validate` 通过。
- C1 三路评审已按分层配置派发（strong / balanced / economy），发现已逐类处置，见 `test-report.md` 第三节。

## 归档入库范围（2026-11-10）

归档目录共 8770 个文件 / 1.9 GB，其中只有机器状态不入库，其余按既有约定原样提交（本 change 已跟踪的 4518 个文件必须在归档后继续被跟踪，否则等于删除历史记录）：

| 排除 | 文件数 | 体积 | 理由 |
|---|---|---|---|
| `validation/**/.local/share/containers/**` | 7 | 1004 MB | 本机 podman WSL 虚拟机磁盘与镜像缓存，机器状态 |
| `validation/**/oci-acquisition-*/**` | 25 | 153 MB | OCI 镜像层，可重新获取 |
| `validation/**/go-cache*/**` | 2703 | 241 MB | Go 构建缓存，可重新生成 |

排除项与当前已跟踪文件零交集（逐路径核对），所以归档不会丢任何已入库内容。入库 6036 个文件 / 487 MB 工作区体积（git 压缩后与既有 4518 个文件的规模同量级）。`*.jsonl`、`*.sql`（含 `original-approval-record.sql`、`schema.sql`）保持既有约定继续跟踪，不在此处单独改变仓库惯例。

## 未纳入本次交付

1. **版本标记**：tag 名称与是否打 tag 待用户确认（deliver Step 6）。
2. **M005 生产者侧**：移交 `BACKLOG-M-RESIDUALS.md` 的 M005 行（待开 change），含 TC-RUN-001/006、M008 真实恢复入口证据、T 侧签名死代码清理。
3. **M006 / M007 / M010**：已在 `BACKLOG-M-RESIDUALS.md` 登记，待触发条件满足后开 change。
4. **M001 / M002 / M009 客户端真实 OS 与跨会话证据**：已接受残余，随 Gate 3 材料。
5. **TC-EVD-008**：2026-11-10 范围裁定 OUT_OF_SCOPE（不是 PASS），由 `2026-10-29-legacy-execution-migration` 在启动条件发生时验收。
6. **code-structure delta**：本 change 从未生成 `code-structure-delta.md`，未执行 `stdd structure merge`（生成器取整个工作树 diff，会把无关在途改动混入），本次如实跳过。
