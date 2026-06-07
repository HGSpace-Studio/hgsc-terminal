from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

import requests


class SessionStore:
    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)

    def load(self, session: requests.Session) -> bool:
        if not self.path.exists():
            return False
        with self.path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
        cookies = payload.get("cookies", [])
        if not isinstance(cookies, list):
            return False
        for item in cookies:
            if not isinstance(item, dict):
                continue
            name = str(item.get("name", "")).strip()
            value = str(item.get("value", ""))
            if not name:
                continue
            session.cookies.set(
                name,
                value,
                domain=_optional_str(item.get("domain")),
                path=_optional_str(item.get("path")) or "/",
                secure=bool(item.get("secure", False)),
                rest=item.get("rest") if isinstance(item.get("rest"), dict) else None,
            )
        return True

    def save(self, session: requests.Session) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "saved_at": int(time.time()),
            "cookies": [
                {
                    "name": cookie.name,
                    "value": cookie.value,
                    "domain": cookie.domain,
                    "path": cookie.path,
                    "secure": cookie.secure,
                    "expires": cookie.expires,
                    "rest": dict(cookie._rest),
                }
                for cookie in session.cookies
            ],
        }
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)
        tmp.replace(self.path)

    def clear(self) -> None:
        if self.path.exists():
            self.path.unlink()


def _optional_str(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value)
    return text or None
