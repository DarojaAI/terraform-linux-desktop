#!/bin/bash
# PostgreSQL Installation Script - MINIMAL VERSION
# Focus: Get PostgreSQL 15 installed and running reliably
# Runs on GCP Compute Engine e2-micro (Ubuntu 22.04)

set -e
set -x

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
BACKUP_BUCKET="${backup_bucket}"

echo "Configuration:"
echo "  DB_NAME: $DB_NAME"
echo "  DB_USER: $DB_USER"
echo "  POSTGRES_VERSION: $POSTGRES_VERSION"
echo "  DATA_DISK_DEVICE: /dev/$DATA_DISK_DEVICE"
echo "  BACKUP_BUCKET: $BACKUP_BUCKET"
echo ""

# Validate required variables
if [ -z "$DB_PASSWORD" ]; then
    echo "ERROR: DB_PASSWORD is empty! This will cause authentication failures."
    echo "Please ensure TF_VAR_postgres_db_password is set in terraform-apply.yml"
    exit 1
fi

echo "Password validation: OK (length: $${#DB_PASSWORD})"

# ============================================
# Step 0: Disable Firewall
# ============================================
echo "===== Step 0: Disable Firewall ====="
ufw disable || echo "ufw not found, skipping."


# ============================================
# Step 1: System Updates
# ============================================
echo "===== Step 1: System Updates ====="
apt-get update
apt-get upgrade -y

# Install dependencies (don't fail if some are missing)
echo "Installing dependencies..."
apt-get install -y wget ca-certificates gnupg lsb-release curl

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
    echo "Disk $DISK_PATH not found yet (attempt $(expr $RETRY_COUNT + 1)/$MAX_RETRIES). Waiting $${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
    RETRY_COUNT=$(expr $RETRY_COUNT + 1)
done

if [ ! -b "$DISK_PATH" ]; then
    echo "ERROR: Disk $DISK_PATH not found after $MAX_RETRIES retries - PostgreSQL data will be on boot disk (data loss on VM recreation!)"
else
    echo "Disk found after $RETRY_COUNT retries"
    echo "Disk found, proceeding with mount..."

    mkdir -p "$MOUNT_POINT"

    # Check if disk is already formatted
    if blkid "$DISK_PATH" > /dev/null 2>&1; then
        echo "Disk already formatted, getting UUID..."
        DISK_UUID=$(blkid -s UUID -o value "$DISK_PATH")
    else
        echo "Formatting disk as ext4..."
        mkfs.ext4 -F "$DISK_PATH"
        DISK_UUID=$(blkid -s UUID -o value "$DISK_PATH")
    fi

    echo "Disk UUID: $DISK_UUID"

    # Add to fstab using UUID (more reliable than device name)
    if ! grep -q "$DISK_UUID" /etc/fstab; then
        echo "Adding disk to fstab for persistent mounting (using UUID)..."
        echo "UUID=$DISK_UUID $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
    fi

    # Mount the disk (using UUID in fstab, but mount by path first)
    mount "$MOUNT_POINT" || mount "$DISK_PATH" "$MOUNT_POINT"

    # Verify mount
    if mountpoint -q "$MOUNT_POINT"; then
        echo "Disk successfully mounted to $MOUNT_POINT"
        df -h "$MOUNT_POINT"
    else
        echo "ERROR: Disk mount verification failed"
        # Try one more time with explicit options
        mount -o defaults,nofail "$DISK_PATH" "$MOUNT_POINT" || true
        if mountpoint -q "$MOUNT_POINT"; then
            echo "Disk successfully mounted on retry"
            df -h "$MOUNT_POINT"
        else
            echo "ERROR: Disk mount failed after retry - continuing anyway, PostgreSQL may use boot disk"
        fi
    fi
fi

# ============================================
# Step 3: Install PostgreSQL
# ============================================
echo ""
echo "===== Step 3: Install PostgreSQL $POSTGRES_VERSION ====="

# Try Ubuntu's default repos first (no external network needed)
echo "Trying Ubuntu default repos..."
apt-get update
apt-get install -y postgresql-$POSTGRES_VERSION postgresql-contrib-$POSTGRES_VERSION || POSTGRES_FROM_UBUNTU=false

# If not found, try PostgreSQL official repo
if [ "$POSTGRES_FROM_UBUNTU" = "false" ]; then
    echo "Ubuntu repos don't have PostgreSQL $POSTGRES_VERSION, trying PostgreSQL official repo..."
    # Add PostgreSQL repository
    sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

    # Update and install PostgreSQL
    echo "Updating package list..."
    apt-get update

    echo "Installing PostgreSQL $POSTGRES_VERSION..."
    apt-get install -y postgresql-$POSTGRES_VERSION postgresql-contrib-$POSTGRES_VERSION
fi

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

# For PostgreSQL 15 on Ubuntu 22.04, pgvector is in its own package
apt-get update
apt-get install -y "postgresql-$POSTGRES_VERSION-pgvector"

# Restart PostgreSQL to be safe
systemctl restart postgresql
sleep 2

# Verify pgvector is available by creating the extension
PGVECTOR_CREATE_OUTPUT=$(sudo -u postgres psql -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>&1)
PGVECTOR_EXIT_CODE=$?

if [ $PGVECTOR_EXIT_CODE -eq 0 ]; then
    echo "✓ pgvector extension created successfully"
else
    echo "ERROR: pgvector extension creation failed: $PGVECTOR_CREATE_OUTPUT"
    # Even though we installed the package, it might have failed.
    # The log from the command above should give a clue.
    exit 1
fi

# Verify pgvector is available
PGVECTOR_CHECK=$(sudo -u postgres psql -d postgres -c "SELECT extversion FROM pg_extension WHERE extname = 'vector';" 2>&1)
# Check if output contains a version number (0.x.x format) - ignore header lines
if echo "$PGVECTOR_CHECK" | grep -qE '[0-9]+\.[0-9]+'; then
    PGVECTOR_VERSION=$(echo "$PGVECTOR_CHECK" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    echo "✓ pgvector extension verified: v$PGVECTOR_VERSION"
else
    echo "ERROR: pgvector extension not found or not available: $PGVECTOR_CHECK"
    exit 1
fi

# ============================================
# Step 4: Configure PostgreSQL Data Directory
# ============================================
echo ""
echo "===== Step 4: Configure PostgreSQL Data Directory ====="

# Stop PostgreSQL if running
systemctl stop postgresql

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
        ln -s "$MOUNT_POINT/postgresql/$POSTGRES_VERSION/main" "$PG_DATA_DIR"
    fi
fi

# Initialize PostgreSQL cluster if not already initialized
if [ ! -f "/var/lib/postgresql/$POSTGRES_VERSION/main/PG_VERSION" ]; then
    echo "Initializing PostgreSQL cluster..."
    sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/initdb -D "/var/lib/postgresql/$POSTGRES_VERSION/main"
else
    echo "PostgreSQL cluster already initialized"
fi

# ============================================
# Step 5: Configure PostgreSQL
# ============================================
echo ""
echo "===== Step 5: Configure PostgreSQL ====="

# Detect actual PostgreSQL version installed (might differ from requested version)
ACTUAL_VERSION=$(pg_lsclusters -h | awk '{print $1}' | head -1)
if [ -n "$ACTUAL_VERSION" ]; then
    echo "Detected actual PostgreSQL version: $ACTUAL_VERSION"
    POSTGRES_VERSION="$ACTUAL_VERSION"
else
    echo "Using configured PostgreSQL version: $POSTGRES_VERSION"
fi

PG_CONF="/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"

# Backup original configs
[ -f "$PG_CONF" ] && cp "$PG_CONF" "$PG_CONF.backup"
[ -f "$PG_HBA" ] && cp "$PG_HBA" "$PG_HBA.backup"

# Create pg_hba.conf for VPC access and external connections
# NOTE: IPv6 address MUST be properly formatted with correct column spacing
echo "Configuring pg_hba.conf..."
cat > "$PG_HBA" <<'EOF'
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             10.0.0.0/8              scram-sha-256
host    all             all             10.8.0.0/28             scram-sha-256
host    all             all             0.0.0.0/0               md5
host    all             all             ::/0                    md5
EOF

chmod 600 "$PG_HBA"
chown postgres:postgres "$PG_HBA"

# Configure postgresql.conf for remote connections and performance
echo "Configuring postgresql.conf..."
# CRITICAL: Remove ALL listen_addresses lines (commented or not) before adding our own
# The pattern matches: listen_addresses with optional leading #
sed -i "/^#*listen_addresses/d" "$PG_CONF"
# Also remove any uncommented listen_addresses ( Ubuntu default might be 'localhost')
sed -i "/^listen_addresses/d" "$PG_CONF"

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

# CRITICAL: Verify disk is mounted before starting PostgreSQL
# The disk might not be mounted immediately after boot even with fstab entry
echo "Verifying disk mount status..."
if ! mountpoint -q "$MOUNT_POINT"; then
    echo "WARNING: Disk not mounted at $MOUNT_POINT, attempting to mount..."
    mount "$MOUNT_POINT"
    echo "Disk mounted successfully"
else
    echo "Disk already mounted at $MOUNT_POINT"
fi

# Verify data directory exists and has correct permissions
if [ ! -d "/var/lib/postgresql/$POSTGRES_VERSION/main" ]; then
    echo "ERROR: PostgreSQL data directory not found at /var/lib/postgresql/$POSTGRES_VERSION/main"
    exit 1
fi

# Stop any existing PostgreSQL processes
echo "Stopping any existing PostgreSQL processes..."
pg_ctlcluster $POSTGRES_VERSION main stop 2>/dev/null || true
sleep 2

# Start PostgreSQL using pg_ctl directly (more reliable than systemctl during startup)
# Note: Values like DB_PASSWORD come from Terraform variables via metadata
echo "Starting PostgreSQL..."
PG_DATA_DIR="/var/lib/postgresql/$POSTGRES_VERSION/main"
PG_LOG_DIR="$PG_DATA_DIR/log"

# Ensure log directory exists
mkdir -p "$PG_LOG_DIR"
chown postgres:postgres "$PG_LOG_DIR"

# Start PostgreSQL as postgres user
sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/pg_ctl -D "$PG_DATA_DIR" -l "$PG_LOG_DIR/startup.log" start -o "-c config_file=$PG_CONF"

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
MAX_PG_WAIT=60
for i in $(seq 1 $MAX_PG_WAIT); do
    if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
        echo "PostgreSQL is ready (attempt $i/$MAX_PG_WAIT)"
        break
    fi
    if [ $i -eq $MAX_PG_WAIT ]; then
        echo "ERROR: PostgreSQL did not become ready after $MAX_PG_WAIT attempts"
        echo "Check logs at: $PG_LOG_DIR/startup.log"
        exit 1
    fi
    echo "Attempt $i/$MAX_PG_WAIT: waiting for PostgreSQL..."
    sleep 2
done

# Create database and user (idempotent - handles existing user)
echo "Creating database and user..."
sudo -u postgres psql <<PSQL_EOF
-- Create user if not exists, or update password if exists
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DB_USER') THEN
      EXECUTE 'CREATE USER $DB_USER WITH PASSWORD '''$DB_PASSWORD'''';
   ELSE
      EXECUTE 'ALTER USER $DB_USER WITH PASSWORD '''$DB_PASSWORD'''';
   END IF;
END
\$\$;

-- Create database if not exists
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME') THEN
      EXECUTE 'CREATE DATABASE $DB_NAME OWNER $DB_USER';
   END IF;
END
\$\$;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;

-- Set default privileges for future tables (idempotent)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
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
        echo "ERROR: pgvector extension may not be available: $PGVECTOR_DB_OUTPUT"
        exit 1
    fi
fi

# Now create the schema inline (can't reference local file from VM)
echo "Creating database schema..."
SCHEMA_OUTPUT=$(sudo -u postgres psql -d $DB_NAME <<'SCHEMA_EOF'
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

-- Patterns table
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

-- Technical decisions
CREATE TABLE IF NOT EXISTS technical_decisions (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    what TEXT NOT NULL,
    why TEXT,
    alternatives TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_decisions_repo_id ON technical_decisions(repo_id);

-- Reusable components
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

-- Keywords
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

-- Dependencies
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

-- Repository relationships
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

-- Deployment scripts
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

-- Analysis history
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

-- Test frameworks
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

-- Runtime issues
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

-- Grant privileges
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;

-- Set default privileges for future tables (idempotent)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
SCHEMA_EOF
)
SCHEMA_EXIT_CODE=$?

if [ $SCHEMA_EXIT_CODE -eq 0 ]; then
    echo "✓ Schema initialization complete"
else
    echo "ERROR: Schema initialization failed with exit code $SCHEMA_EXIT_CODE"
    echo "Schema output:"
    echo "$SCHEMA_OUTPUT"

    if echo "$SCHEMA_OUTPUT" | grep -q "type.*vector"; then
        echo "ERROR: pgvector extension not available"
    fi
    echo "Continuing anyway..."
fi

# Enable PostgreSQL to start on boot
# Using systemctl for boot is fine - the key is that pg_ctl starts successfully during setup
systemctl enable postgresql

# CRITICAL: Ensure listen_addresses is set via ALTER SYSTEM to persist across restarts
# This is more reliable than relying on postgresql.conf alone
echo "Setting listen_addresses to '*' via ALTER SYSTEM..."
sudo -u postgres psql -c "ALTER SYSTEM SET listen_addresses = '*';"

# Create a systemd override to ensure disk is mounted before PostgreSQL starts
# This ensures the persistent data disk is ready before PostgreSQL tries to use it
echo "Creating systemd service override for reliable startup..."
mkdir -p /etc/systemd/system/postgresql.service.d

# Use device path directly since UUID might not be available in early boot
cat > /etc/systemd/system/postgresql.service.d/override.conf <<OVERRIDE
[Unit]
After=local-fs.target mnt-postgres-data.mount
RequiresMountsFor=/mnt/postgres-data
Before=postgresql.service
OVERRIDE

# Create mount unit for the data disk if it doesn't exist
if [ -n "$DISK_PATH" ]; then
    MOUNT_UNIT=$(systemd-escape -p /mnt/postgres-data.mount)
    cat > /etc/systemd/system/$MOUNT_UNIT <<MOUNTUNIT
[Unit]
DefaultDependencies=no
After=systemd-remount-fs.service
Before=local-fs.target
[Mount]
What=$DISK_PATH
Where=/mnt/postgres-data
Type=ext4
Options=defaults,nofail
[Install]
WantedBy=local-fs.target
MOUNTUNIT
    echo "Mount unit created: $MOUNT_UNIT"
fi

# Reload systemd to pick up the override
systemctl daemon-reload
echo "Systemd override created"

# ============================================
# Step 7: Set up automated backups
# ============================================
echo ""
echo "===== Step 7: Set up automated backups ====="

# Install gcloud CLI if not present (needed for gsutil)
if ! command -v gsutil &> /dev/null; then
    echo "Installing Google Cloud SDK..."
    apt-get install -y python3-pip
    pip3 install google-cloud-storage google-cloud-core
fi

# Copy backup script to VM
BACKUP_SCRIPT_DIR="/opt/postgres-backup"
mkdir -p "$BACKUP_SCRIPT_DIR"
chmod +x "$HOME/scripts/backup-postgres.sh" 2>/dev/null || true

# Check if backup script exists in HOME, if not use the one from metadata
if [ -f "$HOME/scripts/backup-postgres.sh" ]; then
    cp "$HOME/scripts/backup-postgres.sh" "$BACKUP_SCRIPT_DIR/backup.sh"
    chmod +x "$BACKUP_SCRIPT_DIR/backup.sh"
elif [ -f "/tmp/backup-postgres.sh" ]; then
    cp /tmp/backup-postgres.sh "$BACKUP_SCRIPT_DIR/backup.sh"
    chmod +x "$BACKUP_SCRIPT_DIR/backup.sh"
else
    echo "WARNING: Backup script not found, downloading from metadata..."
    # Backup script should be passed via metadata or we create a basic one
    mkdir -p "$HOME/scripts"
    cat > "$HOME/scripts/backup-postgres.sh" <<BACKUP_SCRIPT
#!/bin/bash
set -e

BACKUP_BUCKET="${BACKUP_BUCKET}"
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
BACKUP_DATE=\$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="devnexus_\${BACKUP_DATE}.sql.gz"

echo "Starting PostgreSQL backup..."

# Run backup
sudo -u postgres pg_dump -d \${DB_NAME} | gzip > /tmp/\${BACKUP_FILE}

# Upload to GCS
gsutil cp /tmp/\${BACKUP_FILE} gs://\${BACKUP_BUCKET}/\${BACKUP_FILE}

# Cleanup
rm -f /tmp/\${BACKUP_FILE}

echo "Backup complete: \${BACKUP_FILE}"
BACKUP_SCRIPT
    chmod +x "$HOME/scripts/backup-postgres.sh"
    cp "$HOME/scripts/backup-postgres.sh" "$BACKUP_SCRIPT_DIR/backup.sh"
fi

# Set up cron job for daily backups at 2am
CRON_ENTRY="0 2 * * * $BACKUP_SCRIPT_DIR/backup.sh >> /var/log/postgres-backup.log 2>&1"

# Add to crontab if not already present
(crontab -l 2>/dev/null | grep -v "backup-postgres.sh"; echo "$CRON_ENTRY") | crontab -

echo "✓ Automated backup cron job configured (runs daily at 2am UTC)"

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
