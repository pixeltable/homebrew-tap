# Pixeltable Homebrew Tap (`pixeltable/tap`)

Official Homebrew Tap for [Pixeltable](https://github.com/pixeltable/pixeltable) — the declarative multimodal AI data engine for tables, computed columns, embedding search, agents, and FastAPI microservices.

[![CI Verification](https://github.com/pixeltable/homebrew-tap/actions/workflows/ci.yml/badge.svg)](https://github.com/pixeltable/homebrew-tap/actions/workflows/ci.yml)
[![brew test-bot](https://github.com/pixeltable/homebrew-tap/actions/workflows/tests.yml/badge.svg)](https://github.com/pixeltable/homebrew-tap/actions/workflows/tests.yml)
[![Update Formula](https://github.com/pixeltable/homebrew-tap/actions/workflows/update-formula.yml/badge.svg)](https://github.com/pixeltable/homebrew-tap/actions/workflows/update-formula.yml)
[![PyPI version](https://img.shields.io/pypi/v/pixeltable.svg)](https://pypi.org/project/pixeltable/)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

---

## Quickstart

### Installation

Install the `pxt` CLI globally on macOS with a single command:

```bash
brew install pixeltable/tap/pxt
```

Or add the tap first and then install:

```bash
brew tap pixeltable/tap
brew install pxt
```

### Upgrading

To upgrade `pxt` to the latest release:

```bash
brew update
brew upgrade pixeltable/tap/pxt
```

### Verify Installation

```bash
pxt --version
pxt --help
```

### Platform Support

This tap targets **macOS only**, on both Apple Silicon and Intel. CI builds and tests
the formula on `macos-14`, `macos-15`, and `macos-15-intel`. The `brew test-bot` leg on
Ubuntu checks tap syntax only; the formula is not built there and Linux is not supported.

The problem this tap solves is PEP 668, which blocks `pip install` against a Homebrew
Python on macOS. Linux, WSL, and Windows users have no such block and are better served
by a Python tool runner:

```bash
uv tool install "pixeltable[serve]"
# or
pipx install "pixeltable[serve]"
```

### Finding the Tap

`brew search` only indexes `homebrew/core` and `homebrew/cask`, plus taps already present
on your machine, so searching for `pixeltable` will not surface this tap before you add it.
Install by its full name, or `brew tap pixeltable/tap` first:

```bash
brew install pixeltable/tap/pxt
```

---

## Features & Architecture

- **PEP 668 Compliant Virtual Environment**: Encapsulated in an isolated Python 3.12 virtual environment under Homebrew's `libexec`. Only the `pxt` executable is symlinked to your `PATH` (`/opt/homebrew/bin/pxt` on Apple Silicon, `/usr/local/bin/pxt` on Intel), keeping your global Python environment pristine.
- **Embedded Database Pre-configured**: Shipped with pre-compiled platform wheels (`pixeltable-pgserver`), bundling PostgreSQL and the `pgvector` extension with zero system PostgreSQL configuration required.
- **Mach-O Relocation Hardened**: Automatically patches vendored native dylibs (e.g. `psycopg_binary`, Pillow) using `@rpath` references to ensure strict compatibility with Homebrew's bottle relocation and macOS sandboxing.
- **Microservices Ready**: Bundles the `[serve]` extra (`fastapi[standard]`) out of the box, enabling immediate local REST microservice hosting via `pxt service`.

---

## Getting Started with `pxt`

### 1. Initialize a Project Workspace
Create a new project directory and initialize a Pixeltable workspace:
```bash
mkdir my-ai-project && cd my-ai-project
pxt init
```
This generates `pixeltable.toml` in your project root.

### 2. Inspect Database & Catalog Health
Verify your embedded database connection, storage directory, and table catalog:
```bash
pxt status
pxt ls
```

### 3. Declarative Schema & Services
Check, diff, and update declarative application schemas or serve endpoints:
```bash
# Preview sample schema and service definitions
pxt schema example --brief
pxt service example --out app.py

# Check declarative app schema against catalog
pxt schema check app.py

# Apply declarative schema updates
pxt schema update app.py my_app

# Run the FastAPI services your TableModel file declares, in the background
pxt service update app.py my_app
```

---

## Optional AI Packages

The formula installs `pixeltable[serve]` only. Many `pxt.functions.*` helpers
need optional packages, which you can add to the formula's virtualenv with the
`pxt-pip` shim:

```bash
pxt-pip install openai        # pxt.functions.openai
pxt-pip install tiktoken      # token counting in document_splitter
pxt-pip install spacy         # document_splitter(separators="sentence")
pxt-pip install scenedetect   # pxt.functions.video scene detection

# spaCy also needs a language model, e.g.:
"$(brew --prefix)/opt/pxt/libexec/bin/python" -m spacy download en_core_web_sm
```

Missing a package? The error message names it: install it with `pxt-pip install <name>`.

Extras live inside the formula's keg, so `brew reinstall` or an upgrade removes
them. Re-run `pxt-pip install` afterwards.

---

## Daemon Architecture & Lifecycle

`pxt` utilizes an autonomous, project-aware background daemon (`127.0.0.1:22089`) to handle CLI operations, monitor tables, and manage database connection pooling.

The daemon is **self-managed**:
- `pxt` automatically launches the daemon in the background when needed.
- When switching directories, `pxt` dynamically shifts daemon scope to the nearest `pixeltable.toml` project root.

### Daemon Lifecycle Controls
```bash
# Inspect daemon PID, port, and health
pxt daemon status

# Start, stop, or restart daemon
pxt daemon start
pxt daemon stop
pxt daemon restart

# Force-stop the daemon on the configured port, even if it is serving requests
pxt daemon stop -f
```

> **Why not `brew services` / `launchd`?**  
> `pxt` dynamically shifts context to the active project directory where commands are run. Supervised services through `launchd` pin a fixed working directory (typically `$HOME`), breaking project-level runtime isolation. Native self-management ensures project-isolated execution without orphaned processes.

---

## Troubleshooting & FAQ

### Issue: `pxt` command points to an unexpected Python version or old binary
If you have multiple Python environments installed (such as Conda, pyenv, or virtual environments), an earlier entry in your `PATH` might shadow Homebrew's executable:

```bash
# Check which binary is resolved first
which -a pxt
```

**Fix:** Ensure Homebrew's `bin` directory (`/opt/homebrew/bin` on Apple Silicon, `/usr/local/bin` on Intel) is ordered ahead of other package managers in your shell profile (`~/.zshrc` or `~/.bashrc`):
```bash
export PATH="/opt/homebrew/bin:$PATH"
```
Alternatively, invoke the Homebrew-installed binary directly:
```bash
"$(brew --prefix)/bin/pxt" --version
```

### Issue: Port conflict on default port `22089`
If port 22089 is used by another service, override the default port using the `PXT_PORT` environment variable:
```bash
export PXT_PORT=22099
pxt daemon restart
```

### Issue: Custom database storage location
By default, Pixeltable stores local database state in `~/.pixeltable`. You can configure a custom location using `PIXELTABLE_HOME`:
```bash
export PIXELTABLE_HOME="/path/to/custom/pixeltable_data"
pxt status
```

### Issue: Daemon unresponsive or stale lock
If the background daemon fails to respond:
```bash
# Force-stop the daemon on the configured port, even if it is serving requests
pxt daemon stop -f

# Verify status
pxt daemon status

# Re-launch
pxt daemon start
```

### Issue: Broken virtualenv or library link
If Python was updated or linked dylibs were moved:
```bash
brew reinstall pixeltable/tap/pxt
brew test pixeltable/tap/pxt
```

---

## Maintainer Guide

Formula updates are automated: a `repository_dispatch` from `pixeltable/pixeltable` on
release, a 6-hourly PyPI poll as a safety net, and a manual `workflow_dispatch`. The
updater bumps the wheel URL and SHA-256, revalidates the formula, and pushes to `main`.

Setup, the dispatch snippets for the core repo, and the local check commands live in one
place so they cannot drift apart:

👉 **[Release Automation Guide](docs/release-automation.md)**

---

## Alternative Tool Runners

If you work in environments where Homebrew is not available or prefer dedicated Python application runners:

```bash
# Isolated runner with uv
uv tool install "pixeltable[serve]"

# Standard Python application installer
pipx install "pixeltable[serve]"
```

---

## License

This tap and the Pixeltable CLI are distributed under the [Apache-2.0 License](LICENSE).
