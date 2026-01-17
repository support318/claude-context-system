# Claude Context System

**Persistent Memory and Context for Claude Code**

A comprehensive system for maintaining context, tracking projects, and storing conversation history across Claude Code sessions. All data stored centrally on your server with GitHub backups.

---

## 🎯 What This Solves

**Problem**: Claude Code loses context between sessions, forgets main goals when sidetracked, and can't reference past conversations or decisions.

**Solution**:
- ✅ **Full conversation history** with semantic search
- ✅ **Project & task tracking** with main goal vs subtask awareness
- ✅ **Decision audit trail** - what we decided and why
- ✅ **Error logging** with solutions for future reference
- ✅ **Code snapshots** tracking important changes
- ✅ **Proactive reminders** when getting sidetracked
- ✅ **Server-based storage** - all data on 192.168.40.100
- ✅ **GitHub backups** - version controlled history

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Claude Code CLI                         │
└────────────────────────┬────────────────────────────────────┘
                         │ (MCP Protocol)
                         ▼
            ┌────────────────────────┐
            │  Custom MCP Server     │
            │  (TypeScript/Node)     │
            └────────┬───────────────┘
                     │ (SQL)
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              PostgreSQL Database (pgvector)                  │
│              Server: 192.168.40.100                         │
│              Database: claude_context                       │
│                                                              │
│  Tables:                                                    │
│  • projects              - All projects                    │
│  • sessions              - Claude Code sessions            │
│  • tasks                 - Main goals + subtasks           │
│  • conversation_messages - Full chat history               │
│  • decisions             - What we decided + outcomes      │
│  • error_logs            - Errors + solutions              │
│  • code_snapshots        - Before/after code changes       │
│  • knowledge_context     - Important info to remember      │
│  • relationships         - How things connect              │
│  • session_reminders     - Proactive tracking              │
│  • github_backups        - Backup history                  │
└────────────────────────┬────────────────────────────────────┘
                     │
                     ▼ (Optional - for UI)
            ┌────────────────────────┐
            │      AppFlowy UI        │
            │  (Future enhancement)   │
            └────────────────────────┘
```

---

## 📊 Database Schema Highlights

### Core Tables

| Table | Purpose | Key Features |
|-------|---------|--------------|
| `projects` | Track all projects | Status, priority, categories, tags, deadlines |
| `sessions` | Claude Code sessions | Main goal, summary, next steps, duration |
| `tasks` | Main goals + subtasks | Hierarchy, blocking, progress, acceptance criteria |
| `conversation_messages` | Full message history | Semantic search via pgvector embeddings |
| `decisions` | Decision audit trail | Rationale, alternatives, outcomes, lessons learned |
| `error_logs` | Errors + solutions | Reproduction steps, resolution, recurring tracking |
| `code_snapshots` | Important code changes | Before/after, diff, git integration |
| `knowledge_context` | Info to remember | Credentials, instructions, preferences |
| `session_reminders` | Proactive tracking | Main goal reminders, sidetracked alerts |

### Smart Features

- **Semantic Search**: Use pgvector to find relevant past conversations
- **Relationships**: Track how projects, tasks, and decisions connect
- **Auto-Timestamps**: Automatic `updated_at` tracking
- **Full-Text Search**: Fast text search across all tables
- **Views**: Pre-built queries for common scenarios

---

## 🚀 Quick Start

### Prerequisites

- Server access: `ssh candid@192.168.40.100`
- PostgreSQL running (existing container: `candid-crm-staging-postgres-1`)
- Node.js 18+ (for MCP server)
- Claude Code CLI
- gh CLI (for GitHub backup, optional)

### Installation

1. **Clone or create this project**:
```bash
cd /Users/ryanmayiras/claude-context-system
```

2. **Run the setup script**:
```bash
chmod +x setup.sh
./setup.sh
```

This will:
- Create database on server
- Apply schema with all tables
- Build MCP server
- Register with Claude Code
- Set up GitHub repository
- Create initial backup

3. **Restart Claude Code**:
```bash
# Exit current session
exit

# Start new session
claude code
```

4. **Verify MCP server loaded**:
```bash
claude mcp list
# Should show: claude-context: ✓ Connected
```

---

## 📖 Usage

### Basic Workflow

#### 1. Start a Session
```
"Start a new session for working on the SEO import project"
```
→ Calls `session_start` with project context

#### 2. Define Main Goal
```
"Create a main goal: Import 274 SEO markdown files into Google Sheets"
```
→ Calls `create_main_goal`

#### 3. Work on Subtasks
```
"Create a subtask: Parse YAML frontmatter from markdown files"
```
→ Calls `create_subtask` (linked to main goal)

#### 4. Get Sidetracked?
```
"Log that we're sidetracked fixing SSL certificates"
```
→ Calls `create_reminder` with type='sidetracked'

#### 5. Get Back on Track
```
"What was our main goal?"
```
→ Calls `get_session_context` → Shows main goal + reminder

#### 6. End Session
```
"End this session. We completed the YAML parser and tested on 10 files."
```
→ Calls `session_end` with summary and next steps

### MCP Tools Available

#### Session Management
- `session_start` - Start new session with context
- `session_end` - End session with summary
- `get_session_context` - Get current context + main goal

#### Project Management
- `create_project` - Create/update project
- `get_active_projects` - List active projects
- `get_project_details` - Project details + tasks

#### Task Management
- `create_main_goal` - Create primary objective
- `create_subtask` - Create subtask under main goal
- `update_task_status` - Update task progress
- `get_active_main_goals` - See all active goals
- `get_task_context` - Task + subtasks + context

#### Decision Tracking
- `log_decision` - Record decision + rationale
- `get_recent_decisions` - Recent decisions needing review

#### Knowledge & Errors
- `store_knowledge` - Store important info
- `search_knowledge` - Search stored knowledge
- `log_error` - Record error + solution
- `search_errors` - Find past errors

#### Reminders
- `create_reminder` - Create session reminder
- `get_pending_reminders` - Get unacknowledged reminders

#### Utilities
- `backup_to_github` - Backup database to GitHub
- `get_system_status` - System statistics
- `log_conversation_message` - Log chat history
- `save_code_snapshot` - Save code changes

---

## 🔍 Examples

### Example 1: Full Project Workflow

```
You: Start a session for the SimplyNoted automation project

Claude: [Calls session_start]
✓ Session started. Context loaded:
  - Active projects: SimplyNoted, SEO Import
  - Main goals: 2 active
  - Recent decisions: 3

You: Create a main goal: Configure webhook triggers in Make.com

Claude: [Calls create_main_goal]
✓ Main goal created:
  ID: 123e4567-e89b-12d3-a456-426614174000
  Title: Configure webhook triggers
  Priority: high
  Status: pending

You: Create a subtask: Add filters to router routes

Claude: [Calls create_subtask]
✓ Subtask created:
  Parent: Configure webhook triggers
  Title: Add filters to router routes
  Status: pending

[... work on subtask ...]

You: Update the subtask status to completed

Claude: [Calls update_task_status]
✓ Task updated: Add filters → completed
⚠️ Reminder: Main goal "Configure webhook triggers" still in progress

You: We're sidetracked fixing n8n credentials

Claude: [Calls create_reminder]
⚠️ SIDETRACKED ALERT:
Working on: Fix n8n credentials
Main goal was: Configure webhook triggers
Don't forget to return!
```

### Example 2: Decision Tracking

```
You: Log a decision. We chose PostgreSQL over MongoDB for the context database
because we need ACID compliance and complex joins. We also considered SQLite
but decided against it due to concurrency limitations.

Claude: [Calls log_decision]
✓ Decision recorded:
Type: technical
Rationale: Need ACID compliance + complex joins
Alternatives: MongoDB, SQLite
Outcome: pending assessment

[2 weeks later...]

You: How did that PostgreSQL decision work out?

Claude: [Calls get_recent_decisions + log_decision with outcome]
Found decision from 2 weeks ago:
→ Chose PostgreSQL for ACID compliance
→ Assessment: Good decision
→ Notes: Handles concurrent access well
→ Would do differently: Nothing
```

### Example 3: Error Search

```
You: I'm getting "permission denied" errors with PostgreSQL again

Claude: [Calls search_errors]
Found similar error from 5 days ago:
Error: permission denied @ postgresql
Solution: Added user to proper role
Code: GRANT ALL PRIVILEGES ON DATABASE...

Fixed! Should I apply the same solution?
```

---

## 🔄 GitHub Backup

### Automatic Backups

Manual backup:
```bash
chmod +x scripts/backup-to-github.sh
./scripts/backup-to-github.sh data_only
```

Or via Claude:
```
"Backup the database to GitHub"
```

### Backup Types

- `full` - Complete database dump
- `incremental` - Changes since last backup
- `data_only` - Just data, no schema

### Backup Location

- Server: `/tank/services/claude-context/backups/`
- GitHub: `https://github.com/ryanmayiras/claude-context-system/tree/main/database-backups`

---

## 🗄️ Database Location

- **Server**: 192.168.40.100
- **Database**: `claude_context`
- **PostgreSQL Container**: `candid-crm-staging-postgres-1`
- **Port**: 5432
- **User**: `candid`

### Direct Access

```bash
# SSH to server
ssh candid@192.168.40.100

# Connect to database
docker exec -it candid-crm-staging-postgres-1 psql -U candid -d claude_context

# View tables
\dt

# Query example
SELECT * FROM current_main_goals;
```

---

## 📁 Project Structure

```
claude-context-system/
├── schema.sql                    # Database schema
├── setup.sh                      # Installation script
├── .env                          # Configuration
├── README.md                     # This file
├── mcp-server/
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       └── index.ts             # MCP server implementation
├── scripts/
│   └── backup-to-github.sh      # GitHub backup script
├── database-backups/            # Local backup copies
│   └── (git tracked)
└── docs/
    ├── API.md                   # MCP API documentation
    └── EXAMPLES.md              # Usage examples
```

---

## 🛠️ Development

### Build MCP Server

```bash
cd mcp-server
npm install
npm run build
```

### Run MCP Server (Manual)

```bash
node dist/index.js
```

### Update Schema

```bash
# Edit schema.sql
# Apply to database
docker exec -i candid-crm-staging-postgres-1 psql -U candid -d claude_context < schema.sql
```

---

## 🔐 Security Notes

⚠️ **Important**: This system stores sensitive information:

- Credentials (Make.com API, SSH keys)
- Project details and architecture
- Error logs that may reveal system info

**Recommendations**:
1. Keep GitHub repository **private** if possible
2. Use environment variables for sensitive data
3. Regularly review `knowledge_context` table for credentials
4. Consider encryption for sensitive fields
5. Backup regularly

---

## 🚧 Future Enhancements

### Planned Features

- [ ] **AppFlowy UI** - Nice interface for browsing projects
- [ ] **Vector Embeddings** - Semantic search for conversations
- [ ] **Auto-Context Capture** - Watch files, git commits for changes
- [ ] **Dashboard** - Web UI for system overview
- [ ] **Recurring Error Detection** - Auto-flag patterns
- [ ] **Decision Outcome Tracking** - Auto-ask for outcomes after 7 days
- [ ] **Timeline View** - Visual project timeline
- [ ] **Mobile App** - Quick status checks

### Integration Ideas

- **n8n workflows** - Auto-trigger actions based on project state
- **Slack/Teams** - Notifications for deadlines, reminders
- **Obsidian** - Knowledge graph visualization
- **GitHub Actions** - Automated backups

---

## 📊 System Status

Check system health:

```
"Get system status"
```

Returns:
- Total projects, sessions, tasks
- Active main goals
- Recent decisions needing review
- Database size
- Last backup time

---

## 🤝 Contributing

This is a personal system, but structure makes it easy to enhance:

1. Add new tables to `schema.sql`
2. Add corresponding MCP tools in `mcp-server/src/index.ts`
3. Update documentation
4. Test locally, then deploy

---

## 📝 License

MIT License - Feel free to use components for your own context system!

---

## 🎉 Success Metrics

You'll know it's working when:

- ✅ You start sessions and immediately see context
- ✅ Claude reminds you of the main goal when sidetracked
- ✅ You can search past errors and find solutions
- ✅ Decisions are tracked with outcomes
- ✅ No more "what were we working on?"
- ✅ GitHub has regular backups
- ✅ All conversation history is searchable

---

**Built with ❤️ for better AI-human collaboration**

Last updated: 2026-01-16
