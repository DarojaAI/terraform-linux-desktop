#!/bin/bash
# PostgreSQL Installation Script - MINIMAL VERSION
# Focus: Get PostgreSQL 15 installed and running reliably
# Runs on GCP Compute Engine e2-micro (Ubuntu 22.04)

LOG_FILE="/var/log/postgres-setup.log"

# Log everything
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "========================================="
echo "PostgreSQL Setup Starting"
echo "========================================="
echo "Timestamp: $(date)"
echo "User: $(whoami)"
echo "PWD: $(pwd)"
echo ""

# Environment Variables (from Terraform)
DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
POSTGRES_VERSION="${postgres_version}"
DATA_DISK_DEVICE="${data_disk_device}"

echo "Configuration:"
echo "  DB_NAME: $DB_NAME"
echo "  DB_USER: $DB_USER"
echo "  POSTGRES_VERSION: $POSTGRES_VERSION"
echo "  DATA_DISK_DEVICE: /dev/$DATA_DISK_DEVICE"
echo ""

# ============================================
# Step 1: System Updates
# ============================================
echo "===== Step 1: System Updates ====="
apt-get update || echo "WARNING: apt-get update had issues"
apt-get upgrade -y || echo "WARNING: apt-get upgrade had issues"

# Install dependencies (don't fail if some are missing)
echo "Installing dependencies..."
apt-get install -y wget ca-certificates gnupg lsb-release curl || true

# ============================================
# Step 2: Mount Persistent Data Disk
# ============================================
echo ""
echo "===== Step 2: Mount Persistent Data Disk ====="

DISK_PATH="/dev/$DATA_DISK_DEVICE"
MOUNT_POINT="/mnt/postgres-data"

echo "Checking for disk: $DISK_PATH"

# Retry logic: disk might not be immediately available during startup
RETRY_COUNT=0
MAX_RETRIES=30
RETRY_DELAY=2

while [ ! -b "$DISK_PATH" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Disk $DISK_PATH not found yet (attempt $((RETRY_COUNT+1))/$MAX_RETRIES). Waiting ${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
    RETRY_COUNT=$((RETRY_COUNT+1))
done

if [ ! -b "$DISK_PATH" ]; then
    echo "ERROR: Disk $DISK_PATH not found after $MAX_RETRIES retries - PostgreSQL data will be on boot disk (data loss on VM recreation!)"
else
    echo "Disk found after $RETRY_COUNT retries"
    echo "Disk found, proceeding with mount..."

    mkdir -p "$MOUNT_POINT"

    # Check if disk is already formatted
    if blkid "$DISK_PATH" > /dev/null 2>&1; then
        echo "Disk already formatted, mounting..."
    else
        echo "Formatting disk as ext4..."
        mkfs.ext4 -F "$DISK_PATH" || echo "WARNING: mkfs.ext4 failed"
    fi

    # Mount the disk
    mount "$MOUNT_POINT" 2>/dev/null || echo "WARNING: mount may have failed (might already be mounted)"

    # Add to fstab for persistent mounting across reboots
    if ! grep -q "$DISK_PATH" /etc/fstab; then
        echo "Adding disk to fstab for persistent mounting..."
        echo "$DISK_PATH $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
    fi

    # Verify mount
    if mountpoint -q "$MOUNT_POINT"; then
        echo "Disk successfully mounted to $MOUNT_POINT"
        df -h "$MOUNT_POINT"
    else
        echo "WARNING: Disk mount verification failed"
    fi
fi

# ============================================
# Step 3: Install PostgreSQL
# ============================================
echo ""
echo "===== Step 3: Install PostgreSQL $POSTGRES_VERSION ====="

# Add PostgreSQL repository
echo "Adding PostgreSQL repository..."
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' || echo "WARNING: Failed to add repo"

wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - 2>/dev/null || echo "WARNING: Failed to add GPG key"

# Update and install PostgreSQL
echo "Updating package list..."
apt-get update || echo "WARNING: apt-get update after repo add had issues"

echo "Installing PostgreSQL $POSTGRES_VERSION..."
apt-get install -y postgresql-$POSTGRES_VERSION postgresql-contrib-$POSTGRES_VERSION 2>&1 || {
    echo "ERROR: PostgreSQL installation failed"
    exit 1
}

# Verify PostgreSQL is installed
if ! command -v psql &> /dev/null; then
    echo "ERROR: psql not found after installation"
    exit 1
fi

echo "PostgreSQL installed successfully"
psql --version

# ============================================
# Step 3b: Install pgvector Extension
# ============================================
echo ""
echo "===== Installing pgvector extension ====="

# Install postgresql-contrib first (has pgvector for PostgreSQL 15+)
apt-get update -qq > /dev/null 2>&1 || true
apt-get install -y postgresql-$POSTGRES_VERSION-contrib > /dev/null 2>&1 || echo "WARNING: Could not install postgresql-contrib"

# Restart PostgreSQL to load any new extensions
systemctl restart postgresql || true
sleep 2

# Try to create the extension
PGVECTOR_CREATE_OUTPUT=$(sudo -u postgres psql -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>&1)
PGVECTOR_EXIT_CODE=$?

if [ $PGVECTOR_EXIT_CODE -eq 0 ]; then
    echo "✓ pgvector extension created successfully"
else
    echo "WARNING: pgvector extension creation failed: $PGVECTOR_CREATE_OUTPUT"
    echo "Attempting to build pgvector from source..."

    # Install build dependencies
    apt-get install -y build-essential postgresql-server-dev-$POSTGRES_VERSION > /dev/null 2>&1 || echo "WARNING: Could not install build tools"

    # Build from source
    mkdir -p /tmp/pgvector
    cd /tmp/pgvector
    if curl -sL https://github.com/pgvector/pgvector/archive/v0.5.0.tar.gz | tar xz; then
        cd pgvector-0.5.0
        if make && sudo make install; then
            echo "✓ pgvector built and installed from source"
            # Reload PostgreSQL
            systemctl restart postgresql || true
            sleep 2
            # Try creating extension again
            sudo -u postgres psql -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;" || echo "WARNING: pgvector extension still failed after source build"
        else
            echo "ERROR: pgvector source build failed"
        fi
        cd /
        rm -rf /tmp/pgvector
    else
        echo "ERROR: Failed to download pgvector source"
    fi
fi

# Verify pgvector is available
PGVECTOR_CHECK=$(sudo -u postgres psql -d postgres -c "SELECT extversion FROM pg_extension WHERE extname = 'vector';" 2>&1)
if echo "$PGVECTOR_CHECK" | grep -q '^[0-9]'; then
    echo "✓ pgvector extension verified: $PGVECTOR_CHECK"
else
    echo "WARNING: pgvector extension not found or not available: $PGVECTOR_CHECK"
fi

# ============================================
# Step 4: Configure PostgreSQL Data Directory
# ============================================
echo ""
echo "===== Step 4: Configure PostgreSQL Data Directory ====="

# Stop PostgreSQL if running
systemctl stop postgresql || true

# Check if we need to move data directory to persistent disk
if [ -d "$MOUNT_POINT" ]; then
    echo "Setting up data directory on persistent disk..."

    mkdir -p "$MOUNT_POINT/postgresql/$POSTGRES_VERSION/main"
    chown -R postgres:postgres "$MOUNT_POINT"
    chmod 700 "$MOUNT_POINT/postgresql/$POSTGRES_VERSION/main"

    # Create symlink
    PG_DATA_DIR="/var/lib/postgresql/$POSTGRES_VERSION/main"
    if [ -d "$PG_DATA_DIR" ] && [ ! -L "$PG_DATA_DIR" ]; then
        echo "Moving existing data directory..."
        rm -rf "$PG_DATA_DIR"
    fi

    if [ ! -L "$PG_DATA_DIR" ]; then
        mkdir -p "$(dirname "$PG_DATA_DIR")"
        ln -s "$MOUNT_POINT/postgresql/$POSTGRES_VERSION/main" "$PG_DATA_DIR" || echo "WARNING: symlink creation may have failed"
    fi
fi

# Initialize PostgreSQL cluster if not already initialized
if [ ! -f "/var/lib/postgresql/$POSTGRES_VERSION/main/PG_VERSION" ]; then
    echo "Initializing PostgreSQL cluster..."
    sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/initdb -D "/var/lib/postgresql/$POSTGRES_VERSION/main" || {
        echo "ERROR: PostgreSQL cluster initialization failed"
        exit 1
    }
else
    echo "PostgreSQL cluster already initialized"
fi

# ============================================
# Step 5: Configure PostgreSQL
# ============================================
echo ""
echo "===== Step 5: Configure PostgreSQL ====="

PG_CONF="/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"

# Backup original configs
[ -f "$PG_CONF" ] && cp "$PG_CONF" "$PG_CONF.backup"
[ -f "$PG_HBA" ] && cp "$PG_HBA" "$PG_HBA.backup"

# Create minimal pg_hba.conf for VPC access
echo "Configuring pg_hba.conf..."
cat > "$PG_HBA" <<'EOF'
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             10.0.0.0/8              scram-sha-256
host    all             all             10.8.0.0/28             scram-sha-256
EOF

chmod 600 "$PG_HBA"
chown postgres:postgres "$PG_HBA"

# Configure postgresql.conf for remote connections and performance
echo "Configuring postgresql.conf..."
cat >> "$PG_CONF" <<'EOF'

# ====================================
# Dev Nexus Configuration
# ====================================

# Connection Settings
listen_addresses = '*'
max_connections = 100
superuser_reserved_connections = 3

# Memory Settings (optimized for e2-micro: 1GB RAM)
shared_buffers = 256MB
effective_cache_size = 768MB
maintenance_work_mem = 64MB
work_mem = 4MB

# Write-Ahead Log
wal_buffers = 8MB
max_wal_size = 1GB
min_wal_size = 80MB
checkpoint_completion_target = 0.9

# Query Planning
random_page_cost = 1.1
effective_io_concurrency = 200

# Logging (for debugging and monitoring)
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 1000
log_line_prefix = '%m [%p] %u@%d '
log_timezone = 'UTC'

# Autovacuum (important for maintaining vector indices and performance)
autovacuum = on
autovacuum_max_workers = 2
autovacuum_naptime = 30s

# Locale and Timezone
datestyle = 'iso, mdy'
timezone = 'UTC'
lc_messages = 'en_US.UTF-8'
lc_monetary = 'en_US.UTF-8'
lc_numeric = 'en_US.UTF-8'
lc_time = 'en_US.UTF-8'
default_text_search_config = 'pg_catalog.english'

# Preload libraries for performance
shared_preload_libraries = 'pg_stat_statements'
EOF

# ============================================
# Step 6: Create Database and User
# ============================================
echo ""
echo "===== Step 6: Create Database and User ====="

# Start PostgreSQL
echo "Starting PostgreSQL..."
systemctl start postgresql || {
    echo "ERROR: Failed to start PostgreSQL"
    echo "systemctl status:"
    systemctl status postgresql || true
    exit 1
}

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
        echo "PostgreSQL is ready"
        break
    fi
    echo "Attempt $i/30: waiting for PostgreSQL..."
    sleep 2
done

# Create database and user
echo "Creating database and user..."
sudo -u postgres psql <<PSQL_EOF || echo "WARNING: Database creation may have failed"
CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
CREATE DATABASE $DB_NAME OWNER $DB_USER;
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
PSQL_EOF

# Initialize database schema
echo ""
echo "===== Initializing database schema ====="

# First, ensure pgvector extension exists in the target database
echo "Ensuring pgvector extension in target database..."
PGVECTOR_DB_OUTPUT=$(sudo -u postgres psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>&1)
PGVECTOR_DB_EXIT=$?

if [ $PGVECTOR_DB_EXIT -eq 0 ]; then
    echo "✓ pgvector extension available in target database"
else
    # Check if error is just "already exists"
    if echo "$PGVECTOR_DB_OUTPUT" | grep -q "already exists"; then
        echo "✓ pgvector extension already exists in target database"
    else
        echo "WARNING: pgvector extension may not be available: $PGVECTOR_DB_OUTPUT"
        echo "Continuing with schema creation - tables without vector type will work"
    fi
fi

# Now create the schema
SCHEMA_OUTPUT=$(sudo -u postgres psql -d $DB_NAME <<SCHEMA_EOF 2>&1
-- ====================================
-- Dev Nexus Database Schema v1.0
-- With pgvector support for embeddings
-- ====================================

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Repositories table
CREATE TABLE IF NOT EXISTS repositories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    problem_domain TEXT,
    last_analyzed TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_commit_sha VARCHAR(40),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_repositories_name ON repositories(name);
CREATE INDEX IF NOT EXISTS idx_repositories_last_analyzed ON repositories(last_analyzed);

-- Patterns table with vector embeddings
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

-- Technical decisions table
CREATE TABLE IF NOT EXISTS technical_decisions (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    what TEXT NOT NULL,
    why TEXT,
    alternatives TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_decisions_repo_id ON technical_decisions(repo_id);

-- Reusable components table (extended schema for component sensibility)
CREATE TABLE IF NOT EXISTS reusable_components (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    name VARCHAR(500) NOT NULL,
    purpose TEXT,
    location TEXT,

    -- Component metadata
    component_id TEXT UNIQUE,
    component_type VARCHAR(50) DEFAULT 'unknown',
    language VARCHAR(50) DEFAULT 'unknown',

    -- Code analysis
    api_signature TEXT,
    imports JSONB DEFAULT '[]'::jsonb,
    keywords JSONB DEFAULT '[]'::jsonb,
    lines_of_code INTEGER DEFAULT 0,
    cyclomatic_complexity FLOAT,
    public_methods JSONB DEFAULT '[]'::jsonb,

    -- Provenance tracking
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

-- Keywords table (many-to-many with patterns)
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

-- Dependencies table
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

-- Repository relationships (for consumer/derivative tracking)
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

-- Deployment information
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

-- Lessons learned
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

-- Analysis history (for tracking changes over time)
-- Extended to track both pattern analysis and component scans via scan_type field
CREATE TABLE IF NOT EXISTS analysis_history (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    scan_type VARCHAR(50) DEFAULT 'pattern',  -- 'pattern' for pattern analysis, 'component' for component scans
    commit_sha VARCHAR(40),
    analyzed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    patterns_count INTEGER DEFAULT 0,
    decisions_count INTEGER DEFAULT 0,
    components_count INTEGER DEFAULT 0,
    vectors_generated INTEGER DEFAULT 0     -- For component scans: number of vectors created
);

CREATE INDEX IF NOT EXISTS idx_history_repo_id ON analysis_history(repo_id);
CREATE INDEX IF NOT EXISTS idx_history_analyzed_at ON analysis_history(analyzed_at);
CREATE INDEX IF NOT EXISTS idx_history_commit_sha ON analysis_history(commit_sha);
CREATE INDEX IF NOT EXISTS idx_history_scan_type ON analysis_history(scan_type);  -- For filtering by scan type

-- Testing information
CREATE TABLE IF NOT EXISTS test_frameworks (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    framework_name VARCHAR(200) NOT NULL,
    coverage_percentage DECIMAL(5,2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_test_frameworks_repo_id ON test_frameworks(repo_id);

-- Security patterns
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

-- Runtime issues (production monitoring)
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

-- Full-text search configuration
CREATE INDEX IF NOT EXISTS idx_patterns_description_fts ON patterns USING gin(to_tsvector('english', description));
CREATE INDEX IF NOT EXISTS idx_patterns_context_fts ON patterns USING gin(to_tsvector('english', context));
CREATE INDEX IF NOT EXISTS idx_lessons_description_fts ON lessons_learned USING gin(to_tsvector('english', description));

-- Grant privileges to application user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
SCHEMA_EOF
)

SCHEMA_EXIT_CODE=$?

if [ $SCHEMA_EXIT_CODE -eq 0 ]; then
    echo "✓ Schema initialization complete"
else
    echo "ERROR: Schema initialization failed with exit code $SCHEMA_EXIT_CODE"
    echo "Schema output:"
    echo "$SCHEMA_OUTPUT"
    echo ""

    # Check if the error is pgvector-related
    if echo "$SCHEMA_OUTPUT" | grep -q "type.*vector.*does not exist\|unknown type.*vector"; then
        echo "ERROR: pgvector extension is not available!"
        echo ""
        echo "This error occurred when trying to create the patterns table with vector(1536) type."
        echo "Cause: pgvector extension was not successfully installed on the system."
        echo ""
        echo "The startup script attempted to install/build pgvector, but it failed."
        echo ""
        echo "Troubleshooting steps:"
        echo "1. SSH into the PostgreSQL VM and check startup logs:"
        echo "   sudo tail -200 /var/log/postgres-setup.log | grep -A5 -B5 pgvector"
        echo ""
        echo "2. Verify PostgreSQL is running:"
        echo "   sudo systemctl status postgresql"
        echo ""
        echo "3. Check if pgvector can be created manually:"
        echo "   sudo -u postgres psql -d postgres -c \"CREATE EXTENSION vector;\""
        echo ""
        echo "4. Check PostgreSQL system logs:"
        echo "   sudo tail -100 /var/log/postgresql/postgresql-15-main.log"
        echo ""
        echo "5. If pgvector is not installed, you may need to:"
        echo "   - Install postgresql-contrib: sudo apt-get install postgresql-15-contrib"
        echo "   - Or manually build pgvector from source"
        exit 1
    else
        echo "This appears to be a different schema creation error."
        echo "Check the output above for details."
        exit 1
    fi
fi

# Enable PostgreSQL to start on boot
systemctl enable postgresql

echo ""
echo "========================================="
echo "PostgreSQL Setup Completed"
echo "========================================="
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo "Version: $POSTGRES_VERSION"
echo "Timestamp: $(date)"
echo "Log file: $LOG_FILE"
echo ""
echo "To verify:"
echo "  psql -U postgres -d $DB_NAME -c 'SELECT version();'"
echo "========================================="
