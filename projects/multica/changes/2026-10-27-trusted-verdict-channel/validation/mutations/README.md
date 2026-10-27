# 变异归档（`validation/mutations/`）

每个变异一对文件：`<name>.patch` + `<name>.sha256`（sha256 针对 patch 字节）。

## 格式与用法

patch 用标准 `git apply` 的 `-p1` 形式（`--- a/<repo 相对路径>` / `+++ b/<repo 相对路径>`），仓库按目标路径判定：

| 路径前缀 | 仓库 |
|---|---|
| `server/…` | `../multica` |
| `skills/shared/crctl/scripts/…` | `../tools` |

```bash
# 复核某个 patch 是否仍能打到当前源码
cd ../multica && git apply --check "<change>/validation/mutations/m89_nonce_conflict_removed.patch"
cd ../tools   && git apply --check "<change>/validation/mutations/n12_strict_from_contract.patch"
```

## 现状（2026-10-27 核对）

| 项 | 数量 |
|---|---|
| patch 总数 | 112 |
| 可打到当前源码（`git apply --check` 通过） | 107 |
| 格式合法但目标源码已被后续改动覆盖（**历史记录，不可重放到 HEAD**） | 5 |
| 从未打红过任何 leaf、已剔除 | 1（`n24_empty_components_ok`） |

历史记录的 5 条：

| patch | 目标 | 说明 |
|---|---|---|
| `m12_trust_self_reported_pid` | `internal/daemon/execution_control_isolation.go` | 目标文件在取证后继续演进，`-` 行已不存在 |
| `m13_skip_dead_handle` | 同上 | 同上 |
| `m14_plain_read_accepts_fd` | `internal/daemon/execution_control_isolation_linux.go` | 同上 |
| `m17_skip_ancestor_check` | `skills/shared/crctl/scripts/lib/merge-facts.mjs` | 同上 |
| `m79_regrant_resets_origin` | `server/internal/governance/execution_fresh_work.go` | 该文件被 `foundation-fresh-work` 重写后再取样，patch 指向重写前版本 |

这 5 条在取证当时确实跑红过对应 leaf（记录见 `../test-report.md` 与 `../gate3-readiness.md` 的变异编号），但**不能**用它们重放到当前 HEAD 复现；要复现请在当前源码上按描述重新构造变异并重跑。

## 两类变异，判据不同

- **代码变异**（大多数 `m*`）：改实现、跑测试、看指定 leaf 是否红，然后还原并 `go build` 校验。
- **取证前置变异**（`n31`、`n32`）：改的是测试自己的部署前提（把受保护根改成 `0755/0644`、把 key 目录划给 root），用来证明「内核真的在拒绝」，而不是测试里写死了失败。这类变异的对象是测试文件，不是被验实现。

## 已知不对称

- `m86`（删 `AcceptTerminalReport` 中 `required && missing` 那一支）**无可观测差异**：紧随其后的 `if missing` 分支对同一情形返回同一种 sentinel error。已记入 `../channel-test-expectations.json#mutation_asymmetries`，不伪造变异；`m85` 删后一支即可红新 leaf。
- 由 DB 约束兜底的不变式（如 readiness 的 nonce 唯一约束）无法由 Go 侧打红，同样登记在 `mutation_asymmetries`，未伪造变异。

## 修复记录

2026-10-27 本轮修复了归档本身的两处缺陷：

1. **n1–n28 基线错误**：原归档按「第一个内容不同的 lib」选基线，实际等于全部对 `execution-control-policy.mjs` 取 diff，27 条 patch（n1–n27 及 `n24_na_bypass`）与变异内容无关。已按「与 mutant 差异最小」重新识别基线并重生成，全部 `git apply --check` 通过；抽查 `n9`（采集失败改空集）与 `n12`（合同字段删除走 legacy）语义与描述一致。
2. **patch 头写成标签名**：100 条 patch 的 `+++` 行是变异名而非路径，`git apply` 无法使用。已改为 `--- a/<path>` / `+++ b/<path>` 并重算 sha256。
