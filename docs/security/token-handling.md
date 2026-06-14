# Token Handling Policy

> **Status:** Adopted 2026-06-14 after the `ghp_Nh…PiSs` cleartext leak (see incident notes in `linux-desktop-seed/docs/plans/workspace-cleanup-and-token-rotation.md`).
> **Scope:** every repo in `DarojaAI/`. This file is the local copy in this repo; the canonical version lives in `DarojaAI/.github/docs/SECURITY-STANDARDS.md` (proposed via RFC).

## The rule

**Never put a GitHub token in a git remote URL.**

A URL of the form `https://x-access-token:<token>@github.com/...` stores the token in cleartext in `.git/config` (or `.gitmodules` for submodules, or any committed config file). Anyone with read access to the home directory, the disk image, or a backup of either, gets the token. Tokens embedded this way have a 5-week-plus exposure window in practice, because nobody audits `.git/config`.

## Approved authentication paths

Pick one. Do not mix.

1. **GitHub CLI credential helper** (recommended for local dev):
   ```bash
   gh auth login
   git remote set-url origin https://github.com/<owner>/<repo>.git
   # No credentials in URL. gh handles auth.
   ```

2. **SSH key** (recommended for CI runners and prod VMs):
   ```bash
   git remote set-url origin git@github.com:<owner>/<repo>.git
   # Add the public key to https://github.com/settings/keys
   ```

3. **GitHub Actions secret + `GITHUB_TOKEN`** (recommended for CI):
   ```yaml
   # In .github/workflows/*.yml
   permissions:
     contents: write  # or 'read' if only pulling
   # Use the auto-provisioned GITHUB_TOKEN, not a PAT.
   ```
   For cross-repo access from CI, use a fine-grained PAT stored as an Actions secret — never inline.

4. **Deploy keys** (recommended for read-only access from a known host):
   https://github.com/<owner>/<repo>/settings/keys/new — single-repo, read-only or read-write, scoped to the host's public key.

## Banned patterns

Any of the following means the token is exposed. Treat it as compromised.

- `https://x-access-token:<token>@github.com/...`
- `https://<token>@github.com/...`
- `https://<username>:<token>@github.com/...`
- `git+https://<token>@github.com/...`
- Any committed file that contains a `ghp_`, `gho_`, `ghu_`, `ghs_`, or `ghr_` prefix
- A PAT in a Terraform variable, a shell script, a YAML, or a JSON config (even with `sensitive = true`)

## What to do if a token is committed or URL-embedded

1. **Revoke the token immediately** in GitHub → Settings → Developer settings → Personal access tokens. Do this *before* cleaning files.
2. **Audit the token's use** in the security log. Note any actions that aren't yours.
3. **Clean the working tree**: `git remote set-url origin https://github.com/<owner>/<repo>.git` to drop the credentials from the URL.
4. **Clean git history** (only if the token was committed to a tracked file, not just the local `.git/config`):
   - `git filter-repo --invert-paths --path <file>` or
   - BFG Repo-Cleaner: `bfg --replace-text <(echo '<token>')`
   - Force-push. Notify collaborators. Rotate any other credentials that shared the same secret.
5. **Add a CI gate** to prevent recurrence: pre-commit with `gitleaks`, GitHub Actions with `gitleaks/gitleaks-action`.

## Detection

`gitleaks` is the org standard (per `DarojaAI/.github/docs/CI-CD-STANDARDS.md`). Every repo should have it as a pre-commit hook and a CI check. A minimal `.pre-commit-config.yaml` entry:

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

If you find a token in the wild (in a PR, in a memory file, in a chat log), treat it as compromised regardless of context. Revoke, audit, rotate, document.

## See also

- `linux-desktop-seed/docs/plans/workspace-cleanup-and-token-rotation.md` — the original incident notes and rotation procedure
- `DarojaAI/.github/docs/CI-CD-STANDARDS.md` — Gitleaks as a pre-commit standard
- GitHub Docs: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
