#!/bin/bash
# PostgreSQL Installation and Configuration Script with pgvector
# Runs on GCP Compute Engine e2-micro (Ubuntu 22.04)
# Uses persistent disk for data preservation across VM recreations

set -e  # Exit on error
set -x  # Print commands

# ============================================
# Environment Variables (from Terraform)
# ============================================
DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
BACKUP_BUCKET="${backup_bucket}"
POSTGRES_VERSION="${postgres_version}"
ENABLE_MONITORING="${enable_monitoring}"
DATA_DISK_DEVICE="${data_disk_device}"
PG_DATA_DIR="/var/lib/postgresql/data"
PG_MOUNT_POINT="/mnt/postgres-data"

# ============================================
# System Updates and Dependencies
# ============================================
echo "===== Updating system packages ====="
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    curl \
    git \
    build-essential \
    postgresql-common

# ============================================
# Mount Persistent Data Disk
# ============================================
echo "===== Setting up persistent data disk ====="

# Check if disk is attached
if [ ! -b "/dev/$DATA_DISK_DEVICE" ]; then
    echo "Error: Data disk /dev/$DATA_DISK_DEVICE not found!"
    exit 1
fi

# Create mount point
mkdir -p $PG_MOUNT_POINT

# Check if disk is already formatted
if ! sudo blkid "/dev/$DATA_DISK_DEVICE" > /dev/null 2>&1; then
    echo "===== Formatting new disk ====="

    # Format disk as ext4
    mkfs.ext4 -F "/dev/$DATA_DISK_DEVICE"

    # Add to fstab for automatic mounting on reboot
    echo "/dev/$DATA_DISK_DEVICE $PG_MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
else
    echo "===== Disk already formatted, reusing existing data ====="

    # Add to fstab if not already present
    if ! grep -q "/dev/$DATA_DISK_DEVICE" /etc/fstab; then
        echo "/dev/$DATA_DISK_DEVICE $PG_MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
    fi
fi

# Mount the disk
mount "$PG_MOUNT_POINT" || true  # Ignore if already mounted

# Verify mount
df -h | grep "$PG_MOUNT_POINT"

# ============================================
# Install PostgreSQL
# ============================================
echo "===== Installing PostgreSQL $POSTGRES_VERSION ====="

# Add PostgreSQL APT repository
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

# Update and install PostgreSQL
apt-get update
apt-get install -y \
    postgresql-$POSTGRES_VERSION \
    postgresql-contrib-$POSTGRES_VERSION \
    postgresql-server-dev-$POSTGRES_VERSION

# ============================================
# Install pgvector Extension for Vector Embeddings
# ============================================
echo "===== Installing pgvector extension ====="

# Clone and build pgvector
cd /tmp
git clone --branch v0.6.0 https://github.com/pgvector/pgvector.git
cd pgvector

# Build and install
make
make install

# Clean up
cd /
rm -rf /tmp/pgvector

# ============================================
# Move PostgreSQL Data Directory to Persistent Disk
# ============================================
echo "===== Configuring PostgreSQL data directory ====="

# Check if this is first-time setup (no existing data on persistent disk)
if [ ! -d "$PG_MOUNT_POINT/postgresql/$POSTGRES_VERSION/main" ]; then
    echo "===== First-time setup: initializing cluster on persistent disk ====="

    # Stop PostgreSQL if running
    systemctl stop postgresql || true

    # Create directories on persistent disk
    mkdir -p "$PG_MOUNT_POINT/postgresql/$POSTGRES_VERSION/main"
    mkdir -p "$PG_MOUNT_POINT/postgresql/$POSTGRES_VERSION/backups"

    # Set proper ownership and permissions
    chown -R postgres:postgres "$PG_MOUNT_POINT"
    chmod 700 "$PG_MOUNT_POINT/postgresql/$POSTGRES_VERSION/main"

    # Move default data directory
    if [ -d "/var/lib/postgresql/$POSTGRES_VERSION/main" ]; then
        rm -rf "/var/lib/postgresql/$POSTGRES_VERSION/main"
    fi

    mkdir -p "/var/lib/postgresql/$POSTGRES_VERSION"

    # Create symlink to persistent disk
    ln -s "$PG_MOUNT_POINT/postgresql/$POSTGRES_VERSION/main" "/var/lib/postgresql/$POSTGRES_VERSION/main"

    # Initialize cluster
    sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/initdb -D "/var/lib/postgresql/$POSTGRES_VERSION/main"
else
    echo "===== Reusing existing PostgreSQL data directory ====="

    # Stop PostgreSQL if running
    systemctl stop postgresql || true

    # Create symlink if it doesn't exist
    if [ ! -L "/var/lib/postgresql/$POSTGRES_VERSION/main" ]; then
        if [ -d "/var/lib/postgresql/$POSTGRES_VERSION/main" ]; then
            # Move existing to persistent disk if present
            mkdir -p "$PG_MOUNT_POINT/postgresql/$POSTGRES_VERSION"
            mv "/var/lib/postgresql/$POSTGRES_VERSION/main" "$PG_MOUNT_POINT/postgresql/$POSTGRES_VERSION/main" || true
        fi

        mkdir -p "/var/lib/postgresql/$POSTGRES_VERSION"
        ln -s "$PG_MOUNT_POINT/postgresql/$POSTGRES_VERSION/main" "/var/lib/postgresql/$POSTGRES_VERSION/main"
    fi

    # Ensure permissions
    chown -R postgres:postgres "$PG_MOUNT_POINT"
    chmod 700 "$PG_MOUNT_POINT/postgresql/$POSTGRES_VERSION/main"
fi

# ============================================
# Configure PostgreSQL
# ============================================
echo "===== Configuring PostgreSQL ====="

# Configure postgresql.conf for remote connections
PG_CONF="/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"

# Backup original configs if they exist
if [ -f "$PG_CONF" ]; then
    cp "$PG_CONF" "$PG_CONF.backup" || true
fi
if [ -f "$PG_HBA" ]; then
    cp "$PG_HBA" "$PG_HBA.backup" || true
fi

# Update postgresql.conf
cat >> "$PG_CONF" <<EOF

# ====================================
# Dev Nexus Custom Configuration
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

# Logging
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 1000
log_line_prefix = '%m [%p] %u@%d '
log_timezone = 'UTC'

# Autovacuum (important for maintaining vector indices)
autovacuum = on
autovacuum_max_workers = 2
autovacuum_naptime = 30s

# Locale
datestyle = 'iso, mdy'
timezone = 'UTC'
lc_messages = 'en_US.UTF-8'
lc_monetary = 'en_US.UTF-8'
lc_numeric = 'en_US.UTF-8'
lc_time = 'en_US.UTF-8'
default_text_search_config = 'pg_catalog.english'

# Vector Extension Settings
shared_preload_libraries = 'pg_stat_statements'
EOF

# Update pg_hba.conf for Cloud Run access
cat > "$PG_HBA" <<EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             postgres                                peer
local   all             all                                     peer

# IPv4 local connections:
host    all             all             127.0.0.1/32            scram-sha-256

# Cloud Run VPC connections (via VPC connector)
host    $DB_NAME        $DB_USER        10.0.0.0/8              scram-sha-256

# Allow connections from VPC
host    all             all             10.8.0.0/28             scram-sha-256
EOF

# Set proper permissions
chmod 600 "$PG_HBA"
chown postgres:postgres "$PG_HBA"

# Start PostgreSQL
echo "===== Starting PostgreSQL ====="
systemctl start postgresql
systemctl enable postgresql

# Wait for PostgreSQL to be ready
sleep 10

# ============================================
# Create Database and User (if not exists)
# ============================================
echo "===== Setting up database and user ====="

# Check if database already exists
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "^$DB_NAME"; then
    echo "===== Database '$DB_NAME' already exists - skipping creation ====="
else
    echo "===== Creating new database and user ====="

    # Create user and database as postgres user
    sudo -u postgres psql <<EOF
-- Create database user
CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';

-- Create database
CREATE DATABASE $DB_NAME OWNER $DB_USER;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;

-- Connect to database and create extensions
\c $DB_NAME

-- Enable pgvector extension for vector embeddings
CREATE EXTENSION IF NOT EXISTS vector;

-- Enable other useful extensions
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- For text similarity
CREATE EXTENSION IF NOT EXISTS btree_gin;  -- For better indexing

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;

-- Verify pgvector installation
SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';
EOF
fi

# ============================================
# Initialize Schema (create if not exists)
# ============================================
echo "===== Initializing database schema ====="

sudo -u postgres psql -d $DB_NAME <<'SCHEMA_EOF'
-- ====================================
-- Dev Nexus Database Schema v1.0
-- With pgvector support for embeddings
-- ====================================

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
CREATE INDEX IF NOT EXISTS idx_patterns_embedding ON patterns USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

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

-- Reusable components table
CREATE TABLE IF NOT EXISTS reusable_components (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    name VARCHAR(500) NOT NULL,
    purpose TEXT,
    location TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_components_repo_id ON reusable_components(repo_id);
CREATE INDEX IF NOT EXISTS idx_components_name ON reusable_components(name);

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
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
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
CREATE TABLE IF NOT EXISTS analysis_history (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    commit_sha VARCHAR(40),
    analyzed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    patterns_count INTEGER DEFAULT 0,
    decisions_count INTEGER DEFAULT 0,
    components_count INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_history_repo_id ON analysis_history(repo_id);
CREATE INDEX IF NOT EXISTS idx_history_analyzed_at ON analysis_history(analyzed_at);
CREATE INDEX IF NOT EXISTS idx_history_commit_sha ON analysis_history(commit_sha);

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

-- Full-text search configuration
CREATE INDEX IF NOT EXISTS idx_patterns_description_fts ON patterns USING gin(to_tsvector('english', description));
CREATE INDEX IF NOT EXISTS idx_patterns_context_fts ON patterns USING gin(to_tsvector('english', context));
CREATE INDEX IF NOT EXISTS idx_lessons_description_fts ON lessons_learned USING gin(to_tsvector('english', description));

-- Views for common queries
CREATE OR REPLACE VIEW pattern_similarity_view AS
SELECT
    p1.id as pattern1_id,
    p1.name as pattern1_name,
    p1.repo_id as repo1_id,
    p2.id as pattern2_id,
    p2.name as pattern2_name,
    p2.repo_id as repo2_id,
    1 - (p1.embedding <=> p2.embedding) as similarity_score
FROM patterns p1
CROSS JOIN patterns p2
WHERE p1.id < p2.id
  AND p1.embedding IS NOT NULL
  AND p2.embedding IS NOT NULL
  AND 1 - (p1.embedding <=> p2.embedding) > 0.8;

-- Grant privileges to application user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${db_user};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${db_user};

SCHEMA_EOF

echo "===== Schema initialization complete ====="

# ============================================
# Set Up Automated Backups
# ============================================
echo "===== Setting up automated backups ====="

# Create backup script
mkdir -p "$PG_MOUNT_POINT/postgresql/$POSTGRES_VERSION/backups"

cat > /usr/local/bin/backup-postgres.sh <<'BACKUP_EOF'
#!/bin/bash
# PostgreSQL Backup Script
# Uploads to Cloud Storage

set -e

DB_NAME="${db_name}"
BACKUP_DIR="/mnt/postgres-data/postgresql/${postgres_version}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/dev-nexus-$TIMESTAMP.sql.gz"
BUCKET="${backup_bucket}"

# Create backup directory
mkdir -p $BACKUP_DIR

# Create compressed backup
sudo -u postgres pg_dump $DB_NAME | gzip > $BACKUP_FILE

# Upload to Cloud Storage
gsutil cp $BACKUP_FILE gs://$BUCKET/

# Keep only last 7 days of backups
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
echo "Uploaded to: gs://$BUCKET/"
BACKUP_EOF

chmod +x /usr/local/bin/backup-postgres.sh

# Set up daily backup cron job (2 AM UTC)
cat > /etc/cron.d/postgres-backup <<EOF
0 2 * * * root /usr/local/bin/backup-postgres.sh >> /var/log/postgres-backup.log 2>&1
EOF

# Create initial backup
/usr/local/bin/backup-postgres.sh || echo "Initial backup skipped (data may be empty)"

echo "===== Backup setup complete ====="

# ============================================
# Install Monitoring Tools (if enabled)
# ============================================
if [ "$ENABLE_MONITORING" = "true" ]; then
    echo "===== Installing monitoring tools ====="

    # Install pg_stat_statements
    sudo -u postgres psql -d $DB_NAME <<EOF
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EOF

    # Install Cloud Monitoring agent
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh || true
    bash add-google-cloud-ops-agent-repo.sh --also-install || true

    echo "===== Monitoring setup complete ====="
fi

# ============================================
# Verify Installation
# ============================================
echo "===== Verifying PostgreSQL installation ====="

sudo -u postgres psql -d $DB_NAME <<EOF
-- Check PostgreSQL version
SELECT version();

-- Check pgvector extension
SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';

-- Check tables
SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema = 'public';

-- Test vector operations
SELECT vector_dims(ARRAY[1,2,3]::vector);

EOF

# ============================================
# Final Status
# ============================================
echo "======================================"
echo "PostgreSQL Setup Complete!"
echo "======================================"
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo "PostgreSQL Version: $POSTGRES_VERSION"
echo "Data Directory: $PG_MOUNT_POINT/postgresql/$POSTGRES_VERSION/main"
echo "pgvector: Installed and enabled"
echo "Backup location: gs://$BACKUP_BUCKET"
echo "======================================"

# Print connection info
INTERNAL_IP=$(hostname -I | awk '{print $1}')
echo "Internal IP: $INTERNAL_IP"
echo "Connection string: postgresql://$DB_USER:****@$INTERNAL_IP:5432/$DB_NAME"
