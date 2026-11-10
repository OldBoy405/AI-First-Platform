# Proxy 退出回执：作者测试记录

旧 `instance-lifecycle.mjs` raw SHA `8bf026671ffe6b57825848dafc397bdd36cf5df61892fcad0cdad6cbb0e67a88`，含新增测试的 `instance-lifecycle.test.mjs` SHA `ac41d27458e89897d60486fce4ba861f7e0eae20fa59b3b5848332a2cce27d68`。Node v24.15.0、白名单环境、`node --test --test-reporter=tap --test-name-pattern="a (Promise proxy|transparent proxy|revoked proxy)" instance-lifecycle.test.mjs`：3 选中、1 pass、2 fail、0 skip、exit 1；Promise 隐藏 then 与透明 Proxy 以 `Missing expected exception` 失败，已撤销 Proxy 早已失败关闭，不能算漏洞复现。

加 `types.isProxy(result)` 后拒绝代理回执，不读取其属性；Promise 及 thenable 既有拒绝保留。README 标明同步非 Proxy 回执是兼容要求，且若代理内部 Promise reject，调用方须自行处理；本组件不能认证普通回执或证明进程树退出。

四文件一次 Node TAP 回归：**171 pass、0 fail/skip、exit 0**，不同于前一快照 168，不叠加。最终源码 SHA `bbe9f75058143d81136046705416358b000ffca109e2c88ea7a40adb3f7263b9`，测试 SHA 同上，README SHA `504875774d389d45f0a7c810be3a5324be1d7592bd8d8e24097f7048960e6d88`；八文件 `source-final/` 原字节快照。只调用 fake engine；Node test runner 启动测试子进程，未接真实引擎、DB、容器或网络。白名单非 OS 网络隔离；不代表完整监督器或 Gate3。
