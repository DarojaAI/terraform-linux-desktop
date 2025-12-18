#!/bin/bash
# Unified Terraform Initialization Script
#
# Provides consistent terraform init across all projects (dev-nexus, resume-customizer, etc.)
# Automatically configures backend bucket and prefix based on project and environment
#
# Usage:
#   bash terraform-init-unified.sh dev
#   bash terraform-init-unified.sh staging
#   bash terraform-init-unified.sh prod
#
# Configuration (set these environment variables to customize):
#   TERRAFORM_STATE_BUCKET - GCS bucket for state (default: globalbiting-dev-terraform-state)
#   PROJECT_NAME - Project name for prefix (default: detected from directory)
#   RECONFIGURE - Set to 1 to force reconfiguration (default: auto-detect)

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration defaults
STATE_BUCKET="${TERRAFORM_STATE_BUCKET:-globalbiting-dev-terraform-state}"

# Auto-detect project name from directory
PROJECT_NAME="${PROJECT_NAME:-$(basename "$(cd "$(dirname "$0")/../.." && pwd)")}"

# Environment parameter
ENVIRONMENT="${1:-dev}"

# Validate environment
case "$ENVIRONMENT" in
    dev|staging|prod|dr)
        ;;
    *)
        echo -e "${RED}Error: Invalid environment '$ENVIRONMENT'${NC}"
        echo "Allowed: dev, staging, prod, dr"
        exit 1
        ;;
esac

# Display header
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}Unified Terraform Initialization${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo "Project:          $PROJECT_NAME"
echo "Environment:      $ENVIRONMENT"
echo "State Bucket:     $STATE_BUCKET"
echo "State Prefix:     $PROJECT_NAME/$ENVIRONMENT"
echo ""

# Check if .terraform already exists (to determine -reconfigure flag)
RECONFIGURE_FLAG=""
if [ -d .terraform ]; then
    # Check if backend configuration changed
    if [ -f .terraform/terraform.tfstate ]; then
        CURRENT_BACKEND=$(grep -o '"backend": *"[^"]*"' .terraform/terraform.tfstate | head -1 || echo "")
        if [ -z "$CURRENT_BACKEND" ] || [ "$CURRENT_BACKEND" != "\"backend\": \"gcs\"" ]; then
            RECONFIGURE_FLAG="-reconfigure"
            echo -e "${YELLOW}Detected backend change - will reconfigure${NC}"
        fi
    fi

    # If switching between environments, always reconfigure
    if [ -f .terraform/terraform.tfvars.json ]; then
        CURRENT_ENV=$(grep -o '"environment": *"[^"]*"' .terraform/terraform.tfvars.json | cut -d'"' -f4 || echo "")
        if [ "$CURRENT_ENV" != "$ENVIRONMENT" ]; then
            RECONFIGURE_FLAG="-reconfigure"
            echo -e "${YELLOW}Detected environment change - will reconfigure${NC}"
        fi
    fi
fi

echo ""
echo -e "${YELLOW}Running terraform init...${NC}"
echo ""

# Run terraform init with unified backend config
if terraform init \
    -backend-config="bucket=$STATE_BUCKET" \
    -backend-config="prefix=$PROJECT_NAME/$ENVIRONMENT" \
    $RECONFIGURE_FLAG \
    -input=false; then

    echo ""
    echo -e "${GREEN}✓ Terraform initialized successfully!${NC}"
    echo ""

    # Validate configuration
    echo -e "${YELLOW}Validating configuration...${NC}"
    if terraform validate; then
        echo -e "${GREEN}✓ Configuration is valid${NC}"
    else
        echo -e "${RED}✗ Configuration validation failed${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Terraform initialization failed${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}Next Steps${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo "1. Review the plan:"
echo "   terraform plan -var-file=\"${ENVIRONMENT}.tfvars\" -out=tfplan"
echo ""
echo "2. Apply the changes:"
echo "   terraform apply tfplan"
echo ""
echo "3. View outputs:"
echo "   terraform output"
echo ""
echo -e "${BLUE}Backend Configuration${NC}:"
echo "  Bucket: $STATE_BUCKET"
echo "  Prefix: $PROJECT_NAME/$ENVIRONMENT"
echo "  State:  gs://$STATE_BUCKET/$PROJECT_NAME/$ENVIRONMENT/default.tfstate"
echo ""
