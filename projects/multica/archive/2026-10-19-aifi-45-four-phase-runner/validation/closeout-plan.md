# 交付收口清单（DELIVER 阶段，Gate 3 之后）

> 口径：Gate 3 已确认 BUILD。本文件不改写 `tasks.md`，只登记 BUILD 之后追加的补强与验证。
> 记录根：本目录。全部命令在当前 HEAD 上执行。

## 1. 三类残余项

| 类别 | 含义 | 本 change 处置 |
|---|---|---|
| V（只缺验证） | 代码已存在，缺「当前 HEAD 上跑绿」的证据 | 本轮执行，见 §3 |
| C（要改代码/测试） | 断言强度、溯源字段等实质缺陷 | 本轮修复，见 §2 |
| N（不声称） | 无任务可做，只能声明边界 | 见 §4 |

## 2. C 类：本轮修复

### C-4 三条断言强度

| 测试 | 原缺口 | 补法 | 变异 |
|---|---|---|---|
| `TestMKey004` | 未单独注入「写文件失败」 | 新增 `grant_write_failure_fails_closed_then_recovers`：目标路径放非空目录使原子 rename 失败（跨平台，不依赖权限位），断言不 ack、无 `.tmp` 残留，移除阻塞后重试成功 | m94（写失败后仍 ack）→ 2 fail |
| `TestMKey005` | 旧 grant 缺 key 的 `KEY_NOT_FOUND` 交由 crctl 承担，daemon 侧未模拟 | 改为覆盖 daemon 侧真实分支：grant 内 `key_id` 与 server `public_key` 不一致时不得写 grant、不得 ack、不得安装客户端自报 key | m95（删不匹配拒绝）→ 2 fail |
| `TestMKey006` | 未断言完整 dirty 集合 | 改为断言交付前后 `git status --porcelain -uall` 差集：新增恰为 `?? .crctl/keys/<id>.pub`，无删除 | m96（安装 key 时多写 .state）→ 1 fail |

> 关于「旧 grant 缺 `key_id`」：该分支与「`key_id` 不匹配」在实现上重叠（缺值必然不等于 server key），单独为前者造用例无法打红，故按不重复计口径改测不匹配分支，并在变异记录中说明。

### C-5 生成器溯源

- 缺陷：`generate-gate-nodes.mjs` 用 `git rev-parse HEAD` 作 BASE，内容却读工作树；模板有未提交改动时头部谎称来自某干净提交。
- 修复：按 `git status --porcelain -- pipeline-templates/*.pipeline.json` 输出 `BASE <sha>+dirty`；`--check` 的 BASE 归一化正则同步接受 `+dirty`；重新生成 4 个 gen 文件（BASE `9e41ad7` → `de9bf75`）。
- 新增用例 `dirty_templates_are_marked_in_the_base_header`：干净时不出现 `+dirty`，改脏后必须出现。变异 m97（去掉 dirty 标记）→ 2 fail。
- 收窄说明：dirty 探测只针对 `*.pipeline.json`（生成器真正读取的 source），否则夹具自身的 `calls.log` 会把干净树误判为脏。

## 3. V 类：35 个 CP 在当前 HEAD 的复跑

全部经 `scripts/aifi45-db/run.mjs` 在独占 nonce 库上执行；每轮均 `original_unchanged:true`、`owned_resources_cleaned:true`、`skip=0`。

| 包 | CP 数 | 证据前缀 | run/pass/fail/skip |
|---|---|---|---|
| `./internal/daemon` | 17 | `validation/cp-daemon-20261028T031500Z` | 43 / 43 / 0 / 0 |
| `./internal/governance` | 12 | `validation/cp-governance-20261028T032500Z` | 48 / 48 / 0 / 0 |
| `./internal/handler` | 3 | `validation/cp-handler-20261028T033500Z` | 3 / 3 / 0 / 0 |
| `./internal/service` | 2 | `validation/cp-service-20261028T034000Z` | 8 / 8 / 0 / 0 |
| `./pkg/taskfailure` | 1 | 直接 `go test`（该包不接 DB，且不在封装白名单内） | `TestMRecovery006` 全子用例 pass |

合计 35 个 CP 定位符全覆盖。

**范围声明**：本节证明的是「每个 CP 的定位测试在当前 HEAD 上通过」，不是「五个包的完整套件全绿」。完整套件未在本轮执行。

## 4. N 类：不声称

- 恢复时限（`design.md` 要求隔离实测）。
- runtime 实际 Agent UUID 隔离（无对应断言）。
- 五个包的完整套件全绿（未执行）。
- 独立 Linux 主机上的 platform isolation（本 change 的 ADJ-10 仍待外部机器）。

## 5. 证据索引

| 项 | 前缀 |
|---|---|
| C-4 三条补强 | `validation/mkey2-20261028T022500Z`（10/10，skip=0） |
| C-5 生成器 | `validation/gen7-20261028T015500Z`（34/34，skip=0） |
| 变异 m94/m95/m96/m97 | `validation/mut-m94-*`、`mut-m95-*`、`mut-m96d-*`、`mut-m97-*` |
| V 类 CP | 见 §3 表 |
