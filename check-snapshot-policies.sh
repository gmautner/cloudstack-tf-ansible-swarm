#!/bin/bash

# CloudStack Snapshot Policies Checker
# 
# This script checks if there are any snapshot policies for a given volume ID
# using the CloudMonkey (cmk) binary.
#
# Prerequisites:
# - CloudMonkey (cmk) must be installed and available in PATH
# - CloudMonkey must be configured with proper API credentials:
#   cmk set url <cloudstack-api-url>
#   cmk set apikey <your-api-key>
#   cmk set secretkey <your-secret-key>
# - jq must be installed for JSON processing
#
# Usage: ./check-snapshot-policies.sh <volume_id>
#
# CloudMonkey Installation Instructions:
# 1. Download from: https://github.com/apache/cloudstack-cloudmonkey/releases
# 2. Choose the appropriate binary for your platform:
#    - Linux x86-64: cmk.linux.x86-64
#    - Linux ARM64: cmk.linux.arm64
#    - macOS x86-64: cmk.darwin.x86-64
#    - macOS ARM64: cmk.darwin.arm64
#    - Windows: cmk.windows.x86-64.exe
# 3. Make it executable: chmod +x cmk.*
# 4. Move to PATH: sudo mv cmk.* /usr/local/bin/cmk
# 5. Test: cmk version

set -euo pipefail

# Check if volume ID argument is provided
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <volume_id>"
    echo "Example: $0 5265f4ed-169e-4e91-954e-97cf6798a093"
    exit 1
fi

volume_id="$1"

# Validate volume ID format (basic UUID validation)
if [[ ! "$volume_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "Error: Invalid volume ID format. Expected UUID format."
    echo "Example: 5265f4ed-169e-4e91-954e-97cf6798a093"
    exit 1
fi

# Check if cmk is available
if ! command -v cmk &> /dev/null; then
    echo "Error: CloudMonkey (cmk) is not installed or not in PATH."
    echo "Please install CloudMonkey following the instructions above."
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed or not in PATH."
    echo "Please install jq: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
    exit 1
fi

echo "Checking snapshot policies for volume: $volume_id"

# Query snapshot policies and check if any exist
# jq -e exits with code 0 if expression is true, 1 if false
if cmk list snapshotpolicies volumeid="$volume_id" | jq -e '.count > 0' >/dev/null 2>&1; then
    echo "✓ Snapshot policies found for volume $volume_id"
    exit 0
else
    # No output needed when not found, just exit with error code
    exit 1
fi