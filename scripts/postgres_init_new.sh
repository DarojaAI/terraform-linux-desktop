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

# Environment Variables (from Terraform - use $${...} syntax)
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
    echo "Please ensure Secret Manager has the password."
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
    echo "Disk $DISK_PATH not found yet (attempt $(expr $RETRY_COUNT + 1)/$MAX_RETRIES). Waiting ${RETRY_DELAY}s..."
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
    echo "[OK] pgvector extension created successfully"
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
    echo "[OK] pgvector extension verified: v$PGVECTOR_VERSION"
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

    # Check if data directory already exists on mount
    if [ -d "$MOUNT_POINT/$POSTGRES_VERSION/main" ]; then
        echo "Data directory already exists on mount, using it"
        PGDATA_DIR="$MOUNT_POINT/$POSTGRES_VERSION/main"
    else
        echo "Moving PostgreSQL data to mount..."

        # Move existing data if any
        if [ -d "/var/lib/postgresql/$POSTGRES_VERSION/main" ]; then
            cp -a /var/lib/postgresql/$POSTGRES_VERSION/main/* "$MOUNT_POINT/" || true
        fi

        # Ensure proper ownership
        chown -R postgres:postgres "$MOUNT_POINT"

        # Update PostgreSQL config
        PGDATA_DIR="$MOUNT_POINT/$POSTGRES_VERSION/main"
    fi
else
    echo "No mount found, using default data directory"
    PGDATA_DIR="/var/lib/postgresql/$POSTGRES_VERSION/main"
fi

echo "PGDATA_DIR: $PGDATA_DIR"

# Update postgresql.conf to use custom data directory
PG_CONF="/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"
if [ -f "$PG_CONF" ]; then
    # Enable listening on all addresses
    if ! grep -q "^listen_addresses" "$PG_CONF"; then
        echo "listen_addresses = '*'" >> "$PG_CONF"
    fi

    # Set data directory
    if ! grep -q "^data_directory" "$PG_CONF"; then
        echo "data_directory = '$PGDATA_DIR'" >> "$PG_CONF"
    fi
fi

# Start PostgreSQL as postgres user
sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/pg_ctl -D "$PGDATA_DIR" -l "$PG_LOG_DIR/startup.log" start -o "-c config_file=$PG_CONF"

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

# Create database and user (using separate commands to avoid heredoc escaping issues)
echo "Creating database and user..."
sudo -u postgres psql -c "DROP USER IF EXISTS $DB_USER;"
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;"
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;"

# Initialize database schema
echo ""
echo "===== Initializing database schema ====="

# First, ensure pgvector extension exists in the target database
echo "Ensuring pgvector extension in target database..."
PGVECTOR_DB_OUTPUT=$(sudo -u postgres psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>&1)
PGVECTOR_DB_EXIT=$?

if [ $PGVECTOR_DB_EXIT -eq 0 ]; then
    echo "[OK] pgvector extension available in target database"
else
    # Check if error is just "already exists"
    if echo "$PGVECTOR_DB_OUTPUT" | grep -q "already exists"; then
        echo "[OK] pgvector extension already exists in target database"
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
    name VARCHAR(255) NOT NULL UNIQUE,
    full_name VARCHAR(500),
    description TEXT,
    language VARCHAR(100),
    topics JSONB,
    stars INTEGER DEFAULT 0,
    forks INTEGER DEFAULT 0,
    open_issues INTEGER DEFAULT 0,
    watchers INTEGER DEFAULT 0,
    size INTEGER DEFAULT 0,
    default_branch VARCHAR(100) DEFAULT 'main',
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE,
    pushed_at TIMESTAMP WITH TIME ZONE,
    homepage VARCHAR(500),
    license VARCHAR(100),
    forks_count INTEGER DEFAULT 0,
    open_issues_count INTEGER DEFAULT 0,
    watchers_count INTEGER DEFAULT 0,
    owner VARCHAR(255),
    private BOOLEAN DEFAULT FALSE,
    archived BOOLEAN DEFAULT FALSE,
    disabled BOOLEAN DEFAULT FALSE,
    visibility VARCHAR(50) DEFAULT 'public',
    last_analyzed TIMESTAMP WITH TIME ZONE,
    complexity_simple DECIMAL(10,2),
    complexity_mccabe DECIMAL(10,2),
    complexity_cognitive DECIMAL(10,2),
    complexity_grade VARCHAR(1),
    complexity_last_analyzed TIMESTAMP WITH TIME ZONE,
    patterns JSONB,
    problem_domain VARCHAR(255),
    keywords JSONB,
    dependencies JSONB,
    components JSONB,
    metadata JSONB,
    created_at_repo TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_repositories_name ON repositories(name);
CREATE INDEX IF NOT EXISTS idx_repositories_owner ON repositories(owner);
CREATE INDEX IF NOT EXISTS idx_repositories_language ON repositories(language);
CREATE INDEX IF NOT EXISTS idx_repositories_topics ON repositories USING GIN(topics);
CREATE INDEX IF NOT EXISTS idx_repositories_keywords ON repositories USING GIN(keywords);
CREATE INDEX IF NOT EXISTS idx_repositories_problem_domain ON repositories(problem_domain);
CREATE INDEX IF NOT EXISTS idx_repositories_last_analyzed ON repositories(last_analyzed DESC);

-- Components table
CREATE TABLE IF NOT EXISTS components (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    component_id VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    component_type VARCHAR(100),
    purpose TEXT,
    location VARCHAR(500),
    language VARCHAR(100),
    complexity_simple DECIMAL(10,2),
    complexity_mccabe DECIMAL(10,2),
    complexity_cognitive DECIMAL(10,2),
    lines_of_code INTEGER,
    cyclomatic_complexity DECIMAL(10,2),
    cognitive_complexity DECIMAL(10,2),
    halstead_volume DECIMAL(10,2),
    halstead_difficulty DECIMAL(10,2),
    maintainability_index DECIMAL(10,2),
    lines_of_comments INTEGER,
    blank_lines INTEGER,
    code_lines INTEGER,
    total_lines INTEGER,
    imports JSONB,
    exports JSONB,
    dependencies JSONB,
    keywords JSONB,
    documentation TEXT,
    first_commit_date TIMESTAMP WITH TIME ZONE,
    last_commit_date TIMESTAMP WITH TIME ZONE,
    commit_count INTEGER DEFAULT 0,
    contributor_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(repo_id, component_id)
);
CREATE INDEX IF NOT EXISTS idx_components_repo_id ON components(repo_id);
CREATE INDEX IF NOT EXISTS idx_components_type ON components(component_type);
CREATE INDEX IF NOT EXISTS idx_components_language ON components(language);
CREATE INDEX IF NOT EXISTS idx_components_imports ON components USING GIN(imports);
CREATE INDEX IF NOT EXISTS idx_components_dependencies ON components USING GIN(dependencies);

-- Patterns table
CREATE TABLE IF NOT EXISTS patterns (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    pattern_name VARCHAR(255) NOT NULL,
    pattern_type VARCHAR(100),
    description TEXT,
    file_path VARCHAR(500),
    line_number INTEGER,
    code_snippet TEXT,
    language VARCHAR(100),
    severity VARCHAR(50),
    context JSONB,
    metadata JSONB,
    detected_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(repo_id, pattern_name, file_path, line_number)
);
CREATE INDEX IF NOT EXISTS idx_patterns_repo_id ON patterns(repo_id);
CREATE INDEX IF NOT EXISTS idx_patterns_name ON patterns(pattern_name);
CREATE INDEX IF NOT EXISTS idx_patterns_type ON patterns(pattern_type);
CREATE INDEX IF NOT EXISTS idx_patterns_language ON patterns(language);
CREATE INDEX IF NOT EXISTS idx_patterns_severity ON patterns(severity);

-- Dependencies table
CREATE TABLE IF NOT EXISTS dependencies (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    dependency_type VARCHAR(50),
    package_name VARCHAR(255) NOT NULL,
    version VARCHAR(100),
    dev BOOLEAN DEFAULT FALSE,
    optional BOOLEAN DEFAULT FALSE,
    source_file VARCHAR(500),
    line_number INTEGER,
    metadata JSONB,
    detected_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(repo_id, package_name, source_file)
);
CREATE INDEX IF NOT EXISTS idx_dependencies_repo_id ON dependencies(repo_id);
CREATE INDEX IF NOT EXISTS idx_dependencies_package ON dependencies(package_name);

-- Pattern versions table
CREATE TABLE IF NOT EXISTS pattern_versions (
    id SERIAL PRIMARY KEY,
    pattern_name VARCHAR(255) NOT NULL,
    version VARCHAR(50) NOT NULL,
    description TEXT,
    code_example TEXT,
    use_cases JSONB,
    anti_patterns JSONB,
    related_patterns JSONB,
    language VARCHAR(100),
    problem_domain VARCHAR(255),
    keywords JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by VARCHAR(255),
    metadata JSONB,
    status VARCHAR(50) DEFAULT 'active',
    deprecated_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(pattern_name, version)
);
CREATE INDEX IF NOT EXISTS idx_pattern_versions_name ON pattern_versions(pattern_name);
CREATE INDEX IF NOT EXISTS idx_pattern_versions_domain ON pattern_versions(problem_domain);
CREATE INDEX IF NOT EXISTS idx_pattern_versions_status ON pattern_versions(status);

-- Runtime issues table
CREATE TABLE IF NOT EXISTS runtime_issues (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
    issue_type VARCHAR(100) NOT NULL,
    severity VARCHAR(50) NOT NULL,
    title VARCHAR(500),
    description TEXT,
    detected_at TIMESTAMP WITH TIME ZONE NOT NULL,
    resolved_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(50) DEFAULT 'open',
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_runtime_issues_repo_id ON runtime_issues(repo_id);
CREATE INDEX IF NOT EXISTS idx_runtime_issues_detected_at ON runtime_issues(detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_runtime_issues_issue_type ON runtime_issues(issue_type);
CREATE INDEX IF NOT EXISTS idx_runtime_issues_severity ON runtime_issues(severity);
CREATE INDEX IF NOT EXISTS idx_runtime_issues_repo_detected ON runtime_issues(repo_id, detected_at DESC);
SCHEMA_EOF
)
SCHEMA_EXIT_CODE=$?

if [ $SCHEMA_EXIT_CODE -eq 0 ]; then
    echo "[OK] Schema initialization complete"
else
    echo "ERROR: Schema initialization failed with exit code $SCHEMA_EXIT_CODE"
    echo "Schema output:"
    echo "$SCHEMA_OUTPUT"

    if echo "$SCHEMA_OUTPUT" | grep -q "type.*vector"; then
        echo "Warning: pgvector-related error (might be OK if extension already exists)"
    else
        exit 1
    fi
fi

# Grant schema permissions
echo "Granting schema permissions..."
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;"

# Create backup cron job
echo ""
echo "===== Setting up automated backups ====="

# Create backup script
cat > /home/postgres/backup-postgres.sh <<'BACKUP_SCRIPT'
#!/bin/bash
set -e

BACKUP_BUCKET="${BACKUP_BUCKET}"
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
BACKUP_DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="devnexus_${BACKUP_DATE}.sql.gz"

echo "Starting PostgreSQL backup..."

# Run backup
sudo -u postgres pg_dump -d ${DB_NAME} | gzip > /tmp/${BACKUP_FILE}

# Upload to GCS
gsutil cp /tmp/${BACKUP_FILE} gs://${BACKUP_BUCKET}/${BACKUP_FILE}

# Cleanup
rm -f /tmp/${BACKUP_FILE}

echo "Backup complete: ${BACKUP_FILE}"
BACKUP_SCRIPT
chmod +x /home/postgres/backup-postgres.sh
cp /home/postgres/backup-postgres.sh /etc/cron.daily/backup-postgres.sh || true

# Configure PostgreSQL to start on boot
echo ""
echo "===== Configuring PostgreSQL to start on boot ====="
systemctl enable postgresql || echo "Warning: Could not enable postgresql service"

# Final status
echo ""
echo "========================================="
echo "PostgreSQL Setup Complete!"
echo "========================================="
echo "PostgreSQL Version: $(psql --version)"
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo "Data Directory: $PGDATA_DIR"
echo "Mount Point: $MOUNT_POINT"
echo "Backup Bucket: $BACKUP_BUCKET"
echo "========================================="