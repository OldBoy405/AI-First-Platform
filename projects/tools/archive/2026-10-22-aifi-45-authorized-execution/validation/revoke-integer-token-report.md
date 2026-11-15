# T revoke 数字精度 P2 — 主会话修复

## Finding 与边界

非作者 strong（会话 `01a16e02-2ae3-77b9-a3c5-0eb53a155075`）独立证实：`JSON.parse` 把分数 `2.0000000000000001` / `1.99999999999999999` 舍入2；把非零负数 `-1e-1000` 下溢为 -0，旧 reviver 再改为0，导致已签整数与不等原来源被误判一致。前一份151/151作者检查和209项独立复跑没有覆盖这些 raw token，不能用其绿色否认 finding。

这不是修改 raw bytes，也不表明能伪造可信服务签名/突破仍关闭的消费门禁；是独立静态/来源验证判据的 P2，需要修复。

## 主会话 RED → GREEN

实现与测试由主会话承担，未为修复另派 strong 作者。原证据全部保留。

- [RED stdout](revoke-integer-token-red.stdout.tap) / [stderr](revoke-integer-token-red.stderr.log) / [meta](revoke-integer-token-red.meta.json)：公开 CLI **6 RUN / 0P / 6F / exit1**。四例是两种 raw 分数分别放在已签 revoke revision、原 source revision；两例是 initial repair_limit/action.limit 的原 source `-1e-1000`。六例均因旧 CLI **exit0 错误接受**而断言失败；不是编译/依赖/DB/零匹配。
- [最小 GREEN](revoke-integer-token-green.stdout.tap) / [meta](revoke-integer-token-green.meta.json)：上述六例+两个原 `-0` 正例，**8/8、exit0、0skip**。
- [调用者扩展 GREEN](revoke-integer-token-callers-green.stdout.tap) / [meta](revoke-integer-token-callers-green.meta.json)：**11/11、exit0、0skip**，在前8例上增加真实 binding-stdio 的 raw 分数 process_id/revision 拒绝与 MAX_SAFE_INTEGER/数字样 reason 字符串正例；均为公开 CLI，不是仅内存函数。三份 stderr 空。两批 GREEN 重叠，不相加成独立用例。

## 根修复

`lib/execution-authorization.mjs` 复用已有 token walk，在接受解码树前检查字符串外原始数字 token：只允许 JSON 十进制整数、Number 安全整数范围；拒小数/指数/溢出，不把舍入值当整数。语法仍由 JSON.parse 处理，没有另写 JSON parser；合法整数 token `-0` 可语义归零。payload/source/proof 原 buffer、签名输入与摘要不重写。

全部直接调用者包括资源 identity、授权/绑定 payload、运输 envelope、source、stdin proof；当前执行合同的数值字段均为整数，字符串整体 token 不受数字检查。测试 helper 仅新增支持原 Buffer proof，以真实签名构造原始分数 token，而不是用 JS Number 再 JSON.stringify 抹掉反例。

本 P2 仅改此前3文件范围中的 lib 与 test；`crctl.mjs` 不变。wire 明确原始整数 token，并补 initial14/revoke5 的 source profile 和 reason 字段词汇。旧 author manifest 属旧快照，最终源摘要另存，不能覆盖旧报告来冒充同一版本。

## 独立代码复查

上述 strong 会话对新快照 **PASS，F1关闭，无新实质 finding**。其独立内存组件检查为 parser232/232、真实 Ed25519+来源读取11/11、binding4/4，覆盖 parent_process_id、转义与上下界；不落盘/无DB。这些与本报告公开CLI证据分开，不能冒称完整 daemon/CLI 端到端重跑或业务TC。

当前完整三测试/M→T HTTP互操作由非作者 balanced 单独运行并留新证据；尚未结束的工作不在此预判 PASS。M 作者旧T快照的互操作结果仍是旧版证据。

## 模型分层纠正

按用户最新提醒，不为凑齐三档外包 strong 作者。主会话按原生 model+effort 跳过条件承担普通实现；必要 strong 独立审核、balanced 独立测试、economy 文档审核仍保留。有效配置来自本次 native CLI（`revoke-p2-models.json`），requested/harness/actual 分开，无后端回执 actual=unknown。已更新项目恢复 Skill，旧实际作者委派记录不改写成未发生。

完整业务TC0/49、五major unresolved、BUILD普通模式不变；不自动Gate3/commit/push/发布/真实CR试点。
