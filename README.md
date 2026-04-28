# Claude Code Agent Runner

A Docker container that runs [Claude Code](https://github.com/anthropics/claude-code) against a repository to perform automated coding tasks.


## Purpose

The reason to use Agent Runner is to have the coding agent run and perform tasks on a repo while in a sandbox. A Docker container provides the easiest way to sandbox the agent so that you can feel confident that the agent has no access to files or processes on your computer for your protection. 


## Main Scenario

The main use case for this project is when you have a Plan and specs defined for your project and you want to let an agent clone the repo, implement part of the Plan, and then commit it back to the repo. 


## How It Works

There is a container image that contains base packages and runs a shell script which manages execution. 

1. The container clones the repo and creates a task branch
2. The container builds an effective task prompt from a reusable template plus the user task
3. If issue environment variables are provided, the container uses an issue-specific template
4. Claude Code executes the task and handles commit, push, and PR creation
5. Pull requests are created through the GitHub MCP server configured in the container
6. A GitHub MCP preflight check verifies Claude can use the configured GitHub MCP tools before the full task starts
7. A local logs directory is mapped into the container so you can review what happened locally.
8. A session transcript (JSON) and human-readable summary (Markdown) are saved to a local sessions directory mapped into the container.



## Required Environment Variables

| Variable | Description |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic API key for Claude Code |
| `GITHUB_TOKEN` | GitHub token with repo push access |
| `REPO` | GitHub repo in `owner/repo` format |
| `TASK` | Natural language description of the task to perform |

## Optional Environment Variables

| Variable | Default | Description |
|---|---|---|
| `BRANCH_NAME` | `claude/task-<timestamp>` | Branch name for the changes |
| `GIT_EMAIL` | `claude@example.com` | Git commit email |
| `GIT_NAME` | `Claude Code` | Git commit author name |
| `ISSUE_NUMBER` | (empty) | Issue number to enable issue-mode effective task template |
| `ISSUE_URL` | (empty) | Issue URL to enable issue-mode effective task template |

## Usage

```bash
docker build -t agent-runner .

docker run --rm \
  -e ANTHROPIC_API_KEY="sk-..." \
  -e GITHUB_TOKEN="ghp_..." \
  -e REPO="owner/repo" \
  -e TASK="Implement Phase 1..." \
  -v ./logs:/logs \
  -v ./sessions:/sessions \
  agent-runner
```

## Claude Permissions

The image includes a Claude settings file at `claude-settings.json` that allowlists GitHub MCP tools for the run via `permissions.allow`.

Before the main task starts, the runner performs a lightweight GitHub MCP preflight using `mcp__github__get_me`.
If Claude tool permissions or GitHub authentication are not working, the run fails early and records the preflight transcript in `sessions/<run-id>-preflight.json`.

## Use The Agent Skill 

This repository also includes a reusable skill for using Agent Runner from your coding assistant to create workflows:

- `.claude/skills/agent-runner/SKILL.md`

This allows for an agent to orchestrate the use of this agent-runner. 


## Included Toolchain

- **Node.js 22** — Claude Code runtime
- **.NET SDK 10.0** — build and test app
- **git, curl, jq, unzip** — general utilities

## Output

Session artifacts are written to the host-mapped `sessions/` directory:

- `<run-id>.json` — full Claude Code stream-json transcript
- `<run-id>.md` — human-readable summary with task, cost, duration, and files changed


