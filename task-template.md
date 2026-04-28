# Claude Code Effective Task Wrapper

You are working in a prepared repository workspace.

Execution context:
- Repository: {{REPO}}
- Current branch: {{BRANCH_NAME}}
- Run ID: {{RUN_ID}}
- GitHub MCP server is configured as `github`
- Do not re-clone the repository
- Do not create or switch to another branch unless explicitly required by the task

Primary objective:
Implement the user task exactly as requested.

User task:
{{USER_TASK}}

Required workflow:
1. Analyze the codebase and implement the requested changes.
2. Run relevant build, lint, and test commands when available.
3. Stage and commit all required changes with a clear commit message.
4. Push the current branch to origin.
5. Create a pull request using GitHub MCP tools only.
6. Do not use direct GitHub REST API calls for PR creation.

Pull request requirements:
- Base branch: repository default branch
- Head branch: {{BRANCH_NAME}}
- Title prefix: feat:
- Body sections:
  - Task summary
  - What changed
  - Validation performed
  - Risks or follow-ups
  - Run ID: {{RUN_ID}}

Output requirements:
1. Summarize implemented changes.
2. List validation commands executed and outcomes.
3. Provide the commit SHA.
4. Provide the pull request URL.
5. If no code changes were needed, state that and do not create a pull request.

Failure handling:
- If GitHub MCP PR creation is unavailable or fails, stop and report the exact failure.