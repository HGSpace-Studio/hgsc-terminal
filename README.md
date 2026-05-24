# CsAC-Terminal

CsAC-Terminal is a Go TUI client for the UniCsAC HTTP API. The UI is built with
`github.com/rivo/tview` and `github.com/gdamore/tcell/v2`.

It uses the API entrypoint:

```text
https://cschat.ccccocccc.cc/rpc/UniCsAC.php
```

## Features

- Login and register with PHP session cookie persistence inside the running process.
- Persist session cookies locally after login so the next launch can restore the session.
- List friends, groups, and public groups.
- Open private chats and group chats.
- Send text messages.
- Refresh conversations and mark messages as read.
- Send friend requests.
- View and handle incoming friend requests.
- Create groups and apply to public groups.
- Built on tview/tcell for forms, lists, layouts, input handling, and shortcuts.

## Build

```powershell
go build -o bin\CsAC-Terminal.exe .
```

Or use the included script, which keeps the Go build cache inside the project:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

If your Go tool prints an `AppData\Roaming\go\telemetry` access warning, run this once in PowerShell:

```powershell
go telemetry off
```

## Run

```powershell
.\bin\CsAC-Terminal.exe
```

## Shortcuts

- `Ctrl+C`: quit
- `Esc`: return from list/chat views
- `F5`: refresh current list/chat
- `Enter`: send message in chat
- Error dialogs include a `Copy` button for the full error text.
- Main menu includes a friend requests page with agree/refuse actions.

## Session

After login or register, CsAC-Terminal saves the API cookies to the user config
directory, usually:

```text
%APPDATA%\CsAC-Terminal\session.json
```

On startup it loads that file and validates it with `user/get_info`. Logging out
removes the saved session file.

## Notes

The API supports images, voice messages, moderation, notices, and profile changes; the current UI focuses on the daily chat flow.

## License

Apache License 2.0. See [LICENSE](LICENSE).
