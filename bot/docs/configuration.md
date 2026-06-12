# 配置说明

示例配置文件：`bot/example/config.example.toml`。

## 顶层配置

```toml
base_url = "https://example.com/rpc/UniCsAC.php"
username = "bot_username"
password = "bot_password"
room_ids = [123456]
prefixes = ["/", "!", "！"]
poll_interval = 2.0
ignore_self = true
replay_existing = false
mark_read = false
```

- `base_url`：HGSC API 入口地址。库不会写死 API 地址，必须由调用库的项目提供。
- `username`：bot 登录用户名。
- `password`：bot 登录密码。
- `room_ids`：监听的群号列表，至少需要一个群号。
- `prefixes`：命令前缀列表，例如 `/ping`、`!ping`。
- `poll_interval`：主轮询间隔，单位秒。
- `ignore_self`：是否忽略 bot 自己发出的消息，通常保持 `true`。
- `replay_existing`：启动时是否处理已有历史消息。`false` 表示启动时先记录当前最新消息，只处理之后的新消息。
- `mark_read`：拉取消息后是否调用标记已读接口。

## 插件

```toml
[plugins]
enabled = ["ping", "echo", "heartbeat", "web_panel"]
paths = ["plugins"]
watch = true
watch_interval = 2.0

[plugin.ping]
reply_text = "pong"

[plugin.heartbeat]
interval = 60
text = "heartbeat"
```

- `plugins.enabled`：启动时加载的插件名列表。插件名可以是 `paths` 下的 `ping.py`，也可以是可导入的 Python 模块名。
- `plugins.paths`：插件搜索目录。相对路径以 `config.toml` 所在目录为基准。
- `plugins.watch`：是否启用插件文件自动热重载。
- `plugins.watch_interval`：热重载检查间隔，单位秒。

`plugins.enabled` 里的每一项会按这个顺序解析：

1. 如果看起来像路径，直接加载该 `.py` 文件或目录插件。
2. 在 `plugins.paths` 里查找同名目录插件，例如 `plugins/ping/plugin.toml`。
3. 在 `plugins.paths` 里查找同名单文件插件，例如 `plugins/ping.py`。
4. 按 Python 模块名导入。

目录插件的 `plugin.toml` 由 `plugin_manifest.py` 解析。`entry` 必须是插件目录内的相对路径。

## 插件私有配置

- `plugin.<插件名>`：插件私有配置表。框架会先应用 `plugin.toml` 里 `[[config]]` 的默认值，再用这里的值覆盖。插件通过 `ctx.config` 或 `bot.plugin_settings("插件名")` 读取最终配置。
- `plugin.ping.reply_text`：example 的 `ping` 插件回复前缀。
- `plugin.heartbeat.interval`：example 的 `heartbeat` 定时任务间隔，单位秒。
- `plugin.heartbeat.text`：example 的 `heartbeat` 定时任务消息前缀。

支持的配置 schema 类型：

- `string`
- `integer`
- `number`
- `boolean`

## 会话

```toml
[session]
save = true
file = "session.json"
```

- `session.save`：是否保存登录 Cookie。
- `session.file`：Cookie 会话文件。相对路径以配置文件所在目录为基准。

HGSC 使用 PHP Session Cookie 认证。启用会话保存后，下次启动会先复用 Cookie；如果会话失效，runner 会用账号密码重新登录。

## 日志

```toml
[logging]
level = "INFO"
file = "logs/bot.log"
console = true
```

- `logging.level`：日志级别，例如 `DEBUG`、`INFO`、`WARNING`、`ERROR`。
- `logging.file`：日志文件路径。留空表示不写文件。
- `logging.console`：是否输出到控制台。

## 定时任务开关

```toml
[tasks]
heartbeat = true
```

这里的键是定时任务名，值是是否启用。插件注册任务时的默认 `enabled` 会被这里覆盖。

## 插件存储

```toml
[storage]
file = "data/plugins.json"
```

- `storage.file`：插件持久化数据文件。相对路径以配置文件所在目录为基准。

插件可以通过 `ctx.store` 保存 JSON 可序列化数据。示例：`ctx.store.set("count", 1)`。

## Web 控制台

```toml
[web_panel]
enabled = true
host = "127.0.0.1"
port = 8765
```

- `web_panel.enabled`：是否启用 example 里的 `web_panel` 插件。
- `web_panel.host`：监听地址。默认 `127.0.0.1` 只允许本机访问。
- `web_panel.port`：监听端口。
