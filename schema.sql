-- ============================================================
-- CLAUDE CODE CONTEXT SYSTEM - Complete Database Schema
-- Server: 192.168.40.100
-- Database: claude_context
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgvector";  -- For semantic search
CREATE EXTENSION IF NOT EXISTS "pg_trgm";   -- For fuzzy text search

-- ============================================================
-- CORE PROJECTS
-- ============================================================

CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'active', -- active, on_hold, completed, archived
    priority VARCHAR(20) DEFAULT 'medium', -- low, medium, high, critical
    category VARCHAR(100), -- automation, web_dev, data, infrastructure, documentation
    tags TEXT[], -- Array of tags for flexible categorization

    -- Relationships
    parent_project_id UUID REFERENCES projects(id) ON DELETE SET NULL,

    -- Dates
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    deadline_at TIMESTAMP WITH TIME ZONE,

    -- Progress tracking
    progress_percentage INTEGER DEFAULT 0 CHECK (progress_percentage BETWEEN 0 AND 100),
    estimated_hours DECIMAL(10,2),
    actual_hours DECIMAL(10,2),

    -- Metadata
    created_by VARCHAR(100) DEFAULT 'ryan',
    github_repo VARCHAR(255), -- Link to GitHub repo if applicable
    documentation_url TEXT,

    -- Full text search
    search_vector tsvector GENERATED ALWAYS AS (
        to_tsvector('english',
            coalesce(name, '') || ' ' ||
            coalesce(description, '') || ' ' ||
            coalesce(array_to_string(tags, ' '), '')
        )
    ) STORED
);

CREATE INDEX idx_projects_status ON projects(status);
CREATE INDEX idx_projects_category ON projects(category);
CREATE INDEX idx_projects_tags ON projects USING GIN(tags);
CREATE INDEX idx_projects_search ON projects USING GIN(search_vector);
CREATE INDEX idx_projects_parent ON projects(parent_project_id);

-- ============================================================
-- CONVERSATION HISTORY (Full Message Log)
-- ============================================================

CREATE TABLE conversation_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,

    -- Message content
    role VARCHAR(20) NOT NULL, -- 'user', 'assistant', 'system'
    content TEXT NOT NULL,

    -- Metadata
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    token_count INTEGER,

    -- Context tracking
    related_project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
    related_task_id UUID REFERENCES tasks(id) ON DELETE SET NULL,
    message_type VARCHAR(50), -- 'question', 'answer', 'code', 'error', 'decision', 'note'

    -- For code messages
    file_path VARCHAR(500),
    code_diff TEXT,

    -- Semantic search embedding (1536 dimensions for OpenAI embeddings)
    embedding vector(1536)
);

CREATE INDEX idx_conv_messages_session ON conversation_messages(session_id);
CREATE INDEX idx_conv_messages_project ON conversation_messages(related_project_id);
CREATE INDEX idx_conv_messages_timestamp ON conversation_messages(timestamp DESC);
CREATE INDEX idx_conv_messages_embedding ON conversation_messages USING ivfflat(embedding vector_cosine_ops) WITH (lists = 100);

-- ============================================================
-- SESSIONS (Claude Code Sessions)
-- ============================================================

CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Session info
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ended_at TIMESTAMP WITH TIME ZONE,
    duration_minutes INTEGER,

    -- Context
    session_type VARCHAR(50) DEFAULT 'general', -- general, project_specific, debugging, planning
    main_goal TEXT, -- The primary objective of this session
    summary TEXT, -- Auto-generated or manual summary

    -- Environment
    machine_name VARCHAR(100),
    working_directory TEXT,
    claude_version VARCHAR(50),

    -- Outcomes
    status VARCHAR(50) DEFAULT 'in_progress', -- in_progress, completed, aborted
    outcome VARCHAR(100), -- success, partial_success, failed, blocked

    -- Related work
    primary_project_id UUID REFERENCES projects(id) ON DELETE SET NULL,

    -- Statistics
    total_messages INTEGER DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    tasks_completed INTEGER DEFAULT 0,
    tasks_created INTEGER DEFAULT 0,

    -- Next steps for continuation
    next_steps TEXT[]
);

CREATE INDEX idx_sessions_started ON sessions(started_at DESC);
CREATE INDEX idx_sessions_status ON sessions(status);
CREATE INDEX idx_sessions_project ON sessions(primary_project_id);

-- ============================================================
-- TASKS (Main + Subtasks)
-- ============================================================

CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Task info
    title VARCHAR(500) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'pending', -- pending, in_progress, completed, blocked, cancelled

    -- Task hierarchy
    parent_task_id UUID REFERENCES tasks(id) ON DELETE SET NULL,
    is_main_goal BOOLEAN DEFAULT FALSE, -- TRUE = This is a main goal, not a subtask
    main_task_id UUID REFERENCES tasks(id) ON DELETE SET NULL, -- If subtask, points to main

    -- Relationships
    project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
    session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,

    -- Blocking/dependencies
    blocked_by UUID[] REFERENCES tasks(id), -- Array of task IDs blocking this one
    blocking UUID[] REFERENCES tasks(id), -- Array of task IDs this one blocks

    -- Dates
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    deadline_at TIMESTAMP WITH TIME ZONE,

    -- Priority
    priority VARCHAR(20) DEFAULT 'medium', -- low, medium, high, critical

    -- Effort tracking
    estimated_hours DECIMAL(10,2),
    actual_hours DECIMAL(10,2),

    -- Completion criteria
    acceptance_criteria TEXT[],
    definition_of_done TEXT,

    -- Result
    result_summary TEXT,
    artifacts_produced TEXT[], -- Files created, docs written, etc.

    -- Tags
    tags TEXT[]
);

CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_project ON tasks(project_id);
CREATE INDEX idx_tasks_session ON tasks(session_id);
CREATE INDEX idx_tasks_parent ON tasks(parent_task_id);
CREATE INDEX idx_tasks_main_goal ON tasks(is_main_goal) WHERE is_main_goal = TRUE;
CREATE INDEX idx_tasks_main_task ON tasks(main_task_id);

-- Join table for many-to-many session-task relationship
CREATE TABLE session_tasks (
    session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
    task_id UUID REFERENCES tasks(id) ON DELETE CASCADE,
    role VARCHAR(50), -- 'primary', 'secondary', 'sidetracked_from', 'created'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (session_id, task_id)
);

-- ============================================================
-- DECISIONS & OUTCOMES (What we decided and why)
-- ============================================================

CREATE TABLE decisions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Decision info
    title VARCHAR(500) NOT NULL,
    description TEXT NOT NULL, -- What was decided
    rationale TEXT NOT NULL, -- WHY we decided this
    context TEXT, -- Background leading to decision

    -- Relationships
    project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
    session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
    task_id UUID REFERENCES tasks(id) ON DELETE SET NULL,

    -- Decision details
    decision_type VARCHAR(100), -- architecture, technical, design, process, tool_selection
    alternatives_considered TEXT[], -- Other options we explored
    pros TEXT[],
    cons TEXT[],

    -- Outcome tracking
    outcome VARCHAR(50), -- success, partial_success, failure, unknown, needs_revision
    outcome_notes TEXT,
    outcome_assessed_at TIMESTAMP WITH TIME ZONE,

    -- Dates
    decided_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revisited_at TIMESTAMP WITH TIME ZONE,

    -- Lessons learned
    lessons_learned TEXT[],
    would_do_differently TEXT,

    -- Tags
    tags TEXT[]
);

CREATE INDEX idx_decisions_project ON decisions(project_id);
CREATE INDEX idx_decisions_session ON decisions(session_id);
CREATE INDEX idx_decisions_outcome ON decisions(outcome);

-- ============================================================
-- CODE SNAPSHOTS (Before/After of important changes)
-- ============================================================

CREATE TABLE code_snapshots (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- File info
    file_path TEXT NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    language VARCHAR(100),

    -- Snapshots
    content_before TEXT,
    content_after TEXT,
    diff TEXT,

    -- Change info
    change_type VARCHAR(50), -- create, modify, delete, refactor
    change_reason TEXT, -- Why this change was made

    -- Relationships
    project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
    session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
    task_id UUID REFERENCES tasks(id) ON DELETE SET NULL,
    decision_id UUID REFERENCES decisions(id) ON DELETE SET NULL,

    -- Git integration
    git_commit_hash VARCHAR(100),
    git_branch VARCHAR(100),
    git_repo_url TEXT,

    -- Dates
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Review
    reviewed BOOLEAN DEFAULT FALSE,
    review_notes TEXT
);

CREATE INDEX idx_code_snapshots_file ON code_snapshots(file_path);
CREATE INDEX idx_code_snapshots_project ON code_snapshots(project_id);
CREATE INDEX idx_code_snapshots_session ON code_snapshots(session_id);

-- ============================================================
-- ERROR LOGS (Track errors and solutions)
-- ============================================================

CREATE TABLE error_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Error info
    error_message TEXT NOT NULL,
    error_type VARCHAR(255), -- Exception type
    error_code VARCHAR(100),

    -- Context
    stack_trace TEXT,
    reproduction_steps TEXT[],
    environment_info JSONB, -- OS, versions, etc.

    -- Relationships
    project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
    session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
    task_id UUID REFERENCES tasks(id) ON DELETE SET NULL,
    file_path TEXT,

    -- Solution
    solution TEXT, -- How we fixed it
    solution_code TEXT, -- Code that fixed it
    solved_at TIMESTAMP WITH TIME ZONE,
    solved_by VARCHAR(100) DEFAULT 'claude',

    -- Occurrence tracking
    first_occurrence_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    occurrence_count INTEGER DEFAULT 1,
    is_recurring BOOLEAN DEFAULT FALSE,

    -- Tags
    tags TEXT[] -- Categories like 'database', 'api', 'authentication', etc.
);

CREATE INDEX idx_error_logs_project ON error_logs(project_id);
CREATE INDEX idx_error_logs_type ON error_logs(error_type);
CREATE INDEX idx_error_logs_solved ON error_logs(solved_at) WHERE solved_at IS NOT NULL;
CREATE INDEX idx_error_logs_recurring ON error_logs(is_recurring) WHERE is_recurring = TRUE;

-- ============================================================
-- KNOWLEDGE CONTEXT (Important info to remember)
-- ============================================================

CREATE TABLE knowledge_context (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Content
    title VARCHAR(500) NOT NULL,
    content TEXT NOT NULL,
    context_type VARCHAR(100), -- credential, instruction, preference, architecture, process

    -- Relationships
    project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
    global BOOLEAN DEFAULT FALSE, -- TRUE = applies to all projects

    -- Importance
    importance VARCHAR(20) DEFAULT 'normal', -- low, normal, high, critical

    -- Validity
    valid_from TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    valid_until TIMESTAMP WITH TIME ZONE, -- NULL = indefinitely valid

    -- Access tracking
    last_accessed_at TIMESTAMP WITH TIME ZONE,
    access_count INTEGER DEFAULT 0,

    -- Tags
    tags TEXT[],

    -- Semantic search
    embedding vector(1536)
);

CREATE INDEX idx_knowledge_context_project ON knowledge_context(project_id);
CREATE INDEX idx_knowledge_context_global ON knowledge_context(global) WHERE global = TRUE;
CREATE INDEX idx_knowledge_context_type ON knowledge_context(context_type);
CREATE INDEX idx_knowledge_context_embedding ON knowledge_context USING ivfflat(embedding vector_cosine_ops) WITH (lists = 100);

-- ============================================================
-- RELATIONSHIPS (How things connect)
-- ============================================================

CREATE TABLE relationships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- What's being connected
    source_type VARCHAR(50) NOT NULL, -- 'project', 'task', 'decision', 'error', 'context'
    source_id UUID NOT NULL,
    target_type VARCHAR(50) NOT NULL,
    target_id UUID NOT NULL,

    -- Relationship info
    relationship_type VARCHAR(100) NOT NULL, -- 'depends_on', 'blocks', 'relates_to', 'solved_by', 'references'
    description TEXT,
    strength VARCHAR(20) DEFAULT 'normal', -- weak, normal, strong, critical

    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by VARCHAR(100) DEFAULT 'claude',

    -- Constraint: Can't reference same item
    EXCLUDE (source_type WITH =, source_id WITH =, target_type WITH =, target_id WITH =) WHERE (source_type, source_id) IS DISTINCT FROM (target_type, target_id)
);

CREATE INDEX idx_relationships_source ON relationships(source_type, source_id);
CREATE INDEX idx_relationships_target ON relationships(target_type, target_id);
CREATE INDEX idx_relationships_type ON relationships(relationship_type);

-- ============================================================
-- ARTIFACTS (Files, docs, diagrams created)
-- ============================================================

CREATE TABLE artifacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Artifact info
    name VARCHAR(500) NOT NULL,
    type VARCHAR(100), -- 'document', 'image', 'diagram', 'code', 'config', 'video'
    file_path TEXT,
    description TEXT,

    -- Relationships
    project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
    session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
    task_id UUID REFERENCES tasks(id) ON DELETE SET NULL,

    -- Content (for small artifacts)
    content TEXT,

    -- External storage
    storage_type VARCHAR(50), -- 'local', 'github', 's3', 'server'
    storage_path TEXT,
    url TEXT,

    -- Dates
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    modified_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Version tracking
    version INTEGER DEFAULT 1,
    parent_artifact_id UUID REFERENCES artifacts(id) ON DELETE SET NULL
);

CREATE INDEX idx_artifacts_project ON artifacts(project_id);
CREATE INDEX idx_artifacts_session ON artifacts(session_id);
CREATE INDEX idx_artifacts_type ON artifacts(type);

-- ============================================================
-- GITHUB BACKUP TRACKING
-- ============================================================

CREATE TABLE github_backups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Backup info
    backup_type VARCHAR(50), -- 'full', 'incremental', 'schema_only', 'data_only'
    status VARCHAR(50), -- 'pending', 'in_progress', 'completed', 'failed'

    -- GitHub info
    repo_owner VARCHAR(100) DEFAULT 'ryanmayiras',
    repo_name VARCHAR(100),
    branch VARCHAR(100) DEFAULT 'main',
    commit_hash VARCHAR(100),

    -- What was backed up
    tables_included TEXT[],
    rows_affected INTEGER,

    -- Dates
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Result
    status_message TEXT,
    error_message TEXT
);

CREATE INDEX idx_github_backups_type ON github_backups(backup_type);
CREATE INDEX idx_github_backups_status ON github_backups(status);
CREATE INDEX idx_github_backups_date ON github_backups(started_at DESC);

-- ============================================================
-- SESSION REMINDERS (Proactive tracking)
-- ============================================================

CREATE TABLE session_reminders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,

    -- Reminder info
    reminder_type VARCHAR(50), -- 'main_goal', 'sidetracked', 'blocked', 'deadline'
    message TEXT NOT NULL,
    priority VARCHAR(20) DEFAULT 'medium',

    -- Context
    related_project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
    main_task_id UUID REFERENCES tasks(id) ON DELETE SET NULL,
    current_subtask_id UUID REFERENCES tasks(id) ON DELETE SET NULL,

    -- State
    acknowledged BOOLEAN DEFAULT FALSE,
    acknowledged_at TIMESTAMP WITH TIME ZONE,

    -- Timestamp
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_session_reminders_session ON session_reminders(session_id);
CREATE INDEX idx_session_reminders_type ON session_reminders(reminder_type);
CREATE INDEX idx_session_reminders_unacknowledged ON session_reminders(acknowledged) WHERE acknowledged = FALSE;

-- ============================================================
-- USEFUL VIEWS
-- ============================================================

-- Active projects with task counts
CREATE VIEW active_projects_overview AS
SELECT
    p.id,
    p.name,
    p.status,
    p.priority,
    p.category,
    p.progress_percentage,
    COUNT(DISTINCT t.id) FILTER (WHERE t.status != 'completed') as active_tasks,
    COUNT(DISTINCT t.id) FILTER (WHERE t.status = 'completed') as completed_tasks,
    p.deadline_at,
    p.updated_at
FROM projects p
LEFT JOIN tasks t ON t.project_id = p.id
WHERE p.status = 'active'
GROUP BY p.id;

-- Current main goals (not completed)
CREATE VIEW current_main_goals AS
SELECT
    t.id,
    t.title,
    t.description,
    p.name as project_name,
    t.status,
    t.priority,
    t.created_at,
    t.deadline_at
FROM tasks t
LEFT JOIN projects p ON t.project_id = p.id
WHERE t.is_main_goal = TRUE
  AND t.status NOT IN ('completed', 'cancelled')
ORDER BY t.priority DESC, t.created_at ASC;

-- Recent decisions needing outcome assessment
CREATE VIEW pending_decision_outcomes AS
SELECT
    d.id,
    d.title,
    d.decision_type,
    p.name as project_name,
    d.decided_at,
    CASE
        WHEN d.outcome IS NULL THEN TRUE
        WHEN d.outcome = 'unknown' THEN TRUE
        ELSE FALSE
    END as needs_assessment
FROM decisions d
LEFT JOIN projects p ON d.project_id = p.id
WHERE d.outcome IS NULL
   OR d.outcome = 'unknown'
   OR (d.outcome_assessed_at IS NULL AND d.decided_at < NOW() - INTERVAL '7 days')
ORDER BY d.decided_at DESC;

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

-- Update updated_at timestamp automatically
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to relevant tables
CREATE TRIGGER update_projects_updated_at BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tasks_updated_at BEFORE UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to find related context using semantic search
CREATE OR REPLACE FUNCTION find_related_context(
    query_embedding vector(1536),
    max_results INTEGER DEFAULT 10,
    project_id_filter UUID DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    title VARCHAR(500),
    content TEXT,
    context_type VARCHAR(100),
    similarity FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        kc.id,
        kc.title,
        kc.content,
        kc.context_type,
        1 - (kc.embedding <=> query_embedding) as similarity
    FROM knowledge_context kc
    WHERE
        kc.embedding IS NOT NULL
        AND (project_id_filter IS NULL OR kc.project_id = project_id_filter)
        AND (kc.valid_until IS NULL OR kc.valid_until > NOW())
    ORDER BY kc.embedding <=> query_embedding
    LIMIT max_results;
END;
$$ LANGUAGE plpgsql;

-- Function to search conversation history semantically
CREATE OR REPLACE FUNCTION search_conversations(
    query_embedding vector(1536),
    max_results INTEGER DEFAULT 10,
    days_back INTEGER DEFAULT 30
)
RETURNS TABLE (
    id UUID,
    role VARCHAR(20),
    content TEXT,
    timestamp TIMESTAMP WITH TIME ZONE,
    project_name VARCHAR(255),
    similarity FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        cm.id,
        cm.role,
        cm.content,
        cm.timestamp,
        p.name as project_name,
        1 - (cm.embedding <=> query_embedding) as similarity
    FROM conversation_messages cm
    LEFT JOIN projects p ON cm.related_project_id = p.id
    WHERE
        cm.embedding IS NOT NULL
        AND cm.timestamp > NOW() - (days_back || ' days')::INTERVAL
    ORDER BY cm.embedding <=> query_embedding
    LIMIT max_results;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- INITIAL DATA
-- ============================================================

-- Insert default global knowledge context
INSERT INTO knowledge_context (title, content, context_type, global, importance, tags) VALUES
('Make.com API Credentials', 'API Key: e365ada8-17d2-4c0a-9457-40c7dcaf025a
Team ID: 2863954
Organization ID: 2863954
Region: us2.make.com', 'credential', TRUE, 'high', ARRAY['make', 'automation', 'api']),

('SSH Server Access', 'Server: 192.168.40.100
User: candid
Password: Snoboard19
Purpose: Central server for databases and services', 'credential', TRUE, 'critical', ARRAY['server', 'ssh', 'infrastructure']),

('Claude Context System Location', 'System files at: /Users/ryanmayiras/claude-context-system/
Database: claude_context on 192.168.40.100
GitHub: https://github.com/ryanmayiras/claude-context-system', 'infrastructure', TRUE, 'high', ARRAY['claude', 'context', 'database']);

-- ============================================================
-- END OF SCHEMA
-- ============================================================

COMMIT;
