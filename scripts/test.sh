#!/bin/bash
# Runs the unit tests. With only the Command Line Tools installed, swift test can't find Swift Testing by itself.
set -euo pipefail
cd "$(dirname "$0")/.."

developer="$(xcode-select -p)"
if [[ "$developer" == *CommandLineTools* ]]; then
  frameworks="$developer/Library/Developer/Frameworks"
  exec swift test \
    -Xswiftc -F -Xswiftc "$frameworks" \
    -Xlinker -rpath -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$developer/Library/Developer/usr/lib" \
    "$@"
fi
exec swift test "$@"
