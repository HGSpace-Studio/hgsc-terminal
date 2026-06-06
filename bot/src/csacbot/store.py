from __future__ import annotations

import json
import os
import threading
from copy import deepcopy
from pathlib import Path
from typing import Any


class PluginStore:
    def __init__(self, storage: "JsonPluginStorage | MemoryPluginStorage", plugin: str) -> None:
        self._storage = storage
        self.plugin = _plugin_name(plugin)

    def get(self, key: str, default: Any = None) -> Any:
        return self._storage.get(self.plugin, key, default)

    def set(self, key: str, value: Any) -> None:
        self._storage.set(self.plugin, key, value)

    def delete(self, key: str) -> bool:
        return self._storage.delete(self.plugin, key)

    def clear(self) -> None:
        self._storage.clear(self.plugin)

    def all(self) -> dict[str, Any]:
        return self._storage.all(self.plugin)

    def incr(self, key: str, amount: int = 1) -> int:
        value = self.get(key, 0)
        if isinstance(value, bool) or not isinstance(value, int):
            raise TypeError(f"{key} is not an integer")
        value += amount
        self.set(key, value)
        return value


class MemoryPluginStorage:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._data: dict[str, dict[str, Any]] = {}

    def for_plugin(self, plugin: str) -> PluginStore:
        return PluginStore(self, plugin)

    def get(self, plugin: str, key: str, default: Any = None) -> Any:
        with self._lock:
            return deepcopy(self._data.get(_plugin_name(plugin), {}).get(key, default))

    def set(self, plugin: str, key: str, value: Any) -> None:
        _validate_key(key)
        normalized = _json_copy(value)
        with self._lock:
            self._data.setdefault(_plugin_name(plugin), {})[key] = normalized

    def delete(self, plugin: str, key: str) -> bool:
        with self._lock:
            data = self._data.get(_plugin_name(plugin), {})
            if key not in data:
                return False
            del data[key]
            return True

    def clear(self, plugin: str) -> None:
        with self._lock:
            self._data[_plugin_name(plugin)] = {}

    def all(self, plugin: str) -> dict[str, Any]:
        with self._lock:
            return deepcopy(self._data.get(_plugin_name(plugin), {}))

    def snapshot(self) -> dict[str, dict[str, Any]]:
        with self._lock:
            return deepcopy(self._data)


class JsonPluginStorage(MemoryPluginStorage):
    def __init__(self, path: str | os.PathLike[str]) -> None:
        super().__init__()
        self.path = Path(path)
        self.load()

    def load(self) -> None:
        with self._lock:
            if not self.path.exists():
                self._data = {}
                return
            with self.path.open("r", encoding="utf-8") as handle:
                raw = json.load(handle)
            if not isinstance(raw, dict):
                raise ValueError(f"plugin storage file must contain a JSON object: {self.path}")
            data: dict[str, dict[str, Any]] = {}
            for plugin, values in raw.items():
                if isinstance(values, dict):
                    data[_plugin_name(str(plugin))] = deepcopy(values)
            self._data = data

    def set(self, plugin: str, key: str, value: Any) -> None:
        _validate_key(key)
        normalized = _json_copy(value)
        with self._lock:
            self._data.setdefault(_plugin_name(plugin), {})[key] = normalized
            self._save_locked()

    def delete(self, plugin: str, key: str) -> bool:
        with self._lock:
            data = self._data.get(_plugin_name(plugin), {})
            if key not in data:
                return False
            del data[key]
            self._save_locked()
            return True

    def clear(self, plugin: str) -> None:
        with self._lock:
            self._data[_plugin_name(plugin)] = {}
            self._save_locked()

    def _save_locked(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = self.path.with_name(f"{self.path.name}.tmp")
        with tmp_path.open("w", encoding="utf-8") as handle:
            json.dump(self._data, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(tmp_path, self.path)


def _plugin_name(plugin: str) -> str:
    value = str(plugin or "app").strip()
    return value or "app"


def _validate_key(key: str) -> None:
    if not isinstance(key, str) or not key.strip():
        raise ValueError("store key must be a non-empty string")


def _json_copy(value: Any) -> Any:
    try:
        return json.loads(json.dumps(value, ensure_ascii=False))
    except (TypeError, ValueError) as exc:
        raise TypeError("plugin store values must be JSON serializable") from exc
