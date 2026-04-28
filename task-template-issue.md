# Claude Code Effective Task Wrapper (Issue Mode)

You are working in a prepared repository workspace.

Execution context:
- Repository: {{REPO}}
- Current branch: {{BRANCH_NAME}}
- Run ID: {{RUN_ID}}
- GitHub MCP server is configured as github
- Issue number: {{ISSUE_NUMBER}}
- Issue URL: {{ISSUE_URL}}
- Do not re-clone the repository
- Do not create or switch to another branch unless explicitly required by the task

Primary objective:
Use GitHub MCP to read the issue first, then implement the requested fix.

Issue instructions:
1. Read the target issue via GitHub MCP.
2. Treat the issue body and comments as the source of requirements.
3. If there are ambiguities, make minimal assumptions and document them in the pull request.

Additional user task context:
{{USER_TASK}}

Required workflow:
1. Analyze the codebase and implement the issue requirements.
2. Run relevant build, lint, and test commands when available.
3. Stage and commit all required changes with a clear commit message that references {{ISSUE_REFERENCE}}.
4. Push the current branch to origin.
5. Create a pull request using GitHub MCP tools only.
6. Do not use direct GitHub REST API calls for pull request creation.

Pull request requirements:
- Base branch: repository default branch
- Head branch: {{BRANCH_NAME}}
- Title prefix: feat:
- Body sections:
  - Issue summary
  - What changed
  - Validation performed
  - Risks or follow-ups
  - Run ID: {{RUN_ID}}
  - Closing reference: Closes {{ISSUE_REFERENCE}}

Output requirements:
1. Summarize implemented changes.
2. List validation commands executed and outcomes.
3. Provide the commit SHA.
4. Provide the pull request URL.
5. Confirm the issue closing reference used in the pull request body.
6. If no code changes were needed, state that and do not create a pull request.

Failure handling:
- If GitHub MCP issue access or pull request creation fails, stop and report the exact failure.