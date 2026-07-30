#!/usr/bin/env bash
set -Eeuo pipefail

on_error() {
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo "::error::Workbench PR follow-up failed." >&2
  fi
  exit "$status"
}
trap on_error ERR

fail() {
  echo "::error::$1" >&2
  exit 1
}

notice() {
  echo "::notice::$1"
}

PULL_REQUEST_URL="${INPUT_URL:-}"
if [[ -z "$PULL_REQUEST_URL" && -z "${COMMIT:-}" ]]; then
  PULL_REQUEST_URL="${EVENT_PULL_REQUEST_URL:-}"
fi

[[ -n "${PROMPT//[[:space:]]/}" ]] || fail "prompt is required"
[[ -n "${PLURAL_CONSOLE_TOKEN:-}" ]] || fail "PLURAL_CONSOLE_TOKEN is required; run pluralsh/setup-plural first"
[[ -n "${PLURAL_CONSOLE_URL:-}" ]] || fail "PLURAL_CONSOLE_URL is required; run pluralsh/setup-plural first"
[[ -z "$PULL_REQUEST_URL" || -z "${COMMIT:-}" ]] || fail "pull-request-url and commit cannot be used together"
[[ "$PROVIDER" == "auto" || "$PROVIDER" == "github" || "$PROVIDER" == "gitlab" || "$PROVIDER" == "bitbucket" ]] || fail "provider must be auto, github, gitlab, or bitbucket"
[[ "$OUTPUT" == "raw" || "$OUTPUT" == "json" ]] || fail "output must be raw or json"
[[ "$SKIP_MISSING" == "true" || "$SKIP_MISSING" == "false" ]] || fail "skip-missing must be true or false"

TARGET_DESCRIPTION="$PULL_REQUEST_URL"
if [[ -z "$TARGET_DESCRIPTION" ]]; then
  TARGET_DESCRIPTION="commit ${COMMIT:-HEAD}"
fi

notice "Preparing Workbench PR follow-up for ${TARGET_DESCRIPTION}."

args=(
  workbenches pr-followup
  --prompt "$PROMPT"
  --provider "$PROVIDER"
  --defer "$DEFER"
  --output "$OUTPUT"
)
[[ -n "$PULL_REQUEST_URL" ]] && args+=(--url "$PULL_REQUEST_URL")
[[ -n "${COMMIT:-}" ]] && args+=(--commit "$COMMIT")
[[ -n "${BASE_URL:-}" ]] && args+=(--base-url "$BASE_URL")
[[ "$SKIP_MISSING" == "true" ]] && args+=(--skip-missing)

if [[ "$OUTPUT" == "raw" ]]; then
  notice "Submitting Workbench PR follow-up request."
  plural "${args[@]}"
  notice "Workbench PR follow-up command completed."
  exit 0
fi

notice "Submitting Workbench PR follow-up request."
result="$(plural "${args[@]}")"

jq -e 'type == "object"' >/dev/null <<< "$result" || fail "plural returned an invalid JSON response"

prompt_id="$(jq -r '.promptId // empty' <<< "$result")"
pull_request_url="$(jq -r '.pullRequestUrl // empty' <<< "$result")"
workbench_job_url="$(jq -r '.workbenchJobUrl // empty' <<< "$result")"
skipped="$(jq -r '.skipped // false' <<< "$result")"

echo "prompt-id=$prompt_id" >> "$GITHUB_OUTPUT"
echo "pull-request-url=$pull_request_url" >> "$GITHUB_OUTPUT"
echo "workbench-job-url=$workbench_job_url" >> "$GITHUB_OUTPUT"
echo "skipped=$skipped" >> "$GITHUB_OUTPUT"

if [[ "$skipped" == "true" ]]; then
  notice "No associated Workbench job was found for ${pull_request_url}; follow-up skipped."
  exit 0
fi

[[ -n "$prompt_id" ]] || fail "plural returned an empty prompt ID"
[[ -n "$workbench_job_url" ]] || fail "plural returned an empty Workbench job URL"

notice "Workbench PR follow-up created successfully."
echo "Prompt ID: $prompt_id"
echo "Pull request URL: $pull_request_url"
echo "Workbench job URL: $workbench_job_url"
