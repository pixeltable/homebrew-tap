# Pixeltable Homebrew Tap (`pixeltable/tap`)

Official Homebrew Tap for [Pixeltable](https://github.com/pixeltable/pixeltable) — the declarative multimodal AI data engine for tables, computed columns, embedding search, agents, and FastAPI microservices.

[![CI Verification](https://github.com/pixeltable/homebrew-tap/actions/workflows/ci.yml/badge.svg)](https://github.com/pixeltable/homebrew-tap/actions/workflows/ci.yml)
[![Update Formula](https://github.com/pixeltable/homebrew-tap/actions/workflows/update-formula.yml/badge.svg)](https://github.com/pixeltable/homebrew-tap/actions/workflows/update-formula.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

---

## Quickstart

Install the `pxt` CLI globally on macOS with a single command:

```bash
brew install pixeltable/tap/pxt
```

Or add the tap first and then install:

```bash
brew tap pixeltable/tap
brew install pxt
```

Verify your installation:

```bash
pxt --version
pxt --help
```

---

## Features

- **PEP 668 Compliant**: Encapsulated in an isolated Python 3.12 virtual environment under Homebrew's `libexec`. Only the `pxt` executable is symlinked to your `PATH` (`/opt/homebrew/bin/pxt` on Apple Silicon, `/usr/local/bin/pxt` on Intel).
- **Embedded Database Pre-configured**: Shipped with pre-compiled platform wheels (`pixeltable-pgserver`), bundling PostgreSQL and the `pgvector` extension with zero compilation required.
- **Microservices Ready**: Includes `[serve]` extra (`fastapi[standard]`) by default, enabling instant local REST service hosting via `pxt service`.

---

## Getting Started with `pxt`

### 1. Initialize a Project
Create a new Pixeltable project workspace:
```bash
mkdir my-ai-project && cd my-ai-project
pxt init
```

### 2. Inspect Database & Catalog Health
Verify your local embedded PostgreSQL database and tables:
```bash
pxt status
pxt ls
```

### 3. Declarative Schema & Services
Check, diff, and update declarative application schemas or serve endpoints:
```bash
# Check declarative app schema
pxt schema check app.py

# Apply declarative schema updates
pxt schema update app.py my_app

# Run a local FastAPI microservice endpoint defined in your TableModel
pxt service run app.py:my_service
```

---

## Daemon Architecture & Lifecycle

`pxt` uses an autonomous, project-aware background daemon (`127.0.0.1:22089`) to serve CLI commands, monitor tables, and coordinate database connections.

The daemon is **self-managed**:
- `pxt` automatically launches the daemon in the background when needed.
- If you switch project directories, `pxt` transparently shifts the daemon scope to the nearest `pixeltable.toml` project root.

To manually inspect or manage the daemon lifecycle:
```bash
# Inspect daemon PID, port, and health
pxt daemon status

# Start, stop, or restart daemon
pxt daemon start
pxt daemon stop
pxt daemon restart
```

> **Why not `brew services` / `launchd`?**  
> `pxt` dynamically re-targets its background daemon to active project directories. System supervision through `launchd` pins a fixed working directory (typically `$HOME`), conflicting with project-level runtime isolation. Native self-management ensures project-isolated execution without zombie processes.

---

## Alternative Tool Runners

If you operate in environments where Homebrew is not available or prefer dedicated Python CLI managers:

```bash
# Ultra-fast isolated runner with uv
uv tool install "pixeltable[serve]"

# Standard Python application installer
pipx install "pixeltable[serve]"
```

---

## License

This tap and the Pixeltable CLI are distributed under the [Apache-2.0 License](LICENSE).
