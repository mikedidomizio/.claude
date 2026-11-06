#!/bin/bash
#
# Claude Code status line: model, directory, git status, context window usage,
# plan usage limits (Pro/Max) and your last message.
#
#   Opus 5.5 | 📁my-app | 🔀main (2 files uncommitted, synced 5m ago) | ███▄░░░░░░ 35% of 200k tokens
#   Session ████▄░░░░░ 43% · resets in 2h 15m (3:00pm)   Weekly ███████▄░░ 74% · resets in 3d 11h (Mon 9:00am)
#   💬 refactor the auth middleware to use the new session store
#
# Usage limits turn yellow at 70% and red with a ⚠ at 90%. That line is hidden
# for API key, Bedrock and Vertex sessions, which have no plan limits.
#
# Install (requires jq):
#   mkdir -p ~/.claude/scripts
#   cp context-bar.sh ~/.claude/scripts/ && chmod +x ~/.claude/scripts/context-bar.sh
#
# Then add to ~/.claude/settings.json:
#   "statusLine": {
#     "type": "command",
#     "command": "~/.claude/scripts/context-bar.sh"
#   }

# Color theme: gray, orange, blue, teal, green, lavender, rose, gold, slate, cyan
# Preview colors with: bash scripts/color-preview.sh
COLOR="blue"

# Color codes
C_RESET='\033[0m'
C_GRAY='\033[38;5;245m'  # explicit gray for default text
C_BAR_EMPTY='\033[38;5;238m'
case "$COLOR" in
    orange)   C_ACCENT='\033[38;5;173m' ;;
    blue)     C_ACCENT='\033[38;5;74m' ;;
    teal)     C_ACCENT='\033[38;5;66m' ;;
    green)    C_ACCENT='\033[38;5;71m' ;;
    lavender) C_ACCENT='\033[38;5;139m' ;;
    rose)     C_ACCENT='\033[38;5;132m' ;;
    gold)     C_ACCENT='\033[38;5;136m' ;;
    slate)    C_ACCENT='\033[38;5;60m' ;;
    cyan)     C_ACCENT='\033[38;5;37m' ;;
    *)        C_ACCENT="$C_GRAY" ;;  # gray: all same color
esac

input=$(cat)

# Extract model, directory, and cwd
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
cwd=$(echo "$input" | jq -r '.cwd // empty')
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Get git branch, uncommitted file count, and sync status
branch=""
git_status=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        # Count uncommitted files
        file_count=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | wc -l | tr -d ' ')

        # Check sync status with upstream
        sync_status=""
        upstream=$(git -C "$cwd" rev-parse --abbrev-ref @{upstream} 2>/dev/null)
        if [[ -n "$upstream" ]]; then
            # Get last fetch time
            fetch_head="$cwd/.git/FETCH_HEAD"
            fetch_ago=""
            if [[ -f "$fetch_head" ]]; then
                fetch_time=$(stat -c %Y "$fetch_head" 2>/dev/null || stat -f %m "$fetch_head" 2>/dev/null)
                if [[ -n "$fetch_time" ]]; then
                    now=$(date +%s)
                    diff=$((now - fetch_time))
                    if [[ $diff -lt 60 ]]; then
                        fetch_ago="<1m ago"
                    elif [[ $diff -lt 3600 ]]; then
                        fetch_ago="$((diff / 60))m ago"
                    elif [[ $diff -lt 86400 ]]; then
                        fetch_ago="$((diff / 3600))h ago"
                    else
                        fetch_ago="$((diff / 86400))d ago"
                    fi
                fi
            fi

            counts=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
            ahead=$(echo "$counts" | cut -f1)
            behind=$(echo "$counts" | cut -f2)
            if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
                if [[ -n "$fetch_ago" ]]; then
                    sync_status="synced ${fetch_ago}"
                else
                    sync_status="synced"
                fi
            elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
                sync_status="${ahead} ahead"
            elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
                sync_status="${behind} behind"
            else
                sync_status="${ahead} ahead, ${behind} behind"
            fi
        else
            sync_status="no upstream"
        fi

        # Build git status string
        if [[ "$file_count" -eq 0 ]]; then
            git_status="(0 files uncommitted, ${sync_status})"
        elif [[ "$file_count" -eq 1 ]]; then
            # Show the actual filename when only one file is uncommitted
            single_file=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | head -1 | sed 's/^...//')
            git_status="(${single_file} uncommitted, ${sync_status})"
        else
            git_status="(${file_count} files uncommitted, ${sync_status})"
        fi
    fi
fi

# Get transcript path for context calculation and last message feature
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Get context window size from JSON (accurate), but calculate tokens from transcript
# (more accurate than total_input_tokens which excludes system prompt/tools/memory)
# See: github.com/anthropics/claude-code/issues/13652
max_context=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
max_k=$((max_context / 1000))
if [[ $max_k -ge 1000 ]]; then
    max_display="$((max_k / 1000))M"
else
    max_display="${max_k}k"
fi

# Calculate context bar from transcript
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    context_length=$(jq -s '
        map(select(.message.usage and .isSidechain != true and .isApiErrorMessage != true)) |
        last |
        if . then
            (.message.usage.input_tokens // 0) +
            (.message.usage.cache_read_input_tokens // 0) +
            (.message.usage.cache_creation_input_tokens // 0)
        else 0 end
    ' < "$transcript_path")

    # 20k baseline: includes system prompt (~3k), tools (~15k), memory (~300),
    # plus ~2k for git status, env block, XML framing, and other dynamic context
    baseline=20000
    bar_width=10

    if [[ "$context_length" -gt 0 ]]; then
        pct=$((context_length * 100 / max_context))
        pct_prefix=""
    else
        # At conversation start, ~20k baseline is already loaded
        pct=$((baseline * 100 / max_context))
        pct_prefix="~"
    fi

    [[ $pct -gt 100 ]] && pct=100

    bar=""
    for ((i=0; i<bar_width; i++)); do
        bar_start=$((i * 10))
        progress=$((pct - bar_start))
        if [[ $progress -ge 8 ]]; then
            bar+="${C_ACCENT}█${C_RESET}"
        elif [[ $progress -ge 3 ]]; then
            bar+="${C_ACCENT}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done

    ctx="${bar} ${C_GRAY}${pct_prefix}${pct}% of ${max_display} tokens"
else
    # Transcript not available yet - show baseline estimate
    baseline=20000
    bar_width=10
    pct=$((baseline * 100 / max_context))
    [[ $pct -gt 100 ]] && pct=100

    bar=""
    for ((i=0; i<bar_width; i++)); do
        bar_start=$((i * 10))
        progress=$((pct - bar_start))
        if [[ $progress -ge 8 ]]; then
            bar+="${C_ACCENT}█${C_RESET}"
        elif [[ $progress -ge 3 ]]; then
            bar+="${C_ACCENT}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done

    ctx="${bar} ${C_GRAY}~${pct}% of ${max_display} tokens"
fi

# Plan usage limits (Pro/Max only; rate_limits is absent for API key sessions)
# Shown on its own line; turns yellow at 70% and red with a warning at 90%
C_WARN='\033[38;5;178m'
C_CRIT='\033[38;5;167m'
usage=""
limits=$(echo "$input" | jq -r '
    def epoch:
        if type == "number" then . else (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) end;
    .rate_limits // {} |
    [["Session", .five_hour], ["Weekly", .seven_day]][] |
    select(.[1].used_percentage != null) |
    "\(.[0]) \(.[1].used_percentage | floor) \((.[1].resets_at | epoch?) // "")"
' 2>/dev/null)
now=$(date +%s)
while read -r label used reset_at; do
    [[ -z "$label" ]] && continue
    if [[ $used -ge 90 ]]; then
        color="$C_CRIT"; mark="⚠ "
    elif [[ $used -ge 70 ]]; then
        color="$C_WARN"; mark=""
    else
        color="$C_ACCENT"; mark=""
    fi

    bar=""
    for ((i=0; i<10; i++)); do
        progress=$((used - i * 10))
        if [[ $progress -ge 8 ]]; then
            bar+="${color}█"
        elif [[ $progress -ge 3 ]]; then
            bar+="${color}▄"
        else
            bar+="${C_BAR_EMPTY}░"
        fi
    done

    # e.g. "resets in 2h 15m (3:00pm)" or "resets in 3d 11h (Sun 9:00am)"
    reset=""
    if [[ -n "$reset_at" ]]; then
        left=$((reset_at - now))
        if [[ $left -le 0 ]]; then
            reset="resets now"
        else
            d=$((left / 86400)); h=$((left % 86400 / 3600)); m=$((left % 3600 / 60))
            if [[ $d -gt 0 ]]; then
                fmt="%a %-I:%M%p"; in="${d}d ${h}h"
            else
                fmt="%-I:%M%p"; in="${h}h ${m}m"
                [[ $h -eq 0 ]] && in="${m}m"
            fi
            at=$(date -r "$reset_at" +"$fmt" 2>/dev/null || date -d "@$reset_at" +"$fmt" 2>/dev/null)
            reset="resets in ${in}"
            [[ -n "$at" ]] && reset+=" ($(echo "$at" | sed "s/AM$/am/;s/PM$/pm/"))"
        fi
    fi

    [[ -n "$usage" ]] && usage+="${C_GRAY}   "
    usage+="${color}${mark}${label}${C_RESET} ${bar}${C_RESET} ${color}${used}%${C_GRAY}"
    [[ -n "$reset" ]] && usage+=" · ${reset}"
done <<< "$limits"

# Build output: Model | Dir | Branch (uncommitted) | Context
output="${C_ACCENT}${model}${C_GRAY} | 📁${dir}"
[[ -n "$branch" ]] && output+=" | 🔀${branch} ${git_status}"
output+=" | ${ctx}${C_RESET}"

printf '%b\n' "$output"
[[ -n "$usage" ]] && printf '%b\n' "${usage}${C_RESET}"

# Get user's last message (text only, not tool results, skip unhelpful messages)
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    # Calculate visible length (without ANSI codes) - 10 chars for bar + content
    plain_output="${model} | 📁${dir}"
    [[ -n "$branch" ]] && plain_output+=" | 🔀${branch} ${git_status}"
    plain_output+=" | xxxxxxxxxx ${pct}% of ${max_display} tokens"
    max_len=${#plain_output}
    last_user_msg=$(jq -rs '
        # Messages to skip (not useful as context)
        def is_unhelpful:
            startswith("[Request interrupted") or
            startswith("[Request cancelled") or
            . == "";

        [.[] | select(.type == "user") |
         select(.message.content | type == "string" or
                (type == "array" and any(.[]; .type == "text")))] |
        reverse |
        map(.message.content |
            if type == "string" then .
            else [.[] | select(.type == "text") | .text] | join(" ") end |
            gsub("\n"; " ") | gsub("  +"; " ")) |
        map(select(is_unhelpful | not)) |
        first // ""
    ' < "$transcript_path" 2>/dev/null)

    if [[ -n "$last_user_msg" ]]; then
        if [[ ${#last_user_msg} -gt $max_len ]]; then
            echo "💬 ${last_user_msg:0:$((max_len - 3))}..."
        else
            echo "💬 ${last_user_msg}"
        fi
    fi
fi
