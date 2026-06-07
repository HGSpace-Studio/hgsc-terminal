from __future__ import annotations

import logging
from collections.abc import Sequence
from contextlib import contextmanager
from typing import Any

from .client import CsacClient
from .exceptions import CsacPluginPermissionError
from .models import GroupMember, Message, User


class PluginRuntime:
    def __init__(self, bot: Any, logger: logging.Logger) -> None:
        self.bot = bot
        self.logger = logger
        self.registering = ""
        self.active = ""

    @contextmanager
    def registration(self, plugin: str):
        previous_registering = self.registering
        previous_active = self.active
        self.registering = plugin
        self.active = plugin
        try:
            yield
        finally:
            self.registering = previous_registering
            self.active = previous_active

    @contextmanager
    def execution(self, plugin: str):
        previous = self.active
        self.active = plugin
        try:
            yield
        finally:
            self.active = previous

    def permissions(self, plugin: str) -> set[str]:
        manager = getattr(self.bot, "plugin_manager", None)
        if manager is None:
            return set()
        return set(manager.permissions(plugin))

    def require(self, plugin: str, permission: str) -> None:
        if not plugin:
            return
        if permission in self.permissions(plugin):
            return
        error = CsacPluginPermissionError(plugin, permission)
        manager = getattr(self.bot, "plugin_manager", None)
        if manager is not None:
            manager.note_permission_denied(plugin, permission)
        self.bot.record_event("permission_denied", str(error), task=plugin)
        self.logger.error("plugin permission denied: %s", error)
        raise error

    def client(self, plugin: str) -> "PluginClient":
        return PluginClient(self, plugin)


class PluginClient:
    def __init__(self, runtime: PluginRuntime, plugin: str) -> None:
        self._runtime = runtime
        self._plugin = plugin

    @property
    def _client(self) -> CsacClient:
        return self._runtime.bot.client

    def current_user(self) -> User:
        return self._client.current_user()

    def groups(self):
        return self._client.groups()

    def friends(self):
        return self._client.friends()

    def group_members(self, room_id: int) -> list[GroupMember]:
        self._runtime.require(self._plugin, "read_members")
        return self._client.group_members(room_id)

    def group_messages(self, room_id: int, **kwargs: Any) -> list[Message]:
        return self._client.group_messages(room_id, **kwargs)

    def group_messages_after(self, room_id: int, after_id: int, **kwargs: Any) -> list[Message]:
        return self._client.group_messages_after(room_id, after_id, **kwargs)

    def send_group_message(
        self,
        room_id: int,
        content: str,
        *,
        reply_to: int = 0,
        mention_uids: Sequence[int] | None = None,
    ) -> dict[str, Any]:
        self._runtime.require(self._plugin, "send_message")
        return self._client.send_group_message(
            room_id,
            content,
            reply_to=reply_to,
            mention_uids=mention_uids,
        )

    def send_group_image(
        self,
        room_id: int,
        image_path: str,
        *,
        content: str = "",
        reply_to: int = 0,
        mention_uids: Sequence[int] | None = None,
    ) -> dict[str, Any]:
        self._runtime.require(self._plugin, "send_message")
        return self._client.send_group_image(
            room_id,
            image_path,
            content=content,
            reply_to=reply_to,
            mention_uids=mention_uids,
        )

    def mark_group_read(self, room_id: int, last_msg_id: int = 0) -> dict[str, Any]:
        return self._client.mark_group_read(room_id, last_msg_id)
