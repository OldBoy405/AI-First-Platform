# Backlog 来源与关闭条件（AIFI-45 ADJ-001 / 002 / 003）

> 本文件是**来源登记**，不是需求理解阶段的产出。Gate 1 通过后由 proposal.md 承接。
> 状态：已登记、未开始理解；本文件不构成已批准的范围。

## 为什么是一条 change 而不是三条

三条 ADJ 的共同根因是同一个：**验证者读到的事实在本层没有独立可信来源**。

| ADJ | 表面问题 | 实际缺失 |
|---|---|---|
| 001 | 安装根无法独立证明 workspace/project 归属 | 谁有权声明「这个安装根属于这个 project」 |
| 002 | `source_event_id` / `source_bindings` 未接通 T 侧 | 谁有权声明「这条请求来自这个授权人」 |
| 003 | 验签公钥落在被管进程可写集合内 | 谁有权声明「这个公钥是可信的」 |

拆成三条会得到三套设计、三道 Gate 1/2/3，而它们只能一起成立：任何一条单独做完，
另外两条仍能让「独立验证」变成「验证一个可编辑的 sidecar」。所以按一个主题开一条 change。

## 来源（不可改写的历史）

- 归档 change：`projects/tools/archive/2026-10-22-aifi-45-authorized-execution/`
- `pending-adjustments.yaml` 的 `ADJ-AIFI45-001` / `002` / `003`，字段 `adjudication_20261108`
- 相关设计缺口记录：同 change 的 `authorization-trust-gap.md`、`wire-contract.md`

## 各自的关闭条件（可验证，不是「做完了」）

### ADJ-001 · 安装根归属

**关闭条件**：存在一个**本层不可伪造**的事实，能证明「某个安装根目录属于某个 workspace/project/cr」，
并且该事实的获取路径不依赖被管进程可写的任何文件。

- 反例（当前，必须仍然失败）：把 `bindTaskWorkspace` 环境变量或可编辑 sidecar 当作证明。
- 判据：把该证明文件替换成另一 project 的内容后，准入必须失败。

### ADJ-002 · 来源合同

**关闭条件**：一条结构化人类请求能端到端给出 `source_event_id` / `source_digest` / 每个字段的
`json-pointer` 来源绑定，且 T 侧**独立重新提取并核对**，不信任请求自带的摘录。

- 反例（当前，必须仍然失败）：只用 `issue_source_context`（明确标注为只读历史背景）或
  comment 文本作为授权来源。
- 判据：改造一个字段（例如把 `accepted_rules` 改一个字）而不改签名，T 侧必须拒绝。

### ADJ-003 · 公钥安装面隔离

**关闭条件**：验签公钥位于**被管进程无写权限**的位置，并有真实身份级拒绝的证据（不是同 UID 目录权限、
不是路径 pin）。

- 反例（当前，必须仍然失败）：同 UID 下靠文件模式位声称已隔离。
- 判据：以 agent 身份尝试覆盖公钥必须被内核拒绝（Linux uid 级 / Windows 第二身份级）。
  与归档 change 中 Windows 隔离 leaf 的裁决一致：那是**部署前置条件**，同一套证据可复用。

## 2026-11-09 归档后的状态（补充；不改上方来源与关闭条件）

`2026-11-08-aifi45-trust-anchor-chain` 已归档。**归档不等于三条 ADJ 关闭**：proposal 的三条 success criteria 仍未勾选。

| ADJ | 现状 | 关闭还差 |
|---|---|---|
| 001 安装根归属 | 控制面签发绑定 workspace/project/cr 与实际安装根；替换为另一 project 的证明被拒（TC-TAC-003 族） | 平台侧持有该归属的持久事实（当前由签发请求携带、DB 归属行已核），尚无独立查询面 |
| 002 来源合同 | 平台从原 bytes 生成 `source_event_id`/digest/json-pointer 绑定，T 独立重提取（TC-TAC-001/002） | 真实人类事件入口（当前 fixture 签发）与跨仓 production caller |
| 003 公钥隔离 | Linux uid 1500/1501 三种覆盖全 `Permission denied`（`validation/e2-linux-key-isolation-20261108/`） | Windows 第二身份：部署前置（裁决 C），不在代码范围 |

## 控制写入口的证据边界（2026-11-09 核对；不推翻归档记录）

- `requireControlAdmission` 共 5 个调用点，覆盖 6 个控制写：`advance`(1506)、`repair-admit`/`repair-resume`(1945)、`authorization-bind`(2662)、`register`(6195)、`archive`(7194)。
- daemon 亲启的**控制写**只有 `authorization-bind`（`multica/server/internal/daemon/execution_verifier.go:199,243`）；另有只读 `workspace inspect`（`pipeline_task.go:1104,1144`）。其余五个控制写是 CLI 入口，没有 daemon caller。
- 因此交付记录 §六.3 的“三者缺各自真实 daemon 证据”应读作：这三条**不存在** per-verb daemon 证据，因为 daemon 不启动它们；实际缺口是五个 CLI verb 没有平台级真实正例。六个 verb 都有真实 CLI 端到端（fixture 签名），平台级真实正例只有 `authorization-bind`（`e2-m2-real-loop-20261108b`）。
- 2026-11-09 裁决（D2）：**不补 per-verb 平台级正例**。终态口径为“共享缝正向（authorization-bind 真实平台运行）+ per-verb 拒绝面”。理由：per-verb 正例只重复证明各自的平台合同，那些合同已有独立 TC，补做不降低不确定性。归档记录原文保留。

## 外部归属确认（2026-11-09，D4）

| 项 | owner | 处置 |
|---|---|---|
| `TC-AUTH-007` 历史送达可查询 | 平台（multica） | 条款级终态；本仓不建第二本送达账 |
| `TC-EVD-008` legacy 迁移 | Ray | 占位 change `2026-10-29-legacy-execution-migration`，三触发条件不变 |
| Windows 第二身份 | 部署 | 部署前置；Windows runner 不在支持信封内 |
| `ADJ-M001/M002` | multica | accepted risk，随 Gate3 材料原样携带 |

## 不在本期范围

- 不改归档 change 的任何冻结产物（其 `input_manifest` 已冻结）。
- 不为通过测试引入原生依赖（与归档 change 的裁决一致）。
- 不建第二本送达账（`TC-AUTH-007` 的「可查询」仍归平台）。
