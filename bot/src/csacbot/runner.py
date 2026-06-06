from __future__ import annotations

import logging
import time
from collections.abc import Callable

from .bot import GroupBot
from .client import CsacClient
from .config import BotConfig
from .exceptions import CsacAuthenticationError
from .logging import close_logging
from .models import User
from .session import SessionStore


BotFactory = Callable[[CsacClient], GroupBot]


class BotRunner:
    def __init__(
        self,
        config: BotConfig,
        *,
        client: CsacClient,
        bot_factory: BotFactory,
        session_store: SessionStore | None = None,
        logger: logging.Logger | None = None,
    ) -> None:
        self.config = config
        self.client = client
        self.bot_factory = bot_factory
        self.session_store = session_store
        self.logger = logger or logging.getLogger("csacbot")
        self.bot: GroupBot | None = None
        self.user: User | None = None

    def login(self) -> User:
        if self.session_store is not None and self.session_store.load(self.client.session):
            self.logger.info("loaded saved session cookies")
            try:
                self.user = self.client.current_user()
                self.logger.info(
                    "restored saved session as %s (UID %s)",
                    self.user.display_name,
                    self.user.uid,
                )
                return self.user
            except CsacAuthenticationError:
                self.logger.warning("saved session expired; logging in with password")
                self.session_store.clear()

        self.user = self.client.login(self.config.username, self.config.password)
        self.logger.info(
            "logged in as %s (UID %s)",
            self.user.display_name,
            self.user.uid,
        )
        self.save_session()
        return self.user

    def save_session(self) -> None:
        if self.session_store is None:
            return
        self.session_store.save(self.client.session)
        self.logger.debug("saved session cookies")

    def start(self) -> None:
        self.login()
        self.bot = self.bot_factory(self.client)
        self.logger.info("starting bot")
        self.bot.start()
        self.save_session()

    def run_forever(self) -> None:
        self.start()
        assert self.bot is not None
        try:
            while self.bot.running:
                try:
                    self.bot.poll_once()
                    time.sleep(min(self.bot.poll_interval, 1.0))
                except CsacAuthenticationError:
                    self.logger.warning("session expired while polling; logging in again")
                    user = self.login()
                    self.bot.me = user
                except KeyboardInterrupt:
                    self.logger.info("keyboard interrupt received; stopping bot")
                    self.bot.stop()
        finally:
            if self.bot is not None and self.bot.running:
                self.bot.stop()
            self.save_session()
            self.logger.info("bot stopped")
            close_logging(self.logger)
