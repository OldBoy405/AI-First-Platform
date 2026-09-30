# 作废的首轮尝试（不计入证据）

首次运行 `run_one.sh merged` 时 `DATABASE_URL` 取的是 postgres 容器自身 env 的 `POSTGRES_PASSWORD`（7 字符，非应用角色口令），
迁移与套件均在 SASL 认证失败下运行（`migrate_exit=1`，DB 类 TestMain 全部走「Skips tests」分支），**结果无效**，仅留档。
正确的口令来源是 multica 仓 `.env` 的 `DATABASE_URL`（与第七次同步一致）；修正后重跑，日志见上级目录。
