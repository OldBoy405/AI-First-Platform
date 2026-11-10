# Buffer 非字节视图伪装：作者记录

强审指出 `Buffer.isBuffer` 可被修改过原型的非字节 typed array 骗过。作者构造一个底层完整合法的 wire：以 `Uint16Array` 为 backing view，将其原型设为 `Buffer.prototype`。实际 RED 中 decoder 返回 `decoded:true`，collector 也没有拒绝；并非真实进程或容器数据。随后 decoder 和 collector 加入 `node:util` 的 `types.isUint8Array` 检查，拒绝底层非字节视图；collector 的 stdout、stderr 均测试拒绝并保持失败态。

边界：这不证明来源身份，`Uint8Array` 自行改原型仍能通过并正常解码；调用方鉴权与真实进程绑定完全未实现。同进程替换全局内建、共享内存、分离缓冲及其他既有边界仍按单独审查处理。将 collector 测试名中的「genuine」调整为不声称真实来源的措辞。

Node v26.3.0 作者运行 8 个 fake I/O 文件 207/207，fail 0、skip 0；14 个源/测试输入 SHA 前后一致，独占临时目录核空后移除。关键 raw SHA：protocol `92329bb48d9eed2b97eabd26b1b883dfb2b1684278ce91f593ecf3d95e3ea5c8`；collector `a880d23c1ea0c05d1554dd2d4ff83fce6cbebff7e9355f8d33796288e87e1b28`；brand test `abaa1f9ffe6cce3dab655054ba21763d642e722999402e186a54cc75caf55448`；erase test `30c10cb3ce9bf571d49299ec721a0606929fadd5da36b7ed0104c4ab8b11eee3`。本记录与既往基于旧源码 SHA 的独立报告是不同快照；最终版仍待独立复审，不改变 Gate3 BLOCK。
