---
name: agent-runner
description: 'Run Claude Code tasks against a GitHub repository using the agent-runner Docker container. Use when: dispatching automated coding tasks, implementing a plan or spec via AI agent, running Claude Code in a sandbox, creating task branches and pull requests automatically, or executing multi-step code changes without local risk.'
argument-hint: 'Describe the coding task to run, or specify repo/branch/task details'
---

# Agent Runner

Runs [Claude Code](https://github.com/anthropics/claude-code) inside a sandboxed Docker container against a GitHub repository. The agent clones the repo, performs the task, commits changes to a new branch, and opens a pull request — all automatically.

## When to Use

- Dispatching a coding task from a Plan or spec to an AI agent
- Running Claude Code without giving it access to your local machine
- Automating multi-file code changes and getting them back as a PR
- Batch or experimental tasks where isolation is important

## Required Environment Variables

| Variable | Description |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic API key for Claude Code |
| `GITHUB_TOKEN` | GitHub personal access token with `repo` push access |
| `REPO` | Target repo in `owner/repo` format |
| `TASK` | Natural language description of the coding task |

## Optional Environment Variables

| Variable | Default | Description |
|---|---|---|
| `BRANCH_NAME` | `claude/task-<timestamp>` | Branch name for the changes |
| `GIT_EMAIL` | `claude@example.com` | Git commit author email |
| `GIT_NAME` | `Claude Code` | Git commit author name |

## Procedure

### 1. Ensure required token environment variables exist

IMPORTANT: use the following powershell command when run on Windows. Otherwise you can interpret to Bash.

```powershell
if (
  [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY')) -or
  [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('GITHUB_TOKEN'))
) {
  Write-Host "Missing required environment variables: ANTHROPIC_API_KEY and/or GITHUB_TOKEN"
  Write-Host "Set them before running the task. Example:"
  Write-Host '  $env:ANTHROPIC_API_KEY = "<your-anthropic-key>"'
  Write-Host '  $env:GITHUB_TOKEN = "<your-github-token>"'
  Write-Host "After setting them, restart your terminal session, then re-run this skill."
  exit 1
}
```

If either token is missing, instruct the user to set them, restart their terminal session, and stop the process.

### 2. Elicit Variables

Ask the user for the required variables:

- `REPO` (in `owner/repo` format)
- `TASK` (natural-language coding task)

Then ask if they want to define any optional variables or use defaults:

- `BRANCH_NAME`
- `GIT_EMAIL`
- `GIT_NAME`

If optional values are not provided, use defaults.

### 3. Ensure the Docker image exists

```bash
if ! docker image inspect agent-runner >/dev/null 2>&1; then
  echo "Docker image 'agent-runner' was not found. Build it first with:"
  echo "docker build -t agent-runner ."
  exit 1
fi
```

If the image is missing, stop the process and do not continue to task execution.

### 4. Run a task

```powershell
$anthropicKey = [Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY')
$githubToken = [Environment]::GetEnvironmentVariable('GITHUB_TOKEN')

docker run --rm `
  -e ANTHROPIC_API_KEY="$anthropicKey" `
  -e GITHUB_TOKEN="$githubToken" `
  -e REPO="owner/repo" `
  -e TASK="Implement Phase 1 from the plan in PLAN.md" `
  -v ./logs:/logs `
  -v ./sessions:/sessions `
  agent-runner
```

### 5. Review output

After the run, artifacts are written to the host-mapped directories:

| File | Description |
|---|---|
| `logs/run-<timestamp>.log` | Full container execution log |
| `sessions/<run-id>.json` | Raw Claude Code stream-json transcript |
| `sessions/<run-id>.md` | Human-readable summary: task, cost, duration, files changed |

### 6. Review the pull request

The container pushes the branch and opens a PR against the repo's default branch. The PR description includes the task, run ID, cost, duration, and list of changed files.

## Included Toolchain

The container ships with:

- **Node.js 22** — Claude Code runtime
- **.NET SDK 10.0** — build/test .NET projects
- **git, curl, jq, unzip** — general utilities

## How It Works

1. Container validates required environment variables
2. Configures git with credentials from `GITHUB_TOKEN`
3. Clones `REPO` and creates `BRANCH_NAME`
4. Installs project dependencies (`npm install` / `dotnet restore`) if detected
5. Runs `claude -p "$TASK"` with Read, Write, Edit, and Bash tools
6. Saves the full session transcript and a markdown summary to `/sessions`
7. Stages and commits all changes with a structured commit message
8. Pushes the branch and creates a GitHub pull request via the API

## Security Notes

- All secrets are passed at runtime via environment variables — never hardcoded
- The Docker container provides filesystem and process isolation from the host
- `GITHUB_TOKEN` is used only for git credentials and the GitHub API pull request call
- Claude Code is restricted to `Read`, `Write`, `Edit`, and `Bash` tools only
