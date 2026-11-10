# 可信 verdict 结果与命令绑定

<!-- source_hash: a0821fc558d8647a -->
<!-- generated_at: 2026-10-30T13:40:03.052230 -->
<!-- canonical: canonical/proposals/2026-10-29-trusted-verdict-outcome-binding.yaml -->

## Why

AIFI-45 的现有准入查询将 settlement.kind=effect 用作通过条件。现有验签检查绑定原字节、scope 和帧字段，但未验证可信裁决的结果语义或与冻结命令的对应关系；settlement.kind 由调用方输入。不能将未经核实的裁决或结算作为生产授权事实。静态读码未发现完整生产 verdict 写入接线，但不能据此推断现有部署或数据状态。


## What Changes

- 区分可信裁决、实际执行结果和 effect/no_effect 结算，调研可信事实如何绑定冻结命令与主体并由消费方验证；是否改变签名契约、字段、版本和信任根均待确认。
- 与 tools 同 ID 的草案协同定义生产者、验证者、兼容/冻结策略和跨语言一致性；不在此草案提前实施。

### Modified Capabilities

- **verdict-channel**：使生产准入依赖可验证的可信裁决和对应结算，而不是调用方自报的 settlement.kind。

## Success Criteria

- [ ] 经评审批准的契约方案（可确认沿用既有契约）能认证所需可信裁决并绑定正确命令与主体，旧格式及未知结果按批准策略失败关闭。
- [ ] 经批准的可信生产者与 M 验证者有跨语言、负面和重放测试，实际入口及数据库证据由各自变更独立提供。
