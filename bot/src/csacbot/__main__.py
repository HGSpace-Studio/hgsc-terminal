from __future__ import annotations

import argparse
from pathlib import Path

from .plugins import check_plugin, create_plugin


def main() -> None:
    parser = argparse.ArgumentParser(prog="csacbot")
    subparsers = parser.add_subparsers(dest="command", required=True)

    plugin_parser = subparsers.add_parser("plugin", help="plugin development tools")
    plugin_subparsers = plugin_parser.add_subparsers(dest="plugin_command", required=True)

    check_parser = plugin_subparsers.add_parser("check", help="check a plugin")
    check_parser.add_argument("path", help="plugin directory or .py file")

    new_parser = plugin_subparsers.add_parser("new", help="create a plugin project")
    new_parser.add_argument("name", help="plugin name")
    new_parser.add_argument(
        "--path",
        default="plugins",
        help="plugin root directory, default: plugins",
    )

    args = parser.parse_args()
    if args.command == "plugin" and args.plugin_command == "check":
        messages = check_plugin(args.path)
        if messages:
            for message in messages:
                print(f"ERROR: {message}")
            raise SystemExit(1)
        print("OK")
        return
    if args.command == "plugin" and args.plugin_command == "new":
        path = create_plugin(Path(args.path), args.name)
        print(f"created plugin: {path}")
        return


if __name__ == "__main__":
    main()
