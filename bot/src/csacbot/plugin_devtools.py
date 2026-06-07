from __future__ import annotations

import ast
from pathlib import Path

from .plugin_manifest import CONFIG_TYPES, KNOWN_PERMISSIONS, read_manifest


def check_plugin(path: str | Path) -> list[str]:
    messages: list[str] = []
    plugin_path = Path(path).resolve()
    if plugin_path.is_dir():
        manifest_path = plugin_path / "plugin.toml"
        if not manifest_path.exists():
            return [f"missing plugin.toml: {plugin_path}"]
        try:
            manifest = read_manifest(manifest_path, fallback_name=plugin_path.name)
        except Exception as exc:
            return [f"invalid plugin.toml: {exc}"]

        entry = Path(manifest.entry)
        if entry.is_absolute():
            messages.append(f"entry must be a relative path: {manifest.entry}")
            return messages
        entry_path = (plugin_path / entry).resolve()
        try:
            entry_path.relative_to(plugin_path)
        except ValueError:
            messages.append(f"entry must stay inside plugin directory: {manifest.entry}")
            return messages
        if not entry_path.exists():
            messages.append(f"entry file not found: {entry_path}")
        else:
            messages.extend(_check_python_file(entry_path))

        for permission in manifest.permissions:
            if permission not in KNOWN_PERMISSIONS:
                messages.append(f"unknown permission: {permission}")
        for field in manifest.config_schema:
            if field.type not in CONFIG_TYPES:
                messages.append(f"unsupported config type for {field.key}: {field.type}")
        return messages

    if plugin_path.suffix != ".py":
        return [f"plugin path must be a directory or .py file: {plugin_path}"]
    if not plugin_path.exists():
        return [f"plugin file not found: {plugin_path}"]
    return _check_python_file(plugin_path)


def create_plugin(path: str | Path, name: str) -> Path:
    root = Path(path).resolve()
    plugin_dir = root / name
    plugin_dir.mkdir(parents=True, exist_ok=False)
    (plugin_dir / "plugin.toml").write_text(
        "\n".join(
            [
                f'name = "{name}"',
                'version = "0.1.0"',
                'author = ""',
                'description = ""',
                'entry = "main.py"',
                'permissions = ["send_message"]',
                "",
                "[[config]]",
                'key = "reply_text"',
                'type = "string"',
                'default = "hello"',
                'description = "回复文本"',
                "",
            ]
        ),
        encoding="utf-8",
    )
    (plugin_dir / "main.py").write_text(
        "\n".join(
            [
                "from __future__ import annotations",
                "",
                "",
                "def setup(bot):",
                f'    @bot.command("{name}", help="{name} 示例命令")',
                "    def command(ctx):",
                '        return ctx.config.get("reply_text", "hello")',
                "",
            ]
        ),
        encoding="utf-8",
    )
    return plugin_dir


def _check_python_file(path: Path) -> list[str]:
    try:
        ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    except SyntaxError as exc:
        return [f"syntax error in {path}: {exc}"]
    return []
