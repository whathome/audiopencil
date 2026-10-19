#!/bin/zsh
# Writes Config/Signing.local.xcconfig so builds are signed with your free Personal Team.
# A stable signature means macOS keeps the Accessibility grant across rebuilds.
#
# Prerequisite: Xcode > Settings > Accounts > add your Apple ID, then select the
# Personal Team and click "Manage Certificates…" > + > Apple Development.
#
# Usage: scripts/set-team.sh            (detects the team from your Apple Development certificate)
#        scripts/set-team.sh ABCDE12345 (explicit team ID)
set -euo pipefail
cd "$(dirname "$0")/.."

team="${1:-}"
if [[ -z "$team" ]]; then
    cert=$(security find-certificate -c "Apple Development" -p 2>/dev/null || true)
    if [[ -z "$cert" ]]; then
        echo "No Apple Development certificate found. Add your Apple ID in Xcode > Settings > Accounts first." >&2
        exit 1
    fi
    team=$(print -r -- "$cert" | openssl x509 -noout -subject -nameopt multiline | awk -F' = ' '/organizationalUnitName/ {print $2; exit}')
fi

if [[ ! "$team" =~ '^[A-Z0-9]{10}$' ]]; then
    echo "That doesn't look like a team ID: '$team'" >&2
    exit 1
fi

cat > Config/Signing.local.xcconfig <<EOF
DEVELOPMENT_TEAM = $team
CODE_SIGN_IDENTITY = Apple Development
EOF
echo "Signing with team $team. Rebuild, then grant Accessibility once more (the last time)."
