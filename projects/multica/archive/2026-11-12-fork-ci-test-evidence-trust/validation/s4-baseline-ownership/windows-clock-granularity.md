# Windows 时钟粒度探针（归因证据）

## 为什么需要它

整包基线里 handler 的两个失败都是唯一键冲突：

```
FAIL TestPresenterMemberRemovalLinkage :: project_presenter_test.go:450: create member user:
  ERROR: duplicate key value violates unique constraint "user_email_key" (SQLSTATE 23505)
FAIL TestSearchIndexChangesScopeToWorkspace :: search_index_test.go:204: setup: insert into workspace:
  ERROR: duplicate key value violates unique constraint "workspace_slug_key" (SQLSTATE 23505)
```

两个夹具helper都用 `time.Now().UnixNano()` 造唯一值，不是常量 id：

- `project_presenter_test.go:21` `suffix := time.Now().UnixNano()` →
  `presenter-%s-%d@multica.ai`
- `search_index_test.go:22` `token := fmt.Sprintf("%d", time.Now().UnixNano())` →
  `search-index-<token>`

`search_index_test.go:204` 是**同一测试内第二次**调用 `searchIndexWorkspace(t, "SIB")`
（第一次在 203 行），所以冲突发生在两次相邻调用之间。

## 探针

在 OS 临时目录（不在任何仓库内）建 `main.go`，`go mod init clockprobe` 后 `go run main.go`：

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	prev := int64(0)
	same := 0
	for i := 0; i < 200000; i++ {
		n := time.Now().UnixNano()
		if n == prev {
			same++
		}
		prev = n
	}
	fmt.Println("consecutive identical UnixNano pairs:", same, "/ 200000")
}
```

## 结果（本机 Windows，Go 1.26）

```
consecutive identical UnixNano pairs: 199996 / 200000
```

20 万次相邻调用中 **199996 次返回完全相同的 UnixNano**。本机 `time.Now()` 的
实际粒度远粗于纳秒，因此任何以 `UnixNano()` 作唯一后缀的夹具在 Windows 上必然撞键。

探针目录运行后已删除，未在仓库内留下文件。

## 结论

这两个 handler 失败是 **Windows 本机时钟粒度产物**，不是常量 id 缺陷（EXP-2026-0001 的模式），
也不是 CI 会复现的失败：Linux 上 `UnixNano()` 逐次递进，两次相邻调用不会相同。

因此**不得**据此把它们加入 `test-ownership.json` 的排除名单——那会把本机平台问题
变成 CI 的永久 coverage 缺口。它们也不属于本 change 的修复范围，作为发现上报。