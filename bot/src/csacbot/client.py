from __future__ import annotations

import json
import os
import re
from collections.abc import Mapping, Sequence
from typing import Any
from urllib.parse import parse_qsl, urlencode, urljoin, urlparse, urlunparse

import requests

from ._version import CLIENT_PLATFORM
from .exceptions import (
    CsacAPIError,
    CsacAuthenticationError,
    CsacChallengeError,
    CsacEmailVerificationRequired,
    CsacForbiddenError,
)
from .models import Friend, Group, GroupMember, Message, User

BROWSER_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0 Safari/537.36"
)

_CHALLENGE_VARS_RE = re.compile(
    rb'var\s+a=toNumbers\("([0-9a-fA-F]+)"\),'
    rb'b=toNumbers\("([0-9a-fA-F]+)"\),'
    rb'c=toNumbers\("([0-9a-fA-F]+)"\)'
)
_CHALLENGE_LOC_RE = re.compile(rb'location\.href="([^"]+)"')


class CsacClient:
    def __init__(
        self,
        base_url: str,
        *,
        timeout: float = 20.0,
        verify_tls: bool = False,
        platform: str = CLIENT_PLATFORM,
        session: requests.Session | None = None,
    ) -> None:
        parsed = urlparse(base_url)
        if not parsed.scheme or not parsed.netloc:
            raise ValueError("base_url must be an absolute CsAC API URL")
        self.base_url = base_url
        self.timeout = timeout
        self.verify_tls = verify_tls
        self.platform = platform
        self.session = session or requests.Session()
        self.session.verify = verify_tls
        if not verify_tls:
            self._disable_insecure_request_warning()

    @staticmethod
    def _disable_insecure_request_warning() -> None:
        try:
            import urllib3

            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        except Exception:
            pass

    def login(self, username: str, password: str) -> User:
        data = self.post_form(
            "auth/login",
            {
                "username": username,
                "pwd": password,
                "platform": self.platform,
            },
        )
        if data.get("needs_email_verification"):
            raise CsacEmailVerificationRequired(
                "account needs email verification",
                response=data,
            )
        user_data = data.get("user")
        if not isinstance(user_data, dict):
            raise CsacAPIError(
                "login succeeded but server did not return a user", response=data
            )
        return User.from_dict(user_data)

    def logout(self) -> None:
        self.post_form("auth/logout")

    def test(self) -> dict[str, Any]:
        return self.get("test")

    def current_user(self) -> User:
        data = self.get("user/get_info")
        user_data = data.get("user")
        if not isinstance(user_data, dict):
            raise CsacAPIError("server did not return current user", response=data)
        return User.from_dict(user_data)

    def friends(self) -> list[Friend]:
        data = self.get("user/get_friends")
        return [
            Friend.from_dict(item)
            for item in _extract_list(data, ("friends", "list", "data"))
        ]

    def groups(self) -> list[Group]:
        data = self.get("user/get_groups")
        return [
            Group.from_dict(item)
            for item in _extract_list(data, ("groups", "rooms", "list", "data"))
        ]

    def group_members(self, room_id: int) -> list[GroupMember]:
        data = self.get("group/get_members", {"room_id": room_id})
        return [
            GroupMember.from_dict(item)
            for item in _extract_list(data, ("members", "list", "data"))
        ]

    def group_messages(
        self,
        room_id: int,
        *,
        after_id: int = 0,
        before_id: int = 0,
        limit: int = 80,
    ) -> list[Message]:
        params: dict[str, Any] = {"room_id": room_id}
        if after_id > 0:
            params["after_id"] = after_id
        if before_id > 0:
            params["before_id"] = before_id
        if limit > 0:
            params["limit"] = limit
        data = self.get("message/get_group_msg", params)
        messages = [
            Message.from_dict(item)
            for item in _extract_list(
                data, ("messages", "msg", "message_list", "list", "data")
            )
        ]
        messages.sort(key=lambda item: item.message_id)
        return messages

    def group_messages_after(
        self, room_id: int, after_id: int, *, limit: int = 80
    ) -> list[Message]:
        return self.group_messages(room_id, after_id=after_id, limit=limit)

    def send_group_message(
        self,
        room_id: int,
        content: str,
        *,
        reply_to: int = 0,
        mention_uids: Sequence[int] | None = None,
    ) -> dict[str, Any]:
        fields = _send_fields(content, reply_to=reply_to, mention_uids=mention_uids)
        fields["room_id"] = room_id
        return self.post_form("message/send_group_msg", fields)

    def send_group_image(
        self,
        room_id: int,
        image_path: str,
        *,
        content: str = "",
        reply_to: int = 0,
        mention_uids: Sequence[int] | None = None,
    ) -> dict[str, Any]:
        fields = _send_fields(content, reply_to=reply_to, mention_uids=mention_uids)
        fields["room_id"] = room_id
        return self.post_multipart("message/send_group_msg", "img", image_path, fields)

    def mark_group_read(self, room_id: int, last_msg_id: int = 0) -> dict[str, Any]:
        fields: dict[str, Any] = {"room_id": room_id}
        if last_msg_id > 0:
            fields["last_msg_id"] = last_msg_id
        return self.post_form("message/mark_read", fields)

    def get(
        self, route: str, params: Mapping[str, Any] | None = None
    ) -> dict[str, Any]:
        return self._request("GET", route, params=params)

    def post_form(
        self, route: str, data: Mapping[str, Any] | None = None
    ) -> dict[str, Any]:
        return self._request("POST", route, data=data or {})

    def post_json(self, route: str, payload: Any) -> dict[str, Any]:
        return self._request("POST", route, json_data=payload)

    def post_multipart(
        self,
        route: str,
        file_field: str,
        file_path: str,
        data: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        with open(file_path, "rb") as handle:
            file_bytes = handle.read()
        files = {file_field: (os.path.basename(file_path), file_bytes)}
        return self._request("POST", route, data=data or {}, files=files)

    def route_url(self, route: str, params: Mapping[str, Any] | None = None) -> str:
        parsed = urlparse(self.base_url)
        query = dict(parse_qsl(parsed.query, keep_blank_values=True))
        query["route"] = route
        if params:
            for key, value in params.items():
                if value is None:
                    continue
                query[str(key)] = str(value)
        return urlunparse(parsed._replace(query=urlencode(query)))

    def _request(
        self,
        method: str,
        route: str,
        *,
        params: Mapping[str, Any] | None = None,
        data: Mapping[str, Any] | None = None,
        json_data: Any = None,
        files: Mapping[str, tuple[str, bytes]] | None = None,
    ) -> dict[str, Any]:
        url = self.route_url(route, params if method.upper() == "GET" else None)
        kwargs: dict[str, Any] = {
            "timeout": self.timeout,
            "verify": self.verify_tls,
            "headers": self._headers(method),
        }
        if method.upper() != "GET":
            if json_data is not None:
                kwargs["json"] = json_data
            else:
                kwargs["data"] = {
                    str(key): str(value) for key, value in (data or {}).items()
                }
            if files:
                kwargs["files"] = files

        response = self._send_with_challenge(method, url, kwargs)
        return self._decode_response(response)

    def _send_with_challenge(
        self,
        method: str,
        url: str,
        kwargs: dict[str, Any],
        *,
        max_retries: int = 3,
    ) -> requests.Response:
        current_url = url
        for attempt in range(max_retries + 1):
            response = self.session.request(method, current_url, **kwargs)
            if not _is_challenge_page(response.content):
                return response
            if attempt >= max_retries:
                raise CsacChallengeError(
                    f"server returned the JavaScript challenge again after {max_retries} attempt(s)"
                )
            current_url = self._solve_challenge(current_url, response.content)
        raise CsacChallengeError("server challenge retry loop exited unexpectedly")

    def _decode_response(self, response: requests.Response) -> dict[str, Any]:
        try:
            data = response.json()
        except json.JSONDecodeError as exc:
            body = response.text.strip().replace("\n", " ")[:300]
            raise CsacAPIError(
                f"decode response failed: {exc}; body: {body}",
                status_code=response.status_code,
            ) from exc

        if not isinstance(data, dict):
            raise CsacAPIError(
                "server returned a non-object JSON response",
                status_code=response.status_code,
                response={"data": data},
            )

        if response.status_code == 401:
            raise CsacAuthenticationError(
                _message(data, "not logged in"),
                status_code=response.status_code,
                response=data,
            )
        if response.status_code == 403:
            if data.get("needs_email_verification"):
                raise CsacEmailVerificationRequired(
                    _message(data, "account needs email verification"),
                    status_code=response.status_code,
                    response=data,
                )
            raise CsacForbiddenError(
                _message(data, "access forbidden"),
                status_code=response.status_code,
                response=data,
            )
        if not 200 <= response.status_code < 300:
            raise CsacAPIError(
                _message(data, f"HTTP {response.status_code}"),
                status_code=response.status_code,
                response=data,
            )
        if not data.get("success"):
            raise CsacAPIError(_message(data, "request failed"), response=data)
        return data

    def _headers(self, method: str) -> dict[str, str]:
        headers = {
            "User-Agent": BROWSER_USER_AGENT,
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Referer": self.origin_url + "/",
        }
        if method.upper() == "POST":
            headers["Origin"] = self.origin_url
        return headers

    @property
    def origin_url(self) -> str:
        parsed = urlparse(self.base_url)
        return f"{parsed.scheme}://{parsed.netloc}"

    def _solve_challenge(self, request_url: str, body: bytes) -> str:
        match = _CHALLENGE_VARS_RE.search(body)
        if not match:
            raise CsacChallengeError(
                "server returned JavaScript challenge but challenge variables were not found"
            )
        try:
            from Crypto.Cipher import AES
        except ImportError as exc:
            raise CsacChallengeError(
                "pycryptodome is required to solve the CsAC JavaScript challenge"
            ) from exc

        key = bytes.fromhex(match.group(1).decode("ascii"))
        iv = bytes.fromhex(match.group(2).decode("ascii"))
        ciphertext = bytes.fromhex(match.group(3).decode("ascii"))
        if len(iv) != 16:
            raise CsacChallengeError(f"invalid challenge IV length: {len(iv)}")
        if not ciphertext or len(ciphertext) % 16 != 0:
            raise CsacChallengeError(
                f"invalid challenge ciphertext length: {len(ciphertext)}"
            )

        plaintext = AES.new(key, AES.MODE_CBC, iv).decrypt(ciphertext)
        parsed = urlparse(request_url)
        self.session.cookies.set(
            "__test",
            plaintext.hex(),
            domain=parsed.hostname,
            path="/",
        )

        retry_url = request_url
        loc_match = _CHALLENGE_LOC_RE.search(body)
        if loc_match:
            candidate = urljoin(
                request_url, loc_match.group(1).decode("utf-8", "ignore")
            )
            candidate_parsed = urlparse(candidate)
            if (
                candidate_parsed.scheme == parsed.scheme
                and candidate_parsed.netloc == parsed.netloc
            ):
                retry_url = candidate

        retry_parsed = urlparse(retry_url)
        query = dict(parse_qsl(retry_parsed.query, keep_blank_values=True))
        query.setdefault("i", "1")
        return urlunparse(retry_parsed._replace(query=urlencode(query)))


def _is_challenge_page(body: bytes) -> bool:
    return (
        b'document.cookie="__test=' in body
        and b"/aes.js" in body
        and b"slowAES.decrypt" in body
    )


def _message(data: Mapping[str, Any], fallback: str) -> str:
    value = data.get("message")
    if isinstance(value, str) and value.strip():
        return value.strip()
    return fallback


def _extract_list(data: Any, keys: tuple[str, ...]) -> list[dict[str, Any]]:
    value = _find_list(data, keys)
    if not value:
        return []
    return [item for item in value if isinstance(item, dict)]


def _find_list(data: Any, keys: tuple[str, ...]) -> list[Any]:
    if isinstance(data, list):
        return data
    if not isinstance(data, dict):
        return []
    for key in keys:
        value = data.get(key)
        if isinstance(value, list):
            return value
        if isinstance(value, dict):
            nested = _find_list(
                value, ("messages", "members", "groups", "friends", "list", "data")
            )
            if nested:
                return nested
    return []


def _send_fields(
    content: str,
    *,
    reply_to: int = 0,
    mention_uids: Sequence[int] | None = None,
) -> dict[str, Any]:
    fields: dict[str, Any] = {}
    if content.strip():
        fields["content"] = content
    if reply_to > 0:
        fields["reply_to"] = reply_to
    mentions = [str(uid) for uid in (mention_uids or []) if uid > 0]
    if mentions:
        fields["mention_uids"] = ",".join(mentions)
    return fields
