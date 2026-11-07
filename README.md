# Agent Backlight

A menu bar app that shows what Claude Code and Codex are doing on your MacBook's keyboard backlight:

| The agent is…                           | Keyboard                         | Menu bar icon            |
|-----------------------------------------|----------------------------------|--------------------------|
| working                                 | a slow breath wave               | three rolling dots       |
| waiting for you (question, permission, plan approval) | short blink bursts | a "?" that lights the key |
| done                                    | fades back to your own level     | a sun                    |

When several sessions run, the most urgent one wins: question, then thinking, then normal.
The design and every setting come from [design/agent-backlight.html](design/agent-backlight.html).

## Install

Needs macOS 14 or later on a MacBook with a backlit keyboard, and the Swift toolchain (Xcode or the Command Line Tools).

```bash
scripts/build-app.sh --install
```

```bash
open ~/Applications/AgentBacklight.app
```

Then click the keycap in the menu bar and choose **Install hooks** on the Claude Code row, the Codex row or both.
The app adds one command, `AgentBacklight.app/Contents/MacOS/agent-backlight-hook`, to the agent's hook file and keeps
the previous file next to it with `.agent-backlight.bak` added to the name. **Remove hooks** takes it out again. When a
new version listens to more events, the row shows **Update hooks** instead.

- **Claude Code**: nine events in `~/.claude/settings.json`. Restart open sessions to pick them up.
- **Codex**: six events in `~/.codex/hooks.json`. Codex skips new hooks until you trust them: when it asks, choose
  **Trust all and continue**, or review them with `/hooks`. Codex trusts each hook by its place in the file, so the app
  adds its hooks after yours and your hooks keep their trust.

The panel shows a row only for agents whose folder (`~/.claude`, `~/.codex`) exists.

To start it at login, tick **Open at login** in the panel. It adds the app to System Settings → General → Login Items,
where you can also turn it off.

## The panel

- **Signals switch**: turn the signals off for meetings or screen sharing; the keyboard goes back to your setting.
- **Thinking / Question / Normal**: the same sliders and limits as the design page. Changes apply live.
- **Play on keyboard**: plays the selected signal on the real backlight for 5 seconds.
- **Import spec…**: paste the spec copied from the design page to load every value at once.
- **Clear sessions**: ends every signal now (see the Esc note below).
- **Open at login**: starts the app when you log in. If macOS asks for your OK, the panel links to Login Items.

## How it works

- Claude Code runs `agent-backlight-hook` on `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`,
  `PostToolUseFailure`, `Notification`, `Stop`, `StopFailure` and `SessionEnd`. Codex runs it on the six of these it has:
  `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `Stop` and `SessionEnd`. Both send the event
  as JSON with the same field names. The command forwards the event to the app as a distributed notification, prints
  nothing and always exits 0, so it never changes or blocks a session. For `PermissionRequest` that means it never
  answers the prompt: the dialog appears as usual.
- `AskUserQuestion`, `ExitPlanMode`, Codex's `request_user_input`, `PermissionRequest`, and permission or elicitation
  notifications mean *question*; other tool and prompt events mean *thinking*; `Stop`, `StopFailure` and `SessionEnd`
  end the session's signal. In Claude Code, `PermissionRequest` fires as the permission dialog opens, while the
  permission notification comes about 6 seconds later.
- Codex also runs helper sessions in the background, such as memory consolidation and the suggested next message.
  They send no transcript path, and the hook command skips them: the memory session would otherwise keep the wave on
  for about a minute after your turn ends.
- While a signal runs the app pauses idle dimming. When the signal ends or the app quits, it saves your level back the
  way the brightness slider does and resumes idle dimming; if the app is killed mid-signal it does this on its next
  launch. The save matters: any brightness change an app makes pauses auto-brightness, and until a saved change ends
  that pause the keys stay dark when you type.
- macOS still notes when you go idle during a signal, but not when you come back, so resuming idle dimming would turn
  the keys off under your hands. The app then sets your idle-dim time one second longer and straight back, which makes
  macOS check again whether you're active. Your setting ends where it was.
- The light is driven through `KeyboardBrightnessClient` in the private CoreBrightness framework. The app checks every
  method it uses at launch and shows "Keyboard backlight unavailable" if a macOS update changed them.
- Every event and light change is logged to `~/Library/Logs/AgentBacklight.log`.

## Known limits

- **Esc** sends no hook event. After you interrupt Claude, the wave stops at the next `idle_prompt` notification
  (about a minute later) or when you send the next prompt. Use **Clear sessions** to stop it at once.
- Codex has no notification event, so after you interrupt Codex the wave runs until your next prompt or **Clear sessions**.
- Codex sessions that save no transcript, such as `codex exec --ephemeral`, don't show, for the same reason as the helpers.
- A permission prompt you dismiss with Esc keeps blinking until that session's next event, for the same reason.
- If you change the keyboard brightness while a signal runs, the signal overrides it until it ends.

## Develop

```bash
scripts/test.sh
```

`AgentBacklightCore` holds the rules (session priority, signal timing, spec import, settings merge) and its tests;
`AgentBacklight` is the AppKit/SwiftUI app; `agent-backlight-hook` is the hook command.
