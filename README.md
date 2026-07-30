# Plural Workbench Follow-up

A shared GitHub Action that sends a follow-up prompt to the Plural Workbench associated with a merged pull request. It wraps:

```shell
plural workbenches pr-followup
```

Plural is GitOps-based, so the intended workflow runs after the pull request is merged into the deployment branch. This lets the Workbench verify the reconciled system and infrastructure state rather than infer the outcome only from files changed in the pull request.

## Usage

Run the action when a pull request is closed, and guard the job with `github.event.pull_request.merged == true` so it never runs for an open or unmerged pull request. Use `pluralsh/setup-plural` to install the Plural CLI and configure Console authentication before invoking this action:

```yaml
name: Verify merged changes

on:
  pull_request:
    types: [closed]

permissions:
  contents: read
  id-token: write

jobs:
  follow-up:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - name: Set up Plural
        uses: pluralsh/setup-plural@v2
        with:
          consoleUrl: ${{ vars.PLURAL_CONSOLE_URL }}
          email: ${{ vars.PLURAL_CONSOLE_EMAIL }}
          vsn: 0.12.60

      - name: Verify merged changes
        id: follow-up
        uses: pluralsh/workbench-followup-action@v1
        with:
          prompt: |
            Pull request #${{ github.event.pull_request.number }} was merged into ${{ github.event.pull_request.base.ref }}.
            Verify the merged changes against the reconciled system and infrastructure state. Fix any issues you find.
          url: ${{ github.event.pull_request.html_url }}
          defer: 5m
          skip-missing: true

      - name: Print Workbench job
        if: steps.follow-up.outputs.skipped != 'true'
        run: echo '${{ steps.follow-up.outputs.workbench-job-url }}'
```

Adjust `defer` to allow enough time for the GitOps reconciliation to complete before the Workbench starts verification.

### Authentication

`pluralsh/setup-plural` adds the selected CLI release to `PATH` and exports `PLURAL_CONSOLE_URL` and `PLURAL_CONSOLE_TOKEN` to subsequent steps in the same job. Configure it using either federated credentials or a Console token.

#### Federated credentials

The complete workflow above uses `consoleUrl` and `email`. With a matching Plural federated credential, `setup-plural` exchanges the workflow's GitHub OIDC token for a Console access token. This method does not require a Console token secret, but the workflow must grant `id-token: write`:

```yaml
permissions:
  contents: read
  id-token: write

steps:
  - name: Set up Plural
    uses: pluralsh/setup-plural@v2
    with:
      consoleUrl: ${{ vars.PLURAL_CONSOLE_URL }}
      email: ${{ vars.PLURAL_CONSOLE_EMAIL }}
      vsn: 0.12.60
```

#### Console token

Alternatively, store a Console token as a GitHub Actions secret and pass it directly to `setup-plural`. This method does not require `id-token: write`:

```yaml
permissions:
  contents: read

steps:
  - name: Set up Plural
    uses: pluralsh/setup-plural@v2
    with:
      consoleUrl: ${{ vars.PLURAL_CONSOLE_URL }}
      consoleToken: ${{ secrets.PLURAL_CONSOLE_TOKEN }}
      vsn: 0.12.60
```

In either configuration, this action receives the Console URL and token through the environment and does not accept or require them as inputs.

The action does not check the pull request state itself. The workflow must ensure the pull request was merged; the recommended `pull_request: closed` trigger and `github.event.pull_request.merged == true` job condition above provide that guarantee. Do not invoke the action from workflows for open pull requests.

When `url` and `commit` are omitted, the action uses `github.event.pull_request.html_url`. This allows the explicit `url` line in the recommended merged-pull-request workflow to be omitted:

```yaml
- name: Verify merged changes
  uses: pluralsh/workbench-followup-action@v1
  with:
    prompt: |
      Pull request #${{ github.event.pull_request.number }} was merged into ${{ github.event.pull_request.base.ref }}.
      Verify the merged changes against the reconciled system and infrastructure state.
    defer: 5m
```

For a post-merge workflow triggered by a push to the deployment branch, `commit` can instead identify the merged pull request from the checked-out commit subject. Check out the repository with full history first:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0

- name: Verify merged changes
  uses: pluralsh/workbench-followup-action@v1
  with:
    prompt: Verify the merged changes against the reconciled system and infrastructure state.
    commit: HEAD
    provider: github
```

You can combine `base-url` with `provider` in that post-merge commit workflow when the Git remote cannot provide the desired web URL:

```yaml
- name: Verify merged changes
  uses: pluralsh/workbench-followup-action@v1
  with:
    prompt: Verify the merged changes against the reconciled system and infrastructure state.
    commit: HEAD
    base-url: https://github.example.com/acme/example
    provider: github
```

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `prompt` | Yes | — | Follow-up prompt sent to the Workbench. |
| `url` | No | Event PR URL | Explicit merged pull request URL. When omitted without `commit`, uses `github.event.pull_request.html_url`; otherwise the CLI performs inference. |
| `commit` | No | `HEAD` | Commit or ref whose subject identifies the pull request when URL is omitted. |
| `base-url` | No | Origin web URL | Repository web URL used to construct the pull request URL. |
| `provider` | No | `auto` | Source control provider: `auto`, `github`, `gitlab`, or `bitbucket`. |
| `defer` | No | `0s` | Duration to defer the follow-up, such as `30s`, `5m`, or `2h`. |
| `output` | No | `json` | CLI output format: `raw` or `json`. Structured action outputs are only populated with `json`. |
| `skip-missing` | No | `false` | Exit successfully if no Workbench job is associated with the pull request. |

## Outputs

| Output | Description |
| --- | --- |
| `prompt-id` | ID of the created follow-up prompt. Empty when skipped. |
| `pull-request-url` | Pull request URL used by the command. |
| `workbench-job-url` | URL of the associated Workbench job. Empty when skipped. |
| `skipped` | `true` when no associated Workbench job was found and `skip-missing` was enabled. |

The outputs above are parsed from the CLI's JSON response. With `output: raw`, the CLI writes its human-readable result directly to the job log and action outputs are empty because raw output does not expose structured result or skip state.

## Requirements

- A GitHub Actions runner with Bash, Git, and `jq`.
- `pluralsh/setup-plural@v2` run earlier in the same job with CLI version `0.12.60` or newer.
- Access to the target Plural Console.
- One of these `setup-plural` authentication configurations:
  - Federated credentials: `consoleUrl` and `email`, a matching Plural federated credential, and workflow permission `id-token: write`.
  - Console token: `consoleUrl` and `consoleToken`, typically read from a GitHub Actions variable and secret; no OIDC permission is required.
- `actions/checkout` with sufficient history before this action when using commit-based pull request inference.

## Logging

The action is designed to keep workflow logs human-readable:

- The composite step runs a checked-in entrypoint script instead of inlining the full shell program in workflow logs.
- It emits progress notices before submission, on skip, and on success.
- In `output: json` mode, it prints a short success summary and still exposes structured outputs for downstream steps.
- In `output: raw` mode, it streams the CLI's human-readable output directly.

## Development

Validate the action metadata with `actionlint`:

```shell
actionlint action.yml .github/workflows/ci.yml
```
