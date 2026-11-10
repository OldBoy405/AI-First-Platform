# CLI help 措辞补正

针对独立强审指出“configured decider”可能让运维误认为当前已有可用配置开关，保全其审过的 `source-cli-review/cmd_cr_pipeline.go`（raw SHA `13c5d729ec5bbdbb1a1395ea27bdc68aa1c730088194621545159c6e03141258`），把 start/resume 两处 help 补正为：runner 组合需要非 nil decider，否则 server 拒绝启动；当前 server main 不提供。非 nil 不是可信性证明。命令逻辑未变。

新源 raw SHA `9829b5d606d9e70ab3bd7c6d1592f78e1faea44634b3edfac22d75991e3a5a33`。作者 `go build -o <独占临时目录>/multica.exe ./cmd/multica` exit 0，源码哈希前后一致；没有运行程序，删除自有二进制、核空删除自有目录。新措辞未独立复核；未测 DB、真实启动、容器或 CR。
