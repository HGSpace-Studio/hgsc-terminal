# HGSC Bot 开发者文档

这里记录 Python bot 框架的架构、配置、插件写法和插件 API。示例项目在 `bot/example`，可以作为一个完整项目直接复制改造。

## 文档目录

- `architecture.md`：框架模块边界和运行流程。
- `configuration.md`：`config.toml` 每个配置项的说明。
- `plugin-api.md`：命令、消息监听、定时任务、插件存储、插件管理 API。
- `example-plugins.md`：示例插件的功能和可参考写法。
- `running-example.md`：安装、配置和运行 example 项目。

## 基本原则

- 库不内置 API 地址，调用方必须创建 `CsacClient(base_url=...)` 或通过配置传入。
- 插件只通过 `setup(bot)` 注册命令、消息处理器和定时任务。
- 插件身份、权限校验、插件上下文都由框架运行时统一管理，插件不要绕过 `ctx` 或 `bot` 暴露的 API。
- 插件自己的运行状态建议写入 `ctx.store`，不要把数据写死在代码里。
- 插件元信息和配置 schema 写在 `plugin.toml`，Web 面板和 CLI 都从这里读取。
- `config.toml`、`session.json`、`logs/`、`data/` 属于本地运行数据，不应提交到仓库。
