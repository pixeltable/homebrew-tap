# Homebrew Formula Release Automation Guide

This document describes how formula updates are automated in `pixeltable/homebrew-tap` following the pattern popularized by Simon Willison, and provides drop-in workflow snippets for the core [pixeltable/pixeltable](https://github.com/pixeltable/pixeltable) repository.

---

## Architecture Overview

```text
  pixeltable/pixeltable (Core Repo)
    │
    ├─> Publish release to PyPI (e.g. v0.7.9)
    │
    └─> Dispatches `pixeltable-published` via GitHub REST API
              │
              ▼
  pixeltable/homebrew-tap (Tap Repo)
    │
    ├─> Trigger: `repository_dispatch` (instant) OR cron (every 6h) OR `workflow_dispatch`
    │
    ├─> Fetches latest wheel metadata & SHA-256 from PyPI JSON API (with CDN retry loop)
    │
    ├─> Updates `Formula/pxt.rb` with new wheel URL and SHA-256
    │
    ├─> Validates:
    │     • brew style Formula/pxt.rb
    │     • brew livecheck pixeltable/tap/pxt
    │     • brew audit --tap pixeltable/tap pixeltable/tap/pxt
    │     • brew install --build-from-source pixeltable/tap/pxt
    │     • brew test pixeltable/tap/pxt
    │     • scripts/check-macho-install-names.sh
    │
    └─> Commits & pushes to `main` (falls back to PR if branch protection requires it)
```

---

## 1. Setting up `HOMEBREW_TAP_SYNC_TOKEN`

To allow the core repository (`pixeltable/pixeltable`) to trigger workflow runs in the tap repository (`pixeltable/homebrew-tap`), you need a GitHub Personal Access Token (PAT) with dispatch permissions.

### Option A: Fine-Grained Personal Access Token (Recommended)
1. Go to **GitHub Settings** → **Developer Settings** → **Personal Access Tokens** → **Fine-grained tokens**.
2. Click **Generate new token**.
3. Configure the token:
   - **Token name:** `pixeltable-tap-sync-token`
   - **Resource owner:** `pixeltable`
   - **Repository access:** **Only select repositories** → choose `pixeltable/homebrew-tap`.
   - **Permissions:**
     - **Repository permissions** → **Contents:** `Read and write`
     - (Metadata is automatically set to Read-only)
4. Click **Generate token** and copy the value.

### Option B: Classic Personal Access Token
1. Go to **GitHub Settings** → **Developer Settings** → **Personal Access Tokens** → **Tokens (classic)**.
2. Select scopes: `repo` (or `public_repo` if public).
3. Generate and copy the token.

### Add the Secret to `pixeltable/pixeltable`
1. In `pixeltable/pixeltable`, navigate to **Settings** → **Secrets and variables** → **Actions**.
2. Click **New repository secret**.
3. Name: `HOMEBREW_TAP_SYNC_TOKEN`
4. Value: `<paste your token>`
5. Click **Add secret**.

---

## 2. GitHub Actions Integration in Core Repository

Add the following step or standalone workflow to the core repository `pixeltable/pixeltable`.

### Approach A: Integrated Step in Existing Release / Publish Workflow

If `pixeltable/pixeltable` already has a PyPI publishing workflow (e.g. `.github/workflows/publish.yml` or `.github/workflows/release.yml`), add this step at the end of the publish job:

```yaml
      - name: Trigger Homebrew Formula Update
        env:
          GITHUB_TOKEN: ${{ secrets.HOMEBREW_TAP_SYNC_TOKEN }}
          VERSION: ${{ steps.version.outputs.version }} # e.g. "0.7.9" or "v0.7.9" (v-prefix is automatically normalized)
        run: |
          echo "Dispatching formula update to pixeltable/homebrew-tap for version ${VERSION}..."
          curl -f -X POST \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            https://api.github.com/repos/pixeltable/homebrew-tap/dispatches \
            -d "{\"event_type\": \"pixeltable-published\", \"client_payload\": {\"version\": \"${VERSION}\"}}"
```

### Approach B: Using `peter-evans/repository-dispatch` Action

```yaml
      - name: Trigger Homebrew Formula Update
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.HOMEBREW_TAP_SYNC_TOKEN }}
          repository: pixeltable/homebrew-tap
          event-type: pixeltable-published
          client-payload: '{"version": "${{ steps.version.outputs.version }}"}'
```

### Approach C: Complete Standalone Dispatch Workflow

Save this file as `.github/workflows/dispatch-homebrew.yml` in `pixeltable/pixeltable`:

```yaml
name: Dispatch Homebrew Tap Update

on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      version:
        description: "Pixeltable release version to bump in Homebrew tap (e.g. 0.7.9)"
        required: false
        type: string

jobs:
  notify-tap:
    name: Notify pixeltable/homebrew-tap
    runs-on: ubuntu-latest
    steps:
      - name: Determine Target Version
        id: target
        run: |
          if [ -n "${{ inputs.version }}" ]; then
            VERSION="${{ inputs.version }}"
          elif [ -n "${{ github.event.release.tag_name }}" ]; then
            TAG="${{ github.event.release.tag_name }}"
            VERSION="${TAG#v}"
          else
            VERSION=""
          fi
          echo "version=${VERSION}" >> "$GITHUB_OUTPUT"
          echo "Dispatching release notification for version: '${VERSION}'"

      - name: Send Repository Dispatch Event
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.HOMEBREW_TAP_SYNC_TOKEN }}
          repository: pixeltable/homebrew-tap
          event-type: pixeltable-published
          client-payload: '{"version": "${{ steps.target.outputs.version }}"}'
```

---

## 3. Maintenance & Manual Operations

Maintainers can also interact with the tap automation directly:

### Triggering Manual Update via GitHub Actions
1. Navigate to [pixeltable/homebrew-tap Actions](https://github.com/pixeltable/homebrew-tap/actions/workflows/update-formula.yml).
2. Select **Update Formula on PyPI Release**.
3. Click **Run workflow**.
4. (Optional) Provide an explicit version string or leave blank to auto-detect the latest PyPI release.

### Testing Locally Before Releasing
Run the following local checks in your clone of `pixeltable/homebrew-tap`:

```bash
# Check formula style and rubocop rules
brew style Formula/pxt.rb

# Verify livecheck against PyPI API
brew livecheck pixeltable/tap/pxt

# Audit the formula strictly
brew audit --tap pixeltable/tap pixeltable/tap/pxt

# Install from source and run the formula integration tests
brew install --build-from-source pixeltable/tap/pxt
brew test pixeltable/tap/pxt
```
