# Terraform Troubleshooting

## Error: `dial tcp [2607:f8b0:400c:c08::5f]:443: connect: cannot assign requested address`

This error occurs when Terraform attempts to connect to Google Cloud APIs over IPv6, but the local environment has issues with IPv6 connectivity.

### Solution

You can force Terraform to use Go's built-in DNS resolver, which often prefers IPv4 and resolves the issue.

**Temporary Fix (Current Session):**

Set the `GODEBUG` environment variable before running Terraform commands:

```bash
export GODEBUG=netdns=go
terraform plan
```

**Permanent Fix (Recommended):**

Add the `GODEBUG` variable to your shell's startup file to make the change permanent for all future sessions.

1.  **For Bash users:**
    ```bash
    echo 'export GODEBUG=netdns=go' >> ~/.bashrc
    source ~/.bashrc
    ```

2.  **For Zsh users:**
    ```bash
    echo 'export GODEBUG=netdns=go' >> ~/.zshrc
    source ~/.zshrc
    ```

This change instructs the Go runtime (which Terraform is built on) to use a DNS resolution strategy that is less prone to IPv6 issues on misconfigured networks.
