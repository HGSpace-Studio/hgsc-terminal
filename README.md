# CsAC-Terminal

CsAC-Terminal is a Go TUI client for the UniCsAC HTTP API. The UI is built with
`github.com/rivo/tview` and `github.com/gdamore/tcell/v2`.

It uses the API entrypoint:

```text
https://103.40.14.14:14660/rpc/UniCsAC.php
```

## Features

- Login and register with PHP session cookie persistence inside the running process.
- Persist session cookies locally after login so the next launch can restore the session.
- List friends, groups, and public groups.
- Open private chats and group chats.
- Send text messages.
- Send local images from chat with `/imgsend <path> [caption]`.
- Refresh conversations and mark messages as read.
- Cache conversations and messages in local SQLite for faster startup and offline history.
- Search conversations and cached messages from the main menu or `/search` in chat.
- Send friend requests.
- View and handle incoming friend requests.
- Browse notices, mark them read, copy text, and open links.
- Switch between English and Chinese UI language.
- Create groups, apply to public groups, or join by room ID/invite code.
- View user/group info, group members, and essence messages.
- Reply to messages, recall messages, set group essence, and mention group members.
- Manage friends from user info: edit remark, delete, block, recover.
- Manage groups from group info: edit name/description/notice, edit join/public settings, and handle join applications.
- Manage group members from the members page: mute/unmute, kick, set/remove admin.
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
- Main menu `Search`: search friends, groups, and cached chat content.
- Main menu `Join Group`: join/apply by room ID, invite code, or answer.
- Chat commands:
  - `/search`: search current chat
  - `/info`: show user or group details
  - `/members`: show group members
  - `/essence`: show group essence messages
  - `/img`: list image links in the current view
  - `/imgsend <path> [caption]`: send a local image
  - `/reply <msg_id>`: reply to a message; `/reply` clears it
  - `/mention <uid,uid>`: mention users in the next group message; `/mentions` clears it
  - `/recall <msg_id>`: recall a message
  - `/essence <msg_id>`: toggle essence for a group message
- In user info, use `Remark`, `Delete Friend`, `Block Friend`, or `Recover Friend`.
- In group info, use `Edit`, `Settings`, `Applications`, `Members`, or `Essence`.
- In member detail, use `Mute`, `Unmute`, `Kick`, `Set Admin`, or `Remove Admin`.
- Error dialogs include a `Copy` button for the full error text.
- Main menu includes a friend requests page with agree/refuse actions.
- Main menu includes a notices page for `user/get_notice_list`.

## Session

After login or register, CsAC-Terminal saves the API cookies to the user config
directory, usually:

```text
%APPDATA%\CsAC-Terminal\session.json
```

On startup it loads that file and validates it with `user/get_info`. Logging out
removes the saved session file.

## Cache

Messages and conversation metadata are cached in SQLite under the user cache
directory, usually:

```text
%LOCALAPPDATA%\CsAC-Terminal\cache.db
```

The cache is used to show offline history immediately while the app refreshes
new messages from the UniCsAC API.

## Language

The default UI language is English. Use the `Language` button on the login page
or the `Language` item in the main menu to switch to Chinese. The choice is saved
to:

```text
%APPDATA%\CsAC-Terminal\config.json
```

## Notes

Image messages can be copied, opened in the system browser, downloaded to
`Downloads\CsAC-Terminal`, or sent directly from a local path. Voice messages
are decoded and displayed when returned by the API, but recording/sending voice
from the TUI is not implemented yet.

## License

Apache License 2.0. See [LICENSE](LICENSE).
