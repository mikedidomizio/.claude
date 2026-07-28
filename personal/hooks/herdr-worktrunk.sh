#!/usr/bin/env bash

# 1. Add the following to settings.json
#   "hooks": {
#     "SessionStart": [
#       {
#         "hooks": [
#           { "type": "command", "command": "$HOME/.claude/personal/hooks/herdr-worktrunk.sh" }
#         ]
#       }
#     ]
#  },
# 2. Don't forget to `chmod +x` this script

# The script will only continue in a herdr environment, otherwise it will exit
[ "$HERDR_ENV" = "1" ] || exit 0

DOC="$HOME/.claude/personal/agents/herdr-worktrunk.md"
[ -f "$DOC" ] || exit 0

esc=$(sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' "$DOC" | awk '{printf "%s\\n", $0}')
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$esc"