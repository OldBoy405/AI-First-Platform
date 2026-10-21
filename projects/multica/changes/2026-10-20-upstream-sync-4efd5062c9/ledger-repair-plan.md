# CUSTOM.md 台账修复计划（Gate 1 前置）

> 未获用户授权前不修改 CUSTOM.md。以下为拟操作清单；修复提交必须独立于 merge。

## 执行结果（2026-10-20）

- 修复提交：`54d5d5bbf`（`docs(CUSTOM): 同步前台账修复（基线/状态/CR索引）`）
- R1 基线行：已归位到《核对基线》，更新为 442 / 1400 / 541 / 278
- R2 当前状态：已更新为 2026-10-20，HEAD `0d6b4e9f9`，下一窗口 `e0f84dda4..4efd5062c9`
- R3 CR-2026-076：已标为已合并 `c47381ae7`（2026-10-12）
- R4 AIFI-45：已标为已提交 `0d6b4e9f9`；Gate 3 状态另行核对
- R5 条目审计：5 个测试文件已补登记说明
- R6 §0：PASS
- 未 push、未 merge、未部署

## R1：基线行归位并更新

- 将 2026-10-20 基线行从《合并官方记录》表移到《核对基线》表。
- 值更新为 HEAD `0d6b4e9f9` 实测：**442 / 1400 / 541 / 278**。
- 备注：第八次同步后、AIFI-45 落码；与旧行 433 / 1389 / 532 / 278 的差异逐项归因到 AIFI-45 最终提交。

## R2：当前状态刷新

- 《当前状态（2026-10-08）》更新为 2026-10-20，HEAD `0d6b4e9f9`。
- 记录下一次同步窗口 `e0f84dda4..4efd5062c9`（101 提交）。
- 记录上游 tip `4efd5062c9` 与迁移撞号 565–584。

## R3：CR-2026-076 状态

- 《CR 索引》中 CR-2026-076 由“在途（developing）”改为“已合并（`c47381ae7`，2026-10-12）”。
- 10-10 至 10-13 的“在途，未合并”基线行是历史记录，保持不改，或加注“已合并”。

## R4：AIFI-45 状态

- CR 索引 AIFI-45 行“未 commit/push”改为“已提交 `0d6b4e9f9`”。
- “Gate 3 未批准”如仍属实则保留，另行核对，不因已提交而自动视为 Gate 3 通过。

## R5：条目审计

- 对照 HEAD `0d6b4e9f9` 改动的 server/packages/apps 文件与 #139–#152 条目，确认所有 `AIFIRST` / `CR-2026-*` 标记文件都有 #N。
- 发现缺口先补条目，再进入 Gate 1。

## R6：重跑 §0

- 重取四数、迁移水位、状态、格式；目标 PASS 或 PASS-WITH-FIX。
- 建议提交信息：`docs(CUSTOM): 同步前台账修复（基线/状态/CR索引）`。
- 修复提交独立于 merge；不 push、不部署。

## 验证

```bash
git grep -cE "AIFIRST|CR-2026-[0-9]{3}" \
  -- 'server/**/*.go' 'server/**/*.sql' 'server/**/*.mjs' \
     'packages/**/*.ts' 'packages/**/*.tsx' 'packages/**/*.mjs' \
  | awk -F: '{n++; s+=$NF} END {print n" 文件 / "s" 行"}'

git log -1 --format='%h %ad %s' --date=short -- CUSTOM.md
CUSTOM_SHA=$(git log -1 --format=%H -- CUSTOM.md)
git rev-list --count "$CUSTOM_SHA"..HEAD -- server packages apps
```

同时人工核对 CUSTOM 表头列数与行语义、CR 索引状态、当前状态日期。
