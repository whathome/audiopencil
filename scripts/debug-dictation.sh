#!/bin/zsh
# Drives a Debug build without key presses. Dictations started this way never paste;
# the transcript goes to the log:  log stream --predicate 'subsystem == "com.weshopkins.audiopencil"'
#
#   debug-dictation.sh start | tap-start | warm | stop | cancel
#   debug-dictation.sh key:fnDown 0.6 key:fnUp          # simulated keys through the real gesture logic
#   debug-dictation.sh page:settings snapshot           # switch page, snapshot the window
#   debug-dictation.sh scroll:end | scroll:top | appearance:light|dark|system
set -euo pipefail
cd "$(dirname "$0")/.."
binary=build/debug-dictation
if [[ ! -x $binary || scripts/debug-dictation.swift -nt $binary ]]; then
    mkdir -p build
    swiftc -O -o $binary scripts/debug-dictation.swift
fi
exec $binary "$@"
