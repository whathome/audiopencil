#!/bin/zsh
# Drives a Debug build without key presses. Dictations started this way never paste;
# the transcript goes to the log:  log stream --predicate 'subsystem == "com.weshopkins.audiopencil"'
#
#   debug-dictation.sh start | tap-start | warm | stop | cancel
#   debug-dictation.sh key:fnDown 0.6 key:fnUp          # simulated keys through the real gesture logic
#   debug-dictation.sh page:settings snapshot           # switch page, snapshot the window
#   debug-dictation.sh settings:dictation snapshot      # general, dictation, notes, storage, models, permissions
#   debug-dictation.sh scroll:end | scroll:top | scroll:<points> | appearance:light|dark|system
#   debug-dictation.sh window:report                  # current width and native resize limits
#   debug-dictation.sh languages:en,fr,es | language:fr | report:language
set -euo pipefail
cd "$(dirname "$0")/.."
binary=build/debug-dictation
if [[ ! -x $binary || scripts/debug-dictation.swift -nt $binary ]]; then
    mkdir -p build
    swiftc -O -o $binary scripts/debug-dictation.swift
fi
exec $binary "$@"
