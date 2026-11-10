# AIFI-45 supervisor 额外分配擦除测试：独立复核

- Session 自报：`PI_SESSION_ID=01a1859e-2679-7020-aecc-d237c8a5bfb4`；model 自报：`PI_MODEL=gpt-6.1-terra`。这些是会话环境标记，不是后端身份或实际模型的证明；backend receipt 未知。
- 环境：Windows、Git Bash，Node `v24.15.0`。
- 范围：当前六文件快照的独立测试复跑，以及旧、新擦除测试对三个额外复制变异的实测；不解除现有 BLOCK，不构成真实执行或清理授权。

## 当前快照复跑

在 `C:/Users/GOBAO/Downloads/AI/multica/scripts/aifi45-db` 执行：

```text
node --test --test-reporter=tap supervisor-protocol.test.mjs supervisor-collector.test.mjs supervisor-erase.test.mjs supervisor-buffer-brand.test.mjs
```

实际结果：**45 个 top-level，pass 45、fail 0、skip 0**；TAP plan `1..45`，cancelled 0、todo 0，退出码 0。原始 stdout TAP（9307 字节）仅捕获在内存，stderr 0 字节；没有输出或保存原始 TAP。测试子进程环境排除了 `NODE_OPTIONS` 和 `NODE_V8_COVERAGE`。

## 旧、新六文件 raw SHA-256

旧文件来自同目录 `source-buffer-brand-review/`，新文件来自 `multica/scripts/aifi45-db/`。下表为原始字节 SHA-256。新六文件在基线运行前后分别核对，前后值均为表中“新”列；旧、新六文件在变异前及变异后也分别核对，均未变化。仅擦除测试哈希不同。

| 文件 | 旧快照 raw SHA-256 | 新快照 raw SHA-256（基线前＝后） |
| --- | --- | --- |
| `supervisor-protocol.mjs` | `92329bb48d9eed2b97eabd26b1b883dfb2b1684278ce91f593ecf3d95e3ea5c8` | `92329bb48d9eed2b97eabd26b1b883dfb2b1684278ce91f593ecf3d95e3ea5c8` |
| `supervisor-collector.mjs` | `a880d23c1ea0c05d1554dd2d4ff83fce6cbebff7e9355f8d33796288e87e1b28` | `a880d23c1ea0c05d1554dd2d4ff83fce6cbebff7e9355f8d33796288e87e1b28` |
| `supervisor-protocol.test.mjs` | `b7d4dd793cb6cf69d6cdd93c293cee3363d4c1d3deed44cda41af7c2b9c77705` | `b7d4dd793cb6cf69d6cdd93c293cee3363d4c1d3deed44cda41af7c2b9c77705` |
| `supervisor-collector.test.mjs` | `b82fc48bfabb50c50ab934d1151470eef11978de01c2e5cf0d96c57c27f79924` | `b82fc48bfabb50c50ab934d1151470eef11978de01c2e5cf0d96c57c27f79924` |
| `supervisor-erase.test.mjs` | `30c10cb3ce9bf571d49299ec721a0606929fadd5da36b7ed0104c4ab8b11eee3` | `e7728eaeae596f7d5e904dda85004a72e843d59ef3c62163f161bffc6e5c1756` |
| `supervisor-buffer-brand.test.mjs` | `abaa1f9ffe6cce3dab655054ba21763d642e722999402e186a54cc75caf55448` | `abaa1f9ffe6cce3dab655054ba21763d642e722999402e186a54cc75caf55448` |

## 三种变异：旧绿、新红

在一个随机独占临时目录中，将旧、新擦除测试的原始内容分别复制并核对哈希；每种变异都在同一 protocol 副本的私有复制后追加额外复制，分别用旧、新擦除测试运行 `node --test --test-reporter=tap`。六次运行的原始 stdout 均仅捕获在内存中。

| 额外复制变异 | 旧测试 | 新测试 |
| --- | --- | --- |
| `Buffer.copyBytesFrom(view)` | 2 pass、0 fail、0 skip；exit 0 | 1 pass、1 fail、0 skip；exit 1 |
| `Buffer.concat([bytes])` | 2 pass、0 fail、0 skip；exit 0 | 1 pass、1 fail、0 skip；exit 1 |
| `Buffer.allocUnsafe(length)` 后 `set` | 2 pass、0 fail、0 skip；exit 0 | 1 pass、1 fail、0 skip；exit 1 |

每次新测试的失败均命中 `decoder must not make extra Buffer allocations` 断言，且为 `ERR_ASSERTION`；另一 collector 测试通过。已排除语法错误、模块找不到、进程异常及 stderr 非空等非预期结果，未将其算作变异杀死。

实验目录内的 `supervisor-protocol.mjs`、`supervisor-collector.mjs`、`erase-old.test.mjs`、`erase-new.test.mjs` 均逐一删除；核实目录剩余零项后移除目录。未修改原始源码或测试。

## 证据边界

- 实测确认这三种额外分配/复制调用能被增强测试检出，**未单独检验各副本的池 backing**；不能据此证明所有可能的内存分配或复制方式均被监控。
- 未完成收尾的 collector 仍可能保留缓冲数据；本测试不证明异常终止、GC 或真实管道接入后必然擦除。
- 未运行 DB、容器、真实 CR 或真实目标进程。Node 测试运行器自身使用进程，不等于运行真实目标进程；未验证来源认证、OS 退出、进程树或清理权限。
