from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


def _to_int(value: Any, default: int = 0) -> int:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        value = value.strip()
        if not value:
            return default
        try:
            return int(float(value))
        except ValueError:
            return default
    return default


def _to_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "y", "on"}
    return False


def _to_str(value: Any) -> str:
    if value is None:
        return ""
    return str(value)


def _first_text(data: dict[str, Any], keys: tuple[str, ...]) -> str:
    for key in keys:
        value = _to_str(data.get(key)).strip()
        if value:
            return value
    return ""


@dataclass(slots=True)
class User:
    uid: int = 0
    username: str = ""
    nickname: str = ""
    avatar: str = ""
    is_friend: bool = False
    can_add_friend: bool = False
    online_status: str = ""
    remark: str = ""
    signature: str = ""
    bio: str = ""
    raw: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: dict[str, Any] | None) -> "User":
        data = data or {}
        return cls(
            uid=_to_int(data.get("uid")),
            username=_to_str(data.get("username")),
            nickname=_to_str(data.get("nickname")),
            avatar=_to_str(data.get("avatar")),
            is_friend=_to_bool(data.get("is_friend")),
            can_add_friend=_to_bool(data.get("can_add_friend")),
            online_status=_to_str(data.get("online_status")),
            remark=_to_str(data.get("remark")),
            signature=_to_str(data.get("signature")),
            bio=_to_str(data.get("bio")),
            raw=data,
        )

    @property
    def display_name(self) -> str:
        return self.remark or self.nickname or self.username or f"UID {self.uid}"


@dataclass(slots=True)
class Friend:
    uid: int = 0
    friend_id: int = 0
    nickname: str = ""
    remark: str = ""
    avatar: str = ""
    unread_count: int = 0
    online_status: str = ""
    last_msg: str = ""
    last_message: str = ""
    raw: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: dict[str, Any] | None) -> "Friend":
        data = data or {}
        return cls(
            uid=_to_int(data.get("uid")),
            friend_id=_to_int(data.get("friend_id")),
            nickname=_to_str(data.get("nickname")),
            remark=_to_str(data.get("remark")),
            avatar=_to_str(data.get("avatar")),
            unread_count=_to_int(data.get("unread_count")),
            online_status=_to_str(data.get("online_status")),
            last_msg=_to_str(data.get("last_msg")),
            last_message=_to_str(data.get("last_message")),
            raw=data,
        )

    @property
    def id(self) -> int:
        return self.friend_id or self.uid

    @property
    def display_name(self) -> str:
        return self.remark or self.nickname or f"User {self.id}"


@dataclass(slots=True)
class Group:
    room_id: int = 0
    id: int = 0
    room_name: str = ""
    name: str = ""
    description: str = ""
    notice: str = ""
    invite_code: str = ""
    unread_count: int = 0
    member_count: int = 0
    is_in_group: bool = False
    is_admin: bool = False
    is_owner: bool = False
    raw: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: dict[str, Any] | None) -> "Group":
        data = data or {}
        return cls(
            room_id=_to_int(data.get("room_id")),
            id=_to_int(data.get("id")),
            room_name=_to_str(data.get("room_name")),
            name=_to_str(data.get("name")),
            description=_to_str(data.get("description")),
            notice=_to_str(data.get("notice")),
            invite_code=_to_str(data.get("invite_code")),
            unread_count=_to_int(data.get("unread_count")),
            member_count=_to_int(data.get("member_count")),
            is_in_group=_to_bool(data.get("is_in_group")),
            is_admin=_to_bool(data.get("is_admin")),
            is_owner=_to_bool(data.get("is_owner")),
            raw=data,
        )

    @property
    def room(self) -> int:
        return self.room_id or self.id

    @property
    def display_name(self) -> str:
        return self.room_name or self.name or f"Room {self.room}"


@dataclass(slots=True)
class GroupMember:
    uid: int = 0
    user_id: int = 0
    nickname: str = ""
    username: str = ""
    remark: str = ""
    avatar: str = ""
    role: str = ""
    is_owner: bool = False
    is_admin: bool = False
    online_status: str = ""
    raw: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: dict[str, Any] | None) -> "GroupMember":
        data = data or {}
        return cls(
            uid=_to_int(data.get("uid")),
            user_id=_to_int(data.get("user_id")),
            nickname=_to_str(data.get("nickname")),
            username=_to_str(data.get("username")),
            remark=_to_str(data.get("remark")),
            avatar=_to_str(data.get("avatar")),
            role=_to_str(data.get("role")),
            is_owner=_to_bool(data.get("is_owner")),
            is_admin=_to_bool(data.get("is_admin")),
            online_status=_to_str(data.get("online_status")),
            raw=data,
        )

    @property
    def id(self) -> int:
        return self.uid or self.user_id

    @property
    def display_name(self) -> str:
        return self.remark or self.nickname or self.username or f"UID {self.id}"


@dataclass(slots=True)
class Message:
    id: int = 0
    msg_id: int = 0
    uid: int = 0
    from_uid: int = 0
    user_id: int = 0
    nickname: str = ""
    sender_name: str = ""
    content: str = ""
    img: str = ""
    image: str = ""
    image_url: str = ""
    voice: str = ""
    voice_url: str = ""
    duration: int = 0
    voice_duration: int = 0
    add_time: str = ""
    created_at: str = ""
    create_time: str = ""
    time: str = ""
    can_recall: bool = False
    is_recalled: bool = False
    is_essence: bool = False
    is_mentioned: bool = False
    reply_to: int = 0
    raw: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: dict[str, Any] | None) -> "Message":
        data = data or {}
        return cls(
            id=_to_int(data.get("id")),
            msg_id=_to_int(data.get("msg_id")),
            uid=_to_int(data.get("uid")),
            from_uid=_to_int(data.get("from_uid")),
            user_id=_to_int(data.get("user_id")),
            nickname=_to_str(data.get("nickname")),
            sender_name=_to_str(data.get("sender_name")),
            content=_to_str(data.get("content")),
            img=_to_str(data.get("img")),
            image=_to_str(data.get("image")),
            image_url=_to_str(data.get("image_url")),
            voice=_to_str(data.get("voice")),
            voice_url=_to_str(data.get("voice_url")),
            duration=_to_int(data.get("duration")),
            voice_duration=_to_int(data.get("voice_duration")),
            add_time=_to_str(data.get("add_time")),
            created_at=_to_str(data.get("created_at")),
            create_time=_to_str(data.get("create_time")),
            time=_to_str(data.get("time")),
            can_recall=_to_bool(data.get("can_recall")),
            is_recalled=_to_bool(data.get("is_recalled")),
            is_essence=_to_bool(data.get("is_essence")),
            is_mentioned=_to_bool(data.get("is_mentioned")),
            reply_to=_to_int(data.get("reply_to")),
            raw=data,
        )

    @property
    def message_id(self) -> int:
        return self.msg_id or self.id

    @property
    def sender_id(self) -> int:
        return self.from_uid or self.uid or self.user_id

    @property
    def sender(self) -> str:
        if self.nickname:
            return self.nickname
        if self.sender_name:
            return self.sender_name
        if self.sender_id:
            return f"UID {self.sender_id}"
        return "unknown"

    @property
    def timestamp(self) -> str:
        return _first_text(
            self.raw,
            ("add_time", "created_at", "create_time", "time"),
        )

    @property
    def image_link(self) -> str:
        return self.image_url or self.image or self.img

    @property
    def voice_link(self) -> str:
        return self.voice_url or self.voice

    @property
    def body(self) -> str:
        if self.is_recalled:
            return "[recalled]"
        content = self.content.strip()
        if content:
            return content
        if self.image_link:
            return f"[image] {self.image_link}"
        if self.voice_link:
            duration = self.duration or self.voice_duration
            return f"[voice {duration}s] {self.voice_link}"
        return ""
