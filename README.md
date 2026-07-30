# Plural Workbench Follow-up

A shared GitHub Action that sends a follow-up prompt to the Plural Workbench associated with a pull request. It wraps:

```shell
plural workbenches pr-followup
```

## Usage

The action installs its pinned Plural CLI version with `actions/setup-go` and `go install`. Supply Console authentication directly or use `pluralsh/setup-plural` to obtain an OIDC token:

```yaml
name: Workbench follow-up

on:
  pull_request_review:
    types: [submitted]

permissions:
  contents: read
  id-token: write

jobs:
  follow-up:
    if: github.event.review.state == 'changes_requested'
    runs-on: ubuntu-latest
    steps:
      - name: Set up Plural
        uses: pluralsh/setup-plural@v2
        with:
          consoleUrl: https://console.example.com
          email: github-actions@example.com

      - name: Follow up on review feedback
        id: follow-up
        uses: pluralsh/workbench-followup-action@v1
        with:
          prompt: Address the requested changes in the latest pull request review.
          url: ${{ github.event.pull_request.html_url }}
          skip-missing: true

      - name: Print Workbench job
        if: steps.follow-up.outputs.skipped != 'true'
        run: echo '${{ steps.follow-up.outputs.workbench-job-url }}'
```

When `url` and `commit` are omitted, the action first uses `github.event.pull_request.html_url`. This works for events whose payload includes a pull request, such as `pull_request` and `pull_request_review`:

```yaml
- name: Continue Workbench task
  uses: pluralsh/workbench-followup-action@v1
  with:
    prompt: Run the tests again and fix any remaining failures.
```

When `commit` is provided, event URL detection is bypassed and the CLI infers the pull request from the checked-out repository and commit subject. Check out the repository first, preferably with full history when targeting a non-`HEAD` commit:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0

- name: Continue Workbench task
  uses: pluralsh/workbench-followup-action@v1
  with:
    prompt: Run the tests again and fix any remaining failures.
    commit: HEAD
    provider: github
```

You can also combine `base-url` with `provider` when the Git remote cannot provide the desired web URL:

```yaml
- name: Continue Workbench task
  uses: pluralsh/workbench-followup-action@v1
  with:
    prompt: Run the tests again and fix any remaining failures.
    base-url: https://github.example.com/acme/example
    provider: github
```

Token-based authentication is also supported:

```yaml
- name: Set up Plural
  uses: pluralsh/setup-plural@v2
  with:
    consoleUrl: ${{ vars.PLURAL_CONSOLE_URL }}
    consoleToken: ${{ secrets.PLURAL_CONSOLE_TOKEN }}

- name: Continue Workbench task
  uses: pluralsh/workbench-followup-action@v1
  with:
    prompt: Run the tests again and fix any remaining failures.
```

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `prompt` | Yes | — | Follow-up prompt sent to the Workbench. |
| `console-token` | No | `PLURAL_CONSOLE_TOKEN` | Plural Console authentication token. Usually exported by `pluralsh/setup-plural`. |
| `console-url` | No | `PLURAL_CONSOLE_URL` | Plural Console URL. Usually exported by `pluralsh/setup-plural`. |
| `url` | No | Event PR URL | Explicit pull request URL. When omitted without `commit`, uses `github.event.pull_request.html_url`; otherwise the CLI performs inference. |
| `commit` | No | `HEAD` | Commit or ref whose subject identifies the pull request when URL is omitted. |
| `base-url` | No | Origin web URL | Repository web URL used to construct the pull request URL. |
| `provider` | No | `auto` | Source control provider: `auto`, `github`, `gitlab`, or `bitbucket`. |
| `defer` | No | `0s` | Duration to defer the follow-up, such as `30s`, `5m`, or `2h`. |
| `skip-missing` | No | `false` | Exit successfully if no Workbench job is associated with the pull request. |
| `plural-cli-version` | No | Feature commit | Plural CLI tag or commit installed with `go install`. |

## Outputs

| Output | Description |
| --- | --- |
| `prompt-id` | ID of the created follow-up prompt. Empty when skipped. |
| `pull-request-url` | Pull request URL used by the command. |
| `workbench-job-url` | URL of the associated Workbench job. Empty when skipped. |
| `skipped` | `true` when no associated Workbench job was found and `skip-missing` was enabled. |

## Requirements

- A GitHub Actions runner supported by `actions/setup-go` with Bash, Git, and `jq`.
- Network access to download Go and the Plural CLI module.
- Access to the target Plural Console.
- `actions/checkout` before this action when using commit-based pull request inference.
- For OIDC authentication, the workflow needs `id-token: write` and a matching Plural federated credential.

## Development

Validate the action metadata with `actionlint`:

```shell
actionlint action.yml .github/workflows/ci.yml
```
