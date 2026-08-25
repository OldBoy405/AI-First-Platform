# Multica Fork 二开代码审查与最小整改建议

> 日期：2026-08-21  
> 文档性质：代码审查建议，不构成实施授权  
> 目标仓库：`../multica`（AI-First fork）  
> 上游基线：`multica-ai/multica` `upstream/main@8c9b7503a12ded3f28553da48b9851621f10be6b`  
> Fork 基线：`93aa7c5bdd1920625fae16918cb3d4f60dfa9f4f`  
> Tools 基线：`../tools@c4b10d505d737c423c81ee9a4f3dd6980647f46a`  
> 范围依据：`../multica/CUSTOM.md`

## 1. 结论

本次只审查和建议修改 **fork 二开增量**，不修改 upstream 原有代码。二开边界同时满足以下证据：

1. 已登记在 `../multica/CUSTOM.md`；
2. 是 fork 新增文件、明确的 `AIFIRST` 挂钩，或能由 upstream 差异证明属于 fork 增量。

本轮结论分成两类，不能混写：

- **已经解决的基础设施**：`crctl` 已提供 Git/workspace 事务、journal、锁、原子写、恢复和仓库解析；Multica 已有 controlled-shell 准入检查。不得在 Multica 再造事务层、恢复协议、repository resolver 或命令执行框架。
- **本次可复用能力的最小整改**：只保留两项机械清理——删除未使用的 `Guard.Run`，以及用标准库 `sort.Strings` 替换手写排序。

CR-ID、Resolver 和 GitHub URL 归一化存在差异或重复，但当前证据不足以支持新增公共抽象；它们只作为已知差异保留，不进入本次整改。

## 2. 审查边界

### 2.1 纳入整改候选的二开文件

| 文件 | 二开证据 | 本轮结论 |
|---|---|---|
| `server/pkg/gitguard/gitguard.go` | `CUSTOM.md` 代码改动 #8；`server/pkg/gitguard/` 为 fork 新包；upstream 基线无该路径 | 允许清理 fork 自有死代码 |
| `server/internal/drift/binding.go` | `CUSTOM.md` 代码改动 #50；`server/internal/drift/` 为 fork 新包；upstream 基线无该文件 | 允许用标准库替换 fork 自有排序代码 |

核验命令：

```bash
git -C ../multica ls-tree -r --name-only upstream/main -- \
  server/pkg/gitguard server/internal/drift/binding.go
```

当前输出为空，证明上述路径不在所核验的 upstream 基线中。

### 2.2 只读参考，不作为整改对象

为确认调用关系和行为边界，可以只读核对 scheduler、daemon、handler、governance、skill 及 tools 代码；不得因此修改其中的 upstream 原有逻辑。

若未来必须调整一个含 `AIFIRST` 挂钩的 upstream 文件，只允许修改 `CUSTOM.md` 登记的二开增量，周围 upstream 逻辑保持不动。该类修改必须另立 CR，不属于本文授权范围。

### 2.3 明确不做

- 不修改 `../multica`、`../tools` 或 upstream 代码；本文只整理整改建议。
- 不新增事务框架、journal、锁、恢复器、factory、provider 或通用 repository 包。
- 不因“只有一个实现”就删除测试或跨包边界所需的接口。
- 不以减少代码行数作为验收目标。
- 不把没有调用证据、行为证据或契约依据的猜测列为整改项。

## 3. 已经解决的基础设施

这些能力已经存在。后续实施应直接复用，不得在 Multica 复制一套。

| 能力 | 现有事实源 | 本次复用结论 |
|---|---|---|
| Git/workspace 事务边界 | `../tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs:1-5` | 事务与 authority 判定只存在于该模块和 `durable-tx.mjs` |
| journal、锁、原子写、恢复 | `../tools/skills/shared/crctl/scripts/lib/durable-tx.mjs` | register/checkpoint/merge/writeback/archive 已有可恢复基础设施 |
| repository graph 解析 | `workspace-transactions.mjs#resolveRepositories` | 直接读取 `dir-graph.yaml#repositories`，Multica 不新增通用 resolver |
| controlled-shell 准入 | `../multica/server/pkg/gitguard/gitguard.go:129-156` 的 `Guard.Check` | 保留准入判断；删除便利执行层后不补同形 wrapper |
| 字符串排序 | Go 标准库 `sort.Strings` | 不保留手写排序，不新增 helper |
| JSON 类型归一化 | `encoding/json`；`internal/drift/finding.go#DecodeResultV1` | 现有 marshal/unmarshal 同时承担类型归一化和结构校验，保持不动 |
| YAML 数值归一化 | `yaml.v3`、`strconv`、`encoding/json`；`internal/skill/frontmatter.go` | `int64`/`uint64` 分支实际可达，保持不动 |

### 3.1 禁止再造事务框架

`workspace-transactions.mjs` 已明确声明：Git/workspace 事务与 authority 判定只存在于该模块和 `durable-tx.mjs`。后续 Multica 二开代码只消费结果或跨仓契约，不承担以下职责：

- 重新实现 workspace journal；
- 重新实现目录锁或崩溃恢复；
- 重新解析 CR worktree 与 repository graph；
- 在 `Guard.Run` 之外补一个新的 `Check + exec.Command` 包装器。

删除无用便利函数不等于缺少基础设施；调用方现有的 `Guard.Check` 已覆盖准入职责。

## 4. 本次最小整改

### R-01 删除未使用的 `Guard.Run`

**位置**：`../multica/server/pkg/gitguard/gitguard.go:158-164`  
**归属**：fork 新包，`CUSTOM.md` #8  
**优先级**：P0  
**状态**：最小整改候选；实施前确认无仓外消费者

#### 问题证据

仓内搜索只命中方法定义，没有生产或测试调用者：

```bash
rg -n --glob '*.go' \
  'gitguard\.[A-Za-z0-9_]*Run|guard\.Run|func \(g \*Guard\) Run' \
  ../multica/server
```

`Guard.Run` 只是依次执行 `Guard.Check` 和 `exec.Command`。实际调用方已直接使用 `Guard.Check` 后创建命令。

#### 最小动作

1. 删除 `Guard.Run`；
2. 删除仅由该方法使用的 `os/exec` import；
3. 运行 `gofmt`；
4. 不新增替代 wrapper。

#### 保持不变

- `Guard.Check`；
- `FromEnv` 的未配置、配置错误和 fail-closed 语义；
- PATH shim、Claude hooks、spool audit 及 `gitguard-exec`；
- upstream 原有代码。

#### 前置条件

`server/pkg/gitguard` 是可导入包，仓内搜索不能证明不存在仓外消费者。实施 CR 应先核对实际部署、其他内部模块或下游仓库是否调用该导出方法；没有消费者时再删除。

#### 验证

```bash
cd ../multica/server

go test ./pkg/gitguard ./internal/daemon/execenv -count=1
rg -n 'Guard\) Run|guard\.Run|gitguard\.Run' .
```

完成标准：定向测试通过，搜索不再命中 `Guard.Run`，`CUSTOM.md` #8 描述的 controlled-shell 能力保持完整。

### R-02 用 `sort.Strings` 替换手写插入排序

**位置**：`../multica/server/internal/drift/binding.go:117-122`  
**归属**：fork 新包，`CUSTOM.md` #50  
**优先级**：P0  
**状态**：最小整改候选

#### 问题证据

当前代码只需要按字符串升序稳定输出 declaration ID，却自行实现插入排序。同一 fork 功能内的 `overview.go` 已使用 `sort.Strings`。

#### 最小动作

```go
sort.Strings(declIDs)
```

增加或复用 `sort` import，删除原循环；不新增排序 helper、策略接口或配置项。

#### 保持不变

- declaration ID 的升序语义；
- binding、GitHub access 和错误处理逻辑；
- scheduler 消费边界；
- upstream 原有代码。

#### 验证

```bash
cd ../multica/server

gofmt -w internal/drift/binding.go
go test ./internal/drift -count=1
```

完成标准：`TestResolveBindingsHappyPathWithSSHCanonicalization` 等现有测试继续通过，输出顺序不变。

## 5. 已知差异：本次不整改

### O-01 CR-ID 格式并未形成单一跨仓口径

当前事实不是“tools 全部严格三位”：

- `workspace-transactions.mjs` 的 `CR_DIR_RE` 接受 `CR-YYYY-NNN...`（三位以上）；
- register origin 等入口仍要求严格三位；
- Multica 的 crsync、runner、pipeline task、handler 和 commit event 入口也存在严格三位与三位以上并存。

这些入口服务于注册、worktree 发现、pipeline context 和 commit subject 等不同边界。当前不做以下事项：

- 不创建共享 Go package；
- 不创建跨语言正则生成器；
- 不把所有入口机械替换为同一个 pattern；
- 不由 Multica 单方面收紧或放宽 tools 契约。

只有正式跨仓契约明确编号上限，或出现可复现的入口判定缺陷时，才另立 CR 做局部对齐和表驱动测试。

### O-02 保留 `RepositoryBindingResolver`

`RepositoryBindingResolver` 虽然目前只有一个实现，但 scheduler 正通过该接口消费 drift 能力。把未导出的 `resolver` 改成导出具体类型会扩大 API 面，没有行为收益。

当前结论：保持现状，不导出 `Resolver`，不新增 factory/provider，也不搬移接口。只有出现真实测试替换困难或编译维护问题时再评估。

### O-03 暂不合并 GitHub URL parser

`binding.go`、`overview.go` 和 `jobs_commit_prefix.go` 存在同类 canonicalization，但当前失败语义不同：

- binding 对非 GitHub provider 返回显式错误；
- overview/scheduler 对未知 URL 有各自的“未配置/不可用”处理；
- 空白、未知 provider 和非法路径的处理并不完全一致。

因此合并不是纯机械去重。当前不新建公共 parser 包。只有发生真实缺陷或必须新增第四个调用点时，才优先复用 drift 已有 parser，并由调用方保持原失败语义。

## 6. 保持现状

| 项目 | 结论 | 原因 |
|---|---|---|
| `DecodeResultV1` JSON 往返 | 保留 | 承担 map 到类型结构的归一化和 shape validation；无性能证据 |
| `coerceFrontmatterValue` 的 `int64/uint64` | 保留 | `yaml.v3` 可产生这些类型 |
| `AccessResolver` 等窄接口 | 保留 | 位于外部 client、数据库或测试 fake 边界 |
| `ParseSkillFrontmatter` | 保留 | 已是复用 `ParseSkillMetadata` 的薄兼容入口 |
| `ProtectedPathPatterns` | 保留 | 是 tools controlled-shell 规则的跨仓 pin 契约 |
| 前端二开文件 | 本轮不处理 | 未发现可由调用证据证明的独立冗余项 |
| upstream 原有代码 | 不处理 | 明确不在本次二开整改范围 |

## 7. 实施顺序与变更边界

本文不直接授权代码修改。若后续创建实施 CR，只按以下顺序执行：

1. 单独实施 R-01，确认仓外消费者后删除死代码；
2. 单独实施 R-02，使用标准库替换手写排序；
3. 每项完成后立即运行其最小定向测试；
4. 只修改对应 fork 新文件及必要的 `CUSTOM.md` 台账，不顺手整理邻近代码；
5. Git diff 若出现 upstream 原有文件或未登记挂钩，立即停止并缩回边界。

建议的差异检查：

```bash
git -C ../multica status --short
git -C ../multica diff --name-only
git -C ../multica diff --cached --name-only
git -C ../multica diff -- server/pkg/gitguard/gitguard.go \
  server/internal/drift/binding.go CUSTOM.md
```

## 8. 最终清单

| 编号 | 项目 | 当前决策 | 是否进入本次最小整改 |
|---|---|---|---|
| R-01 | 删除 `Guard.Run` | 确认无仓外消费者后实施 | 是 |
| R-02 | 插入排序改为 `sort.Strings` | 直接复用标准库 | 是 |
| O-01 | 统一 CR-ID 正则 | 保留差异，等待正式契约或真实缺陷 | 否 |
| O-02 | 收缩 `RepositoryBindingResolver` | 不做 | 否 |
| O-03 | 合并 GitHub URL parser | 保留差异，等待真实复用需求 | 否 |
| K-01 | 优化 `DecodeResultV1` | 无性能证据，保持现状 | 否 |
| K-02 | 删除 frontmatter 大整数分支 | 事实不成立，保持现状 | 否 |
| K-03 | 删除窄接口、兼容入口或跨仓 pin | 保持现状 | 否 |

本轮最小且可靠的结论是：**复用既有基础设施，只清理 fork 自有死代码和标准库可替代实现；不修改 upstream 原有代码，不新增公共抽象，不再造事务框架。**
