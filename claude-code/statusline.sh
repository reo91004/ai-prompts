#!/usr/bin/env bash
# Claude Code statusline: model | dir (branch) | context | effort | ponytail mode
in=$(cat)

eval "$(jq -r '@sh "model=\(.model.display_name)
dir=\(.workspace.current_dir // .cwd)
pct=\(.context_window.used_percentage // 0 | floor)
size=\(.context_window.context_window_size // 0)
effort=\(.effort.level // "")"' <<<"$in")"

branch=$(git -C "$dir" branch --show-current 2>/dev/null)

# green under half, amber past 60%, red past 85% — refill/compact warning
if   [ "$pct" -ge 85 ]; then c=203
elif [ "$pct" -ge 60 ]; then c=179
else c=108
fi

printf '\033[38;5;110m%s\033[0m \033[38;5;245m|\033[0m \033[38;5;109m%s\033[0m' \
  "$model" "$(basename "$dir")"
[ -n "$branch" ] && printf ' \033[38;5;245m(%s)\033[0m' "$branch"
printf ' \033[38;5;245m|\033[0m \033[38;5;%sm%s%% of %sk\033[0m' \
  "$c" "$pct" "$((size / 1000))"
# effort is absent when the model has no effort parameter
[ -n "$effort" ] && printf ' \033[38;5;245m|\033[0m \033[38;5;176meffort:%s\033[0m' "$effort"

# ponytail mode flag, written by the plugin's SessionStart hook
# uppercased via tr: macOS ships bash 3.2, which has no ${var^^}
mode=$(tr -d '[:space:]' < "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.ponytail-active" 2>/dev/null \
  | tr '[:lower:]' '[:upper:]')
[ -n "$mode" ] && printf ' \033[38;5;245m|\033[0m \033[38;5;108m[PONYTAIL:%s]\033[0m' "$mode"
echo
