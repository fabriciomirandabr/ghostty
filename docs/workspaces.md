# Ghostty Workspaces

## What it is

Ghostty Workspaces is a fork of Ghostty for macOS that adds workspaces to the terminal window. Its purpose is to control several projects from one window.

A window holds a list of workspaces. A workspace is a project, backed by a folder. Tabs are terminals inside a workspace. Each terminal carries its own activity indicator, and a badge at the right of the title bar summarizes the activity of the whole window. Two overlays give the overview: a grid of all workspaces and a popover listing the terminals in progress.

![Workspace grid](images/workspaces/workspace-grid.png)

macOS only. Based on Ghostty 1.4.1-dev at commit e95bed6.

Repository: https://github.com/fabriciomirandabr/ghostty

## Install

1. Download the `.dmg` or `.zip` from GitHub Releases.
2. Move the app to `/Applications`.
3. Launch it.

The build is self-signed and not notarized, so Gatekeeper blocks the first launch. Open it once with a right-click and then Open, or remove the quarantine attribute from the app bundle:

```
xattr -d com.apple.quarantine "/Applications/Ghostty Workspaces.app"
```

The app installs beside stock Ghostty. It has its own bundle id `com.fabriciomirandabr.ghostty-workspaces` and shares `~/.config/ghostty/config` with stock Ghostty.

## Opt out

The workspaces UI is on by default, with no config line needed. To go back to the upstream look (the upstream default was `transparent`), set the style in `~/.config/ghostty/config`:

```
macos-titlebar-style = transparent
```

The accepted values are `workspaces` (the default), `tabs`, `native`, `transparent` and `hidden`. The upstream default was `transparent`. The workspace keybind defaults and the workspaces window are also off when `window-decoration = none`. A change applies to new windows. Existing windows keep the style they were opened with, and the other styles keep upstream behavior.

To choose where the terminals of the `Default` workspace start, set:

```
workspace-default-directory = ~/code
```

The value is an absolute path or a path with a `~/` prefix. A path that does not exist or is not a directory is reported as a config error. The default is your home directory.

## Using it

### Default workspace

Every window has a workspace called `Default`, first in the list. It cannot be closed: its Close Workspace menu item is disabled and it has no x.

### Tabs

The tab bar shows one pill per tab of the active workspace: a circle state indicator on the left, the name, and an x on hover or when active. The `+` after the last pill opens a new terminal.

![Tab bar](images/workspaces/tab-bar.png)

![Renaming a tab](images/workspaces/rename.png)

Rename a tab with `F2` (action `prompt_tab_title`) or a double click. An inline field appears, `Enter` applies the name (40 characters maximum), `Esc` cancels. Names persist.

### Workspace menu

The workspace button (chevron plus name) in the title bar opens a menu:

- The workspace list, each entry with state indicator, running count (`N running`), abbreviated folder and, for the first nine, its shortcut.
- Switch Workspace, New Workspace, New Terminal, Close Workspace, Show All.
- A Font Size submenu with 12, 13, 14, 15, 16 and 18.

Close Workspace is disabled on `Default`.

![Workspace menu](images/workspaces/workspace-menu.png)

### New workspace

New Workspace opens a sheet with Name and Folder. `Choose...` opens a folder picker and pre-fills Name with the last path component, for example `api` for `~/code/api`. A duplicate name, compared case-insensitively, shows `A workspace with this name already exists.` and disables Create.

Every new terminal in a workspace starts in the workspace folder, not in the working directory of the focused terminal.

### Closing tabs and workspaces

Closing the last tab of a workspace opens a fresh shell tab. A workspace never has zero tabs.

Closing a workspace happens immediately when nothing is running. Otherwise an inline confirmation lists the running terminals (`N terminals running. Close anyway?`) with Cancel and Close. Closing selects the previous workspace in the list. Close a workspace from the menu, the card x or `Cmd+Shift+W`.

Inactive workspaces keep their processes alive and keep updating the badge.

### Activity badge

The badge at the right of the title bar counts the running terminals across the window. The badge is a circle with a dark fill and a white digit or grid icon in dark mode, and a light fill with a dark digit in light mode. The fill is the same whether or not anything runs. While the count is above zero a thin static ring surrounds the badge at 60% opacity: white in dark mode and dark ink in light mode, or yellow in dark mode and dark amber in light mode when a terminal needs you. Nothing animates. An orange dot appears when a terminal needs you.

Terminal states:

- running: blue
- needs you: yellow
- done: white, kept for 10 seconds, then idle
- idle

Aggregation priority: needs you, running, done, idle.

### Activity popover

Hover the badge for 250 ms, or press `Cmd+J`, to open the popover. It lists the terminals that are not idle, sorted by priority. Each row has a round indicator in the same style as the badge (no digit, since a row is one terminal: a static ring when running, a yellow dot and a yellow ring when it needs you, a check when done), the tab name and `workspace · last command`. A click goes to that tab. An empty list shows `No terminals in progress.` The footer `Show workspaces` opens the grid.

![Activity popover](images/workspaces/activity-popover.png)

### Workspace grid

Click the badge, or press `Cmd+O`, to open the grid of workspace cards. Each card has a thumbnail, a state badge (Running, Needs you, Done), the name and the folder. The header menu offers `Sort by name` and `Sort by activity`, with `Default` always first. A `+ New workspace` card sits in the grid. A click selects a workspace, `Esc` closes the grid. The thumbnail of the active workspace is live; inactive ones show the last snapshot taken when you left them.

### Quick switcher

`Cmd+K` opens a switcher that searches by name or folder. Arrow keys move, `Enter` selects, `Esc` closes. No result shows `No workspace found.`

### Splits

When a tab has splits, every pane gets a 24 pt header with the title and an x on hover. The active pane has a thin line on top. A tab without splits has no headers.

![Split pane headers](images/workspaces/split-headers.png)

### Power

The workspaces chrome adapts to the machine automatically, with no setting. It switches to a saver mode when Low Power Mode is on, when the thermal state is serious or critical, or when the Mac runs on battery, and goes back to performance mode as soon as none of them holds. The saver mode only slows the chrome refresh: the title bar, the activity badge, the overlays and the persistence check all run on that refresh, so they update at most once per second instead of five times, and the grid thumbnails are captured and redrawn every 2 seconds instead of every 0.5 s. It changes nothing else: terminals and notifications behave the same. Each mode change is logged once at info level.

Thumbnails are stored at the size of the card (at most 480 points wide), so a snapshot takes a small fraction of the memory of a full capture. Captures are skipped while the window is not key or is hidden.

### Persistence

Workspaces, tabs, names, folders and the selection are saved in two places:

- The macOS window state, written when you quit. With `window-save-state = always` the window comes back with its splits and working directories on the next launch.
- A JSON file at `~/Library/Application Support/com.fabriciomirandabr.ghostty-workspaces/workspaces.json`. It keeps the workspace list (name, folder, which one is selected) and, per tab, the name you gave it, the working directory of the focused terminal, the resume token reported by a program in that terminal (see [Resume Claude Code](#resume-claude-code)) and the selected tab. The file is version 2; an older version of the app leaves a version 2 file untouched until you change a workspace or tab.

One window is persisted: the primary workspaces window. A window becomes primary when it was restored with its workspaces (by macOS or from the file) or when it was opened while no other workspaces window existed; a window opened next to an existing one never becomes primary on its own, and a window restored by macOS from a state without workspaces never claims the role. A window restored by macOS claims the role only when it shares at least one workspace with the saved file as it was at launch (or when there is no readable file and it is the first), so a scratch window never takes the role from the window that owns the saved projects, and a restored window writes nothing until its state changes. If macOS restored windows but none of them owns the saved file, one extra window is opened from the file at launch so the saved projects are visible again and become the persisted ones. When the primary window closes, the role passes to the oldest remaining workspaces window that was allowed to claim it (restored with workspaces that match the file, or opened when no other workspaces window existed); a window opened next to another workspaces window or restored without workspaces never becomes primary by hand-off, so closing the primary window never lets a scratch window overwrite its projects. The new primary writes on its next change. Other windows never write or delete the file. Saves happen at most once per second after a change, and again when the primary window closes or the app quits; nothing is written when the state did not change, and a failed write is retried on the next change or at close.

When a new window is requested and no workspaces window exists (at launch when macOS did not restore one, from the Dock icon, `Cmd+N`, a folder opened from Finder, the `new_window` action, Services, AppleScript or Shortcuts), the window is rebuilt from the file: each tab gets a fresh shell in its saved directory, falling back to the workspace folder and then to your home folder when a directory no longer exists. A tab that saved a resume token and whose own directory still exists also starts the program again (see [Resume Claude Code](#resume-claude-code)). A requested folder or command opens as a new tab in `Default`. So closing the window with the red button and opening it again brings the projects back. A file written by a newer version of the app is left untouched until you change a workspace or tab (directory changes alone do not count).

`window-save-state = never` disables both: nothing is saved, the file is deleted, and nothing is restored.

Closing the window or quitting asks for confirmation, taking all workspaces into account.

## Keyboard shortcuts

The defaults below are installed only when `macos-titlebar-style = workspaces` (the default) and the window is decorated (`window-decoration` is not `none`). Under any other style the stock bindings apply. An explicit `keybind` of yours always wins. Each default replaces one stock binding, and only that one: `Cmd+K` (`clear_screen`), `Cmd+J` (`scroll_to_selection`), `Cmd+G` (`navigate_search:next`), `Cmd+Shift+W` (`close_window`), `Cmd+Shift+[` (`previous_tab`), `Cmd+Shift+]` (`next_tab`). The defaults are not applied when `keybind = clear` is used.

In a window that is not a workspace window (the quick terminal) the workspace shortcuts do nothing. `Cmd+K`, `Cmd+J`, `Cmd+G`, `Cmd+O` and `Opt+Cmd+1` to `9` are `performable`, so the key passes to the program there. `Cmd+Shift+W`, `Cmd+Shift+[` and `Cmd+Shift+]` are consumed like the stock bindings they replace. Performable bindings show no shortcut symbol in menus or in the command palette. The workspace entries are hidden from the command palette outside workspace windows. `F2` renames the tab in workspace windows and in the quick terminal, so programs never receive it; rebind it with `keybind = f2=unbind` or bind another key to `prompt_tab_title`. Rebind with `keybind =` if you need something else. The defaults are defined in `src/config/Config.zig`.

| Shortcut | Action |
| --- | --- |
| `Cmd+T` | `new_tab` |
| `Cmd+G` | `new_workspace` |
| `Cmd+K` | `toggle_workspace_switcher` |
| `Cmd+O` | `toggle_workspace_overview` |
| `Cmd+J` | `toggle_activity_popover` |
| `Cmd+Shift+W` | `close_workspace` |
| `Opt+Cmd+1` to `9` | `goto_workspace:N` |
| `Cmd+Shift+[` | `previous_workspace` |
| `Cmd+Shift+]` | `next_workspace` |
| `Cmd+1` to `9` | `goto_tab:N` (tab N of the active workspace) |
| `Cmd+D` | `new_split:right` |
| `Cmd+Shift+D` | `new_split:down` |
| `F2` | `prompt_tab_title` |

`Cmd+W` closes the pane or the tab.

Example rebind:

```
keybind = super+shift+n=new_workspace
```

All the workspace actions except `goto_workspace` are also available in the command palette (`goto_workspace`, like `goto_tab`, has no palette entry). On other title bar styles the workspace actions do nothing.

## Agent and CLI integration

### Activity state sources

A terminal becomes running on `OSC 133;C` (command start, which needs shell integration) until `133;D`, or on `OSC 9;4` with set or indeterminate progress. It needs you on a bell, an `OSC 9` or `OSC 777` desktop notification, or `OSC 9;4` error or pause. It is done when a command finishes (`OSC 133;D`) or a program reports status done. Without shell integration or a status report the terminal stays idle. There is no heuristic based on titles.

### OSC 7501 Program Status Protocol

A program uses this protocol to report what it is doing. Format:

```
ESC ] 7501 ; key=value:key=value ESC \
```

Keys:

- `state`: `idle`, `working`, `blocked`, `done`, `error` or `clear`
- `kind`: `permission`, `question` or `auth`, used with `blocked`
- `progress`: integer
- `title`, `msg`: base64 text. The parser accepts a title of up to 192 bytes and a message of up to 2048 bytes (decoded). The app keeps at most 127 bytes of the title and 255 bytes of the message, cut at a character boundary, so that is what the popover and the notifications can show
- `app`: short name, up to 32 bytes
- `id`: separates concurrent records, one record per id, each report replaces its record; `state=clear` removes the record of that id, or all records when no id is given
- `resume`: `<program>/<token>`, up to 97 bytes. The terminal remembers it for the tab and uses it when the tab is restored; an empty value (`resume=`) forgets it. It is read in every report, including a `clear` for an id nobody uses, which leaves the activity state as it was. See [Resume Claude Code](#resume-claude-code)

A whole sequence is at most 4096 bytes. Mapping to the indicator: `working` is running, `blocked` and `error` are needs you, `done` is done and `idle` is idle. `clear` removes the record and the terminal returns to the state derived from the shell (running when a command is in flight, otherwise idle). A new shell command (`OSC 133;C`) or the shell exiting also drops the records, so a status left behind by a program that quit does not hide later activity. At most 64 records are kept per terminal, the oldest is evicted first.

Send `ESC ] 7501 ; ? ESC \` to probe. A supporting terminal answers with `ESC ] 7501 ; ?:states=idle,working,done,blocked,error:kinds=...`.

Recent Claude Code versions emit the protocol.

Example with `printf`:

```sh
printf '\e]7501;state=working:app=build\e\\'
# ...
printf '\e]7501;state=done:app=build\e\\'
```

With a base64 message:

```sh
printf '\e]7501;state=blocked:kind=question:app=build:msg=%s\e\\' "$(printf 'Overwrite dist/?' | base64)"
```

### Resume Claude Code

A tab that had a Claude Code conversation open can come back inside the same conversation instead of in a bare shell.

How it works:

1. A hook in Claude Code tells the terminal the id of the live session with `resume=claude/<session-id>` (OSC 7501, see above).
2. The terminal keeps only the program name and the id for each tab, taken from the focused terminal of the tab, and saves them with the rest of the workspace state.
3. When the tab is restored, from the saved file or from the macOS window state, its shell starts in the saved directory and `claude --resume <session-id>` is typed into it as the first input. The shell stays open, so quitting Claude Code leaves you at the prompt. If `claude` is not in the `PATH`, the shell shows its own error and stays open.

Three tabs in three folders with three conversations come back as three conversations, all started at the same time. A restored tab holds its id from the start, so quitting again before the hook reports keeps it; the first report from the hook replaces it.

The terminal never stores or runs a command taken from the escape. It accepts the program `claude` only, and a token that is a session id: 36 characters in lowercase UUID form (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`, hex digits `0-9a-f`), so a token can never start with `-` and become a flag; anything else is ignored. When shell integration reports the command running in the terminal, the id is accepted only if the command line contains `claude` as a whole word (split on spaces, `/`, `=`, `;`, `&` and `|`), so wrappers such as `env A=1 claude` or `/path/to/claude` work and `cat notes` or `myclaude` do not. The command is built by the app from those two values. The saved file is checked again when it is read.

The report that carries the id is `state=clear:id=resume:resume=claude/<session-id>`. A `clear` for an id that has no record changes nothing, so the status Claude Code reports about itself is not disturbed. `state=clear:id=resume:resume=` forgets the id. The id is also forgotten when a shell command starts or finishes (needs shell integration) and when the terminal's process exits.

Setup:

1. Copy [`hooks/claude-code-resume.sh`](hooks/claude-code-resume.sh) to `~/.config/ghostty/hooks/claude-code-resume.sh`.
2. Add the hooks to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "sh \"$HOME/.config/ghostty/hooks/claude-code-resume.sh\" set"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "sh \"$HOME/.config/ghostty/hooks/claude-code-resume.sh\" clear"
          }
        ]
      }
    ]
  }
}
```

The script takes exactly one argument: `set` (read `session_id` from the hook input and report it) or `clear` (forget it). The two entries above pass them; any other argument does nothing. `SessionStart` reports the id each time a session starts, resumes, is cleared or is compacted, so the saved id is always the live one. `SessionEnd` forgets it when the session ends.

Claude Code runs hooks without a controlling terminal, so a hook cannot write to `/dev/tty`, and its `terminalSequence` output does not accept OSC 7501. The script instead reads `session_id` from the JSON on standard input, follows the parent processes (up to 12 levels, with `ps -o tty=` and `ps -o ppid=`) until it finds the terminal device of the `claude` process, and writes the escape sequence there if the device is writable. It prints nothing to standard output, because the output of a `SessionStart` hook is added to the conversation. It exits `0` in every case: outside Ghostty (`TERM_PROGRAM` is not `ghostty`), when no terminal device is found, or when the session id is not in lowercase UUID form. Writing to the terminal device of a parent process is not something the Claude Code documentation covers; if a Claude Code version stops allowing it, the script does nothing and tabs come back as plain shells.

Turn it off with:

```
workspace-resume-programs = false
```

With `false` nothing is saved and nothing is started on restore. The default is `true`. With `window-save-state = never` nothing is saved or restored either.

Limitations:

- Only `claude` is supported.
- Without shell integration, only the `SessionEnd` hook forgets the id when you quit Claude Code.
- Quitting Ghostty keeps the id of a running conversation, so the next launch resumes it.
- The saved file keeps one token per tab, from the focused pane, so only that pane is resumed when a window is rebuilt from the file; the other panes of a split come back as shells. The macOS window state keeps a token per pane, so with `window-save-state = always` every pane that reported one is resumed.
- A tab whose own directory no longer exists comes back as a shell in the workspace folder, without resuming.
- tmux and screen are not supported: inside them `TERM_PROGRAM` is not `ghostty`, so the script exits.
- Resuming starts one `claude` process per tab at once.

### macOS notifications

A notification fires when a job finishes (running, then done) or needs you, if that terminal is not the focused one of the active workspace and tab. The title is `tab name · workspace name`, the body is `Done` or `Needs you`, plus up to 120 characters of detail from the program status message. A click focuses the workspace and the tab. Repeated notifications for the same terminal within 2 seconds are coalesced, and a needs-you notification is retracted when the state changes. macOS asks for permission on first launch.

Disable them with:

```
workspace-notifications = false
```

They are also off when the Ghostty option `desktop-notifications = false` is set. Terminal-requested `OSC 9` and `OSC 777` notifications are unaffected by `workspace-notifications`. The default is `true`.

### Pasting images

`Cmd+V` with an image on the clipboard sends `Ctrl+V` (0x16), so TUI agents read the image themselves. With any text on the clipboard, a copied path included, the paste is normal.

```
macos-paste-image-sends-ctrl-v = false
```

The default is `true`.

## Building from source

Requirements: Zig 0.17.0 (see `minimum_zig_version` in `build.zig.zon`) and Xcode 26.

```
zig build -Demit-macos-app=false -Doptimize=ReleaseFast
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Release build
```

SwiftPM can hang while resolving Sparkle if the login keychain is locked. Unlock it first. If you redistribute, sign the app with your own identity and set your own bundle id.

## Differences from upstream

- `macos/Sources/Features/Workspaces/` holds the model, title bar, overlays, activity tracking and notifier.
- New `macos-titlebar-style` value `workspaces`, which is the default in this fork (upstream: `transparent`).
- Handler and app plumbing for the existing OSC 7501 parser (`src/terminal/osc/parsers/program_status.zig`): `src/termio/stream_handler.zig`, the `program_status` action and the macOS activity tracking.
- New `command_started` action from `OSC 133;C` into the app.
- Eight new keybind actions (`new_workspace`, `close_workspace`, `goto_workspace`, `previous_workspace`, `next_workspace`, `toggle_workspace_overview`, `toggle_workspace_switcher`, `toggle_activity_popover`), all with command palette entries except `goto_workspace`.
- New config keys `workspace-default-directory`, `workspace-notifications`, `workspace-resume-programs`, `macos-paste-image-sends-ctrl-v`.
- New `resume` key in the OSC 7501 parser, carried into the app by the `program_status` action, and `workspaces.json` version 2 with a per-tab resume token.
- Restorable state version 8.
- Renamed bundle id.

Other title bar styles keep upstream behavior. On Linux/GTK there is no UI and the new actions are no-ops.

## Known limitations

- macOS only.
- The font size picked from the workspace menu applies to the current terminals. It is not applied to surfaces created later and is not persisted; set `font-size` in the config instead.
- Fullscreen bar height differs from windowed height.
- The build is not notarized.
- Features tied to native tab groups are off under this style: dragging a tab between windows, Merge All Windows, `close_other_tabs`, `close_tabs_right`, `move_tab_to_new_window`, AppleScript tab groups.
- `Cmd+N` opens a second, independent workspaces window.
- UI text is English only.
- An agent that asks a question without OSC 7501 or a bell is not detected.
- Resuming a Claude Code conversation needs the hook from [Resume Claude Code](#resume-claude-code); see its limitations.
- Switching away from the workspaces style after saving state restores only the visible tab; hidden workspaces are dropped (their shells are started during decoding and then discarded).
