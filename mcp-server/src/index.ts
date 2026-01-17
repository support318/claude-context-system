#!/usr/bin/env node

/**
 * CLAUDE CONTEXT MCP SERVER
 * Connects Claude Code to PostgreSQL context database
 * Server: 192.168.40.100
 * Database: claude_context
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import pg from 'pg';
import { spawn } from 'child_process';

// Database configuration
const DB_CONFIG = {
  host: '192.168.40.100',
  port: 5432,
  database: 'claude_context',
  user: 'candid',
  password: 'Snoboard19', // In production, use environment variables
};

// Helper: Get database connection
async function getConnection() {
  const client = new pg.Client(DB_CONFIG);
  await client.connect();
  return client;
}

// Helper: Execute query with error handling
async function executeQuery(query: string, params: any[] = []) {
  const client = await getConnection();
  try {
    const result = await client.query(query, params);
    return result.rows;
  } finally {
    await client.end();
  }
}

// ============================================================
// SESSION CONTEXT TOOLS
// ============================================================

const SERVER_TOOLS = [
  // ---------- Session Management ----------
  {
    name: 'session_start',
    description: 'Start a new Claude Code session with context loading. Call this at the start of every session.',
    inputSchema: {
      type: 'object',
      properties: {
        session_type: {
          type: 'string',
          enum: ['general', 'project_specific', 'debugging', 'planning'],
          description: 'Type of session',
        },
        main_goal: {
          type: 'string',
          description: 'Primary objective of this session',
        },
        primary_project_id: {
          type: 'string',
          description: 'UUID of primary project (optional)',
        },
      },
      required: ['session_type'],
    },
  },

  {
    name: 'session_end',
    description: 'End current session with summary and next steps. Call this before closing Claude Code.',
    inputSchema: {
      type: 'object',
      properties: {
        session_id: {
          type: 'string',
          description: 'Session UUID from session_start',
        },
        summary: {
          type: 'string',
          description: 'Summary of what was accomplished',
        },
        outcome: {
          type: 'string',
          enum: ['success', 'partial_success', 'failed', 'blocked'],
          description: 'Session outcome',
        },
        next_steps: {
          type: 'array',
          items: { type: 'string' },
          description: 'Next steps for continuation',
        },
      },
      required: ['session_id', 'summary', 'outcome'],
    },
  },

  {
    name: 'get_session_context',
    description: 'Get current session context including main goal and active subtasks',
    inputSchema: {
      type: 'object',
      properties: {
        session_id: {
          type: 'string',
          description: 'Session UUID',
        },
      },
      required: ['session_id'],
    },
  },

  // ---------- Project Management ----------
  {
    name: 'create_project',
    description: 'Create a new project or update existing one',
    inputSchema: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Project name' },
        description: { type: 'string', description: 'Project description' },
        category: {
          type: 'string',
          enum: ['automation', 'web_dev', 'data', 'infrastructure', 'documentation', 'other'],
          description: 'Project category',
        },
        priority: {
          type: 'string',
          enum: ['low', 'medium', 'high', 'critical'],
          description: 'Project priority',
        },
        tags: {
          type: 'array',
          items: { type: 'string' },
          description: 'Project tags',
        },
        github_repo: { type: 'string', description: 'GitHub repo URL' },
      },
      required: ['name', 'category'],
    },
  },

  {
    name: 'get_active_projects',
    description: 'Get all active projects with task counts',
    inputSchema: {
      type: 'object',
      properties: {
        limit: { type: 'number', description: 'Max results (default: 20)' },
      },
    },
  },

  {
    name: 'get_project_details',
    description: 'Get detailed information about a specific project',
    inputSchema: {
      type: 'object',
      properties: {
        project_id: { type: 'string', description: 'Project UUID' },
      },
      required: ['project_id'],
    },
  },

  // ---------- Task Management ----------
  {
    name: 'create_main_goal',
    description: 'Create a main goal task. Use this for primary objectives.',
    inputSchema: {
      type: 'object',
      properties: {
        title: { type: 'string', description: 'Goal title' },
        description: { type: 'string', description: 'Detailed description' },
        project_id: { type: 'string', description: 'Associated project UUID' },
        session_id: { type: 'string', description: 'Current session UUID' },
        priority: {
          type: 'string',
          enum: ['low', 'medium', 'high', 'critical'],
          description: 'Task priority',
        },
        deadline_at: { type: 'string', description: 'Deadline ISO 8601' },
      },
      required: ['title', 'project_id'],
    },
  },

  {
    name: 'create_subtask',
    description: 'Create a subtask under a main goal. Automatically links to parent.',
    inputSchema: {
      type: 'object',
      properties: {
        title: { type: 'string', description: 'Subtask title' },
        description: { type: 'string', description: 'Detailed description' },
        main_task_id: { type: 'string', description: 'Parent main task UUID' },
        session_id: { type: 'string', description: 'Current session UUID' },
        status: {
          type: 'string',
          enum: ['pending', 'in_progress', 'completed', 'blocked'],
          description: 'Initial status',
        },
      },
      required: ['title', 'main_task_id'],
    },
  },

  {
    name: 'update_task_status',
    description: 'Update task status and progress',
    inputSchema: {
      type: 'object',
      properties: {
        task_id: { type: 'string', description: 'Task UUID' },
        status: {
          type: 'string',
          enum: ['pending', 'in_progress', 'completed', 'blocked', 'cancelled'],
          description: 'New status',
        },
        result_summary: { type: 'string', description: 'Summary of results' },
        progress_percentage: { type: 'number', description: 'Progress 0-100' },
      },
      required: ['task_id', 'status'],
    },
  },

  {
    name: 'get_active_main_goals',
    description: 'Get all active main goals across all projects',
    inputSchema: {
      type: 'object',
      properties: {
        include_completed: {
          type: 'boolean',
          description: 'Include recently completed goals (last 7 days)',
        },
      },
    },
  },

  {
    name: 'get_task_context',
    description: 'Get task with subtasks and related context',
    inputSchema: {
      type: 'object',
      properties: {
        task_id: { type: 'string', description: 'Task UUID' },
      },
      required: ['task_id'],
    },
  },

  // ---------- Decision & Outcome Tracking ----------
  {
    name: 'log_decision',
    description: 'Record a decision with rationale and alternatives',
    inputSchema: {
      type: 'object',
      properties: {
        title: { type: 'string', description: 'Decision title' },
        description: { type: 'string', description: 'What was decided' },
        rationale: { type: 'string', description: 'WHY this decision was made' },
        decision_type: {
          type: 'string',
          enum: ['architecture', 'technical', 'design', 'process', 'tool_selection'],
          description: 'Type of decision',
        },
        alternatives_considered: {
          type: 'array',
          items: { type: 'string' },
          description: 'Other options explored',
        },
        project_id: { type: 'string', description: 'Related project' },
        session_id: { type: 'string', description: 'Session where decided' },
        task_id: { type: 'string', description: 'Related task' },
      },
      required: ['title', 'description', 'rationale', 'decision_type'],
    },
  },

  {
    name: 'get_recent_decisions',
    description: 'Get recent decisions, especially those needing outcome assessment',
    inputSchema: {
      type: 'object',
      properties: {
        project_id: { type: 'string', description: 'Filter by project' },
        days_back: { type: 'number', description: 'Days to look back (default: 30)' },
        needs_assessment_only: {
          type: 'boolean',
          description: 'Only return decisions needing outcome review',
        },
      },
    },
  },

  // ---------- Context & Knowledge ----------
  {
    name: 'store_knowledge',
    description: 'Store important information for future reference',
    inputSchema: {
      type: 'object',
      properties: {
        title: { type: 'string', description: 'Knowledge entry title' },
        content: { type: 'string', description: 'Content to store' },
        context_type: {
          type: 'string',
          enum: ['credential', 'instruction', 'preference', 'architecture', 'process', 'documentation'],
          description: 'Type of knowledge',
        },
        project_id: { type: 'string', description: 'Related project (optional)' },
        global: {
          type: 'boolean',
          description: 'TRUE = applies to all projects',
        },
        importance: {
          type: 'string',
          enum: ['low', 'normal', 'high', 'critical'],
          description: 'Importance level',
        },
        tags: {
          type: 'array',
          items: { type: 'string' },
          description: 'Tags for categorization',
        },
      },
      required: ['title', 'content', 'context_type'],
    },
  },

  {
    name: 'search_knowledge',
    description: 'Search stored knowledge by tags, type, or text',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Text search query' },
        context_type: { type: 'string', description: 'Filter by type' },
        project_id: { type: 'string', description: 'Filter by project' },
        global_only: { type: 'boolean', description: 'Only global knowledge' },
        tags: {
          type: 'array',
          items: { type: 'string' },
          description: 'Filter by tags',
        },
      },
    },
  },

  // ---------- Error Logging ----------
  {
    name: 'log_error',
    description: 'Record an error with solution for future reference',
    inputSchema: {
      type: 'object',
      properties: {
        error_message: { type: 'string', description: 'Error message' },
        error_type: { type: 'string', description: 'Exception/error type' },
        stack_trace: { type: 'string', description: 'Full stack trace' },
        reproduction_steps: {
          type: 'array',
          items: { type: 'string' },
          description: 'Steps to reproduce',
        },
        solution: { type: 'string', description: 'How it was fixed' },
        solution_code: { type: 'string', description: 'Code that fixed it' },
        file_path: { type: 'string', description: 'Related file' },
        project_id: { type: 'string', description: 'Related project' },
        session_id: { type: 'string', description: 'Session where error occurred' },
        task_id: { type: 'string', description: 'Related task' },
        tags: {
          type: 'array',
          items: { type: 'string' },
          description: 'Error category tags',
        },
      },
      required: ['error_message', 'error_type'],
    },
  },

  {
    name: 'search_errors',
    description: 'Search past errors by type, tags, or text',
    inputSchema: {
      type: 'object',
      properties: {
        error_type: { type: 'string', description: 'Filter by error type' },
        project_id: { type: 'string', description: 'Filter by project' },
        solved: { type: 'boolean', description: 'Only solved errors' },
        recurring: { type: 'boolean', description: 'Only recurring errors' },
        tags: {
          type: 'array',
          items: { type: 'string' },
          description: 'Filter by tags',
        },
      },
    },
  },

  // ---------- Code Snapshots ----------
  {
    name: 'save_code_snapshot',
    description: 'Save before/after code snapshot for important changes',
    inputSchema: {
      type: 'object',
      properties: {
        file_path: { type: 'string', description: 'Full file path' },
        content_before: { type: 'string', description: 'Code before change' },
        content_after: { type: 'string', description: 'Code after change' },
        change_reason: { type: 'string', description: 'Why this change was made' },
        change_type: {
          type: 'string',
          enum: ['create', 'modify', 'delete', 'refactor'],
          description: 'Type of change',
        },
        project_id: { type: 'string', description: 'Related project' },
        session_id: { type: 'string', description: 'Current session' },
        task_id: { type: 'string', description: 'Related task' },
      },
      required: ['file_path', 'content_after', 'change_type'],
    },
  },

  // ---------- Reminders ----------
  {
    name: 'create_reminder',
    description: 'Create a session reminder (e.g., when getting sidetracked)',
    inputSchema: {
      type: 'object',
      properties: {
        session_id: { type: 'string', description: 'Current session' },
        reminder_type: {
          type: 'string',
          enum: ['main_goal', 'sidetracked', 'blocked', 'deadline'],
          description: 'Type of reminder',
        },
        message: { type: 'string', description: 'Reminder message' },
        priority: {
          type: 'string',
          enum: ['low', 'medium', 'high', 'critical'],
          description: 'Reminder priority',
        },
        main_task_id: { type: 'string', description: 'Main goal being sidetracked from' },
        current_subtask_id: { type: 'string', description: 'Current subtask causing distraction' },
      },
      required: ['session_id', 'reminder_type', 'message'],
    },
  },

  {
    name: 'get_pending_reminders',
    description: 'Get unacknowledged reminders for current session',
    inputSchema: {
      type: 'object',
      properties: {
        session_id: { type: 'string', description: 'Session UUID' },
      },
      required: ['session_id'],
    },
  },

  // ---------- GitHub Backup ----------
  {
    name: 'backup_to_github',
    description: 'Backup database to GitHub repository',
    inputSchema: {
      type: 'object',
      properties: {
        backup_type: {
          type: 'string',
          enum: ['full', 'incremental', 'data_only'],
          description: 'Type of backup',
        },
        commit_message: { type: 'string', description: 'Custom commit message' },
      },
      required: ['backup_type'],
    },
  },

  // ---------- Conversation History (with future semantic search) ----------
  {
    name: 'log_conversation_message',
    description: 'Log a conversation message for history and future search',
    inputSchema: {
      type: 'object',
      properties: {
        session_id: { type: 'string', description: 'Session UUID' },
        role: {
          type: 'string',
          enum: ['user', 'assistant', 'system'],
          description: 'Message role',
        },
        content: { type: 'string', description: 'Message content' },
        related_project_id: { type: 'string', description: 'Related project' },
        related_task_id: { type: 'string', description: 'Related task' },
        message_type: {
          type: 'string',
          enum: ['question', 'answer', 'code', 'error', 'decision', 'note'],
          description: 'Message type',
        },
        file_path: { type: 'string', description: 'Related file (if code)' },
      },
      required: ['session_id', 'role', 'content'],
    },
  },

  // ---------- Utilities ----------
  {
    name: 'get_system_status',
    description: 'Get overall system status and statistics',
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },
];

// ============================================================
// MCP SERVER SETUP
// ============================================================

const server = new Server(
  {
    name: 'claude-context-server',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: SERVER_TOOLS,
  };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    // ... tool implementations will go here ...

    return {
      content: [
        {
          type: 'text',
          text: `Tool ${name} executed successfully`,
        },
      ],
    };
  } catch (error) {
    return {
      content: [
        {
          type: 'text',
          text: `Error executing ${name}: ${error.message}`,
        },
      ],
      isError: true,
    };
  }
});

// ============================================================
// START SERVER
// ============================================================

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);

  // Test database connection
  try {
    const client = await getConnection();
    await client.query('SELECT 1');
    await client.end();
    console.error('✓ Connected to claude_context database');
  } catch (error) {
    console.error('✗ Database connection failed:', error.message);
    process.exit(1);
  }

  console.error('Claude Context MCP Server running');
}

main().catch((error) => {
  console.error('Server error:', error);
  process.exit(1);
});
