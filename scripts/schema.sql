-- Dev Nexus Database Schema v1.0 (Canonical)
--
-- NOTE: This is the CANONICAL source for PostgreSQL schema definitions.
-- DBT models in dbt/models/core/ are derived from this file.
-- Python migrations are deprecated for new schema changes — DBT owns schema now.
-- See docs/dbt-schema-management.md for details.
--
-- With pgvector support for embeddings

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- ── repositories ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS repositories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    problem_domain TEXT,
    last_analyzed TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_commit_sha VARCHAR(40),
    -- Complexity metrics (added via migration 005)
    complexity_metrics JSONB DEFAULT NULL,
    complexity_last_analyzed TIMESTAMP DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_repositories_name ON repositories(name);
CREATE INDEX IF NOT EXISTS idx_repositories_last_analyzed ON repositories(last_analyzed);
CREATE INDEX IF NOT EXISTS idx_repositories_complexity_metrics ON repositories USING GIN (complexity_metrics);

-- ── reusable_components ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS reusable_components (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    name VARCHAR(500) NOT NULL,
    purpose TEXT,
    location TEXT,
    component_id TEXT UNIQUE,
    component_type VARCHAR(50) DEFAULT 'unknown',
    language VARCHAR(50) DEFAULT 'unknown',
    api_signature TEXT,
    imports JSONB DEFAULT '[]'::jsonb,
    keywords JSONB DEFAULT '[]'::jsonb,
    lines_of_code INTEGER DEFAULT 0,
    -- Complexity columns (added via migration 005)
    complexity_simple FLOAT,
    complexity_mccabe FLOAT,
    complexity_cognitive FLOAT,
    -- Legacy cyclomatic complexity (superseded by complexity_* columns)
    cyclomatic_complexity FLOAT,
    public_methods JSONB DEFAULT '[]'::jsonb,
    first_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    derived_from TEXT,
    sync_status VARCHAR(50) DEFAULT 'unknown',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_components_repo_id ON reusable_components(repo_id);
CREATE INDEX IF NOT EXISTS idx_components_name ON reusable_components(name);
CREATE INDEX IF NOT EXISTS idx_components_component_id ON reusable_components(component_id);
CREATE INDEX IF NOT EXISTS idx_components_type ON reusable_components(component_type);
CREATE INDEX IF NOT EXISTS idx_components_language ON reusable_components(language);
CREATE INDEX IF NOT EXISTS idx_components_simple ON reusable_components(complexity_simple);
CREATE INDEX IF NOT EXISTS idx_components_mccabe ON reusable_components(complexity_mccabe);
CREATE INDEX IF NOT EXISTS idx_components_cognitive ON reusable_components(complexity_cognitive);

-- ── patterns ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS patterns (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    name VARCHAR(500) NOT NULL,
    description TEXT,
    context TEXT,
    embedding vector(1536),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(repo_id, name)
);

CREATE INDEX IF NOT EXISTS idx_patterns_repo_id ON patterns(repo_id);
CREATE INDEX IF NOT EXISTS idx_patterns_name ON patterns(name);

-- ── technical_decisions ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS technical_decisions (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    what TEXT NOT NULL,
    why TEXT,
    alternatives TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_decisions_repo_id ON technical_decisions(repo_id);

-- ── keywords ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS keywords (
    id SERIAL PRIMARY KEY,
    keyword VARCHAR(200) UNIQUE NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_keywords_keyword ON keywords(keyword);

CREATE TABLE IF NOT EXISTS pattern_keywords (
    pattern_id INTEGER REFERENCES patterns(id) ON DELETE CASCADE,
    keyword_id INTEGER REFERENCES keywords(id) ON DELETE CASCADE,
    PRIMARY KEY (pattern_id, keyword_id)
);

-- ── dependencies ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dependencies (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    dependency_name VARCHAR(500) NOT NULL,
    dependency_version VARCHAR(100),
    dependency_type VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dependencies_repo_id ON dependencies(repo_id);
CREATE INDEX IF NOT EXISTS idx_dependencies_name ON dependencies(dependency_name);

-- ── repository_relationships ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS repository_relationships (
    id SERIAL PRIMARY KEY,
    source_repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    target_repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    relationship_type VARCHAR(50) NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(source_repo_id, target_repo_id, relationship_type)
);

CREATE INDEX IF NOT EXISTS idx_repo_relationships_source ON repository_relationships(source_repo_id);
CREATE INDEX IF NOT EXISTS idx_repo_relationships_target ON repository_relationships(target_repo_id);

-- ── deployment_scripts ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS deployment_scripts (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    name VARCHAR(500) NOT NULL,
    description TEXT,
    commands JSONB,
    environment_variables JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(repo_id, name)
);

CREATE INDEX IF NOT EXISTS idx_deployment_scripts_repo_id ON deployment_scripts(repo_id);

-- ── lessons_learned ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS lessons_learned (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    title VARCHAR(500) NOT NULL,
    description TEXT,
    category VARCHAR(100),
    impact VARCHAR(50),
    date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lessons_repo_id ON lessons_learned(repo_id);
CREATE INDEX IF NOT EXISTS idx_lessons_category ON lessons_learned(category);
CREATE INDEX IF NOT EXISTS idx_lessons_date ON lessons_learned(date);

-- ── analysis_history ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS analysis_history (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    scan_type VARCHAR(50) DEFAULT 'pattern',
    commit_sha VARCHAR(40),
    analyzed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    patterns_count INTEGER DEFAULT 0,
    decisions_count INTEGER DEFAULT 0,
    components_count INTEGER DEFAULT 0,
    vectors_generated INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_history_repo_id ON analysis_history(repo_id);
CREATE INDEX IF NOT EXISTS idx_history_analyzed_at ON analysis_history(analyzed_at);
CREATE INDEX IF NOT EXISTS idx_history_commit_sha ON analysis_history(commit_sha);
CREATE INDEX IF NOT EXISTS idx_history_scan_type ON analysis_history(scan_type);

-- ── test_frameworks ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS test_frameworks (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    framework_name VARCHAR(200) NOT NULL,
    coverage_percentage DECIMAL(5,2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_test_frameworks_repo_id ON test_frameworks(repo_id);

-- ── security_patterns ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS security_patterns (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    pattern_name VARCHAR(500) NOT NULL,
    description TEXT,
    authentication_method VARCHAR(200),
    compliance_standard VARCHAR(200),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_security_patterns_repo_id ON security_patterns(repo_id);

-- ── runtime_issues ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS runtime_issues (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    issue_id VARCHAR(100) UNIQUE NOT NULL,
    detected_at TIMESTAMP WITH TIME ZONE NOT NULL,
    issue_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    service_type VARCHAR(50) NOT NULL,
    log_snippet TEXT,
    root_cause TEXT,
    suggested_fix TEXT,
    pattern_reference VARCHAR(500),
    github_issue_url VARCHAR(500),
    status VARCHAR(50) DEFAULT 'open',
    metrics JSONB,
    resolution_time TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_runtime_issues_repo_id ON runtime_issues(repo_id);
CREATE INDEX IF NOT EXISTS idx_runtime_issues_detected_at ON runtime_issues(detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_runtime_issues_issue_type ON runtime_issues(issue_type);
CREATE INDEX IF NOT EXISTS idx_runtime_issues_severity ON runtime_issues(severity);
CREATE INDEX IF NOT EXISTS idx_runtime_issues_repo_detected ON runtime_issues(repo_id, detected_at DESC);

-- ── repository_complexity_history (added via migration 006) ─────────────────────
CREATE TABLE IF NOT EXISTS repository_complexity_history (
    id SERIAL PRIMARY KEY,
    repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    grade VARCHAR(1),
    component_count INTEGER,
    simple_average NUMERIC(10,2),
    simple_median NUMERIC(10,2),
    simple_max NUMERIC(10,2),
    simple_total NUMERIC(12,2),
    simple_weighted_avg NUMERIC(10,2),
    mccabe_average NUMERIC(10,2),
    mccabe_median NUMERIC(10,2),
    mccabe_max NUMERIC(10,2),
    mccabe_total NUMERIC(12,2),
    mccabe_weighted_avg NUMERIC(10,2),
    cognitive_average NUMERIC(10,2),
    cognitive_median NUMERIC(10,2),
    cognitive_max NUMERIC(10,2),
    cognitive_total NUMERIC(12,2),
    cognitive_weighted_avg NUMERIC(10,2),
    distribution_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_repo_complexity_history_repo_id ON repository_complexity_history(repository_id);
CREATE INDEX IF NOT EXISTS idx_repo_complexity_history_timestamp ON repository_complexity_history(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_repo_complexity_history_repo_time ON repository_complexity_history(repository_id, timestamp DESC);

-- ── component_complexity_history (added via migration 006) ──────────────────────
CREATE TABLE IF NOT EXISTS component_complexity_history (
    id SERIAL PRIMARY KEY,
    component_id INTEGER NOT NULL REFERENCES reusable_components(id) ON DELETE CASCADE,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    complexity_simple NUMERIC(10,2),
    complexity_mccabe NUMERIC(10,2),
    complexity_cognitive NUMERIC(10,2),
    lines_of_code INTEGER,
    category_simple VARCHAR(20),
    category_mccabe VARCHAR(20),
    category_cognitive VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_comp_complexity_history_comp_id ON component_complexity_history(component_id);
CREATE INDEX IF NOT EXISTS idx_comp_complexity_history_timestamp ON component_complexity_history(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_comp_complexity_history_comp_time ON component_complexity_history(component_id, timestamp DESC);

-- ── system_settings (added via migration 007) ───────────────────────────────────
CREATE TABLE IF NOT EXISTS system_settings (
    key VARCHAR(100) PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_system_settings_key ON system_settings(key);

-- ── error_reports (added via migration 008) ───────────────────────────────────
CREATE TABLE IF NOT EXISTS error_reports (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE SET NULL,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    severity VARCHAR(20) NOT NULL DEFAULT 'error'
        CHECK (severity IN ('info', 'warning', 'error')),
    component VARCHAR(255) NOT NULL,
    action VARCHAR(255),
    error_message TEXT NOT NULL,
    stack_trace TEXT,
    state JSONB DEFAULT '{}'::jsonb,
    skill_called VARCHAR(255),
    issue_created BOOLEAN DEFAULT FALSE,
    github_issue_url VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_error_reports_timestamp ON error_reports(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_error_reports_component ON error_reports(component);
CREATE INDEX IF NOT EXISTS idx_error_reports_severity ON error_reports(severity);
CREATE INDEX IF NOT EXISTS idx_error_reports_issue_created ON error_reports(issue_created);

-- ── user_feedback (added via migration 008) ────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_feedback (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE SET NULL,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    feedback_type VARCHAR(50) NOT NULL
        CHECK (feedback_type IN ('feature_request', 'bug_report', 'ux_issue', 'general')),
    category VARCHAR(100),
    title VARCHAR(500) NOT NULL,
    content TEXT NOT NULL,
    user_session_id VARCHAR(255),
    status VARCHAR(50) DEFAULT 'new'
        CHECK (status IN ('new', 'reviewed', 'planned', 'completed')),
    github_issue_url VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_user_feedback_timestamp ON user_feedback(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_user_feedback_type ON user_feedback(feedback_type);
CREATE INDEX IF NOT EXISTS idx_user_feedback_category ON user_feedback(category);
CREATE INDEX IF NOT EXISTS idx_user_feedback_status ON user_feedback(status);

-- ── user_settings (added via migration 014) ───────────────────────────────────
CREATE TABLE IF NOT EXISTS user_settings (
    user_id TEXT PRIMARY KEY,
    preferences JSONB NOT NULL DEFAULT '{}',
    integrations JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_settings_user_id ON user_settings(user_id);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_user_settings_updated_at ON user_settings;
CREATE TRIGGER trigger_user_settings_updated_at
    BEFORE UPDATE ON user_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ── external_skills (added via migration 013) ─────────────────────────────────
CREATE TABLE IF NOT EXISTS external_skills (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    skill_id VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100),
    repository_url VARCHAR(500),
    repository_name VARCHAR(255),
    capabilities TEXT[] DEFAULT '{}',
    input_schema JSONB,
    output_schema JSONB,
    version VARCHAR(50),
    utility_score FLOAT DEFAULT 0.5,
    utility_rationale TEXT,
    last_updated TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_external_skills_capabilities ON external_skills USING GIN (capabilities);
CREATE INDEX IF NOT EXISTS idx_external_skills_category ON external_skills (category);
CREATE INDEX IF NOT EXISTS idx_external_skills_repository_name ON external_skills (repository_name);
CREATE INDEX IF NOT EXISTS idx_external_skills_is_active ON external_skills (is_active);

-- ── action_audit_log ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS action_audit_log (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE SET NULL,
    skill_id VARCHAR(255),
    status VARCHAR(50) DEFAULT 'started'
        CHECK (status IN ('started', 'success', 'failed', 'rolled_back')),
    input_params JSONB,
    output_data JSONB,
    files_created TEXT[],
    pr_url VARCHAR(500),
    error_message TEXT,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    duration_ms INTEGER
);

-- Full-text search indexes
CREATE INDEX IF NOT EXISTS idx_patterns_description_fts ON patterns USING gin(to_tsvector('english', description));
CREATE INDEX IF NOT EXISTS idx_patterns_context_fts ON patterns USING gin(to_tsvector('english', context));
CREATE INDEX IF NOT EXISTS idx_lessons_description_fts ON lessons_learned USING gin(to_tsvector('english', description));

-- Grant privileges
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO devnexus;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO devnexus;