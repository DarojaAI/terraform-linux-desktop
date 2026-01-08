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

if [ ! -b "$DISK_PATH" ]; then
    echo "WARNING: Disk $DISK_PATH not found - skipping mount"
else
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

# Configure postgresql.conf for remote connections
echo "Configuring postgresql.conf..."
cat >> "$PG_CONF" <<'EOF'

# Dev Nexus Configuration
listen_addresses = '*'
max_connections = 100
shared_buffers = 256MB
effective_cache_size = 768MB
maintenance_work_mem = 64MB
work_mem = 4MB
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
