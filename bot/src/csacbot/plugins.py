from __future__ import annotations

import threading
import time
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path
from types import ModuleType
from typing import Any

from .bot import GroupBot
from .plugin_devtools import check_plugin, create_plugin
from .plugin_loader import PluginResolver, plugin_mtime
from .plugin_manifest import KNOWN_PERMISSIONS, PluginConfigField, PluginManifest


@dataclass(slots=True)
class PluginState:
    name: str
    enabled: bool = True
    loaded: bool = False
    path: str = ""
    manifest_path: str = ""
    manifest_name: str = ""
    version: str = ""
    author: str = ""
    description: str = ""
    entry: str = ""
    permissions: tuple[str, ...] = field(default_factory=tuple)
    config_schema: tuple[PluginConfigField, ...] = field(default_factory=tuple)
    module_name: str = ""
    last_loaded: float = 0.0
    last_error: str = ""
    last_changed: float = 0.0
    permission_missing: tuple[str, ...] = field(default_factory=tuple)
    permission_denied: tuple[str, ...] = field(default_factory=tuple)


class PluginManager:
    def __init__(
        self,
        bot: GroupBot,
        names: Iterable[str],
        *,
        search_paths: Iterable[str] = (),
    ) -> None:
        self.bot = bot
        self.names = list(names)
        self.search_paths = [Path(path) for path in search_paths]
        self.resolver = PluginResolver(self.search_paths)
        self.states: dict[str, PluginState] = {
            name: PluginState(name=name) for name in self.names
        }
        self.modules: dict[str, ModuleType] = {}
        self._watcher_stop = threading.Event()
        self._watcher_thread: threading.Thread | None = None
        self._mtimes: dict[str, float] = {}

    def load_all(self) -> list[str]:
        loaded: list[str] = []
        for name in self.names:
            state = self.states.setdefault(name, PluginState(name=name))
            if not state.enabled:
                continue
            if self.load(name):
                loaded.append(name)
        return loaded

    def load(self, name: str) -> bool:
        state = self.states.setdefault(name, PluginState(name=name))
        if not state.enabled:
            return False
        self.unload(name)
        try:
            loaded = self.resolver.load(name)
            module = loaded.module
            path = loaded.path
            manifest = loaded.manifest
            setup = getattr(module, "setup", None)
            if not callable(setup):
                raise RuntimeError(f"plugin {name!r} does not define setup(bot)")
            with self.bot.plugin_scope(name):
                setup(self.bot)
            state.loaded = True
            state.path = path
            state.manifest_path = manifest.path
            state.manifest_name = manifest.name
            state.version = manifest.version
            state.author = manifest.author
            state.description = manifest.description
            state.entry = manifest.entry
            state.permissions = manifest.permissions
            state.config_schema = manifest.config_schema
            state.module_name = module.__name__
            state.last_loaded = time.time()
            state.last_changed = plugin_mtime(path, manifest.path)
            state.last_error = ""
            state.permission_missing = tuple(
                sorted(permission for permission in state.permissions if permission not in KNOWN_PERMISSIONS)
            )
            state.permission_denied = ()
            self.modules[name] = module
            self.bot.record_event("plugin_loaded", f"loaded plugin {name}", task=name)
            self._mtimes[name] = state.last_changed
            self.call_hook_for(name, "on_load", self.bot)
            return True
        except Exception as exc:
            state.loaded = False
            state.last_error = str(exc)
            state.last_loaded = time.time()
            self.bot.record_event("plugin_error", str(exc), task=name)
            self.bot.logger.exception("plugin %s load failed", name)
            return False

    def reload(self, name: str) -> bool:
        return self.load(name)

    def reload_all(self) -> list[str]:
        return self.load_all()

    def start_watcher(self, interval: float = 2.0) -> None:
        if self._watcher_thread is not None and self._watcher_thread.is_alive():
            return
        self._watcher_stop.clear()
        self._watcher_thread = threading.Thread(
            target=self._watch_loop,
            args=(float(interval),),
            name="csacbot-plugin-watcher",
            daemon=True,
        )
        self._watcher_thread.start()
        self.bot.record_event("plugin_watcher", f"watching plugins every {interval:g}s")

    def stop_watcher(self) -> None:
        self._watcher_stop.set()
        thread = self._watcher_thread
        if thread is not None and thread.is_alive():
            thread.join(timeout=3.0)
        self._watcher_thread = None

    def _watch_loop(self, interval: float) -> None:
        while not self._watcher_stop.wait(interval):
            self.check_for_changes()

    def check_for_changes(self) -> list[str]:
        reloaded: list[str] = []
        for name, state in list(self.states.items()):
            if not state.enabled or not state.loaded:
                continue
            current_mtime = plugin_mtime(state.path, state.manifest_path)
            previous_mtime = self._mtimes.get(name, state.last_changed)
            if current_mtime <= previous_mtime:
                continue
            self.bot.record_event("plugin_changed", f"detected change in plugin {name}", task=name)
            if self.reload(name):
                reloaded.append(name)
        return reloaded

    def set_enabled(self, name: str, enabled: bool) -> bool:
        state = self.states.setdefault(name, PluginState(name=name))
        state.enabled = enabled
        if not enabled:
            self.unload(name)
            self.bot.record_event("plugin_disabled", f"disabled plugin {name}", task=name)
            return True
        self.bot.record_event("plugin_enabled", f"enabled plugin {name}", task=name)
        return self.load(name)

    def snapshot(self) -> list[dict[str, object]]:
        return [
            {
                "name": state.name,
                "enabled": state.enabled,
                "loaded": state.loaded,
                "path": state.path,
                "manifest_path": state.manifest_path,
                "manifest_name": state.manifest_name,
                "version": state.version,
                "author": state.author,
                "description": state.description,
                "entry": state.entry,
                "permissions": state.permissions,
                "permission_known": tuple(
                    permission for permission in state.permissions if permission in KNOWN_PERMISSIONS
                ),
                "permission_missing": state.permission_missing,
                "permission_denied": state.permission_denied,
                "permission_ok": not state.permission_missing and not state.permission_denied,
                "config_schema": [field.to_dict() for field in state.config_schema],
                "config_keys": sorted(self.bot.plugin_settings(state.name).keys()),
                "module_name": state.module_name,
                "last_loaded": state.last_loaded,
                "last_changed": state.last_changed,
                "last_error": state.last_error,
            }
            for state in self.states.values()
        ]

    def permissions(self, name: str) -> tuple[str, ...]:
        state = self.states.get(name)
        if state is None:
            return ()
        return state.permissions

    def note_permission_denied(self, name: str, permission: str) -> None:
        state = self.states.setdefault(name, PluginState(name=name))
        denied = set(state.permission_denied)
        denied.add(permission)
        state.permission_denied = tuple(sorted(denied))

    def config_defaults(self, name: str) -> dict[str, Any]:
        state = self.states.get(name)
        if state is None:
            return {}
        return {
            field.key: field.default
            for field in state.config_schema
            if field.default is not None
        }

    def call_hook(self, hook: str, *args: Any) -> None:
        for name in list(self.modules):
            self.call_hook_for(name, hook, *args)

    def call_hook_for(self, name: str, hook: str, *args: Any) -> None:
        module = self.modules.get(name)
        if module is None:
            return
        handler = getattr(module, hook, None)
        if not callable(handler):
            return
        try:
            with self.bot.active_plugin(name):
                handler(*args)
        except Exception as exc:
            state = self.states.setdefault(name, PluginState(name=name))
            state.last_error = str(exc)
            self.bot.record_event("plugin_hook_error", f"{hook}: {exc}", task=name)
            self.bot.logger.exception("plugin %s hook %s failed", name, hook)

    def unload(self, name: str) -> None:
        module = self.modules.pop(name, None)
        if module is not None:
            _call_module_hook(self.bot, name, module, "on_unload", self.bot)
            teardown = getattr(module, "teardown", None)
            if callable(teardown):
                try:
                    with self.bot.active_plugin(name):
                        teardown(self.bot)
                except Exception as exc:
                    state = self.states.setdefault(name, PluginState(name=name))
                    state.last_error = str(exc)
                    self.bot.logger.exception("plugin %s teardown failed", name)
        self.bot.unload_plugin_scope(name)
        state = self.states.setdefault(name, PluginState(name=name))
        state.loaded = False


def load_plugins(
    bot: GroupBot,
    names: Iterable[str],
    *,
    search_paths: Iterable[str] = (),
    watch: bool = False,
    watch_interval: float = 2.0,
) -> list[str]:
    manager = PluginManager(bot, names, search_paths=search_paths)
    bot.plugin_manager = manager
    loaded = manager.load_all()
    if watch:
        manager.start_watcher(watch_interval)
    return loaded


def _call_module_hook(bot: GroupBot, name: str, module: ModuleType, hook: str, *args: Any) -> None:
    handler = getattr(module, hook, None)
    if not callable(handler):
        return
    try:
        with bot.active_plugin(name):
            handler(*args)
    except Exception as exc:
        bot.record_event("plugin_hook_error", f"{hook}: {exc}", task=name)
        bot.logger.exception("plugin %s hook %s failed", name, hook)
