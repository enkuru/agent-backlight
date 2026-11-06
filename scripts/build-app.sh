#!/bin/bash
# Builds build/AgentBacklight.app. With --install, also copies it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
bin="$(swift build -c release --show-bin-path)"

app="build/AgentBacklight.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp Packaging/Info.plist "$app/Contents/Info.plist"
cp "$bin/AgentBacklight" "$bin/agent-backlight-hook" "$app/Contents/MacOS/"
codesign --force --sign - "$app/Contents/MacOS/agent-backlight-hook"
codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  if pgrep -x AgentBacklight >/dev/null; then
    echo "Agent Backlight is running. Quit it from its menu bar panel, then run this again." >&2
    exit 1
  fi
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/AgentBacklight.app"
  ditto "$app" "$HOME/Applications/AgentBacklight.app"
  echo "Installed ~/Applications/AgentBacklight.app"
fi
