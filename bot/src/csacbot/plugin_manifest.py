from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - Python 3.10 fallback.
    import tomli as tomllib


KNOWN_PERMISSIONS = {
    "send_message",
    "read_members",
    "storage",
    "manage_plugins",
    "manage_tasks",
    "edit_plugin_source",
    "read_events",
    "read_storage",
    "logging",
}

CONFIG_TYPES = {"string", "integer", "number", "boolean"}


@dataclass(slots=True)
class PluginConfigField:
    key: str
    type: str = "string"
    default: Any = None
    description: str = ""
    required: bool = False

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> "PluginConfigField":
        key = _str_value(raw, "key")
        if not key:
            raise RuntimeError("plugin config field key must not be empty")
        return cls(
            key=key,
            type=_str_value(raw, "type", fallback="string"),
            default=raw.get("default"),
            description=_str_value(raw, "description"),
            required=bool(raw.get("required", False)),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "type": self.type,
            "default": self.default,
            "description": self.description,
            "required": self.required,
        }


@dataclass(slots=True)
class PluginManifest:
    name: str
    version: str = ""
    author: str = ""
    description: str = ""
    entry: str = "main.py"
    permissions: tuple[str, ...] = field(default_factory=tuple)
    config_schema: tuple[PluginConfigField, ...] = field(default_factory=tuple)
    path: str = ""

    @classmethod
    def from_dict(
        cls,
        raw: dict[str, Any],
        *,
        fallback_name: str,
        path: str = "",
    ) -> "PluginManifest":
        return cls(
            name=_str_value(raw, "name", fallback=fallback_name),
            version=_str_value(raw, "version"),
            author=_str_value(raw, "author"),
            description=_str_value(raw, "description"),
            entry=_str_value(raw, "entry", fallback="main.py"),
            permissions=tuple(_str_list(raw, "permissions")),
            config_schema=tuple(_config_schema(raw)),
            path=path,
        )

    @classmethod
    def file_plugin(cls, name: str, path: str) -> "PluginManifest":
        return cls(name=name, entry=Path(path).name, path="")


def read_manifest(path: Path, *, fallback_name: str) -> PluginManifest:
    with path.open("rb") as handle:
        raw = tomllib.load(handle)
    if not isinstance(raw, dict):
        raise RuntimeError(f"plugin manifest must be a TOML table: {path}")
    return PluginManifest.from_dict(
        raw,
        fallback_name=fallback_name,
        path=str(path.resolve()),
    )


def _config_schema(raw: dict[str, Any]) -> list[PluginConfigField]:
    value = raw.get("config", [])
    if not isinstance(value, list):
        raise RuntimeError("plugin manifest field config must be a list")
    fields: list[PluginConfigField] = []
    seen: set[str] = set()
    for index, item in enumerate(value):
        if not isinstance(item, dict):
            raise RuntimeError(f"plugin manifest field config[{index}] must be a table")
        field = PluginConfigField.from_dict(item)
        if field.key in seen:
            raise RuntimeError(f"duplicated plugin config key: {field.key}")
        seen.add(field.key)
        fields.append(field)
    return fields


def _str_value(raw: dict[str, Any], key: str, *, fallback: str = "") -> str:
    value = raw.get(key, fallback)
    if value is None:
        return ""
    if not isinstance(value, str):
        raise RuntimeError(f"plugin manifest field {key} must be a string")
    return value.strip()


def _str_list(raw: dict[str, Any], key: str) -> list[str]:
    value = raw.get(key, [])
    if not isinstance(value, list):
        raise RuntimeError(f"plugin manifest field {key} must be a list")
    result: list[str] = []
    for index, item in enumerate(value):
        if not isinstance(item, str) or not item.strip():
            raise RuntimeError(f"plugin manifest field {key}[{index}] must be a non-empty string")
        result.append(item.strip())
    return result
