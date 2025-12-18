@echo off
REM Unified Terraform Initialization Script (Windows)
REM
REM Provides consistent terraform init across all projects
REM
REM Usage:
REM   terraform-init-unified.bat dev
REM   terraform-init-unified.bat staging
REM   terraform-init-unified.bat prod
REM
REM Environment variables:
REM   TERRAFORM_STATE_BUCKET - GCS bucket for state
REM   PROJECT_NAME - Project name for prefix

setlocal enabledelayedexpansion

REM Configuration
if not defined TERRAFORM_STATE_BUCKET (
    set "STATE_BUCKET=globalbiting-dev-terraform-state"
) else (
    set "STATE_BUCKET=%TERRAFORM_STATE_BUCKET%"
)

REM Auto-detect project name from directory
if not defined PROJECT_NAME (
    for %%I in ("..") do set "PROJECT_NAME=%%~nxI"
)

REM Get environment parameter
set "ENVIRONMENT=%1"
if "%ENVIRONMENT%"=="" set "ENVIRONMENT=dev"

REM Validate environment
if /i "%ENVIRONMENT%"=="dev" (
    set "VALID_ENV=1"
) else if /i "%ENVIRONMENT%"=="staging" (
    set "VALID_ENV=1"
) else if /i "%ENVIRONMENT%"=="prod" (
    set "VALID_ENV=1"
) else if /i "%ENVIRONMENT%"=="dr" (
    set "VALID_ENV=1"
) else (
    echo Error: Invalid environment '%ENVIRONMENT%'
    echo Allowed: dev, staging, prod, dr
    exit /b 1
)

echo ================================================
echo Unified Terraform Initialization
echo ================================================
echo.
echo Project:          %PROJECT_NAME%
echo Environment:      %ENVIRONMENT%
echo State Bucket:     %STATE_BUCKET%
echo State Prefix:     %PROJECT_NAME%/%ENVIRONMENT%
echo.

REM Check for existing .terraform
set "RECONFIGURE_FLAG="
if exist ".terraform" (
    echo [INFO] Detected existing .terraform directory - will reconfigure
    set "RECONFIGURE_FLAG=-reconfigure"
)

echo Running terraform init...
echo.

REM Run terraform init
terraform init ^
    -backend-config="bucket=%STATE_BUCKET%" ^
    -backend-config="prefix=%PROJECT_NAME%/%ENVIRONMENT%" ^
    %RECONFIGURE_FLAG% ^
    -input=false

if %ERRORLEVEL% NEQ 0 (
    echo Error: Terraform initialization failed
    exit /b 1
)

echo.
echo [OK] Terraform initialized successfully!
echo.

REM Validate configuration
echo Validating configuration...
terraform validate

if %ERRORLEVEL% NEQ 0 (
    echo Error: Configuration validation failed
    exit /b 1
)

echo [OK] Configuration is valid
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
echo Backend Configuration:
echo   Bucket: %STATE_BUCKET%
echo   Prefix: %PROJECT_NAME%/%ENVIRONMENT%
echo   State:  gs://%STATE_BUCKET%/%PROJECT_NAME%/%ENVIRONMENT%/default.tfstate
echo.

endlocal
