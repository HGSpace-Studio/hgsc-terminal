from __future__ import annotations

import logging
from pathlib import Path


def configure_logging(
    *,
    level: str = "INFO",
    file: str = "",
    console: bool = True,
) -> logging.Logger:
    logger = logging.getLogger("csacbot")
    logger.handlers.clear()
    logger.setLevel(_log_level(level))
    logger.propagate = False

    formatter = logging.Formatter(
        "%(asctime)s %(levelname)s [%(name)s] %(message)s",
        "%Y-%m-%d %H:%M:%S",
    )

    if console:
        handler = logging.StreamHandler()
        handler.setFormatter(formatter)
        logger.addHandler(handler)

    if file:
        path = Path(file)
        path.parent.mkdir(parents=True, exist_ok=True)
        handler = logging.FileHandler(path, encoding="utf-8")
        handler.setFormatter(formatter)
        logger.addHandler(handler)

    return logger


def close_logging(logger: logging.Logger) -> None:
    for handler in list(logger.handlers):
        handler.close()
        logger.removeHandler(handler)


def _log_level(level: str) -> int:
    return getattr(logging, level.strip().upper(), logging.INFO)
