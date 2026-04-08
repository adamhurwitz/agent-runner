#!/bin/bash
set -e

LOG_FILE="/logs/run-$(date +%Y%m%d-%H%M%S).log"
SESSION_DIR="/sessions"
RUN_ID="$(date +%Y%m%d-%H%M%S)"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Validate required env vars
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${REPO:?REPO is required}"
: "${TASK:?TASK is required}"

BRANCH_NAME="${BRANCH_NAME:-claude/task-$(date +%s)}"

log "=== Claude Code Task Runner ==="
log "Repo:   $REPO"s
log "Branch: $BRANCH_NAME"
log "Task:   $TASK"
log "Run ID: $RUN_ID"

# Configure git
git config --global user.email "${GIT_EMAIL:-claude@example.com}"
git config --global user.name "${GIT_NAME:-Claude Code}"
git config --global credential.helper store
echo "https://x-access-token:${GITHUB_TOKEN}@github.com" > ~/.git-credentials

# Clone repo
log "Cloning $REPO..."
git clone "https://github.com/${REPO}.git" /repo 2>&1 | tee -a "$LOG_FILE"
cd /repo

# Install dependencies if present
if [ -f package.json ]; then
  log "Installing Node dependencies..."
  npm install 2>&1 | tee -a "$LOG_FILE"
fi

if [ -f *.sln ] || [ -f *.csproj ]; then
  log "Restoring .NET dependencies..."
  dotnet restore 2>&1 | tee -a "$LOG_FILE"
fi

# Create branch
log "Creating branch: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME" 2>&1 | tee -a "$LOG_FILE"

# Prepare session directory
mkdir -p "$SESSION_DIR"

SESSION_JSON="$SESSION_DIR/$RUN_ID.json"
SESSION_MD="$SESSION_DIR/$RUN_ID.md"

log "Running Claude Code task..."
log "Session will be saved to /sessions/$RUN_ID.json"

# Run Claude Code — capture full stream-json output as the session record
claude -p "$TASK" \
  --allowedTools "Read,Write,Edit,Bash" \
  --output-format stream-json \
  --verbose \
  2>&1 | tee "$SESSION_JSON" | tee -a "$LOG_FILE"

# Extract summary info from the session JSON for the markdown file
RESULT=$(grep '"type":"result"' "$SESSION_JSON" | tail -1 || echo '{}')
COST=$(echo "$RESULT" | grep -o '"total_cost_usd":[0-9.]*' | cut -d: -f2 || echo "unknown")
DURATION=$(echo "$RESULT" | grep -o '"duration_ms":[0-9]*' | cut -d: -f2 || echo "unknown")
SESSION_ID=$(echo "$RESULT" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
TURNS=$(echo "$RESULT" | grep -o '"num_turns":[0-9]*' | cut -d: -f2 || echo "unknown")
INPUT_TOKENS=$(echo "$RESULT" | grep -o '"input_tokens":[0-9]*' | head -1 | cut -d: -f2 || echo "unknown")
OUTPUT_TOKENS=$(echo "$RESULT" | grep -o '"output_tokens":[0-9]*' | head -1 | cut -d: -f2 || echo "unknown")
CACHE_READ_TOKENS=$(echo "$RESULT" | grep -o '"cache_read_input_tokens":[0-9]*' | head -1 | cut -d: -f2 || echo "unknown")
CACHE_CREATION_TOKENS=$(echo "$RESULT" | grep -o '"cache_creation_input_tokens":[0-9]*' | head -1 | cut -d: -f2 || echo "unknown")

# Generate markdown header
cat > "$SESSION_MD" << EOF
# Claude Code Session — $RUN_ID

## Task
$TASK

## Run Info
| Field | Value |
|---|---|
| Run ID | $RUN_ID |
| Session ID | $SESSION_ID |
| Branch | $BRANCH_NAME |
| Repo | $REPO |
| Timestamp | $(date -u '+%Y-%m-%d %H:%M:%S UTC') |
| Turns | $TURNS |
| Duration | ${DURATION}ms |
| Cost | \$$COST |
| Input tokens | $INPUT_TOKENS |
| Output tokens | $OUTPUT_TOKENS |
| Cache read tokens | $CACHE_READ_TOKENS |
| Cache creation tokens | $CACHE_CREATION_TOKENS |

## Files Changed
\`\`\`
$(git diff --name-only HEAD 2>/dev/null || git diff --name-only 2>/dev/null || echo "none")
\`\`\`

## What Happened

EOF

# Extract Claude Code's own result summary directly from the session JSON
log "Extracting session summary from result block..."
CLAUDE_SUMMARY=$(echo "$RESULT" | grep -o '"result":"[^"]*"' | sed 's/"result":"//;s/"$//' | sed 's/\\n/\n/g' || echo "")

if [ -n "$CLAUDE_SUMMARY" ]; then
  echo "$CLAUDE_SUMMARY" >> "$SESSION_MD"
else
  echo "_No summary available. See $RUN_ID.json for the full transcript._" >> "$SESSION_MD"
fi


# Append footer
cat >> "$SESSION_MD" << EOF

---
*Full machine-readable transcript: \`$RUN_ID.json\`*
EOF

log "Session summary written to /sessions/$RUN_ID.md"

# Stage all changes: new files, modifications, and deletions
log "Staging all changes..."
git add -A 2>&1 | tee -a "$LOG_FILE"

# Log what is staged
STAGED_FILES=$(git diff --staged --name-status 2>/dev/null || echo "none")
log "Staged files:"
echo "$STAGED_FILES" | tee -a "$LOG_FILE"

if [ -z "$STAGED_FILES" ] || [ "$STAGED_FILES" = "none" ]; then
  log "Nothing to commit. Exiting."
  exit 0
fi

# Build a commit subject from the first 72 characters of the task
TASK_SUMMARY=$(echo "$TASK" | head -c 72 | tr '\n' ' ' | sed 's/[[:space:]]*$//')

# Commit with a summary subject and full task in the body
log "Committing changes..."
git commit -m "feat: $TASK_SUMMARY

Task: $TASK

Run ID: $RUN_ID
Session: .claude-sessions/$RUN_ID.json
Branch: $BRANCH_NAME
Cost: \$$COST

Automated by Claude Code" 2>&1 | tee -a "$LOG_FILE"

log "Pushing branch $BRANCH_NAME..."
git push origin "$BRANCH_NAME" 2>&1 | tee -a "$LOG_FILE"

# Detect default branch
DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# Create pull request via GitHub API
log "Creating pull request..."
PR_TITLE="feat: $TASK_SUMMARY"

CHANGED_FILES=$(git diff --name-only "origin/$DEFAULT_BRANCH...HEAD" 2>/dev/null || echo "none")

PR_BODY_FILE=$(mktemp)
cat > "$PR_BODY_FILE" << EOF
## Task

$TASK

## Run Info

| Field | Value |
|---|---|
| Run ID | \`$RUN_ID\` |
| Branch | \`$BRANCH_NAME\` |
| Turns | $TURNS |
| Duration | ${DURATION}ms |
| Cost | \$$COST |

## Files Changed

\`\`\`
$CHANGED_FILES
\`\`\`

---
*Automated by Claude Code — session transcript: \`$RUN_ID.json\`*
EOF

PR_PAYLOAD=$(jq -n \
  --arg title "$PR_TITLE" \
  --rawfile body "$PR_BODY_FILE" \
  --arg head "$BRANCH_NAME" \
  --arg base "$DEFAULT_BRANCH" \
  '{title: $title, body: $body, head: $head, base: $base}')
rm -f "$PR_BODY_FILE"

log "Sending PR payload to GitHub API..."
PR_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${REPO}/pulls" \
  -d "$PR_PAYLOAD" \
  2>>"$LOG_FILE")
log "GitHub API response: $PR_RESPONSE"

PR_URL=$(echo "$PR_RESPONSE" | jq -r '.html_url // empty')

if [ -n "$PR_URL" ]; then
  log "Pull request created: $PR_URL"
else
  log "WARNING: Failed to create pull request. Response: $PR_RESPONSE"
fi

log "=== Done ==="
log "Branch pushed:   $BRANCH_NAME"
log "Pull request:    ${PR_URL:-"(not created)"}"
log "Session JSON:    /sessions/$RUN_ID.json"
log "Session summary: /sessions/$RUN_ID.md"
log "Container log:   $LOG_FILE"
