from __future__ import annotations

from typing import Any


class CsacBotError(Exception):
    """Base error for the CsAC bot framework."""


class CsacAPIError(CsacBotError):
    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = None,
        response: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.response = response or {}


class CsacAuthenticationError(CsacAPIError):
    """Raised when the current session is missing or expired."""


class CsacForbiddenError(CsacAPIError):
    """Raised when the API returns HTTP 403."""


class CsacEmailVerificationRequired(CsacForbiddenError):
    """Raised when the account must finish email verification before syncing."""


class CsacChallengeError(CsacBotError):
    """Raised when the JavaScript challenge cannot be solved or replayed."""


class CsacPluginPermissionError(CsacBotError):
    def __init__(self, plugin: str, permission: str) -> None:
        super().__init__(f"plugin {plugin!r} requires permission {permission!r}")
        self.plugin = plugin
        self.permission = permission


class CsacCommandDeniedError(CsacBotError):
    """Raised when a command is blocked by command-level rules."""
