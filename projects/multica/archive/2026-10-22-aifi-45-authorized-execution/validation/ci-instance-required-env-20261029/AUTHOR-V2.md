# 必需环境与环境集合 V2：作者证据

V1 strong 发现隐藏属性替换合法键可绕过全键检查，详见 `REVIEW-STRONG-V1.md`。在 V1 代码 `1593287fafd87424bb8d19564748048003a07ed0c2966e0d6c9936ee28b2b871` 上增加独立负例后，Node v24.15.0 白名单环境执行 `node --test --test-reporter=tap --test-name-pattern="reject hidden unapproved environment key" instance-ownership.test.mjs`；实际选中 1、pass 0/fail 1/skip 0、exit 1，失败为预期的 `Missing expected exception`。新增测试 raw SHA `25938c4d8881c06942db5d906a9e18e930679c97f7361e0b83741831bf168a5c`。

最小修复将实际 Config.Env 每个键的期望集成员检查由 hasOwn 收紧到 own 且 enumerable，与输入允许清单及最后 `Object.keys` 计数一致。不防多次读取间被恶意 Proxy/getter/可变对象操控；正常 lifecycle 会先拷贝普通对象，本次缺陷未证明可触及真实容器。

四文件单次无 DB 回归：Node TAP 167 pass/0 fail/0 skip、exit 0，不和历史 166 相加。源码 raw SHA `a93f1a229dce5a08cebe584902b3b90a2e01e7c2ad5d6f74579b7b02cdd5a7a1`，测试 SHA 同上；其余三个测试与 V1 一致。七文件位于独占新建 `source-final-v2/` 原字节快照，V1 `source-final/` 保留。未保存原始 stdout/stderr、未调用真实引擎/DB/网络，白名单不证明 OS 网络隔离。V2 独立复核等待中；无 Gate 或完整 CI 验收结论。
