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
ISSUE_NUMBER="${ISSUE_NUMBER:-}"
ISSUE_URL="${ISSUE_URL:-}"

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
CLAUDE_SETTINGS_FILE="/claude-settings.json"
CLAUDE_ALLOWED_TOOLS="Read,Write,Edit,Bash,mcp__github__*"

log "Configuring GitHub MCP server..."
# Build MCP JSON safely from runtime environment rather than parsing a .env file.
GITHUB_MCP_CONFIG=$(jq -cn --arg token "$GITHUB_TOKEN" '{type:"http",url:"https://api.githubcopilot.com/mcp",headers:{Authorization:("Bearer " + $token)}}')
claude mcp remove github >/dev/null 2>&1 || true
claude mcp add-json github "$GITHUB_MCP_CONFIG" 2>&1 | tee -a "$LOG_FILE"

log "Running GitHub MCP preflight check..."
PREFLIGHT_JSON="$SESSION_DIR/$RUN_ID-preflight.json"
claude -p "Call the GitHub MCP tool mcp__github__get_me exactly once. After the tool responds, output exactly one line in this format with no other text: GITHUB_LOGIN=<the login value from the response>. If the tool call fails or is denied, output: GITHUB_LOGIN=ERROR" \
  --settings "$CLAUDE_SETTINGS_FILE" \
  --allowedTools "$CLAUDE_ALLOWED_TOOLS" \
  --permission-mode dontAsk \
  --output-format stream-json \
  --verbose \
  2>&1 | tee "$PREFLIGHT_JSON" | tee -a "$LOG_FILE"

PREFLIGHT_RESULT=$(grep '"type":"result"' "$PREFLIGHT_JSON" | tail -1 || echo '{}')
PREFLIGHT_RESULT_TEXT=$(echo "$PREFLIGHT_RESULT" | jq -r '.result // ""' 2>/dev/null || echo "")
PREFLIGHT_LOGIN=$(echo "$PREFLIGHT_RESULT_TEXT" | grep -oP '(?<=GITHUB_LOGIN=)\S+' || true)

if [ -z "$PREFLIGHT_LOGIN" ] || [ "$PREFLIGHT_LOGIN" = "ERROR" ]; then
  log "ERROR: GitHub MCP preflight did not confirm authenticated access."
  log "Result text: $PREFLIGHT_RESULT_TEXT"
  log "See $PREFLIGHT_JSON for details."
  exit 1
fi

log "GitHub MCP preflight succeeded for login: $PREFLIGHT_LOGIN"

log "add dotnet plugins"

# Add the marketplace once
claude plugin marketplace add dotnet/skills

# Install plugins
claude plugin install dotnet@dotnet-agent-skills
claude plugin install dotnet-data@dotnet-agent-skills
claude plugin install dotnet-msbuild@dotnet-agent-skills
claude plugin install dotnet-ai@dotnet-agent-skills
claude plugin install dotnet-test@dotnet-agent-skills
claude plugin install dotnet-aspnet@dotnet-agent-skills

log "Building effective task prompt from template..."
TEMPLATE_FILE="/task-template.md"
ISSUE_REFERENCE=""
if [ -n "$ISSUE_NUMBER" ] || [ -n "$ISSUE_URL" ]; then
  TEMPLATE_FILE="/task-template-issue.md"
  if [ -n "$ISSUE_NUMBER" ]; then
    ISSUE_REFERENCE="#$ISSUE_NUMBER"
  else
    ISSUE_REFERENCE="$ISSUE_URL"
  fi
  log "Using issue-mode template ($TEMPLATE_FILE)"
else
  log "Using standard template ($TEMPLATE_FILE)"
fi

EFFECTIVE_TASK=$(awk \
  -v repo="$REPO" \
  -v branch="$BRANCH_NAME" \
  -v run_id="$RUN_ID" \
  -v user_task="$TASK" \
  -v issue_number="$ISSUE_NUMBER" \
  -v issue_url="$ISSUE_URL" \
  -v issue_reference="$ISSUE_REFERENCE" \
  'BEGIN {
    gsub(/&/, "\\\\&", repo)
    gsub(/&/, "\\\\&", branch)
    gsub(/&/, "\\\\&", run_id)
    gsub(/&/, "\\\\&", user_task)
    gsub(/&/, "\\\\&", issue_number)
    gsub(/&/, "\\\\&", issue_url)
    gsub(/&/, "\\\\&", issue_reference)
  }
  {
    gsub(/\{\{REPO\}\}/, repo)
    gsub(/\{\{BRANCH_NAME\}\}/, branch)
    gsub(/\{\{RUN_ID\}\}/, run_id)
    gsub(/\{\{USER_TASK\}\}/, user_task)
    gsub(/\{\{ISSUE_NUMBER\}\}/, issue_number)
    gsub(/\{\{ISSUE_URL\}\}/, issue_url)
    gsub(/\{\{ISSUE_REFERENCE\}\}/, issue_reference)
    print
  }' "$TEMPLATE_FILE")

log "Running Claude Code task..."
log "Session will be saved to /sessions/$RUN_ID.json"


# Run Claude Code — capture full stream-json output as the session record
claude -p "$EFFECTIVE_TASK" \
  --settings "$CLAUDE_SETTINGS_FILE" \
  --allowedTools "$CLAUDE_ALLOWED_TOOLS" \
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

PR_URL=$(grep -Eo 'https://github\.com/[^[:space:]]+/pull/[0-9]+' "$SESSION_JSON" | tail -1 || true)
if [ -n "$PR_URL" ]; then
  log "Pull request reported by Claude: $PR_URL"
else
  log "No pull request URL detected in session output."
fi

log "=== Done ==="
log "Branch:          $BRANCH_NAME"
log "Pull request:    ${PR_URL:-"(not detected)"}"
log "Session JSON:    /sessions/$RUN_ID.json"
log "Session summary: /sessions/$RUN_ID.md"
log "Container log:   $LOG_FILE"
