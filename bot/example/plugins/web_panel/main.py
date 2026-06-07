from __future__ import annotations

import html
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


def setup(bot):
    config = getattr(bot, "config", None)
    if config is not None and not config.web_panel_enabled:
        bot.record_event("web_panel", "web panel disabled by config")
        return
    teardown(bot)
    host = getattr(config, "web_panel_host", "127.0.0.1") if config else "127.0.0.1"
    port = getattr(config, "web_panel_port", 8765) if config else 8765
    server = _PanelServer((host, int(port)), _PanelHandler, bot)
    thread = threading.Thread(target=server.serve_forever, name="csacbot-web-panel", daemon=True)
    thread.start()
    bot.web_panel_server = server
    bot.record_event("web_panel", f"web panel listening on http://{host}:{port}")


def teardown(bot):
    server = getattr(bot, "web_panel_server", None)
    if server is None:
        return
    server.shutdown()
    server.server_close()
    bot.web_panel_server = None
    bot.record_event("web_panel", "web panel stopped")


class _PanelServer(ThreadingHTTPServer):
    def __init__(self, address, handler, bot):
        super().__init__(address, handler)
        self.bot = bot


class _PanelHandler(BaseHTTPRequestHandler):
    server: _PanelServer

    def log_message(self, fmt, *args):
        self.server.bot.logger.debug("web panel: " + fmt, *args)

    def do_GET(self):
        with self.server.bot.active_plugin("web_panel"):
            self._do_GET()

    def _do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/":
            self._html(_render_index(self.server.bot))
            return
        if path == "/plugins/source":
            if not _panel_can(self.server.bot, "edit_plugin_source"):
                self.send_error(403, "web_panel missing edit_plugin_source permission")
                return
            query = parse_qs(parsed.query)
            name = query.get("name", [""])[0]
            self._html(_render_source(self.server.bot, name))
            return
        if path == "/api/status":
            self._json(_status(self.server.bot))
            return
        self.send_error(404)

    def do_POST(self):
        with self.server.bot.active_plugin("web_panel"):
            self._do_POST()

    def _do_POST(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        if parsed.path == "/tasks/toggle":
            if not _panel_can(self.server.bot, "manage_tasks"):
                self.send_error(403, "web_panel missing manage_tasks permission")
                return
            name = query.get("name", [""])[0]
            enabled = query.get("enabled", [""])[0].lower() in {"1", "true", "yes", "on"}
            ok = self.server.bot.set_task_enabled(name, enabled)
            if not ok:
                self.send_error(404, "task not found")
                return
            self._redirect()
            return
        if parsed.path == "/plugins/toggle":
            if not _panel_can(self.server.bot, "manage_plugins"):
                self.send_error(403, "web_panel missing manage_plugins permission")
                return
            name = query.get("name", [""])[0]
            enabled = query.get("enabled", [""])[0].lower() in {"1", "true", "yes", "on"}
            if not self.server.bot.set_plugin_enabled(name, enabled):
                self.send_error(404, "plugin manager not found")
                return
            self._redirect()
            return
        if parsed.path == "/plugins/reload":
            if not _panel_can(self.server.bot, "manage_plugins"):
                self.send_error(403, "web_panel missing manage_plugins permission")
                return
            name = query.get("name", [""])[0]
            if name:
                ok = self.server.bot.reload_plugin(name)
            else:
                ok = bool(self.server.bot.reload_plugins())
            if not ok and name:
                self.send_error(404, "plugin manager not found")
                return
            self._redirect()
            return
        if parsed.path == "/plugins/save":
            if not _panel_can(self.server.bot, "edit_plugin_source"):
                self.send_error(403, "web_panel missing edit_plugin_source permission")
                return
            manager = getattr(self.server.bot, "plugin_manager", None)
            if manager is None:
                self.send_error(404, "plugin manager not found")
                return
            query = parse_qs(parsed.query)
            name = query.get("name", [""])[0]
            body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            form = parse_qs(body.decode("utf-8", "replace"))
            source = form.get("source", [""])[0]
            if not _save_plugin_source(manager, name, source):
                self.send_error(404, "plugin source not found")
                return
            manager.reload(name)
            self._redirect(f"/plugins/source?name={name}")
            return
        if parsed.path == "/plugins/config":
            if not _panel_can(self.server.bot, "manage_plugins"):
                self.send_error(403, "web_panel missing manage_plugins permission")
                return
            name = query.get("name", [""])[0]
            body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            form = parse_qs(body.decode("utf-8", "replace"))
            if not _save_plugin_config(self.server.bot, name, form):
                self.send_error(404, "plugin config not found")
                return
            self._redirect()
            return
        self.send_error(404)

    def _redirect(self, location="/"):
        self.send_response(303)
        self.send_header("Location", location)
        self.end_headers()

    def _json(self, payload):
        body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _html(self, body):
        data = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def _status(bot):
    return {
        "running": bot.running,
        "rooms": bot.room_ids,
        "prefixes": bot.prefixes,
        "me": {
            "uid": bot.me.uid if bot.me else 0,
            "name": bot.me.display_name if bot.me else "",
        },
        "last_ids": bot.last_ids,
        "commands": [
            {"name": name, "aliases": aliases, "help": help_text}
            for name, aliases, help_text in bot.commands
        ],
        "tasks": bot.interval_tasks,
        "plugins": bot.plugin_status(),
        "storage": _storage_status(bot) if _panel_can(bot, "read_storage") else {},
        "events": [_event_dict(event) for event in bot.events[-100:]],
    }


def _storage_status(bot):
    storage = getattr(bot, "storage", None)
    if storage is None or not hasattr(storage, "snapshot"):
        return {}
    return {
        plugin: sorted(values.keys())
        for plugin, values in storage.snapshot().items()
    }


def _event_dict(event):
    return {
        "time": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(event.time)),
        "kind": event.kind,
        "detail": event.detail,
        "room_id": event.room_id,
        "task": event.task,
        "message_id": event.message_id,
        "sender_id": event.sender_id,
        "command": event.command,
    }


def _render_index(bot):
    status = _status(bot)
    title = bot.plugin_settings("web_panel").get("title", "CsAC Bot Panel")
    plugin_rows = "".join(_plugin_row(plugin) for plugin in status["plugins"])
    config_panels = "".join(_plugin_config_panel(bot, plugin) for plugin in status["plugins"])
    task_rows = "".join(_task_row(task) for task in status["tasks"])
    storage_rows = "".join(
        f"<tr><td>{_e(plugin)}</td><td>{_e(', '.join(keys))}</td></tr>"
        for plugin, keys in status["storage"].items()
    )
    command_rows = "".join(
        f"<tr><td>{_e(cmd['name'])}</td><td>{_e(', '.join(cmd['aliases']))}</td><td>{_e(cmd['help'])}</td></tr>"
        for cmd in status["commands"]
    )
    event_rows = "".join(_event_row(event) for event in reversed(status["events"]))
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{_e(title)}</title>
  <style>
    body {{ font-family: system-ui, sans-serif; margin: 24px; color: #1f2937; }}
    h1, h2 {{ margin: 20px 0 10px; }}
    table {{ border-collapse: collapse; width: 100%; margin-bottom: 18px; }}
    th, td {{ border: 1px solid #d1d5db; padding: 8px; text-align: left; vertical-align: top; }}
    th {{ background: #f3f4f6; }}
    code {{ background: #f3f4f6; padding: 2px 5px; border-radius: 4px; }}
    button {{ padding: 5px 10px; }}
    .config-form {{ border: 1px solid #d1d5db; padding: 12px; margin-bottom: 12px; }}
    .config-form label {{ display: block; margin: 8px 0 2px; }}
    .config-form span {{ display: inline-block; min-width: 140px; font-weight: 600; }}
    .config-form input {{ padding: 5px; min-width: 240px; }}
    .config-form small {{ display: block; color: #6b7280; margin-left: 144px; }}
    .muted {{ color: #6b7280; }}
  </style>
</head>
<body>
  <h1>{_e(title)}</h1>
  <p>状态：<code>{_e(str(status["running"]))}</code> 群：<code>{_e(", ".join(map(str, status["rooms"])))}</code> 前缀：<code>{_e(", ".join(status["prefixes"]))}</code></p>
  <p>当前用户：<code>{_e(status["me"]["name"])} / UID {status["me"]["uid"]}</code></p>
  <p><a href="/api/status">JSON 状态</a></p>
  <h2>插件</h2>
  <form method="post" action="/plugins/reload"><button>重载全部插件</button></form>
  <table><tr><th>名称</th><th>版本</th><th>作者</th><th>说明</th><th>权限</th><th>权限状态</th><th>配置键</th><th>启用</th><th>已加载</th><th>路径</th><th>最后加载</th><th>错误</th><th>操作</th></tr>{plugin_rows}</table>
  <h2>插件配置</h2>
  {config_panels}
  <h2>定时任务</h2>
  <table><tr><th>名称</th><th>间隔</th><th>目标群</th><th>状态</th><th>运行次数</th><th>下次运行</th><th>错误</th><th>操作</th></tr>{task_rows}</table>
  <h2>插件存储</h2>
  <table><tr><th>插件</th><th>已保存键</th></tr>{storage_rows}</table>
  <h2>命令</h2>
  <table><tr><th>命令</th><th>别名</th><th>说明</th></tr>{command_rows}</table>
  <h2>接收 / 发送 / 任务逻辑线</h2>
  <table><tr><th>时间</th><th>类型</th><th>群</th><th>命令</th><th>任务</th><th>详情</th></tr>{event_rows}</table>
  <p class="muted">页面刷新即可查看最新状态。</p>
</body>
</html>"""


def _plugin_row(plugin):
    enabled = bool(plugin["enabled"])
    action = "false" if enabled else "true"
    label = "禁用" if enabled else "启用"
    last_loaded = _time(plugin["last_loaded"])
    permissions = ", ".join(plugin.get("permissions", ()))
    missing = ", ".join(plugin.get("permission_missing", ()))
    denied = ", ".join(plugin.get("permission_denied", ()))
    permission_parts = []
    if missing:
        permission_parts.append(f"未知权限：{missing}")
    if denied:
        permission_parts.append(f"缺权限调用：{denied}")
    permission_status = "正常" if plugin.get("permission_ok", False) else "；".join(permission_parts)
    config_keys = ", ".join(plugin.get("config_keys", ()))
    display_name = plugin.get("manifest_name") or plugin["name"]
    return (
        f"<tr><td>{_e(display_name)}</td><td>{_e(plugin.get('version', ''))}</td><td>{_e(plugin.get('author', ''))}</td>"
        f"<td>{_e(plugin.get('description', ''))}</td><td>{_e(permissions)}</td><td>{_e(permission_status)}</td><td>{_e(config_keys)}</td>"
        f"<td>{_e(str(enabled))}</td><td>{_e(str(plugin['loaded']))}</td>"
        f"<td>{_e(plugin['path'])}</td><td>{_e(last_loaded)}</td><td>{_e(plugin['last_error'])}</td>"
        f"<td><form method='post' action='/plugins/toggle?name={_e(plugin['name'])}&enabled={action}'><button>{label}</button></form>"
        f"<form method='post' action='/plugins/reload?name={_e(plugin['name'])}'><button>重载</button></form>"
        f"<a href='/plugins/source?name={_e(plugin['name'])}'>源码</a></td></tr>"
    )


def _plugin_config_panel(bot, plugin):
    schema = plugin.get("config_schema", ())
    if not schema:
        return f"<p class='muted'>{_e(plugin['name'])} 没有声明配置项。</p>"
    settings = bot.plugin_settings(plugin["name"])
    fields = []
    for field in schema:
        key = field["key"]
        value = settings.get(key, field.get("default", ""))
        input_type = "checkbox" if field.get("type") == "boolean" else "number" if field.get("type") in {"integer", "number"} else "text"
        checked = " checked" if input_type == "checkbox" and bool(value) else ""
        value_attr = "" if input_type == "checkbox" else f" value='{_e(value)}'"
        fields.append(
            f"<label><span>{_e(key)}</span><input name='{_e(key)}' type='{input_type}'{value_attr}{checked}></label>"
            f"<small>{_e(field.get('description', ''))}</small>"
        )
    return (
        f"<form method='post' action='/plugins/config?name={_e(plugin['name'])}' class='config-form'>"
        f"<h3>{_e(plugin['name'])}</h3>{''.join(fields)}<button>保存配置</button></form>"
    )


def _task_row(task):
    target = task["room_ids"] if task["room_ids"] == "all" else ", ".join(map(str, task["room_ids"]))
    enabled = bool(task["enabled"])
    action = "false" if enabled else "true"
    label = "禁用" if enabled else "启用"
    return (
        f"<tr><td>{_e(task['name'])}</td><td>{task['seconds']:g}s</td><td>{_e(str(target))}</td>"
        f"<td>{_e(str(enabled))}</td><td>{task['run_count']}</td><td>{task['next_run_in']:.1f}s</td>"
        f"<td>{_e(task['last_error'])}</td><td><form method='post' action='/tasks/toggle?name={_e(task['name'])}&enabled={action}'><button>{label}</button></form></td></tr>"
    )


def _event_row(event):
    return (
        f"<tr><td>{_e(event['time'])}</td><td>{_e(event['kind'])}</td><td>{_e(str(event['room_id'] or ''))}</td>"
        f"<td>{_e(event['command'])}</td><td>{_e(event['task'])}</td><td>{_e(event['detail'])}</td></tr>"
    )


def _e(value):
    return html.escape(str(value), quote=True)


def _time(value):
    if not value:
        return ""
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(float(value)))


def _render_source(bot, name):
    manager = getattr(bot, "plugin_manager", None)
    if manager is None:
        return "<p>plugin manager not found</p>"
    state = manager.states.get(name)
    if state is None or not state.path:
        return f"<p>plugin not found: {_e(name)}</p>"
    path = state.path
    try:
        source = _read_plugin_source(manager, name)
    except OSError as exc:
        return f"<p>cannot read plugin: {_e(exc)}</p>"
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Plugin Source - {_e(name)}</title>
  <style>
    body {{ font-family: system-ui, sans-serif; margin: 24px; color: #1f2937; }}
    textarea {{ width: 100%; min-height: 70vh; font-family: ui-monospace, Consolas, monospace; font-size: 14px; }}
    button {{ padding: 7px 14px; margin-top: 10px; }}
    code {{ background: #f3f4f6; padding: 2px 5px; border-radius: 4px; }}
  </style>
</head>
<body>
  <p><a href="/">返回面板</a></p>
  <h1>{_e(name)}</h1>
  <p><code>{_e(path)}</code></p>
  <form method="post" action="/plugins/save?name={_e(name)}">
    <textarea name="source">{_e(source)}</textarea>
    <button>保存并重载</button>
  </form>
</body>
</html>"""


def _read_plugin_source(manager, name):
    path = _editable_plugin_path(manager, name)
    if path is None:
        raise OSError("plugin source is not editable")
    return path.read_text(encoding="utf-8")


def _save_plugin_source(manager, name, source):
    path = _editable_plugin_path(manager, name)
    if path is None:
        return False
    path.write_text(source, encoding="utf-8")
    return True


def _editable_plugin_path(manager, name):
    state = manager.states.get(name)
    if state is None or not state.path:
        return None
    from pathlib import Path

    path = Path(state.path).resolve()
    if path.suffix != ".py" or not path.exists():
        return None
    for search_path in manager.search_paths:
        base = Path(search_path).resolve()
        try:
            path.relative_to(base)
            return path
        except ValueError:
            continue
    return None


def _panel_can(bot, permission):
    manager = getattr(bot, "plugin_manager", None)
    if manager is None:
        return False
    return permission in manager.permissions("web_panel")


def _save_plugin_config(bot, name, form):
    status = {plugin["name"]: plugin for plugin in bot.plugin_status()}
    plugin = status.get(name)
    if plugin is None:
        return False
    values = {}
    for field in plugin.get("config_schema", ()):
        key = field["key"]
        raw = form.get(key, [""])[0]
        values[key] = _coerce_config_value(raw, field.get("type", "string"))
    bot.plugin_config[name] = values
    config = getattr(bot, "config", None)
    if config is not None:
        config.plugin_config[name] = values
        if getattr(config, "path", ""):
            _write_plugin_config(Path(config.path), config.plugin_config)
    manager = getattr(bot, "plugin_manager", None)
    if manager is not None:
        manager.reload(name)
    return True


def _coerce_config_value(value, type_name):
    if type_name == "boolean":
        return str(value).lower() in {"1", "true", "yes", "on"}
    if type_name == "integer":
        try:
            return int(value)
        except ValueError:
            return 0
    if type_name == "number":
        try:
            return float(value)
        except ValueError:
            return 0.0
    return str(value)


def _write_plugin_config(path, plugin_config):
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    lines = text.splitlines()
    kept = []
    skip = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[plugin."):
            skip = True
            continue
        if skip and stripped.startswith("["):
            skip = False
        if not skip:
            kept.append(line)
    while kept and not kept[-1].strip():
        kept.pop()
    for name, values in plugin_config.items():
        kept.append("")
        kept.append(f"[plugin.{name}]")
        for key, value in values.items():
            kept.append(f"{key} = {_toml_value(value)}")
    path.write_text("\n".join(kept) + "\n", encoding="utf-8")


def _toml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return json.dumps(str(value), ensure_ascii=False)
