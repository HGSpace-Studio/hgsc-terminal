from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any

from .models import GroupMember, Message
from .plugin_runtime import PluginClient
from .store import PluginStore


def member_is_admin(member: GroupMember | None) -> bool:
    if member is None:
        return False
    return member.is_admin or member.is_owner or member.role.lower() in {"admin", "administrator"}


def member_is_owner(member: GroupMember | None) -> bool:
    if member is None:
        return False
    return member.is_owner or member.role.lower() in {"owner", "group_owner"}


@dataclass(slots=True)
class PluginContextBase:
    bot: Any
    plugin: str = ""

    @property
    def client(self) -> PluginClient:
        return self.bot.plugin_client(self.plugin)

    @property
    def log(self) -> logging.Logger:
        return self.bot.logger

    @property
    def store(self) -> PluginStore:
        self.bot.require_permission(self.plugin, "storage")
        return self.bot.plugin_store(self.plugin)

    @property
    def config(self) -> dict[str, Any]:
        return self.bot.plugin_settings(self.plugin)

    def send_group(self, room_id: int, content: str, **kwargs: Any) -> dict[str, Any]:
        self.bot.require_permission(self.plugin, "send_message")
        return self.bot.send_group(room_id, content, **kwargs)

    def send_all(self, content: str) -> None:
        self.bot.require_permission(self.plugin, "send_message")
        self.bot.send_all(content)


@dataclass(slots=True)
class RoomPluginContext(PluginContextBase):
    room_id: int = 0
    message: Message | None = None

    @property
    def sender_id(self) -> int:
        return self.message.sender_id if self.message is not None else 0

    @property
    def sender_name(self) -> str:
        return self.message.sender if self.message is not None else ""

    @property
    def message_id(self) -> int:
        return self.message.message_id if self.message is not None else 0

    def reply(
        self,
        content: str,
        *,
        quote: bool = False,
        mention_sender: bool = False,
    ) -> dict[str, Any]:
        self.bot.require_permission(self.plugin, "send_message")
        mention_uids = [self.sender_id] if mention_sender and self.sender_id else None
        reply_to = self.message_id if quote else 0
        return self.bot.send_group(
            self.room_id,
            content,
            reply_to=reply_to,
            mention_uids=mention_uids,
        )

    def members(self) -> list[GroupMember]:
        self.bot.require_permission(self.plugin, "read_members")
        return self.bot.group_members(self.room_id)

    def sender_member(self) -> GroupMember | None:
        self.bot.require_permission(self.plugin, "read_members")
        return self.bot.find_member(self.room_id, self.sender_id)

    def find_member(self, query: str | int) -> GroupMember | None:
        self.bot.require_permission(self.plugin, "read_members")
        return self.bot.find_member(self.room_id, query)

    def is_admin(self) -> bool:
        return member_is_admin(self.sender_member())

    def is_owner(self) -> bool:
        return member_is_owner(self.sender_member())


@dataclass(slots=True)
class GroupMessageEvent(RoomPluginContext):
    pass


@dataclass(slots=True)
class CommandContext(RoomPluginContext):
    prefix: str = ""
    command: str = ""
    args: list[str] = field(default_factory=list)
    arg_text: str = ""

    def mention(self, uid: int | None = None) -> str:
        return f"@{int(uid or self.sender_id)}"


@dataclass(slots=True)
class IntervalContext(PluginContextBase):
    task_name: str = ""
    run_count: int = 0

    def task_enabled(self, name: str) -> bool:
        task = self.bot.get_task(name)
        return bool(task and task["enabled"])

    def set_task_enabled(self, name: str, enabled: bool) -> bool:
        self.bot.require_permission(self.plugin, "manage_tasks")
        return self.bot.set_task_enabled(name, enabled)
