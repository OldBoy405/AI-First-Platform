# CI 实例唯一自身绑定键 — 局部复核

`instance-ownership.mjs` 在 created/running 核验中对 `HostConfig.Tmpfs`、`HostConfig.PortBindings`、running `NetworkSettings.Ports` 要求唯一自身可枚举字符串键就是预期键，同时拒绝数组/函数，保留原值和端口检查。之前可以用继承或不可枚举的预期键、配一个自身可枚举额外键，绕过仅检查键数量的条件。

旧源码 `source-red-v2` 的两文件测试：144 总计、135 pass / 9 fail、skip 0、exit 1；其中包括 3 个继承对象、3 个不可枚举预期键、created 两个 fake 引擎边界及 running 一个 fake 引擎边界。最早 `source-red` 139/135/4 是另一测试版本，不与 V2 相加。修后 `source-final` 作者和独立各单次 144/144 pass、skip 0、exit 0；4 文件 SHA 前后和当时 live 一致，作者 raw TAP/stderr 留存，独立 raw TAP 未保存。

最终 SHA-256：`instance-ownership.mjs` `0361ea8f8322c702220b794912a9d7daad431cb9fd04c50a2063128dbd482d23`；`instance-ownership.test.mjs` `2cd78b64c1c5c63917823ac8a40047537dce6c6d9da56c9ef7df5ee52e889c7e`；`instance-lifecycle.mjs` `bbe9f75058143d81136046705416358b000ffca109e2c88ea7a40adb3f7263b9`；`instance-lifecycle.test.mjs` `98aa51dbeb76058074c6397ee0ef884d76c06eb68fd5b4cd269980ebf80e59db`。

独立静态复核限定通过：created 假引擎失败不调用 start/probe/stop/remove/exists；running 例先 start，随后失败不调用 probe/stop/remove/exists。created 失败后已创建的假实例保留，不能说 cleanup 成功；直接 unit 负例使用 running 模式，created 控制流由假引擎覆盖。新增多处测试并未证明真实 backend 会返回该形状或发生真实端口暴露。

**未解决**：不可枚举额外键、symbol、继承的额外键及非 running Ports 可能被忽略；nested HostIp/HostPort、自定义 getter/Proxy、检查后重读和不可信 adapter 的稳定快照问题仍存在。需单独定义 adapter 身份、数据与生命周期契约；本修复不是容器安全、清理、RUN 或 Gate3 证据。未执行真实 DB/容器/网络/真实 CR，未清理资源。Node runner 可产生子进程，环境白名单不证明 OS 隔离，actual backend unknown。multica `CUSTOM.md` #282 已登记。
