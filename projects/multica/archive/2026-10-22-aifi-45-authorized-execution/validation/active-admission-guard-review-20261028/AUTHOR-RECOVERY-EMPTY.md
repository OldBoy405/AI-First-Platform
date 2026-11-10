# 精确恢复空 pin：作者证据

原源码及测试在 `source-recovery-zero-final/` 保全，raw SHA 分别为 `449216c3469c48cdc7bb33fd9e138bd632bfabf0c95815f891fb00bab446178a` 和 `2a5bcd5fae7d965a74a96263940c30aa32d36775882fbacdd7ac1cbfbd9a0de5`。追加双侧空 origin、双侧空 digest × STOP_NEW/过期 ACTIVE 四例，旧源码均返回 ExactRecovery（断言期望 Denied），真实 RED。修后保留其他恢复正控，整个 no-DB 子包 7 顶层、79 leaf PASS、0 fail、0 skip；运行前后源码测试 SHA 稳定，分别是 `0d9773985591f63035c7bc706d9e406e1a929f2bed990235b5d0d287cea96e0a` 和 `e556f9b8e532669cfbec72fb34b364d991842cb3d2aadb15d2a459d75d758032`。

作者以独占临时 Go overlay 分别移除 origin 空值和 digest 空值守卫；两项各 exit 1、各有 2 个对应状态下 `ExactRecovery, want Denied` 断言失败。工作树源码/测试未改变，逐一删除自有文件并核空移除目录；去掉 overlay 后目标 1 顶层及 14 子例全部 PASS，0 skip。待独立复核。

不校验字符串的其他格式；非空相等不证明来自可信 DB，也不能解决可控 `Now`、缺 RequestID DB 回查、签名或锁竞态。真实 DB、容器和 CR 均未运行；RUN-006 不由此验收。CUSTOM #274。
