# CsAC Bot Python 库

这是一个放在仓库内的 CsAC bot 框架。客户端标识为 `bot-leon-0.1.0`，登录时会通过 `platform` 参数发送给服务端。

## 安装

```powershell
cd D:\Projects\Go\CsAC-Terminal\bot
py -m pip install -e .
```

依赖：

- `requests`：HTTP 会话和 Cookie。
- `pycryptodome`：处理 CsAC 服务端可能返回的 `__test` AES JavaScript 防护挑战。

## 群命令 bot 示例

先复制配置文件并填入自己的 API 地址、账号、密码和群号：

```powershell
$src = "D:\Projects\Go\CsAC-Terminal\bot\example\config.example.toml"
$dst = "D:\Projects\Go\CsAC-Terminal\bot\example\config.toml"
Copy-Item $src $dst
notepad $dst
```

运行：

```powershell
py D:\Projects\Go\CsAC-Terminal\bot\example\group_command_bot.py --config D:\Projects\Go\CsAC-Terminal\bot\example\config.toml
```

示例支持：

- `/ping`
- `/echo 文本`
- `/say 文本`
- `/whoami`
- `/member 昵称或UID`
- `/help`
- `heartbeat` 定时任务
- Web 控制台：`http://127.0.0.1:8765`

## 最小用法

```python
from csacbot import CsacClient, GroupBot

client = CsacClient(base_url="https://example.com/rpc/UniCsAC.php")
client.login("username", "password")

bot = GroupBot(client, room_ids=[123456])

@bot.command("ping")
def ping(ctx):
    return "pong"

bot.run_forever()
```

## 插件

示例项目里的插件会从 `plugins.paths` 中查找。相对路径以配置文件所在目录为基准：

```toml
[plugins]
enabled = ["ping", "echo"]
paths = ["plugins"]
```

推荐使用目录插件：

```text
plugins/ping/
  plugin.toml
  main.py
```

`plugin.toml` 用来声明名称、版本、作者、说明、入口文件和权限：

```toml
name = "ping"
version = "0.2.0"
author = "CsAC Team"
description = "基础在线测试命令。"
entry = "main.py"
permissions = ["send_message", "read_members", "storage"]

[[config]]
key = "reply_text"
type = "string"
default = "pong"
description = "ping 回复文本"
```

入口文件只需要暴露 `setup(bot)`：

```python
def setup(bot):
    @bot.command("ping", help="测试 bot 是否在线")
    def ping(ctx):
        return "pong"
```

仍然兼容旧式 `plugins/ping.py` 单文件插件。

框架内部已经把插件运行时、上下文、manifest 解析、模块加载、生命周期管理和开发 CLI 拆成独立模块。开发者文档里的 `architecture.md` 说明了每个模块的边界。

插件也可以注册定时任务：

```python
def setup(bot):
    @bot.interval(60, name="heartbeat", room_ids=None, enabled=True)
    def heartbeat(ctx):
        return f"heartbeat #{ctx.run_count}"
```

`room_ids=None` 表示发送到所有监听群；也可以写 `room_ids=[123456]` 只发到指定群。定时任务异常会写入 logger，不会中断主轮询。

配置里可以开关任务：

```toml
[tasks]
heartbeat = true
```

示例还包含一个 `web_panel` 插件，可以通过网页查看配置、状态、命令、定时任务和最近的接收/发送/任务事件线，并能启用或禁用任务：

```toml
[web_panel]
enabled = true
host = "127.0.0.1"
port = 8765
```

Web 控制台也可以管理插件：

- 查看插件是否启用、是否加载成功、文件路径、最后加载时间和错误。
- 启用或禁用插件。
- 重载单个插件。
- 重载全部插件。
- 查看插件源码。
- 在线编辑示例项目 `plugins.paths` 下的 `.py` 插件，保存后自动重载。

重载插件时，框架会先卸载旧插件注册的命令、消息处理器和定时任务，再执行新的 `setup(bot)`。如果插件提供 `teardown(bot)`，禁用或重载前会先调用它。`web_panel` 自身也支持 `teardown`，但在网页里操作它自己时当前页面连接可能会中断，刷新页面即可确认结果。

## 插件 API 和持久化存储

命令、消息监听和定时任务上下文都提供常用插件 API：

- `ctx.log`：写日志。
- `ctx.store`：当前插件的持久化存储。
- `ctx.config`：当前插件私有配置。
- `ctx.client`：当前插件的受限 API 客户端，敏感方法会做权限校验。
- `ctx.reply(...)` / `ctx.send_group(...)` / `ctx.send_all(...)`：发送消息。
- `ctx.members()` / `ctx.find_member(...)` / `ctx.sender_member()`：读取群成员。
- `ctx.is_admin()` / `ctx.is_owner()`：判断发送者群身份。

插件存储默认由 example 注入：

```toml
[storage]
file = "data/plugins.json"
```

插件可以这样保存状态：

```python
count = ctx.store.incr("ping_count")
ctx.store.set("last_sender", ctx.sender_id)
```

插件私有配置写在 `config.toml`：

```toml
[plugin.ping]
reply_text = "pong"
```

插件权限会强校验。未声明 `send_message`、`read_members`、`storage`、`manage_plugins`、`manage_tasks`、`edit_plugin_source` 等权限却调用对应 API，会被拒绝并写入日志。

命令支持群身份限制和冷却：

```python
@bot.command("reload", admin_only=True, cooldown=5)
def reload_plugin(ctx):
    ctx.bot.reload_plugin(ctx.arg_text)
    return "ok"
```

插件可以定义 `on_load`、`on_unload`、`on_bot_start`、`on_bot_stop`、`on_command_error`、`on_task_error` 钩子。

可开启插件自动热重载：

```toml
[plugins]
watch = true
watch_interval = 2.0
```

插件开发 CLI：

```powershell
py -m csacbot plugin check D:\Projects\Go\CsAC-Terminal\bot\example\plugins\ping
py -m csacbot plugin new hello --path D:\Projects\Go\CsAC-Terminal\bot\example\plugins
```

更完整的开发者文档在 `bot/docs`：

- `bot/docs/architecture.md`
- `bot/docs/configuration.md`
- `bot/docs/plugin-api.md`
- `bot/docs/example-plugins.md`
- `bot/docs/running-example.md`

## 会话和日志

示例会把登录 Cookie 保存到 `session.file`，下次启动会先尝试复用会话；如果会话失效，会用配置里的账号密码重新登录。

```toml
[session]
save = true
file = "session.json"
```

日志使用 Python 标准 `logging`，可以同时输出到控制台和文件：

```toml
[logging]
level = "INFO"
file = "logs/bot.log"
console = true
```

`config.toml`、`session.json`、`logs/` 和 `data/` 都已加入 `.gitignore`。

## 库能力

- 自动保存同一个 `requests.Session` 内的 PHP Session Cookie。
- 库本身不内置 API 地址，调用方必须创建 `CsacClient(base_url=...)`。
- 自动处理服务端 `__test` JavaScript 防护挑战。
- 支持 TOML 配置文件、插件加载、会话持久化和日志配置。
- 支持插件 JSON 持久化存储。
- 支持登录、登出、当前用户、群列表、群成员、群消息拉取、发送群消息、标记已读。
- 支持群消息轮询、命令前缀、命令别名、内置 `/help`。
- 命令函数可以直接 `return str`，框架会自动回复到群里。
