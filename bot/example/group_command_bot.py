from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from csacbot import (
    CLIENT_PLATFORM,
    BotConfig,
    BotRunner,
    CsacClient,
    GroupBot,
    JsonPluginStorage,
    SessionStore,
    configure_logging,
    load_plugins,
)
from csacbot.exceptions import CsacEmailVerificationRequired


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a CsAC group command bot.")
    parser.add_argument(
        "--config",
        default=str(Path(__file__).resolve().parent / "config.toml"),
        help="TOML config file path",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config = BotConfig.from_file(args.config)
    logger = configure_logging(
        level=config.log_level,
        file=config.log_file,
        console=config.log_console,
    )
    client = CsacClient(base_url=config.base_url)
    session_store = SessionStore(config.session_file) if config.save_session else None
    plugin_storage = JsonPluginStorage(config.storage_file)

    def create_bot(bot_client):
        bot = GroupBot(
            bot_client,
            room_ids=config.room_ids,
            prefixes=config.prefixes,
            poll_interval=config.poll_interval,
            ignore_self=config.ignore_self,
            replay_existing=config.replay_existing,
            mark_read=config.mark_read,
            task_enabled=config.task_enabled,
            plugin_config=config.plugin_config,
            storage=plugin_storage,
            logger=logger,
        )
        bot.config = config

        @bot.on_unknown_command
        def unknown(ctx):
            return f"未知命令：{ctx.command}。发送 {ctx.prefix}help 查看命令列表。"

        loaded_plugins = load_plugins(
            bot,
            config.plugins,
            search_paths=config.plugin_paths,
            watch=config.plugin_watch,
            watch_interval=config.plugin_watch_interval,
        )
        logger.info(
            "loaded plugins: %s",
            ", ".join(loaded_plugins) if loaded_plugins else "none",
        )
        return bot

    runner = BotRunner(
        config,
        client=client,
        bot_factory=create_bot,
        session_store=session_store,
        logger=logger,
    )
    logger.info("client platform: %s", CLIENT_PLATFORM)
    logger.info(
        "listening rooms: %s",
        ", ".join(str(room_id) for room_id in config.room_ids),
    )
    try:
        runner.run_forever()
    except CsacEmailVerificationRequired as exc:
        raise SystemExit("账号需要先完成邮箱验证，bot 暂不继续同步。") from exc


if __name__ == "__main__":
    main()
