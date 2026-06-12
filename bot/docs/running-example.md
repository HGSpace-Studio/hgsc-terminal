# 运行 example 项目

## 安装库

```powershell
cd D:\Projects\Go\HGSC-Terminal\bot
py -m pip install -e .
```

也可以不安装，`bot/example/group_command_bot.py` 会把 `bot/src` 临时加入 `sys.path`。

## 准备配置

```powershell
Copy-Item D:\Projects\Go\HGSC-Terminal\bot\example\config.example.toml D:\Projects\Go\HGSC-Terminal\bot\example\config.toml
notepad D:\Projects\Go\HGSC-Terminal\bot\example\config.toml
```

至少需要修改：

- `base_url`
- `username`
- `password`
- `room_ids`

## 启动

```powershell
py D:\Projects\Go\HGSC-Terminal\bot\example\group_command_bot.py --config D:\Projects\Go\HGSC-Terminal\bot\example\config.toml
```

启动后可以在监听群里发送：

```text
/help
/ping
/whoami
/echo 你好
```

如果启用了 Web 控制台，浏览器打开：

```text
http://127.0.0.1:8765
```

## 插件开发命令

检查 example 插件：

```powershell
$env:PYTHONPATH = "D:\Projects\Go\HGSC-Terminal\bot\src"
py -m csacbot plugin check D:\Projects\Go\HGSC-Terminal\bot\example\plugins\ping
```

创建新插件：

```powershell
$env:PYTHONPATH = "D:\Projects\Go\HGSC-Terminal\bot\src"
py -m csacbot plugin new hello --path D:\Projects\Go\HGSC-Terminal\bot\example\plugins
```

## 本地运行数据

example 会生成这些本地文件：

- `bot/example/config.toml`
- `bot/example/session.json`
- `bot/example/logs/bot.log`
- `bot/example/data/plugins.json`

这些文件已经加入 `.gitignore`。
