# CLI help 可用性提示

强审发现 start/resume 的 help 只讲 feature switch，未说明缺 decider 时整个 server 不能启动。`server/cmd/multica/cmd_cr_pipeline.go` 两处 help 均补充此条件，不更改命令逻辑；raw SHA `13c5d729ec5bbdbb1a1395ea27bdc68aa1c730088194621545159c6e03141258`，LF。已纳入 CUSTOM #275。

`go build -o <独占临时目录>/multica.exe ./cmd/multica` exit 0，未运行可执行文件；删除自有二进制并核空删除自有目录。未运行有 TestMain 的 cmd/multica 包测试，未做 DB/容器/真实 CR 操作。此处是构建和 help 文本证据，不是启动、服务可用性或 Gate3 验收。
