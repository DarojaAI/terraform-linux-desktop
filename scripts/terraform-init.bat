@echo off
REM Multi-environment Terraform Initialization Script (Windows)
REM Initializes Terraform with environment-specific state isolation
REM
REM Usage:
REM   terraform-init.bat dev
REM   terraform-init.bat staging
REM   terraform-init.bat prod

setlocal enabledelayedexpansion

REM Color codes (using conditional formatting)
set "PROJECT_NAME=dev-nexus"
REM Updated to use unified bucket naming (matching resume-customizer pattern)
set "TERRAFORM_STATE_BUCKET=globalbiting-dev-terraform-state"

REM Get script directory
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "TERRAFORM_DIR=%%~fI"

REM Validate environment parameter
if "%1"=="" (
    echo Error: Environment not specified
    echo Usage: %~nx0 ^<environment^>
    echo.
    echo Available environments:
    echo   dev       - Development environment (unauthenticated, scale-to-zero)
    echo   staging   - Staging environment (authenticated, moderate resources)
    echo   prod      - Production environment (authenticated, HA, monitoring)
    exit /b 1
)

set "ENVIRONMENT=%1"

REM Validate environment value
if /i "%ENVIRONMENT%"=="dev" (
    set "VALID_ENV=1"
) else if /i "%ENVIRONMENT%"=="staging" (
    set "VALID_ENV=1"
) else if /i "%ENVIRONMENT%"=="prod" (
    set "VALID_ENV=1"
) else (
    echo Error: Invalid environment '%ENVIRONMENT%'
    echo Allowed values: dev, staging, prod
    exit /b 1
)

echo ================================================
echo Terraform Multi-Environment Initialization
echo ================================================
echo.

REM Check if environment-specific tfvars exists
set "TFVARS_FILE=%TERRAFORM_DIR%\%ENVIRONMENT%.tfvars"
if not exist "%TFVARS_FILE%" (
    echo Error: tfvars file not found: %TFVARS_FILE%
    exit /b 1
)

echo [OK] Found tfvars file: %TFVARS_FILE%
echo.

REM Change to terraform directory
cd /d "%TERRAFORM_DIR%"

REM Prepare backend config prefix
set "BACKEND_PREFIX=%PROJECT_NAME%/%ENVIRONMENT%"

echo Initializing Terraform with:
echo   Project:        %PROJECT_NAME%
echo   Environment:    %ENVIRONMENT%
echo   State Bucket:   %TERRAFORM_STATE_BUCKET%
echo   State Prefix:   %BACKEND_PREFIX%
echo   Config File:    %ENVIRONMENT%.tfvars
echo.

echo Running: terraform init -backend-config="prefix=%BACKEND_PREFIX%"
echo.

terraform init -backend-config="prefix=%BACKEND_PREFIX%"

if %ERRORLEVEL% NEQ 0 (
    echo Error: Terraform initialization failed
    exit /b 1
)

echo.
echo [OK] Terraform initialized successfully!
echo.

echo Running: terraform validate
echo.

terraform validate

if %ERRORLEVEL% NEQ 0 (
    echo Error: Terraform validation failed
    exit /b 1
)

echo.
echo [OK] Terraform configuration is valid
echo.

echo ================================================
echo Next Steps
echo ================================================
echo.
echo 1. Review the plan:
echo    terraform plan -var-file="%ENVIRONMENT%.tfvars" -out=tfplan
echo.
echo 2. Apply the changes:
echo    terraform apply tfplan
echo.
echo 3. View outputs:
echo    terraform output
echo.
echo Environment-Specific Information:
echo.

if /i "%ENVIRONMENT%"=="dev" (
    echo   - Service allows unauthenticated access (development only)
    echo   - Scales to zero for cost savings
    echo   - Database uses e2-micro free tier
    echo   - Secrets stored with 'dev-nexus-dev' prefix in Secret Manager
    echo.
    echo IMPORTANT: Before applying, update secrets in dev.tfvars:
    echo   gcloud secrets versions access latest --secret="dev-nexus-dev_GITHUB_TOKEN"
    echo   gcloud secrets versions access latest --secret="dev-nexus-dev_ANTHROPIC_API_KEY"
    echo   gcloud secrets versions access latest --secret="dev-nexus-dev_POSTGRES_PASSWORD"
) else if /i "%ENVIRONMENT%"=="staging" (
    echo   - Service requires authentication
    echo   - External service accounts created for integrations
    echo   - Monitoring and alerting enabled
    echo   - Secrets stored with 'dev-nexus-staging' prefix in Secret Manager
    echo.
    echo IMPORTANT: Before applying, update secrets in staging.tfvars:
    echo   gcloud secrets versions access latest --secret="dev-nexus-staging_GITHUB_TOKEN"
    echo   gcloud secrets versions access latest --secret="dev-nexus-staging_ANTHROPIC_API_KEY"
    echo   gcloud secrets versions access latest --secret="dev-nexus-staging_POSTGRES_PASSWORD"
) else if /i "%ENVIRONMENT%"=="prod" (
    echo   - Service requires authentication (strict security)
    echo   - CPU always allocated (no cold starts)
    echo   - Minimum 1 instance running at all times
    echo   - Monitoring and alerting ENABLED
    echo   - Secrets stored with 'dev-nexus-prod' prefix in Secret Manager
    echo.
    echo IMPORTANT: Before applying:
    echo   1. Review prod.tfvars and update:
    echo      - allow_ssh_from_cidrs set to YOUR_OFFICE_IP/32
    echo      - orchestrator_url and log_attacker_url
    echo      - alert_notification_channels
    echo.
    echo   2. Create production secrets in Secret Manager:
    echo      gcloud secrets create dev-nexus-prod_GITHUB_TOKEN --replication-policy=automatic
    echo      gcloud secrets create dev-nexus-prod_ANTHROPIC_API_KEY --replication-policy=automatic
    echo      gcloud secrets create dev-nexus-prod_POSTGRES_PASSWORD --replication-policy=automatic
    echo.
    echo   3. Add secret values:
    echo      gcloud secrets versions add dev-nexus-prod_GITHUB_TOKEN --data-file=-
    echo      gcloud secrets versions add dev-nexus-prod_ANTHROPIC_API_KEY --data-file=-
    echo      gcloud secrets versions add dev-nexus-prod_POSTGRES_PASSWORD --data-file=-
)

echo.
echo Setup complete! Proceed to 'terraform plan' when ready.
echo.

endlocal
