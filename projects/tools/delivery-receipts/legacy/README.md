# legacy/ — 旧代 change 的交付说明（不是回执）

这个目录里的文件**不是** `delivery-receipts/<change>.yaml` 那种交付回执，也不会被 `stdd` 读取。

## 为什么存在

`stdd bind-commit`（v2）要求被绑定的 change 满足两条：

1. `.stdd.yaml` 里有 `phases.build.selected_evidence`（Gate 3 选定的 run）；
2. `validation/runs/<run-id>/tc-evidence.json` 存在，且其中 `inputs[].sha256` 能由目标提交的内容复现。

v1 代的 change 没有这两样东西——它们只有人工评审记录和旧式 `validation/` 目录。事后补算哈希并不能证明当时的执行结果，只会把数周前的评审绑到今天的代码树上，产生回执本应防止的虚假保证。因此这些 change 一律**不生成 v2 回执**，改为在这里留下可追溯的说明。

## 约定

- `kind: legacy-delivery-note`、`is_receipt: false`、`contains_cp_evidence: false`。
- 记录：change 身份、归档状态、`why_unbound`（含 CLI 的原始拒绝信息）、提交信息里引用过该 change id 的提交（不声称穷尽、也不声称被绑定）、证据文件位置、已知缺口、核对时间与方式。
- 不写 CP 通过结论，不写「已验证」，不写业务提交与证据之间的绑定关系。

## 现状

| change | 归档 | 回执 |
|---|---|---|
| `2026-10-22-aifi-45-authorized-execution` | 是（v1，`current_phase: deliver`） | 无，见同名 note |
| `2026-11-08-aifi45-trust-anchor-chain` | 是（v1，`current_phase: deliver`） | 无，见同名 note |

`stdd status` 对两者的口径一致：**已封存未绑定**，Gate 3 显示「批准无效（`phases.build.selected_evidence` 为空）」。
