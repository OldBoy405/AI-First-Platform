# 跨仓 verdict 契约草案登记与复核

用户要求按是否修改已归档签名契约分流。使用 `stdd new trusted-verdict-outcome-binding` 在 multica/tools 对应 workspace 目录登记同 ID 草案 `2026-10-29-trusted-verdict-outcome-binding`；负责人待指定，不擅自把 legacy 迁移负责人 Ray 推定为此草案负责人。两侧均 understand、四阶段 pending，proposal status=draft；没有 Gate 批准，code/agent specs、design、test-plan 仍为模板。

独立静态复核最初指出不可预断必须扩展签名契约、要区分可信裁决与实际执行/结算、澄清完整 scope 检查及跨仓计数。作者修订后，复核者进一步建议明确可沿用现有契约；最终措辞再调整后，复核者仅就草案内容给出通过，无阻断项，但无法计算或核对 SHA，亦未运行 Gate/DB/容器/CR。生产者、信任根、实际存量兼容和测试的单一计数归属仍未决定；结论不代表方案或 Gate 审批。实际后端 receipt 不可用。

协调者独立计算最终 proposal raw SHA：multica `76e293cde604f1c0050fffce38f5b7366c1f6103c3daf673c1e23a20ee8f4ad9`，tools `f110f65c298a392bb3dade64207a43dabd3b62fe1a177a436275da1e06175881`；reviewer 未独立核哈希。前一版按 SHA 保护的 proposal 和索引状态副本见 `verdict-outcome-proposal-source-20261029/`。

协调者用 YAML parser 检查两仓 proposal、状态和 index 可解析，两个 index 均有 3 个目标且实际存在；该检查不等于 stdd validate。实跑 `stdd validate 2026-10-29-trusted-verdict-outcome-binding` 两仓均 exit 1，原因 `缺少必需文件: proposal.md`；YAML-first 的 Gate1 尚未生成 Human View，不能据此宣称验证或 Gate 通过。未生成或伪造审批。
