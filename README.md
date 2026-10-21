# ClaudeWhy Collector / 溯因采集器

A local macOS diagnostic collector for reviewing system settings and selected terminal-session metadata. No telemetry, account login, or network probing. The interface is currently in Chinese.

用于在本机采集、预览和导出诊断信息的 macOS 工具。所有采集项默认关闭，用户选择范围后才读取数据，导出前可以检查 JSON。工具不判断账号封禁原因。

## 下载与使用

需要 **macOS 13+**，支持 Apple Silicon 和 Intel。

从 [Releases](https://github.com/Grimnirobser/claudewhy-collector/releases) 下载：

- `.dmg`：打开后，把“溯因采集器.app”拖到应用程序文件夹。
- `.pkg`：安装到 `/Applications`；安装器可能按系统权限策略要求授权，采集器本身不请求管理员权限。
- `SHA256SUMS.txt`：核对下载文件的 SHA-256。

当前版本使用 ad-hoc 本地签名，**没有 Developer ID 签名或 Apple 公证**，系统可能阻止运行。也可以阅读源码后自行构建。不要关闭系统安全防护。

打开应用后：

1. 勾选系统信息、当前网络配置或会话元数据。
2. 如需会话记录，手动选择保存终端 JSONL 日志的目录。不会自动扫描用户主目录。
3. 点击“扫描并预览”，检查提取结果。
4. 点击“导出诊断 JSON”，自行选择保存位置。文件不会自动上传。

导出格式为 `ban-evidence-diagnostic`，schemaVersion `1.0`，可导入 ClaudeWhy 的本地分析工具，也可以使用文本编辑器检查。源码版和预编译版本均保留“溯因采集器”这个应用名称。

## 采集范围

| 项目 | 导出的信息 |
| --- | --- |
| 系统 | 系统版本、处理器架构、当前时区 |
| 网络 | HTTP/HTTPS/SOCKS/自动代理启用状态、DNS 服务器数量、默认路由是否存在 |
| 会话 | 允许的事件类型、时间、会话/消息/请求 ID、消息角色、token 用量、明确记录的 HTTP 状态码 |
| 来源 | 匿名文件编号、SHA-256、字节数、修改时间 |

不导出聊天正文、工具输入输出、完整文件路径、代理/DNS/路由地址或凭据文件内容。为了从明确标记的错误事件中提取状态码，正文可能在内存中被检查，但不会被写入报告。**ID、时间、时区、用量和文件哈希仍可能用于关联记录；元数据并不等于完全匿名。** 分享前请自行审核。

网络信息来自本机只读命令，不向外部服务查询出口 IP。快照仅代表采集时刻，不能恢复未保存的历史配置。错误、缺失和跳过状态需分别理解；未知不等于关闭或正常。

## 从源码构建 / Build from source

在 macOS 上安装 Xcode Command Line Tools 和 Python 3。没有第三方 Swift 包或 Python 包依赖。

```sh
git clone https://github.com/Grimnirobser/claudewhy-collector.git
cd claudewhy-collector
./build.sh
python3 test-fixtures.py
```

脚本分别编译 arm64 和 x86_64，并生成：

```text
build/溯因采集器.app
dist/Suyin-Collector-0.2.0-universal.dmg
dist/Suyin-Collector-0.2.0-universal.pkg
dist/SHA256SUMS.txt
dist/download-info.json
```

构建不会安装应用、读取用户日志或发布文件。产物留在仓库内的 `build/` 和 `dist/`，这些目录不进入 Git。安装包包含构建时间等信息，不保证逐字节可复现。

测试仅创建临时合成日志，明确跳过系统和网络采集，验证元数据白名单、错误码提取、文件哈希、无效行、超限文件、符号链接、空目录及读取错误。测试输出在 `test-evidence/`，不提交到仓库。

## 限制与开发

- 每个 JSONL 文件最多 20 MiB，合计读取最多 100 MiB，最多处理 100,000 行；跳过隐藏文件、符号链接和非 JSONL 文件。
- 预览最多显示 200,000 个字符；导出保留完整的已提取数据。
- 系统命令约 8 秒超时，必要时终止进程；只读取当前配置，不修改网络设置。
- 尚未覆盖所有 macOS 版本及网络配置；没有 Windows/Linux 版本，也不保证能确定异常原因。

欢迎通过 Issues 和 Pull Requests 提交问题与修改。请使用合成、脱敏的最小示例，**不要提交真实会话日志、诊断文件或凭据**。涉及采集范围或导出字段的修改，请同步说明并补充隐私边界测试。

## License

[MIT](LICENSE) · Shinerain LLC
