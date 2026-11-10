# 可信 verdict 结果与命令绑定（tools 侧）

<!-- source_hash: 1db813510c93a647 -->
<!-- generated_at: 2026-10-30T13:40:45.254658 -->
<!-- canonical: canonical/proposals/2026-10-29-trusted-verdict-outcome-binding.yaml -->

## Why

AIFI-45 消费侧将 settlement.kind=effect 用作通过条件，但当前 verdict 验签检查没有核验由可信生产者认证的结果，结算 kind 由调用方输入；该断言不能直接作为可信执行结果。归档通道规定未知字段不产生授权事实，须先核实既有契约字段及语义能否表达、验证相应可信事实。静态读码不证明真实部署和历史数据状态。


## What Changes

- 区分可信裁决、实际执行结果和 effect/no_effect 结算，调研可信事实的真实来源、生产者身份和签发时机；先核实既有契约，是否改变签名契约、字段与版本均待评审。
- 与 multica 验证方共同评审旧格式、恢复及跨语言测试；不提前实施或签发真实 verdict。

### Modified Capabilities

- **verdict-channel**：为结果认证及消费方独立验证提供经批准的跨语言契约。

## Success Criteria

- [ ] 经评审批准的契约方案（可确认沿用既有契约）有明确生产者和信任根，并绑定正确命令、主体及可信裁决。
- [ ] T/M 具有跨语言、未知字段、旧格式、重放和负面场景的可复核测试；Gate 和部署各自批准。
