#!/bin/zsh
# Drives a Debug build's dictation loop without key presses: start | stop | cancel.
# Dictations started this way never paste; the transcript goes to the log instead:
#   log stream --predicate 'subsystem == "com.weshopkins.audiopencil"'
set -euo pipefail
command="${1:?usage: debug-dictation.sh start|stop|cancel}"
swift - "$command" <<'SWIFT'
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.weshopkins.audiopencil.debug"),
    object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)
SWIFT
