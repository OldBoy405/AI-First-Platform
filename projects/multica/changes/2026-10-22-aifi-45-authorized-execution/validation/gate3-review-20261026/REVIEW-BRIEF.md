# AIFI-45 Gate3 两轴评审简报（非作者）

日期 2026-10-26。评审对象是本文件同目录的 `source-manifest.json` 所列字节。

- 工作区记录根：`C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/{multica,tools}/changes/2026-10-22-aifi-45-authorized-execution/`
- 源码根：`C:/Users/GOBAO/Downloads/AI/tools`（HEAD `9e41ad7`）、`C:/Users/GOBAO/Downloads/AI/multica`（HEAD `f6e90ab8`）
- 源码清单：`source-manifest.json`，sha256 `9b80fec568b995b40a24c58288daf31a04ce6aab5d70faac668543e275dcc02d`，162 个文件（tools 22 / multica 140），逐文件带 `sha256`。

## 硬规则

1. **只读**：不得改任何文件、不跑 DB、不跑部署、不 commit/push。允许读源码与记录、跑只读命令（grep/读文件）。
2. **不得**给出 Gate3 通过、TC 完成、上线许可的结论。你们给的是 finding 列表与轴的结论。
3. finding 必须带：严重度（blocker/major/minor）、`文件:行`、**具体反例**（什么输入/时序会出错）、最小修复建议。
4. 无法核实的写 `INCOMPLETE` 并说明缺什么，不要用推测补齐。
5. 区分**代码事实**与**动态证据**：本轮没有人跑过 DB/端到端，读码结论不得写成"已验证"。
6. 不采信作者自述；不沿用任何历史评审结论（v0.2 计划评审、F4 审核等）作为本次通过依据。

## 代码必须满足的规范（Canonical 记录根）

- multica：`canonical/specs/{agent,code}/authorized-runner.yaml`（SC-RUN-001～010）、`attention-routing.yaml`（SC-NTF-001～007）
- tools：`canonical/specs/{agent,code}/execution-authorization.yaml`（SC-AUTH-001～010）、`evidence-delivery-contract.yaml`（SC-EVD-001～010）、`repair-governance.yaml`（SC-RPR-001～012）

## 作者声称的现状（用来检验诚实性，不是用来采信）

- 台账 **41/49** PRESENT；缺 8 条：RUN-002/003/006/010（正向路径依赖已搁置的可信 T 裁决通道）、RUN-001/007/008（端到端/隔离/legacy 接受面）、RUN-009（仅部分维度）。
- 已知缺口（作者已记录，评审要核这些记录是否准确、是否还有没记的）：
  - EVD-007（组件就绪）与 EVD-008（显式迁移）**无生产调用点**；EVD-009 仅 `merge` 路径已接线，`checkpoint`/`writeback` 按构造复用冻结快照、未接判定函数。
  - NTF `DeliverNotice`/`RecoverPendingNotices`/`BusBroadcaster`/`LoadInboxItem` **无生产调用点**，且缺"通知正文产出方"；见 `ntf-producer-gap-20261026.md`。
  - F7 `relayExecutionBinding` 无生产调用点。
  - RUN-009：run 维度补丁已撤回（会永久吞掉乱序评审）；node/cycle/UUID 无检查、subject 只查非空、全服务无"实际 diff"检查。
  - 原 HOLD 库仍冻结（137 表 / 6228 行 / 82 审批），41 行历史缺失未定位。
- 本轮新增并已动态验证（tools only）：`lib/workspace-transactions.mjs::mergeCr` 的发布 receipt 重放守卫，证据在 `../evd-009-wiring-20261026/`（RED 变异→还原 sha→GREEN→merge 23/23→邻接 69/69）。

## 分轴

- **规格轴**：每条 SC 的 given/when/then 是否在代码里有真实执行点；声称 PRESENT 的是否只是单测自证；有没有"规范要求但完全没实现"的缺项（含 SC 与 CP 对不上的地方）。
- **安全轴**：fail-open 路径、TOCTOU（检查与生效之间）、锁序与死锁、撤销/终态竞态、授权绑定与工作区隔离（SQL 是否带 `workspace_id`）、信任根与密钥边界、bearer 能力面、单执行者 DB 纪律。
- **测试配置轴**：测试是否真的 pin 住声称的行为；skip/父 PASS 掩盖；DB 隔离（nonce 库/独占 role/原库不变）；RED 是否是真业务 RED。
- **文档轴**：台账/记录是否与源码一致；有无把"函数存在"写成"能力可用"；有无把计划评审写成实现验证；计数与引用是否自洽。
