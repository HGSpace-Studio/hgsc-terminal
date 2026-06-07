from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - Python 3.10 fallback.
    import tomli as tomllib


@dataclass(slots=True)
class BotConfig:
    base_url: str
    username: str
    password: str
    room_ids: list[int]
    prefixes: list[str] = field(default_factory=lambda: ["/"])
    poll_interval: float = 2.0
    ignore_self: bool = True
    replay_existing: bool = False
    mark_read: bool = False
    plugins: list[str] = field(default_factory=list)
    plugin_paths: list[str] = field(default_factory=list)
    plugin_watch: bool = False
    plugin_watch_interval: float = 2.0
    plugin_config: dict[str, dict[str, Any]] = field(default_factory=dict)
    session_file: str = ""
    save_session: bool = True
    log_level: str = "INFO"
    log_file: str = ""
    log_console: bool = True
    task_enabled: dict[str, bool] = field(default_factory=dict)
    storage_file: str = ""
    web_panel_enabled: bool = False
    web_panel_host: str = "127.0.0.1"
    web_panel_port: int = 8765
    path: str = ""

    @classmethod
    def from_file(cls, path: str | os.PathLike[str]) -> "BotConfig":
        config_path = Path(path)
        with config_path.open("rb") as handle:
            raw = tomllib.load(handle)
        config = cls.from_dict(raw, base_dir=config_path.parent)
        config.path = str(config_path.resolve())
        return config

    @classmethod
    def from_dict(
        cls,
        raw: dict[str, Any],
        *,
        base_dir: Path | None = None,
    ) -> "BotConfig":
        base_dir = base_dir or Path.cwd()
        plugins_section = _dict_value(raw, "plugins")
        plugin_config_section = _dict_value(raw, "plugin")
        session_section = _dict_value(raw, "session")
        logging_section = _dict_value(raw, "logging")
        tasks_section = _dict_value(raw, "tasks")
        storage_section = _dict_value(raw, "storage")
        web_panel_section = _dict_value(raw, "web_panel")
        room_ids = [
            _int_value(item, "room_ids item")
            for item in _list_value(raw, "room_ids")
        ]
        if not room_ids:
            raise ValueError("room_ids must contain at least one room id")

        return cls(
            base_url=_required_str(raw, "base_url"),
            username=_required_str(raw, "username"),
            password=_required_str(raw, "password"),
            room_ids=room_ids,
            prefixes=_str_list(raw, "prefixes", default=["/"]),
            poll_interval=float(raw.get("poll_interval", 2.0)),
            ignore_self=bool(raw.get("ignore_self", True)),
            replay_existing=bool(raw.get("replay_existing", False)),
            mark_read=bool(raw.get("mark_read", False)),
            plugins=_str_list(plugins_section, "enabled", default=[]),
            plugin_paths=[
                _resolve_path(base_dir, value)
                for value in _str_list(plugins_section, "paths", default=[])
            ],
            plugin_watch=bool(plugins_section.get("watch", False)),
            plugin_watch_interval=float(plugins_section.get("watch_interval", 2.0)),
            plugin_config=_nested_dict(plugin_config_section, "plugin"),
            session_file=_resolve_path(
                base_dir,
                _str_value(session_section, "file", default="session.json"),
            ),
            save_session=bool(session_section.get("save", True)),
            log_level=_str_value(logging_section, "level", default="INFO"),
            log_file=_resolve_optional_path(
                base_dir,
                _str_value(logging_section, "file", default=""),
            ),
            log_console=bool(logging_section.get("console", True)),
            task_enabled=_bool_map(tasks_section),
            storage_file=_resolve_path(
                base_dir,
                _str_value(storage_section, "file", default="data/plugins.json"),
            ),
            web_panel_enabled=bool(web_panel_section.get("enabled", False)),
            web_panel_host=_str_value(
                web_panel_section,
                "host",
                default="127.0.0.1",
            ),
            web_panel_port=_int_value(
                web_panel_section.get("port", 8765),
                "web_panel.port",
            ),
            path=str((base_dir / "config.toml").resolve()),
        )


def _required_str(raw: dict[str, Any], key: str) -> str:
    value = raw.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{key} must be a non-empty string")
    return value.strip()


def _str_value(raw: dict[str, Any], key: str, *, default: str) -> str:
    value = raw.get(key, default)
    if not isinstance(value, str):
        raise ValueError(f"{key} must be a string")
    return value.strip()


def _dict_value(raw: dict[str, Any], key: str) -> dict[str, Any]:
    value = raw.get(key, {})
    if not isinstance(value, dict):
        raise ValueError(f"{key} must be a table")
    return value


def _list_value(raw: dict[str, Any], key: str) -> list[Any]:
    value = raw.get(key, [])
    if not isinstance(value, list):
        raise ValueError(f"{key} must be a list")
    return value


def _str_list(
    raw: dict[str, Any],
    key: str,
    *,
    default: list[str],
) -> list[str]:
    if key not in raw:
        return list(default)
    values = _list_value(raw, key)
    result: list[str] = []
    for index, value in enumerate(values):
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{key}[{index}] must be a non-empty string")
        result.append(value.strip())
    return result


def _int_value(value: Any, name: str) -> int:
    if isinstance(value, bool):
        raise ValueError(f"{name} must be an integer")
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.strip().isdigit():
        return int(value.strip())
    raise ValueError(f"{name} must be an integer")


def _resolve_path(base_dir: Path, value: str) -> str:
    path = Path(value)
    if not path.is_absolute():
        path = base_dir / path
    return str(path.resolve())


def _resolve_optional_path(base_dir: Path, value: str) -> str:
    if not value:
        return ""
    return _resolve_path(base_dir, value)


def _bool_map(raw: dict[str, Any]) -> dict[str, bool]:
    result: dict[str, bool] = {}
    for key, value in raw.items():
        if not isinstance(value, bool):
            raise ValueError(f"tasks.{key} must be a boolean")
        result[str(key)] = value
    return result


def _nested_dict(raw: dict[str, Any], name: str) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for key, value in raw.items():
        if not isinstance(value, dict):
            raise ValueError(f"{name}.{key} must be a table")
        result[str(key)] = dict(value)
    return result
