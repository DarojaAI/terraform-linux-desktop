#!/bin/bash
# Multi-environment Terraform Initialization Script
# Initializes Terraform with environment-specific state isolation
#
# Usage:
#   bash terraform-init.sh dev
#   bash terraform-init.sh staging
#   bash terraform-init.sh prod
#
# This script:
# 1. Validates the environment parameter
# 2. Initializes Terraform with environment-specific backend prefix
# 3. Selects the appropriate tfvars file
# 4. Displays next steps for deployment

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TERRAFORM_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# Configuration
# Updated to use unified bucket naming (matching resume-customizer pattern)
PROJECT_NAME="dev-nexus"
TERRAFORM_STATE_BUCKET="globalbiting-dev-terraform-state"

# Validate environment parameter
if [ -z "$1" ]; then
    echo -e "${RED}Error: Environment not specified${NC}"
    echo "Usage: bash $0 <environment>"
    echo ""
    echo "Available environments:"
    echo "  dev       - Development environment (unauthenticated, scale-to-zero)"
    echo "  staging   - Staging environment (authenticated, moderate resources)"
    echo "  prod      - Production environment (authenticated, HA, monitoring)"
    exit 1
fi

ENVIRONMENT="$1"

# Validate environment value
case "$ENVIRONMENT" in
    dev|staging|prod)
        ;;
    *)
        echo -e "${RED}Error: Invalid environment '$ENVIRONMENT'${NC}"
        echo "Allowed values: dev, staging, prod"
        exit 1
        ;;
esac

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}Terraform Multi-Environment Initialization${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Check if terraform.tfbackend file exists (optional pre-configuration)
BACKEND_CONFIG="${TERRAFORM_DIR}/.terraform-${ENVIRONMENT}.tfbackend"
if [ -f "$BACKEND_CONFIG" ]; then
    echo -e "${GREEN}✓${NC} Using existing backend config: $BACKEND_CONFIG"
else
    echo -e "${YELLOW}ℹ${NC} Backend config file not found at: $BACKEND_CONFIG"
    echo "   (This is OK - using command-line configuration)"
fi

# Check if environment-specific tfvars exists
TFVARS_FILE="${TERRAFORM_DIR}/${ENVIRONMENT}.tfvars"
if [ ! -f "$TFVARS_FILE" ]; then
    echo -e "${RED}Error: tfvars file not found: $TFVARS_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found tfvars file: $TFVARS_FILE"

# Change to terraform directory
cd "$TERRAFORM_DIR"

# Prepare backend config prefix
BACKEND_PREFIX="${PROJECT_NAME}/${ENVIRONMENT}"

echo ""
echo -e "${BLUE}Initializing Terraform with:${NC}"
echo "  Project:        $PROJECT_NAME"
echo "  Environment:    $ENVIRONMENT"
echo "  State Bucket:   $TERRAFORM_STATE_BUCKET"
echo "  State Prefix:   $BACKEND_PREFIX"
echo "  Config File:    ${ENVIRONMENT}.tfvars"
echo ""

# Initialize Terraform with environment-specific backend prefix
echo -e "${YELLOW}Running: terraform init -backend-config=\"prefix=${BACKEND_PREFIX}\"${NC}"
echo ""

if terraform init -backend-config="prefix=${BACKEND_PREFIX}"; then
    echo ""
    echo -e "${GREEN}✓ Terraform initialized successfully!${NC}"
else
    echo -e "${RED}✗ Terraform initialization failed${NC}"
    exit 1
fi

# Validate configuration
echo ""
echo -e "${YELLOW}Running: terraform validate${NC}"
echo ""

if terraform validate; then
    echo ""
    echo -e "${GREEN}✓ Terraform configuration is valid${NC}"
else
    echo -e "${RED}✗ Terraform validation failed${NC}"
    exit 1
fi

# Display next steps
echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}Next Steps${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo "1. Review the plan:"
echo -e "   ${YELLOW}terraform plan -var-file=\"${ENVIRONMENT}.tfvars\" -out=tfplan${NC}"
echo ""
echo "2. Apply the changes:"
echo -e "   ${YELLOW}terraform apply tfplan${NC}"
echo ""
echo "3. View outputs:"
echo -e "   ${YELLOW}terraform output${NC}"
echo ""
echo -e "${BLUE}Environment-Specific Information:${NC}"
echo ""

case "$ENVIRONMENT" in
    dev)
        echo "  • Service allows unauthenticated access (development only)"
        echo "  • Scales to zero for cost savings"
        echo "  • Database uses e2-micro free tier"
        echo "  • Secrets stored with 'dev-nexus-dev' prefix in Secret Manager"
        echo ""
        echo -e "${YELLOW}IMPORTANT: Before applying:${NC}"
        echo "  1. Update secrets in dev.tfvars with actual values from Secret Manager:"
        echo "     gcloud secrets versions access latest --secret=\"dev-nexus-dev_GITHUB_TOKEN\""
        echo "     gcloud secrets versions access latest --secret=\"dev-nexus-dev_ANTHROPIC_API_KEY\""
        echo "     gcloud secrets versions access latest --secret=\"dev-nexus-dev_POSTGRES_PASSWORD\""
        ;;
    staging)
        echo "  • Service requires authentication"
        echo "  • External service accounts will be created for integrations"
        echo "  • Monitoring and alerting enabled"
        echo "  • Secrets stored with 'dev-nexus-staging' prefix in Secret Manager"
        echo ""
        echo -e "${YELLOW}IMPORTANT: Before applying:${NC}"
        echo "  1. Create staging secrets in Secret Manager (if not already created)"
        echo "  2. Update secrets in staging.tfvars with values from Secret Manager:"
        echo "     gcloud secrets versions access latest --secret=\"dev-nexus-staging_GITHUB_TOKEN\""
        echo "     gcloud secrets versions access latest --secret=\"dev-nexus-staging_ANTHROPIC_API_KEY\""
        echo "     gcloud secrets versions access latest --secret=\"dev-nexus-staging_POSTGRES_PASSWORD\""
        ;;
    prod)
        echo "  • Service requires authentication (strict security)"
        echo "  • CPU always allocated (no cold starts)"
        echo "  • Minimum 1 instance running at all times"
        echo "  • Monitoring and alerting ENABLED"
        echo "  • Secrets stored with 'dev-nexus-prod' prefix in Secret Manager"
        echo ""
        echo -e "${RED}IMPORTANT: Before applying:${NC}"
        echo "  1. Review and update prod.tfvars:"
        echo "     - Set allow_ssh_from_cidrs to YOUR_OFFICE_IP/32"
        echo "     - Add orchestrator_url and log_attacker_url"
        echo "     - Add alert_notification_channels"
        echo "  2. Create production secrets in Secret Manager:"
        echo "     gcloud secrets create dev-nexus-prod_GITHUB_TOKEN --replication-policy=automatic"
        echo "     gcloud secrets create dev-nexus-prod_ANTHROPIC_API_KEY --replication-policy=automatic"
        echo "     gcloud secrets create dev-nexus-prod_POSTGRES_PASSWORD --replication-policy=automatic"
        echo "  3. Add secret values:"
        echo "     gcloud secrets versions add dev-nexus-prod_GITHUB_TOKEN --data-file=-"
        echo "     gcloud secrets versions add dev-nexus-prod_ANTHROPIC_API_KEY --data-file=-"
        echo "     gcloud secrets versions add dev-nexus-prod_POSTGRES_PASSWORD --data-file=-"
        echo "  4. Grant Cloud Run access to secrets (terraform does this automatically)"
        ;;
esac

echo ""
echo -e "${GREEN}Setup complete! Proceed to 'terraform plan' when ready.${NC}"
echo ""
