# 框架架构

`csacbot` 现在按职责拆分插件框架，避免把加载、运行时、权限和上下文逻辑都堆在一个文件里。

## 模块职责

```text
csacbot/
  client.py            CsAC HTTP API、Cookie 会话、防护挑战处理
  bot.py               GroupBot：轮询、命令派发、任务调度、事件线
  plugin_runtime.py    插件注册期/执行期身份、权限强校验、PluginClient
  plugin_context.py    CommandContext、GroupMessageEvent、IntervalContext
  plugin_manifest.py   plugin.toml 解析、权限常量、配置 schema
  plugin_loader.py     插件解析和模块加载
  plugins.py           PluginManager：状态、生命周期、热重载、钩子
  plugin_devtools.py   CLI 检查和插件脚手架
  store.py             插件 JSON 存储
  config.py            example 项目的 TOML 配置解析
```

## 运行流程

1. 调用方创建 `CsacClient(base_url=...)`。库本身不写死 API 地址。
2. example 读取 `config.toml`，创建 `GroupBot`。
3. `load_plugins(...)` 创建 `PluginManager` 并绑定到 `bot.plugin_manager`。
4. `PluginManager` 使用 `PluginResolver` 查找插件目录、单文件插件或 Python 模块。
5. 目录插件由 `plugin_manifest.py` 读取 `plugin.toml`，得到权限和配置 schema。
6. 加载插件时，`PluginRuntime.registration(name)` 标记注册期插件身份，插件在 `setup(bot)` 里注册命令、消息处理器和定时任务。
7. 收到消息或运行任务时，`PluginRuntime.execution(name)` 标记执行期插件身份。
8. 插件通过 `ctx`、`ctx.client`、`ctx.bot` 调用敏感 API 时，`PluginRuntime.require(...)` 做权限强校验。
9. 如果开启 `plugins.watch`，`PluginManager` 监控入口文件和 `plugin.toml` 的修改时间，变化后自动重载。

## 插件身份

框架区分两个插件身份：

- 注册期身份：插件执行 `setup(bot)` 时的插件名，用来记录它注册了哪些命令、任务和消息处理器。
- 执行期身份：命令、消息处理器、任务或 Web 面板调用管理 API 时的插件名，用来做权限校验。

插件不需要自己设置身份。只要通过 `PluginManager` 加载，框架会自动维护这两个身份。

## 权限边界

权限声明写在 `plugin.toml`：

```toml
permissions = ["send_message", "storage"]
```

敏感 API 会集中经过 `PluginRuntime`：

- `send_message`：`ctx.reply(...)`、`ctx.send_group(...)`、`ctx.send_all(...)`、`ctx.client.send_group_message(...)`。
- `read_members`：`ctx.members()`、`ctx.find_member(...)`、`ctx.sender_member()`、`ctx.is_admin()`、`ctx.is_owner()`。
- `storage`：`ctx.store`。
- `manage_plugins`：启用、禁用、重载插件。
- `manage_tasks`：启用、禁用定时任务。
- `read_events`：读取事件线。
- `read_storage`：Web 面板读取插件存储状态。
- `edit_plugin_source`：Web 面板编辑插件源码。

没有声明权限就调用对应 API，会抛出 `CsacPluginPermissionError`，并写入日志和事件线。Web 面板会显示“缺权限调用”。

## 插件加载格式

推荐目录插件：

```text
plugins/ping/
  plugin.toml
  main.py
```

也兼容：

- `plugins/ping.py`
- 可导入的 Python 模块名
- 直接传入 `.py` 文件路径

目录插件的 `entry` 必须是插件目录内的相对路径，不能指向目录外文件。

## 生命周期

插件可以定义：

- `setup(bot)`：必须，用来注册命令、消息处理器和定时任务。
- `teardown(bot)`：可选，禁用或重载前释放资源。
- `on_load(bot)`：插件加载成功后。
- `on_unload(bot)`：插件卸载时。
- `on_bot_start(bot)`：bot 启动后。
- `on_bot_stop(bot)`：bot 停止时。
- `on_command_error(plugin, command, exc)`：命令异常。
- `on_task_error(plugin, task_name, exc)`：任务异常。

钩子异常会写日志和事件线，不会中断主轮询。
