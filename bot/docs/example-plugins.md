# 示例插件

example 项目的插件目录：`bot/example/plugins`。

插件现在使用目录结构：

```text
plugins/ping/
  plugin.toml
  main.py
```

`plugin.toml` 用来声明名称、版本、作者、说明、入口文件和权限。

## ping

提供命令：

- `/ping` 或 `/p`：回复在线状态，回复前缀来自 `ctx.config["reply_text"]`，并用 `ctx.store.incr("ping_count")` 持久化响应次数。
- `/whoami`：显示发送者 UID、显示名和群身份。
- `/member 昵称或UID`：通过 `ctx.find_member(...)` 查找群成员。

这个插件展示了：

- 命令别名。
- 读取发送者信息。
- 使用插件持久化存储。
- 查询群成员。
- 判断管理员和群主。

## echo

提供命令：

- `/echo 文本`：复读文本。
- `/say 文本`：通过 `ctx.send_group(...)` 主动发送群消息，并写一条日志。

这个插件展示了：

- 使用 `ctx.arg_text` 获取完整参数。
- 命令函数返回字符串自动回复。
- 命令函数返回 `None` 后自行发送消息。
- 使用 `ctx.log` 记录日志。

## heartbeat

提供定时任务：

- `heartbeat`：每 60 秒向所有监听群发送一次心跳消息。

这个插件展示了：

- 从 `bot.plugin_settings("heartbeat")` 读取任务间隔和消息前缀。
- 注册间隔任务。
- 任务发送到所有监听群。
- 使用 `ctx.run_count` 获取任务运行次数。
- 使用 `ctx.store` 保存任务状态。
- 通过 `[tasks] heartbeat = true/false` 控制任务开关。

## web_panel

提供 Web 控制台：

- 查看 bot 运行状态。
- 查看命令列表。
- 查看定时任务状态并启用或禁用任务。
- 查看插件状态并启用、禁用、重载插件。
- 查看插件 manifest 信息、权限声明、权限状态和配置键。
- 显示权限是否正常、是否声明了未知权限、运行中是否发生过缺权限调用。
- 查看和编辑 `plugins.paths` 下的插件源码。
- 查看最近的接收、发送、命令和任务事件线。
- 查看插件存储里已有的键。

默认地址：

```text
http://127.0.0.1:8765
```

这个插件展示了：

- 插件里启动后台线程和 HTTP 服务。
- `teardown(bot)` 释放资源。
- 使用 `bot.plugin_status()`、`bot.reload_plugin(...)`、`bot.set_plugin_enabled(...)` 等管理 API。
- 通过 `bot.events` 和 `bot.interval_tasks` 构建状态页面。
- 根据 `plugin.toml` 的 `[[config]]` 自动生成插件配置表单。
