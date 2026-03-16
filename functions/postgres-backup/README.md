# PostgreSQL Backup Cloud Function

This Cloud Function is triggered by Cloud Scheduler to perform automated backups of the PostgreSQL database to Google Cloud Storage.

## Function Structure

```
postgres-backup/
├── main.py              # Cloud Function entry point
├── requirements.txt    # Python dependencies
└── backup.sh          # Backup script (executed inside function)
```

## Deployment

```bash
# Set variables
PROJECT_ID="your-project"
REGION="us-central1"
FUNCTION_NAME="postgres-backup"

# Deploy Cloud Function
gcloud functions deploy $FUNCTION_NAME \
  --runtime python311 \
  --trigger-http \
  --region $REGION \
  --source . \
  --service-account dev-nexus-postgres-vm@$PROJECT_ID.iam.gserviceaccount.com \
  --env-vars-file .env.yaml
```

## Environment Variables

Create `.env.yaml`:

```yaml
POSTGRES_HOST: "10.8.0.12"
POSTGRES_PORT: "5432"
POSTGRES_DB: "devnexus"
POSTGRES_USER: "devnexus"
POSTGRES_PASSWORD: "your-password"  # Or use Secret Manager
BACKUP_BUCKET: "gs://your-project-postgres-backups"
```

## Cloud Scheduler

```bash
# Create scheduled job
gcloud scheduler jobs create http postgres-backup \
  --schedule="0 2 * * *" \
  --uri="https://$REGION-$PROJECT_ID.cloudfunctions.net/$FUNCTION_NAME" \
  --location=$REGION \
  --oidc-service-account-email="dev-nexus-postgres-vm@$PROJECT_ID.iam.gserviceaccount.com"
```

## Testing

```bash
# Test the function directly
gcloud functions call $FUNCTION_NAME --region=$REGION

# Check logs
gcloud functions logs read $FUNCTION_NAME --region=$REGION
```
