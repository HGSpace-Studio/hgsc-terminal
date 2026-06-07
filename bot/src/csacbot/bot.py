from __future__ import annotations

import logging
import signal
import time
from collections.abc import Callable, Iterable
from contextlib import contextmanager
from dataclasses import dataclass, field
from typing import Any

from .client import CsacClient
from .models import GroupMember, Message, User
from .plugin_context import CommandContext, GroupMessageEvent, IntervalContext
from .plugin_runtime import PluginClient, PluginRuntime
from .store import MemoryPluginStorage, PluginStore


@dataclass(slots=True)
class BotEvent:
    time: float
    kind: str
    detail: str
    room_id: int | None = None
    task: str = ""
    message_id: int = 0
    sender_id: int = 0
    command: str = ""


CommandHandler = Callable[[CommandContext], str | None]
MessageHandler = Callable[[GroupMessageEvent], str | None]
IntervalHandler = Callable[[IntervalContext], str | None]


@dataclass(slots=True)
class _Command:
    name: str
    handler: CommandHandler
    aliases: tuple[str, ...]
    help: str
    plugin: str = ""
    admin_only: bool = False
    owner_only: bool = False
    cooldown: float = 0.0
    last_used: dict[int, float] = field(default_factory=dict)


@dataclass(slots=True)
class _IntervalTask:
    name: str
    handler: IntervalHandler
    seconds: float
    room_ids: tuple[int, ...] | None
    enabled: bool
    next_run: float
    run_count: int = 0
    last_run: float = 0.0
    last_error: str = ""
    plugin: str = ""


@dataclass(slots=True)
class _PluginScope:
    commands: set[str] = field(default_factory=set)
    intervals: set[str] = field(default_factory=set)
    message_handlers: list[MessageHandler] = field(default_factory=list)
    unknown_handler: CommandHandler | None = None


class GroupBot:
    def __init__(
        self,
        client: CsacClient,
        *,
        room_ids: Iterable[int],
        prefixes: Iterable[str] = ("/",),
        poll_interval: float = 2.0,
        ignore_self: bool = True,
        replay_existing: bool = False,
        mark_read: bool = False,
        include_builtin_help: bool = True,
        task_enabled: dict[str, bool] | None = None,
        plugin_config: dict[str, dict[str, Any]] | None = None,
        storage: MemoryPluginStorage | None = None,
        logger: logging.Logger | None = None,
        max_events: int = 200,
    ) -> None:
        self.client = client
        self.room_ids = [int(room_id) for room_id in room_ids]
        self.prefixes = tuple(prefixes)
        self.poll_interval = poll_interval
        self.ignore_self = ignore_self
        self.replay_existing = replay_existing
        self.mark_read = mark_read
        self.task_enabled = dict(task_enabled or {})
        self.plugin_config = {
            str(name): dict(values)
            for name, values in (plugin_config or {}).items()
        }
        self.storage = storage or MemoryPluginStorage()
        self.logger = logger or logging.getLogger("csacbot")
        self.max_events = max_events
        self.me: User | None = None
        self.last_ids: dict[int, int] = {}
        self.running = False
        self._commands: dict[str, _Command] = {}
        self._interval_tasks: dict[str, _IntervalTask] = {}
        self._message_handlers: list[MessageHandler] = []
        self._unknown_command_handler: CommandHandler | None = None
        self._unknown_command_plugin = ""
        self._events: list[BotEvent] = []
        self.runtime = PluginRuntime(self, self.logger)
        self._plugin_scopes: dict[str, _PluginScope] = {}
        if include_builtin_help:
            self._register_builtin_help()

    def command(
        self,
        name: str,
        *,
        aliases: Iterable[str] = (),
        help: str = "",
        admin_only: bool = False,
        owner_only: bool = False,
        cooldown: float = 0.0,
    ) -> Callable[[CommandHandler], CommandHandler]:
        normalized_name = name.strip().lower()
        normalized_aliases = tuple(alias.strip().lower() for alias in aliases if alias.strip())

        def decorator(handler: CommandHandler) -> CommandHandler:
            command = _Command(
                normalized_name,
                handler,
                normalized_aliases,
                help,
                self.runtime.registering,
                bool(admin_only),
                bool(owner_only),
                float(cooldown),
            )
            self._commands[normalized_name] = command
            self._track_plugin_command(normalized_name)
            for alias in normalized_aliases:
                self._commands[alias] = command
                self._track_plugin_command(alias)
            return handler

        return decorator

    def on_group_message(self, handler: MessageHandler) -> MessageHandler:
        self._message_handlers.append(handler)
        plugin = self.runtime.registering
        if plugin:
            scope = self._plugin_scopes.setdefault(plugin, _PluginScope())
            scope.message_handlers.append(handler)
        return handler

    def on_unknown_command(self, handler: CommandHandler) -> CommandHandler:
        self._unknown_command_handler = handler
        plugin = self.runtime.registering
        self._unknown_command_plugin = plugin
        if plugin:
            scope = self._plugin_scopes.setdefault(plugin, _PluginScope())
            scope.unknown_handler = handler
        return handler

    def interval(
        self,
        seconds: float,
        *,
        name: str | None = None,
        room_ids: Iterable[int] | None = None,
        enabled: bool = True,
    ) -> Callable[[IntervalHandler], IntervalHandler]:
        if seconds <= 0:
            raise ValueError("interval seconds must be greater than 0")

        def decorator(handler: IntervalHandler) -> IntervalHandler:
            task_name = (name or handler.__name__).strip()
            if not task_name:
                raise ValueError("interval task name must not be empty")
            task_enabled = self.task_enabled.get(task_name, enabled)
            rooms = None if room_ids is None else tuple(int(room_id) for room_id in room_ids)
            self._interval_tasks[task_name] = _IntervalTask(
                name=task_name,
                handler=handler,
                seconds=float(seconds),
                room_ids=rooms,
                enabled=task_enabled,
                next_run=time.monotonic() + float(seconds),
                plugin=self.runtime.registering,
            )
            plugin = self.runtime.registering
            if plugin:
                scope = self._plugin_scopes.setdefault(plugin, _PluginScope())
                scope.intervals.add(task_name)
            self.record_event(
                "task_registered",
                f"registered interval task {task_name} every {seconds:g}s",
                task=task_name,
            )
            return handler

        return decorator

    @contextmanager
    def plugin_scope(self, name: str):
        self._plugin_scopes.setdefault(name, _PluginScope())
        with self.runtime.registration(name):
            yield

    @contextmanager
    def active_plugin(self, name: str):
        with self.runtime.execution(name):
            yield

    def unload_plugin_scope(self, name: str) -> None:
        scope = self._plugin_scopes.pop(name, None)
        if scope is None:
            return
        for command_name in list(scope.commands):
            self._commands.pop(command_name, None)
        for task_name in list(scope.intervals):
            self._interval_tasks.pop(task_name, None)
        for handler in scope.message_handlers:
            self._message_handlers = [
                item for item in self._message_handlers if item is not handler
            ]
        if scope.unknown_handler is not None and self._unknown_command_handler is scope.unknown_handler:
            self._unknown_command_handler = None
            self._unknown_command_plugin = ""
        self.record_event("plugin_unloaded", f"unloaded plugin {name}")

    @property
    def commands(self) -> list[tuple[str, tuple[str, ...], str]]:
        unique: dict[str, _Command] = {}
        for command in self._commands.values():
            unique[command.name] = command
        return [
            (command.name, command.aliases, command.help)
            for command in sorted(unique.values(), key=lambda item: item.name)
        ]

    @property
    def interval_tasks(self) -> list[dict[str, Any]]:
        if self.runtime.active:
            self.require_permission(self.runtime.active, "manage_tasks")
        now = time.monotonic()
        return [
            {
                "name": task.name,
                "seconds": task.seconds,
                "room_ids": list(task.room_ids) if task.room_ids is not None else "all",
                "enabled": task.enabled,
                "run_count": task.run_count,
                "last_run": task.last_run,
                "last_error": task.last_error,
                "next_run_in": max(0.0, task.next_run - now),
                "plugin": task.plugin,
            }
            for task in sorted(self._interval_tasks.values(), key=lambda item: item.name)
        ]

    @property
    def events(self) -> list[BotEvent]:
        if self.runtime.active:
            self.require_permission(self.runtime.active, "read_events")
        return list(self._events)

    def plugin_store(self, plugin: str = "") -> PluginStore:
        if self.runtime.active:
            self.require_permission(self.runtime.active, "storage")
        name = plugin or self.runtime.registering or self.runtime.active or "app"
        return self.storage.for_plugin(name)

    def plugin_client(self, plugin: str) -> PluginClient:
        return self.runtime.client(plugin)

    def plugin_settings(self, plugin: str = "") -> dict[str, Any]:
        name = plugin or self.runtime.registering or self.runtime.active or "app"
        settings = {}
        manager = getattr(self, "plugin_manager", None)
        if manager is not None:
            settings.update(manager.config_defaults(name))
        settings.update(self.plugin_config.get(name, {}))
        return settings

    def plugin_permissions(self, plugin: str) -> set[str]:
        return self.runtime.permissions(plugin)

    def require_permission(self, plugin: str, permission: str) -> None:
        self.runtime.require(plugin, permission)

    def record_event(
        self,
        kind: str,
        detail: str,
        *,
        room_id: int | None = None,
        task: str = "",
        message_id: int = 0,
        sender_id: int = 0,
        command: str = "",
    ) -> None:
        self._events.append(
            BotEvent(
                time=time.time(),
                kind=kind,
                detail=detail,
                room_id=room_id,
                task=task,
                message_id=message_id,
                sender_id=sender_id,
                command=command,
            )
        )
        if len(self._events) > self.max_events:
            del self._events[: len(self._events) - self.max_events]

    def set_task_enabled(self, name: str, enabled: bool) -> bool:
        if self.runtime.active:
            self.require_permission(self.runtime.active, "manage_tasks")
        task = self._interval_tasks.get(name)
        if task is None:
            return False
        task.enabled = enabled
        self.task_enabled[name] = enabled
        if enabled:
            task.next_run = time.monotonic() + task.seconds
        self.record_event(
            "task_enabled" if enabled else "task_disabled",
            f"{'enabled' if enabled else 'disabled'} task {name}",
            task=name,
        )
        return True

    def get_task(self, name: str) -> dict[str, Any] | None:
        for task in self.interval_tasks:
            if task["name"] == name:
                return task
        return None

    def enable_task(self, name: str) -> bool:
        return self.set_task_enabled(name, True)

    def disable_task(self, name: str) -> bool:
        return self.set_task_enabled(name, False)

    def plugin_status(self) -> list[dict[str, object]]:
        manager = getattr(self, "plugin_manager", None)
        if manager is None:
            return []
        return manager.snapshot()

    def reload_plugin(self, name: str) -> bool:
        if self.runtime.active:
            self.require_permission(self.runtime.active, "manage_plugins")
        manager = getattr(self, "plugin_manager", None)
        if manager is None:
            return False
        return manager.reload(name)

    def reload_plugins(self) -> list[str]:
        if self.runtime.active:
            self.require_permission(self.runtime.active, "manage_plugins")
        manager = getattr(self, "plugin_manager", None)
        if manager is None:
            return []
        return manager.reload_all()

    def set_plugin_enabled(self, name: str, enabled: bool) -> bool:
        if self.runtime.active:
            self.require_permission(self.runtime.active, "manage_plugins")
        manager = getattr(self, "plugin_manager", None)
        if manager is None:
            return False
        return manager.set_enabled(name, enabled)

    def enable_plugin(self, name: str) -> bool:
        return self.set_plugin_enabled(name, True)

    def disable_plugin(self, name: str) -> bool:
        return self.set_plugin_enabled(name, False)

    def group_members(self, room_id: int) -> list[GroupMember]:
        if self.runtime.active:
            self.require_permission(self.runtime.active, "read_members")
        return self.client.group_members(room_id)

    def find_member(self, room_id: int, query: str | int) -> GroupMember | None:
        query_text = str(query).strip().lower()
        if not query_text:
            return None
        query_id = int(query_text) if query_text.isdigit() else 0
        for member in self.group_members(room_id):
            if query_id and member.id == query_id:
                return member
            values = {
                member.display_name.lower(),
                member.nickname.lower(),
                member.username.lower(),
                member.remark.lower(),
            }
            if query_text in values:
                return member
        return None

    def send_group(self, room_id: int, content: str, **kwargs: Any) -> dict[str, Any]:
        if self.runtime.active:
            self.require_permission(self.runtime.active, "send_message")
        result = self.client.send_group_message(room_id, content, **kwargs)
        self.record_event(
            "send",
            content,
            room_id=room_id,
        )
        return result

    def send_all(self, content: str) -> None:
        for room_id in self.room_ids:
            self.send_group(room_id, content)

    def start(self) -> None:
        self.me = self.client.current_user()
        if not self.replay_existing:
            for room_id in self.room_ids:
                messages = self.client.group_messages(room_id, limit=80)
                self.last_ids[room_id] = max((message.message_id for message in messages), default=0)
        self.running = True
        self._call_plugin_hook("on_bot_start", self)

    def stop(self) -> None:
        self.running = False
        self._call_plugin_hook("on_bot_stop", self)
        manager = getattr(self, "plugin_manager", None)
        if manager is not None:
            manager.stop_watcher()

    def run_forever(self) -> None:
        self.start()
        previous_sigint = signal.getsignal(signal.SIGINT)
        signal.signal(signal.SIGINT, self._handle_sigint)
        try:
            while self.running:
                self.poll_once()
                time.sleep(self.poll_interval)
        finally:
            signal.signal(signal.SIGINT, previous_sigint)

    def poll_once(self) -> None:
        self.run_due_tasks()
        for room_id in self.room_ids:
            after_id = self.last_ids.get(room_id, 0)
            messages = self.client.group_messages_after(room_id, after_id)
            if not messages:
                continue
            for message in messages:
                if message.message_id <= after_id:
                    continue
                self.last_ids[room_id] = max(self.last_ids.get(room_id, 0), message.message_id)
                if self.ignore_self and self.me is not None and message.sender_id == self.me.uid:
                    continue
                self.record_event(
                    "receive",
                    message.body,
                    room_id=room_id,
                    message_id=message.message_id,
                    sender_id=message.sender_id,
                )
                self._dispatch_message(room_id, message)
            if self.mark_read:
                self.client.mark_group_read(room_id, self.last_ids.get(room_id, 0))

    def _dispatch_message(self, room_id: int, message: Message) -> None:
        for handler in self._message_handlers:
            plugin = self._handler_plugin(handler)
            event = GroupMessageEvent(
                bot=self,
                plugin=plugin,
                room_id=room_id,
                message=message,
            )
            try:
                with self.active_plugin(plugin):
                    result = handler(event)
                if isinstance(result, str) and result.strip():
                    self.require_permission(plugin, "send_message")
                    self.send_group(room_id, result)
            except Exception as exc:
                self._handle_plugin_error(plugin, exc, kind="message_error")

        context = self._command_context(room_id, message)
        if context is None:
            return
        command = self._commands.get(context.command)
        if command is None:
            if self._unknown_command_handler is not None:
                context.plugin = self._unknown_command_plugin
                try:
                    with self.active_plugin(context.plugin):
                        result = self._unknown_command_handler(context)
                    if isinstance(result, str) and result.strip():
                        context.reply(result)
                except Exception as exc:
                    self._handle_plugin_error(context.plugin, exc, kind="command_error", command=context.command)
            return
        context.plugin = command.plugin
        try:
            if not self._command_allowed(command, context):
                return
        except Exception as exc:
            self._handle_plugin_error(command.plugin, exc, kind="command_error", command=context.command)
            return
        self.record_event(
            "command",
            message.body,
            room_id=room_id,
            message_id=message.message_id,
            sender_id=message.sender_id,
            command=context.command,
        )
        try:
            with self.active_plugin(command.plugin):
                result = command.handler(context)
            if isinstance(result, str) and result.strip():
                context.reply(result)
        except Exception as exc:
            self._handle_plugin_error(command.plugin, exc, kind="command_error", command=context.command)

    def run_due_tasks(self) -> None:
        now = time.monotonic()
        for task in list(self._interval_tasks.values()):
            if not task.enabled or task.next_run > now:
                continue
            task.next_run = now + task.seconds
            task.run_count += 1
            task.last_run = time.time()
            ctx = IntervalContext(
                bot=self,
                task_name=task.name,
                run_count=task.run_count,
                plugin=task.plugin,
            )
            try:
                self.record_event(
                    "task_run",
                    f"running task {task.name}",
                    task=task.name,
                )
                with self.active_plugin(task.plugin):
                    result = task.handler(ctx)
                task.last_error = ""
                if isinstance(result, str) and result.strip():
                    self.require_permission(task.plugin, "send_message")
                    targets = self.room_ids if task.room_ids is None else task.room_ids
                    for room_id in targets:
                        self.send_group(room_id, result)
            except Exception as exc:
                task.last_error = str(exc)
                self.record_event(
                    "task_error",
                    str(exc),
                    task=task.name,
                )
                self._call_plugin_hook("on_task_error", task.plugin, task.name, exc)
                self.logger.exception("interval task %s failed", task.name)

    def _track_plugin_command(self, name: str) -> None:
        plugin = self.runtime.registering
        if not plugin:
            return
        scope = self._plugin_scopes.setdefault(plugin, _PluginScope())
        scope.commands.add(name)

    def _handler_plugin(self, handler: MessageHandler) -> str:
        for plugin, scope in self._plugin_scopes.items():
            if handler in scope.message_handlers:
                return plugin
        return ""

    def _command_allowed(self, command: _Command, ctx: CommandContext) -> bool:
        if command.owner_only and not ctx.is_owner():
            self.record_event(
                "command_denied",
                f"command {ctx.command} requires owner",
                room_id=ctx.room_id,
                message_id=ctx.message_id,
                sender_id=ctx.sender_id,
                command=ctx.command,
            )
            return False
        if command.admin_only and not ctx.is_admin():
            self.record_event(
                "command_denied",
                f"command {ctx.command} requires admin",
                room_id=ctx.room_id,
                message_id=ctx.message_id,
                sender_id=ctx.sender_id,
                command=ctx.command,
            )
            return False
        if command.cooldown <= 0:
            return True
        key = ctx.sender_id or 0
        now = time.monotonic()
        last_used = command.last_used.get(key, 0.0)
        remaining = command.cooldown - (now - last_used)
        if remaining > 0:
            self.record_event(
                "command_cooldown",
                f"command {ctx.command} cooldown {remaining:.1f}s",
                room_id=ctx.room_id,
                message_id=ctx.message_id,
                sender_id=ctx.sender_id,
                command=ctx.command,
            )
            return False
        command.last_used[key] = now
        return True

    def _handle_plugin_error(
        self,
        plugin: str,
        exc: Exception,
        *,
        kind: str,
        command: str = "",
    ) -> None:
        self.record_event(kind, str(exc), task=plugin, command=command)
        if kind == "command_error":
            self._call_plugin_hook("on_command_error", plugin, command, exc)
        self.logger.exception("plugin %s %s", plugin or "app", kind)

    def _call_plugin_hook(self, hook: str, *args: Any) -> None:
        manager = getattr(self, "plugin_manager", None)
        if manager is None:
            return
        manager.call_hook(hook, *args)

    def _command_context(self, room_id: int, message: Message) -> CommandContext | None:
        body = message.body.strip()
        if not body:
            return None
        matched_prefix = ""
        for prefix in self.prefixes:
            if prefix and body.startswith(prefix):
                matched_prefix = prefix
                break
        if not matched_prefix:
            return None
        rest = body[len(matched_prefix) :].strip()
        if not rest:
            return None
        parts = rest.split()
        command = parts[0].lower()
        args = parts[1:]
        arg_text = rest[len(parts[0]) :].strip()
        return CommandContext(
            bot=self,
            room_id=room_id,
            message=message,
            prefix=matched_prefix,
            command=command,
            args=args,
            arg_text=arg_text,
        )

    def _register_builtin_help(self) -> None:
        @self.command("help", aliases=("?",), help="显示命令列表")
        def help_command(ctx: CommandContext) -> str:
            lines = ["可用命令："]
            for name, aliases, help_text in self.commands:
                alias_text = f" ({', '.join(aliases)})" if aliases else ""
                description = f" - {help_text}" if help_text else ""
                lines.append(f"{ctx.prefix}{name}{alias_text}{description}")
            return "\n".join(lines)

    def _handle_sigint(self, signum: int, frame: Any) -> None:
        self.stop()
