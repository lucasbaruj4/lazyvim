#!/usr/bin/env bash
# Claude Code status line: active subscription usage for Claude or ChatGPT.

WIDTH=10
CACHE_TTL=60
CACHE_DIR="$HOME/.claude/cache"
MANAGEMENT_URL="http://127.0.0.1:8317/v0/management"
MANAGEMENT_KEY_FILE="$HOME/.cli-proxy-api/.claudex-key"

umask 077
input=$(cat)
model_id=$(jq -r '.model.id // ""' <<<"$input")
model_name=$(jq -r '.model.display_name // ""' <<<"$input")
model_hint="${model_id,,} ${model_name,,}"

if [[ "$model_id" == *-tpg || "$model_id" == *-dd-* || "$model_hint" == *gpt* || "$model_hint" == *codex* || "$model_hint" == *openai* ]]; then
  provider="codex"
  provider_label="GPT"
else
  provider="claude"
  provider_label="Claude"
fi

bar() {
  local label=$1 pct=$2
  awk -v label="$label" -v pct="$pct" -v w="$WIDTH" '
    BEGIN {
      if (pct < 0) pct = 0; if (pct > 100) pct = 100
      eighths = int(pct / 100 * w * 8 + 0.5)
      full = int(eighths / 8)
      rem  = eighths % 8
      split("▏▎▍▌▋▊▉", parts, "")

      color = (pct >= 85) ? "\033[31m" : (pct >= 60) ? "\033[33m" : "\033[32m"
      dim = "\033[2m"; reset = "\033[0m"

      fill = ""
      for (i = 0; i < full; i++) fill = fill "█"
      if (rem > 0 && full < w) fill = fill parts[rem]

      used = full + (rem > 0 && full < w ? 1 : 0)
      empty = ""
      for (i = used; i < w; i++) empty = empty "─"

      printf "%s%s %s%s%s%s%s %.0f%%", dim, label, color, fill, dim, empty, reset, pct
    }'
}

management_get() {
  local path=$1 key=$2
  curl -fsS --connect-timeout 0.5 --max-time 2 \
    --config /dev/fd/3 "$MANAGEMENT_URL/$path" \
    3<<<"header = \"Authorization: Bearer $key\""
}

management_post() {
  local path=$1 key=$2 payload=$3
  curl -fsS --connect-timeout 0.5 --max-time 4 \
    --config /dev/fd/3 \
    -H 'Content-Type: application/json' \
    --data-binary "$payload" "$MANAGEMENT_URL/$path" \
    3<<<"header = \"Authorization: Bearer $key\""
}

cache_is_fresh() {
  local file=$1 now=$2
  [[ -r "$file" ]] && jq -e --argjson cutoff "$((now - CACHE_TTL))" \
    '(.fetched_at // 0) >= $cutoff and (.windows | type == "array")' "$file" >/dev/null 2>&1
}

fetch_proxy_usage() {
  local requested_provider=$1
  local cache_file="$CACHE_DIR/statusline-${requested_provider}-usage.json"
  local lock_file="$cache_file.lock"
  local now key auth_files auth_index headers payload response parsed temp

  mkdir -p "$CACHE_DIR"
  now=$(date +%s)

  if cache_is_fresh "$cache_file" "$now"; then
    cat "$cache_file"
    return
  fi

  exec 9>"$lock_file"
  if ! flock -n 9; then
    [[ -r "$cache_file" ]] && cat "$cache_file"
    return
  fi

  now=$(date +%s)
  if cache_is_fresh "$cache_file" "$now"; then
    cat "$cache_file"
    return
  fi

  if [[ ! -r "$MANAGEMENT_KEY_FILE" ]]; then
    [[ -r "$cache_file" ]] && cat "$cache_file"
    return
  fi
  key=$(<"$MANAGEMENT_KEY_FILE")

  auth_files=$(management_get "auth-files" "$key") || {
    [[ -r "$cache_file" ]] && cat "$cache_file"
    return
  }
  auth_index=$(jq -r --arg provider "$requested_provider" '
    .files[]
    | select(((.provider // .type // "") | ascii_downcase) == $provider)
    | .auth_index // .authIndex // empty
  ' <<<"$auth_files" | head -n 1)
  if [[ -z "$auth_index" ]]; then
    [[ -r "$cache_file" ]] && cat "$cache_file"
    return
  fi

  if [[ "$requested_provider" == "codex" ]]; then
    headers=$(jq -nc '{
      Authorization:"Bearer $TOKEN$",
      "Content-Type":"application/json",
      "User-Agent":"codex_cli_rs/0.76.0 (Debian 13.0.0; x86_64) WindowsTerminal"
    }')
    payload=$(jq -nc --arg auth "$auth_index" --argjson headers "$headers" '{
      authIndex:$auth,
      method:"GET",
      url:"https://chatgpt.com/backend-api/wham/usage",
      header:$headers
    }')
  else
    headers=$(jq -nc '{
      Authorization:"Bearer $TOKEN$",
      "Content-Type":"application/json",
      "anthropic-beta":"oauth-2025-04-20"
    }')
    payload=$(jq -nc --arg auth "$auth_index" --argjson headers "$headers" '{
      authIndex:$auth,
      method:"GET",
      url:"https://api.anthropic.com/api/oauth/usage",
      header:$headers
    }')
  fi

  response=$(management_post "api-call" "$key" "$payload") || {
    [[ -r "$cache_file" ]] && cat "$cache_file"
    return
  }

  if [[ $(jq -r '.status_code // 0' <<<"$response") != "200" ]]; then
    [[ -r "$cache_file" ]] && cat "$cache_file"
    return
  fi

  if [[ "$requested_provider" == "codex" ]]; then
    parsed=$(jq -c --argjson now "$now" '
      (.body | if type == "string" then (fromjson? // {}) else . end) as $body
      | {
          fetched_at:$now,
          windows:([
            $body.rate_limit.primary_window,
            $body.rate_limit.secondary_window
          ]
          | map(select(type == "object" and (.used_percent | type) == "number")
            | {
                label:(
                  (.limit_window_seconds // 0) as $seconds
                  | if $seconds > 0 and ($seconds % 86400 == 0) then "\($seconds / 86400 | floor)d"
                    elif $seconds > 0 and ($seconds % 3600 == 0) then "\($seconds / 3600 | floor)h"
                    elif $seconds > 0 and ($seconds % 60 == 0) then "\($seconds / 60 | floor)m"
                    else "limit"
                    end
                ),
                pct:.used_percent
              }
          ))
        }
    ' <<<"$response")
  else
    parsed=$(jq -c --argjson now "$now" '
      (.body | if type == "string" then (fromjson? // {}) else . end) as $body
      | {
          fetched_at:$now,
          windows:([
            {label:"5h", pct:$body.five_hour.utilization},
            {label:"7d", pct:$body.seven_day.utilization}
          ] | map(select(.pct | type == "number")))
        }
    ' <<<"$response")
  fi

  if ! jq -e '.windows | type == "array" and length > 0' <<<"$parsed" >/dev/null 2>&1; then
    [[ -r "$cache_file" ]] && cat "$cache_file"
    return
  fi

  temp=$(mktemp "$CACHE_DIR/.statusline-usage.XXXXXX")
  printf '%s\n' "$parsed" >"$temp"
  mv "$temp" "$cache_file"
  printf '%s' "$parsed"
}

usage_json=""
if [[ "$provider" == "claude" ]]; then
  usage_json=$(jq -c '
    {
      windows:([
        {label:"5h", pct:.rate_limits.five_hour.used_percentage},
        {label:"7d", pct:.rate_limits.seven_day.used_percentage}
      ] | map(select(.pct | type == "number")))
    }
  ' <<<"$input")

  if ! jq -e '.windows | length > 0' <<<"$usage_json" >/dev/null 2>&1; then
    usage_json=$(fetch_proxy_usage "$provider")
  fi
else
  usage_json=$(fetch_proxy_usage "$provider")
fi

[[ -z "$usage_json" ]] && exit 0

out="\033[2m${provider_label}\033[0m"
while IFS=$'\t' read -r label pct; do
  [[ -z "$label" || -z "$pct" ]] && continue
  out+="  $(bar "$label" "$pct")"
done < <(jq -r '.windows[] | [.label, .pct] | @tsv' <<<"$usage_json")

printf '%b' "$out"
