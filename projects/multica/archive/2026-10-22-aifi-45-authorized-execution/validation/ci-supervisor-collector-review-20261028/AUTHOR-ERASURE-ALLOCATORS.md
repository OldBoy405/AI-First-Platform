# 擦除测试：额外分配路径（作者记录）

针对独立强审在旧测试 SHA `30c10cb3ce9bf571d49299ec721a0606929fadd5da36b7ed0104c4ab8b11eee3` 下指出的三个存活变异，增强测试前保全了 `source-buffer-brand-review/` 六文件。作者在独占复制树复现：额外执行 `Buffer.copyBytesFrom`、`Buffer.concat`、`Buffer.allocUnsafe`+`set` 时，旧擦除测试分别 2/2 假绿；增强后相同三个变异分别 1 pass、1 fail，导入时捕获函数的三个对应变异也分别失败。仅删除自建复制树内本次文件，核空删除目录。

测试现在在导入和解码时监控 `from`、`copyBytesFrom`、`concat`、`allocUnsafe`、`alloc`、`of`，以及额外 `allocUnsafeSlow`，并恢复原 property descriptor。这是有限 API 变异防护，**不是**所有分配、原生接口或任意同进程篡改的完全证明；collector 未收尾及真实管道等缺口仍在。仅测试改动，产品代码无变化。

Node v26.3.0 作者重跑 8 个 fake I/O 文件：207/207，0 fail、0 skip，14 个输入文件前后 SHA 不变，独占临时目录核空删除。增强测试 raw SHA `e7728eaeae596f7d5e904dda85004a72e843d59ef3c62163f161bffc6e5c1756`，尚待独立复核。既往强审和 45/45 独立复跑只覆盖旧测试快照，不能冒充对新测试的复核；进程/容器能力与 Gate3 BLOCK 不变。
