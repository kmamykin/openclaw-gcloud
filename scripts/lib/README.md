# Shell Script Library

Reusable utilities for OpenClaw GCP deployment scripts.

## Files

### path.sh
Path and directory resolution utilities.

**Functions:**
- `get_project_root()` - Returns the project root directory (parent of scripts/)

**Example:**
```bash
source "${SCRIPT_DIR}/lib/path.sh"
PROJECT_ROOT="$(get_project_root)"
cd "$PROJECT_ROOT"
```

### env.sh
Environment variable loading utilities.

**Functions:**
- `load_env()` - Load .env file with basic variable export (sources both .env files)

**Example:**
```bash
source "${SCRIPT_DIR}/lib/env.sh"
load_env || { echo "ERROR: Failed to load .env" >&2; exit 1; }
```

### validation.sh
Variable validation utilities.

**Functions:**
- `require_vars VAR1 VAR2 ...` - Validate that required variables are set

**Example:**
```bash
source "${SCRIPT_DIR}/lib/validation.sh"
require_vars VM_NAME GCP_ZONE GCP_PROJECT_ID || exit 1
```

## Usage Pattern

Standard pattern for scripts using these libraries:

```bash
#!/bin/bash
set -e

# Get script directory (still needed for sourcing libraries)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/path.sh"
source "${SCRIPT_DIR}/lib/env.sh"
source "${SCRIPT_DIR}/lib/validation.sh"

# Get project root and change to it
PROJECT_ROOT="$(get_project_root)"
cd "$PROJECT_ROOT"

# Load environment
load_env || { echo "ERROR: Failed to load .env" >&2; exit 1; }

# Validate required variables
require_vars VM_NAME GCP_ZONE || exit 1

# Rest of script...
```
