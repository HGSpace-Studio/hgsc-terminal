# 插件 API

插件文件需要暴露 `setup(bot)`。如果插件需要释放资源，可以再暴露 `teardown(bot)`，插件禁用或重载前会调用它。

插件由 `PluginManager` 加载，框架会自动维护当前插件身份。插件不需要手动传插件名，也不要直接绕过 `ctx`、`ctx.client` 或 `ctx.bot` 调用敏感能力。

推荐使用目录插件：

```text
plugins/ping/
  plugin.toml
  main.py
```

`plugin.toml`：

```toml
name = "ping"
version = "0.2.0"
author = "HGSpace Studio"
description = "基础在线测试命令。"
entry = "main.py"
permissions = ["send_message", "read_members", "storage"]

[[config]]
key = "reply_text"
type = "string"
default = "pong"
description = "ping 回复文本"
```

字段说明：

- `name`：插件显示名，通常和目录名一致。
- `version`：插件版本。
- `author`：作者。
- `description`：说明。
- `entry`：入口文件，必须是插件目录内的相对路径。
- `permissions`：权限声明。插件没声明权限却调用对应 API 时会被拒绝，并写入日志和事件线。
- `config`：配置 schema，用于默认值、Web 面板配置表单和 CLI 检查。

已支持权限：

- `send_message`：发送群消息、返回字符串自动发送、发送图片。
- `read_members`：读取群成员、查找成员、判断管理员或群主。
- `storage`：使用 `ctx.store`。
- `manage_plugins`：启用、禁用、重载插件。
- `manage_tasks`：启用、禁用定时任务。
- `edit_plugin_source`：通过 Web 面板编辑插件源码。
- `read_storage`：Web 面板读取插件存储键。
- `read_events`：Web 面板读取事件线。
- `logging`：声明插件会写日志，当前不拦截。

配置类型支持：

- `string`
- `integer`
- `number`
- `boolean`

仍然兼容旧式单文件插件：

```text
plugins/ping.py
```

```python
def setup(bot):
    @bot.command("ping")
    def ping(ctx):
        return "pong"

def teardown(bot):
    pass
```

## 注册命令

```python
@bot.command("ping", aliases=("p",), help="测试 bot 是否在线")
def ping(ctx):
    return "pong"
```

命令可以加群身份限制和冷却：

```python
@bot.command("reload", admin_only=True, cooldown=5)
def reload_plugin(ctx):
    ctx.bot.reload_plugin(ctx.arg_text)
    return "ok"
```

- `admin_only=True`：仅管理员或群主可用，需要插件声明 `read_members`。
- `owner_only=True`：仅群主可用，需要插件声明 `read_members`。
- `cooldown=5`：同一个发送者 5 秒内只能触发一次。

命令函数可以返回字符串，框架会自动回复到当前群。也可以返回 `None`，由插件自己调用发送 API。

`CommandContext` 常用字段：

- `ctx.bot`：当前 `GroupBot`。
- `ctx.client`：当前插件的受限 API 客户端，发送消息和读取群成员也会检查权限。
- `ctx.room_id`：当前群号。
- `ctx.message`：原始消息对象。
- `ctx.prefix`：本次匹配到的命令前缀。
- `ctx.command`：命令名。
- `ctx.args`：按空白拆分后的参数列表。
- `ctx.arg_text`：命令后的完整参数文本。
- `ctx.plugin`：当前插件名。
- `ctx.config`：当前插件私有配置。
- `ctx.sender_id`：发送者 UID。
- `ctx.sender_name`：发送者显示名。
- `ctx.message_id`：消息 ID。
- `ctx.log`：bot logger。
- `ctx.store`：当前插件的持久化存储。

`CommandContext` 常用方法：

- `ctx.reply(content, quote=False, mention_sender=False)`：回复当前群，可选引用原消息或 @ 发送者。
- `ctx.send_group(room_id, content, **kwargs)`：发送到指定群。
- `ctx.send_all(content)`：发送到所有监听群。
- `ctx.members()`：获取当前群成员列表。
- `ctx.sender_member()`：获取发送者的群成员信息。
- `ctx.find_member(query)`：按 UID、昵称、用户名或备注查找群成员。
- `ctx.mention(uid=None)`：返回 `@UID` 文本。
- `ctx.is_admin()`：发送者是否为管理员或群主。
- `ctx.is_owner()`：发送者是否为群主。

`ctx.client` 支持：

- `current_user()`：当前登录用户。
- `groups()`：群列表。
- `friends()`：好友列表。
- `group_messages(room_id, **kwargs)`：读取群消息。
- `group_messages_after(room_id, after_id, **kwargs)`：读取指定消息之后的新消息。
- `mark_group_read(room_id, last_msg_id=0)`：标记群消息已读。
- `group_members(room_id)`：读取群成员，需要 `read_members`。
- `send_group_message(room_id, content, reply_to=0, mention_uids=None)`：发送群消息，需要 `send_message`。
- `send_group_image(room_id, image_path, content="", reply_to=0, mention_uids=None)`：发送群图片，需要 `send_message`。

## 监听普通群消息

```python
@bot.on_group_message
def on_message(event):
    if "关键词" in event.message.body:
        event.reply("匹配到了关键词")
```

`GroupMessageEvent` 常用字段和方法与命令上下文类似：

- `event.bot`
- `event.client`
- `event.room_id`
- `event.message`
- `event.plugin`
- `event.config`
- `event.sender_id`
- `event.sender_name`
- `event.message_id`
- `event.log`
- `event.store`
- `event.reply(...)`
- `event.send_group(...)`
- `event.send_all(...)`
- `event.members()`
- `event.sender_member()`
- `event.find_member(...)`
- `event.is_admin()`
- `event.is_owner()`

消息处理器也可以返回字符串，框架会自动发送到当前群。

## 注册定时任务

```python
@bot.interval(60, name="heartbeat", room_ids=None, enabled=True)
def heartbeat(ctx):
    return f"heartbeat #{ctx.run_count}"
```

- `seconds`：间隔秒数。
- `name`：任务名，会用于配置里的 `[tasks]` 开关。
- `room_ids=None`：发送到所有监听群。
- `room_ids=[123456]`：只发送到指定群。
- `enabled`：默认是否启用，会被配置里的 `[tasks]` 覆盖。

定时任务异常会写入日志和事件线，不会中断主轮询。

`IntervalContext` 常用字段：

- `ctx.bot`
- `ctx.client`
- `ctx.task_name`
- `ctx.run_count`
- `ctx.plugin`
- `ctx.config`
- `ctx.log`
- `ctx.store`

`IntervalContext` 常用方法：

- `ctx.send_group(room_id, content)`
- `ctx.send_all(content)`
- `ctx.task_enabled(name)`
- `ctx.set_task_enabled(name, enabled)`

## 插件存储

每个插件有独立命名空间：

```python
count = ctx.store.incr("ping_count")
ctx.store.set("last_sender", ctx.sender_id)
last_sender = ctx.store.get("last_sender", 0)
all_values = ctx.store.all()
ctx.store.delete("last_sender")
```

支持的 API：

- `store.get(key, default=None)`：读取值。
- `store.set(key, value)`：保存值，值必须能 JSON 序列化。
- `store.delete(key)`：删除键，返回是否真的删除。
- `store.clear()`：清空当前插件命名空间。
- `store.all()`：返回当前插件所有数据。
- `store.incr(key, amount=1)`：整数自增。

example 项目默认写入 `bot/example/data/plugins.json`。

## 插件私有配置

在 `config.toml` 里写：

```toml
[plugin.ping]
reply_text = "pong"

[plugin.heartbeat]
interval = 60
text = "heartbeat"
```

插件里读取：

```python
reply_text = ctx.config.get("reply_text", "pong")
interval = bot.plugin_settings("heartbeat").get("interval", 60)
```

上下文里的 `ctx.config` 会自动按当前插件名读取。注册任务这类发生在 `setup(bot)` 阶段的逻辑，可以用 `bot.plugin_settings("插件名")`。

Web 面板会根据 `plugin.toml` 的 `[[config]]` 自动生成配置表单。保存后会写回 `config.toml` 的 `[plugin.<name>]` 段，并重载对应插件。

## 插件生命周期钩子

插件可以按需定义：

```python
def on_load(bot):
    pass

def on_unload(bot):
    pass

def on_bot_start(bot):
    pass

def on_bot_stop(bot):
    pass

def on_command_error(plugin, command, exc):
    pass

def on_task_error(plugin, task_name, exc):
    pass
```

框架会捕获钩子异常并写日志，不会中断主轮询。

## 运行时和权限

权限校验集中在 `PluginRuntime`，以下路径都会被拦截：

- 上下文方法，例如 `ctx.reply(...)`、`ctx.store`、`ctx.members()`。
- 插件客户端方法，例如 `ctx.client.send_group_message(...)`。
- bot 管理 API，例如 `ctx.bot.reload_plugin(...)`、`ctx.bot.set_task_enabled(...)`。

权限被拒绝时会：

- 抛出 `CsacPluginPermissionError`。
- 写入 logger。
- 写入事件线。
- 在 `PluginManager` 状态里记录 `permission_denied`，Web 面板会显示“缺权限调用”。

## 自动热重载

```toml
[plugins]
watch = true
watch_interval = 2.0
```

开启后，框架会监控插件入口文件和 `plugin.toml` 的修改时间，变化后自动重载插件。

## 插件开发 CLI

检查插件：

```powershell
py -m csacbot plugin check D:\Projects\Go\HGSC-Terminal\bot\example\plugins\ping
```

创建插件：

```powershell
py -m csacbot plugin new hello --path D:\Projects\Go\HGSC-Terminal\bot\example\plugins
```

## Bot 管理 API

插件也可以通过 `ctx.bot` 控制任务和插件：

```python
ctx.bot.enable_task("heartbeat")
ctx.bot.disable_task("heartbeat")
task = ctx.bot.get_task("heartbeat")

ctx.bot.reload_plugin("ping")
ctx.bot.enable_plugin("echo")
ctx.bot.disable_plugin("echo")
plugins = ctx.bot.plugin_status()
```

可用 API：

- `bot.get_task(name)`：返回任务快照或 `None`。
- `bot.enable_task(name)` / `bot.disable_task(name)`：启用或禁用任务。
- `bot.set_task_enabled(name, enabled)`：设置任务开关。
- `bot.plugin_status()`：返回插件状态列表。
- `bot.reload_plugin(name)`：重载单个插件。
- `bot.reload_plugins()`：重载全部插件。
- `bot.enable_plugin(name)` / `bot.disable_plugin(name)`：启用或禁用插件。
- `bot.set_plugin_enabled(name, enabled)`：设置插件开关。
- `bot.group_members(room_id)`：获取群成员。
- `bot.find_member(room_id, query)`：查找群成员。
- `bot.send_group(room_id, content, **kwargs)`：发群消息。
- `bot.send_all(content)`：发到所有监听群。
- `bot.record_event(kind, detail, ...)`：写入 Web 面板事件线。
