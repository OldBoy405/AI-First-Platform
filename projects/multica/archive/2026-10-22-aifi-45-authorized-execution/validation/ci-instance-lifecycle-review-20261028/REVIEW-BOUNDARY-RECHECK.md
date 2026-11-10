# AIFI-45 lifecycle 独立安全复审报告

## 一、结论与覆盖范围

**对本报告完整审查的 `9c7b…` 源码快照：BLOCK。**

局部确认作者的新修复成立：

- options/target getter 抛出的异常已进入固定错误路径；
- 主流程与 cleanup 使用固定 phase，不再读取原异常文本；
- failure journal 未同步确认时，撤销 cleanup trust；
- cleaned ack 在 absence verification 之后、`cleaned=true` 之前；
- 空异常不再造成成功返回。

但 **Promise constructor/species、Promise Proxy、record acknowledgement，以及 engine 异步返回值的实际输出边界仍有缺口**。补充隔离复现已观察到：同步错误和 journal 均无假 secret，但 Node stderr 仍输出该标记；部分 fake adapter 反例还先返回了 `{ cleaned: true }`。

### 版本边界——特别说明

本报告最后一次**实际完整读取并审查**的组合是：

- lifecycle：`9c7bbb23…`
- lifecycle test：`c58aeec9…`
- ownership：`5c4785ae…`
- 复审文档：`754f7659…`

**测试 SHA `c58a…` 对应当时的 36 项版本，早于你提到的后续 38 项快照。没有完整读取或执行后续 38 项测试，不声称覆盖它。**

续审期间源码又变化，单独字节哈希检测得到：

```text
a6d4452911b002b7ec60c7fd2e59acabae98f15c3fa14a1b93d53cb7e391f13d
```

该版本**没有完整读取、审查或测试**。哈希守卫阻止了将其混入旧快照复现。因此，本报告不能作为后续版本的通过或不通过回执；原 gate 不因本报告而放行。

---

## 二、原始 SHA-256

使用 Python `Path.read_bytes()` 和 `hashlib.sha256()` 独立计算，未归一化换行或编码。

源码目录：

`C:/Users/GOBAO/Downloads/AI/multica/scripts/aifi45-db/`

| 文件 | 字节数 | 原始 SHA-256 |
|---|---:|---|
| `instance-lifecycle.mjs` | 4702 | `9c7bbb2308ee4533e5d68dedf0819ed22b85b67fc86934d06590e8b033ae37f8` |
| `instance-lifecycle.test.mjs` | 15815 | `c58aeec9a525d6e04098b5139ad6928b7d7b00c14bf45535d12756c1372a3ff7` |
| `instance-ownership.mjs` | 5894 | `5c4785ae4a03a951a00a72248528ba97b11163caf5675c8304e6a8c656e05288` |

文档实际路径：

`C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/ci-instance-lifecycle-review-20261028/REVIEW-FAILURE-RECHECK.md`

| 字节数 | 原始 SHA-256 |
|---:|---|
| 5515 | `754f7659281fea9bb34f23d06ea31d1fa1020ec4b7a66ebe89690599c9339e5a` |

以上是已审查历史快照的身份，**不是声称磁盘当前仍保持这些内容**。

---

## 三、实际执行与方法

### 已提供的测试

此前实际运行：

```text
node --test …/instance-lifecycle.test.mjs
Node v24.15.0
36 tests / 36 pass / 0 fail
```

这对应上述 `c58a…` 阶段，不覆盖后续 38 项版本。

### 补充独立复现

本次补充完成 **30 个有效的内存 fake-I/O 场景**：

- 每个场景使用隔离 Node 子进程；
- 使用 `--unhandled-rejections=strict`；
- 捕获 stdout、stderr、退出码及 fake engine 调用顺序；
- 只使用假标记 `REVIEW_FAKE_ONLY_SECRET`；
- 因磁盘变化，使用从已完整读取内容重建的内存源码；执行前验证其 **4702 个原始字节的 SHA-256 与 `9c7b…` 完全一致**；
- ownership 同样进行 SHA 守卫；仅在内存中将 import 指向对应模块。

计数不包括哈希守卫中止或无效夹具尝试。

| 场景组 | 数量 | 实际结果 |
|---|---:|---|
| 正常生命周期 | 1 | 返回 cleaned=true，正常退出 |
| options/target/env Proxy 抛错、抛出的异常 Proxy | 4 | 固定错误，无标记输出；异常 Proxy 未被读取 |
| failure ack=false / throw / 普通 rejected Promise | 3 | 整体失败，不 stop/remove |
| cleaned ack=false / 空异常 / 普通 rejected Promise | 3 | 已 remove，但整体失败 |
| 普通 rejected Promise probe | 1 | 固定错误，不清理，无标记输出 |
| record 普通 rejected Promise、普通 thenable 调 reject | 2 | 不 create，无标记输出 |
| probe constructor/species/派生结果/Promise Proxy | 4 | 不清理；**stderr 含标记，退出码 1** |
| record then getter/non-function then/constructor/species/then 返回 rejection | 5 | 不 create；**stderr 含标记，退出码 1** |
| start/stop/remove 返回 rejected Promise | 3 | **先返回 cleaned=true，再 stderr 含标记、退出码 1** |
| create 返回 rejected Promise | 1 | 固定失败、不清理；**stderr 含标记、退出码 1** |
| 首次 running 请求端口漂移、created 已有实际绑定 | 2 | 仍可返回 cleaned=true |
| adapter 自行写 stderr | 1 | 固定同步错误，但 stderr 仍含标记，退出码 0 |

**这些是 JavaScript/Node 输出路径和 fake 状态机证据，不是真实 DB、容器、引擎隔离或 journal 持久化验收。**

---

## 四、作者新改的确认结果

以下源码行号均属于 **`9c7b…` lifecycle**；测试行号属于 **`c58a…` 测试**。

### 1. options/target 异常 getter、Proxy：同步异常封装成立

**位置：`instance-lifecycle.mjs:5–13`。**

options 解构位于 try 内；target 字段读取及 expectedEnv 展开也在同一 try 内。

可复现条件：

- options 的 `engine` getter 或 Proxy `get` trap 抛含密错误；
- target 字段 getter/Proxy 抛错；
- expectedEnv 的 `ownKeys` trap 抛错。

结果为固定的：

```text
instance intent unreadable
```

不 create。新增 options 回归测试位于 `instance-lifecycle.test.mjs:172–177`，当时执行通过。补充 Proxy 场景也确认无标记进入 stderr。

**此前 options 参数解构越过 try 的旧问题，不应继续归于此快照。**

### 2. 不再读取原异常，固定 phase 成立

**位置：**

- 主 catch：`:68–72`
- cleanup catch：`:96–101`
- 最终失败判定：`:105`

这两处 catch 不读取原错误的 `message`、`stack` 或字符串转换结果。

补充复现中，engine 抛出一个读取属性便抛 secret 的 Proxy；其 trap 调用次数为 **0**，输出仍为固定的 `instance create failed`。

测试 `:160–170` 覆盖异常 message getter；空 start/cleaned 异常测试位于 `:186–197`。`hadFailure` 与 `!cleaned` 的最终检查不依赖异常文本真假。

### 3. failure journal ack 失败后，cleanup trust 撤销成立

**位置：`:71–74`。**

当一个已取得合法退出回执、code=1 的 probe 失败时，原本仍可清理已确认归属的实例；但 failure event：

- 返回 false；
- 同步抛错；
- 返回普通 rejected Promise；

均会令 `event` 失败，随后 `trusted=false`，不进入 cleanup。

补充三个场景均确认：**没有 stop/remove，也没有 cleaned 成功事件。**

测试覆盖：`instance-lifecycle.test.mjs:206–221`。

### 4. cleaned ack 顺序成立，但不能回滚已发生的删除

**位置：`:88–95`。**

顺序明确为：

```text
remove
→ exists(id) === false
→ exists(name) === false
→ record('cleaned') === true
→ cleaned = true
```

cleaned ack=false、抛空字符串、返回普通 rejected Promise，三个补充场景均整体失败，错误为 `instance cleaned journal failed`。

**这修复了“ack 未确认却返回成功”的路径；并不意味着 ack 失败时实例仍被保留——此时 remove 已发生。**

---

## 五、未关闭的发现与可复现条件

复现片段可接到 `c58a…` 测试文件 `:8–39` 的 `setup()/run()` fixture 上；`S` 表示假 secret 标记。

### F1. probe 的内建 `then.call` 仍受 constructor/species 影响

**位置：`instance-lifecycle.mjs:59–61`。**  
**结论：已复现的异步输出缺口。**

#### 条件 A：species getter 抛错

```js
class P extends Promise {
  static get [Symbol.species]() {
    throw Error('species failed');
  }
}
s.runProbe = () => P.reject(Error(S));
```

#### 条件 B：原生 Promise 的 constructor getter 抛错

```js
s.runProbe = () => {
  const p = Promise.reject(Error(S));
  Object.defineProperty(p, 'constructor', {
    get() { throw Error('constructor failed'); }
  });
  return p;
};
```

两者均可在给原 rejection 安装 handler 前抛错。同步外层 catch 虽生成固定错误，**原 rejection 仍未处理**。

另外，自定义 species constructor 可以产生一个立即拒绝的派生 Promise；`:60` 返回的派生对象被忽略。以原 probe Promise 已 resolve 的形式，也复现了派生结果的未处理拒绝。

**三个场景实际结果：**

- 同步错误均为 `instance probe failed`；
- 不 stop/remove；
- journal 无假标记；
- **stderr 有假标记，子进程退出码 1。**

因此，绕过 `result.then` 覆盖并不等于绕过 constructor/species，也不等于安全消费所有实际 Promise。

### F2. Promise Proxy 走不到原生 Promise 分支

**位置：`:59–65`。**  
**结论：已复现的异步输出缺口，不恢复 cleanup 许可。**

```js
s.runProbe = () =>
  new Proxy(Promise.reject(Error(S)), {});
```

该 Proxy 不具备原 Promise 的内部品牌。后续 callable `then` 判定使 receipt 被拒绝，但并未消费背后 Promise 的 rejection。

实际结果：

- 固定的 `instance probe failed`；
- 不 stop/remove；
- **stderr 有标记，退出码 1。**

同理，普通 receipt 字段本身只是 adapter 的声明；本函数不能独立证明一个外部进程真的退出。可信 adapter 与真实退出回执仍是必要边界。

### F3. record 的 acknowledgement 处理也有未处理拒绝路径

**位置：`:15–19`，尤其 `:18`。**  
**结论：已复现；非 true ack 未获放行，但输出不安全。**

例如：

```js
const p = Promise.reject(Error(S));
Object.defineProperty(p, 'then', {
  get() { throw Error('ack unreadable'); }
});
s.record = name => name === 'intent' ? p : true;
```

在安装 handler 前，读取 `.then` 就抛错。

以下变体也实际复现：

1. rejected Promise 自有 `then=null`：不进入消费分支；
2. rejected Promise 的 constructor getter 抛错：`Promise.resolve` 失败；
3. Promise 子类 species getter 抛错：assimilation 调用其 `then` 时失败；
4. thenable 的 `then` 返回一个额外 rejected Promise：

```js
s.record = name => name === 'intent'
  ? {
      then(resolve) {
        resolve(true);
        return Promise.reject(Error(S));
      }
    }
  : true;
```

最后一种情况下，标准 thenable assimilation 不会消费 `then` 方法的返回值。这也说明不能将任意 thenable 的副作用纳入“已安全消化”的承诺。

**五个场景：均不 create；同步错误固定；但 stderr 有标记、退出码 1。**

对照场景中，普通 rejected Promise 和正常调用 reject 的普通 thenable 被消费，未输出标记。

### F4. engine 异步返回值被忽略，可出现先成功、后失败

**位置：**

- create：`:39–42`
- start：`:50`
- stop：`:82`
- remove：`:88`
- 成功判定及返回：`:105–106`

**结论：已复现的接线风险。**

例如：

```js
const remove = s.engine.remove;
s.engine.remove = value => {
  remove(value);                    // fake 状态同步更新
  return Promise.reject(Error(S)); // 调用者未检查
};
```

同样包装 start、stop。

三个场景均：

1. fake 状态允许后续 inspect/absence 检查通过；
2. 返回 `{ cleaned: true }`；
3. 随后未处理 rejection 输出假标记，子进程退出码 1。

create 返回 rejected Promise 时，ID 校验会失败，不进入 cleanup；但 rejection 本身仍未消费。

**限定：**这不证明真实引擎已发生错误删除。它证明此 runner **不能单独强制所有 engine 操作同步完成，也不能保护误接异步 adapter 时的输出与成功边界**。真实接线必须有明确、可验证的同步 adapter 契约；不能仅靠这些 fake 测试推断。

### F5. 动态端口仅约束 created 请求值，未锁定跨阶段值

**位置：**

- `instance-ownership.mjs:71–72`
- `instance-lifecycle.mjs:47–55、25–28`

created 阶段报告固定非零请求端口，会被拒绝；这一具体规则成立。

但 requestedPort 基准是在第一次 running inspect 后才保存。

补充复现：

- 第一次 created inspect：`HostPort:''`；
- 从第一次 running inspect 起：`HostPort:'39421'`；
- 实际端口也为 `'39421'`，后续保持一致。

结果仍可返回 cleaned=true。

另一个场景中，created 的 requestedPort 为空，但 `NetworkSettings.Ports` 已报告合法 loopback 实际绑定，也可通过。

**限定：**这是动态端口端到端证明不足，不是已证明真实 Docker 会产生该状态，更不是已证明发生越权删除。当前代码只关闭了“created 明确报告固定请求端口仍获启动”的路径。

### F6. 固定 error/journal 不等于整个进程的输出过滤

**相关位置：engine/probe/record 调用点及上述异步分支。**

补充输出边界演示：

```js
s.engine.create = () => {
  process.stderr.write(S);
  throw Error('create failed');
};
```

实际结果：

- 同步错误为 `instance create failed`；
- journal 无假标记；
- **stderr 有假标记，子进程正常退出 0。**

这不是要求 runner 能约束任意恶意 JavaScript 的日志副作用，而是限定安全声明：**它只控制自己构造的错误和事件，不控制 adapter 的直接输出、子进程流或所有异步 rejection。**

---

## 六、其它毁坏性风险与已确认的保护边界

在已审查快照中：

- create 回执必须是完整 64 位小写十六进制 ID；无有效 ID 时不猜测、不重试、不按名称清理：`:39–42、74`。
- stop/remove 传入的是保存的 ID，不是名称：`:82、88`。
- cleanup 前重新核验 ownership；stop 后再次核验 stopped 状态：`:77–85`。
- `instance-ownership.mjs:37–65` 检查身份、时间窗、环境、关键隔离配置及 mounts；`:66–95` 检查端口与状态。
- ID/name 任一 absence 不明确，不能宣称 cleaned：`:90–95`。

**没有从这四个文件中建立一个无条件“删除任意其它实例”的反例。**但也没有真实 adapter 的 argv、删除选项、inspect 规范化、进程回执、日志处理或 journal 落盘证据。inspection 与破坏性操作之间也不是原子授权事务。

因此，不能据此认证真实 stop/remove 的目标与副作用，也不能把 `record(...) === true` 等同于已持久化、可恢复的审计记录。

---

## 七、旧复审文档的适用性

`REVIEW-FAILURE-RECHECK.md` 不能充当本报告快照的验收回执：

- `:12–19` 中 lifecycle/test 哈希与本报告快照不一致；
- `:31` 的 cleaned 状态与 record 顺序描述已过期；
- `:39、77` 提到的 `scrub` 在本报告源码中不存在；
- 测试行号已变化；
- constructor/species 风险判断仍有效，但原文是静态反例，本报告补充了隔离 Node 输出证据。

---

## 最终限定

**`9c7b…` 快照：局部修复认可，整体 BLOCK。**  
**`c58a…`：当时 36 项测试通过，明确不覆盖后续 38 项快照。**  
**后续源码：未完成审查，不给予通过结论。**

全过程没有修改项目文件、没有运行 DB/容器；补充复现仅涉及内存 fake-I/O 与隔离 Node 子进程。上述证据不能升级为真实环境安全验收，也不构成任何真实操作授权。
