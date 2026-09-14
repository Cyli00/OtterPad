# 提交与日志中的敏感信息

凭据文件留在 Git 之外，运行时密钥继续使用现有安全存储。`.gitignore` 排除环境文件、认证文件和签名密钥；不要强制添加这些文件。

本地启用提交检查：

```bash
git config core.hooksPath .githooks
uv run --no-project python scripts/check_secrets.py --staged
```

检查读取暂存区的实际字节，拦截受保护文件名、已知 Token 格式、URL 内嵌密码和疑似凭据常量。只输出文件、行号和规则；受保护文件直接拒绝，不读取内容。它不联网验证密钥。CI 使用 `--tracked` 检查整个索引，并运行 `scripts/test_check_secrets.py` 的合成回归。

`lib/core/app_logger.dart` 在控制台与日志文件输出前统一调用 `redactLogText`，遮盖认证头、凭据字段、签名查询参数和本机用户名。调用方仍应避免记录完整请求／响应、文献正文和绝对资料路径；自动脱敏不能识别任意形式的私密内容。

截图、压缩包和历史提交需要单独审计，文本提交检查不替代这部分检查。根目录 `test/` 是被忽略的本地回归集，其中的个人样本、认证文件及结果包不进入提交或 CI。
