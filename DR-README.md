# Disaster Recovery Guide

This guide documents the disaster recovery procedure for the Docker Swarm cluster on CloudStack.

## Overview

The disaster recovery script (`dr.sh`) automates restoring worker data disks from snapshots stored in CloudStack. This is necessary when worker data disks are lost or corrupted.

## Prerequisites

### Required Software

- **bash** (shell)
- **jq** - JSON processing
- **terraform** - State and infrastructure management
- **CloudMonkey (cmk)** - CloudStack command-line client

### Environment Credentials

Before running the script, export the following environment variables:

```bash
export CLOUDSTACK_API_KEY="your-api-key"
export CLOUDSTACK_SECRET_KEY="your-secret-key"
export CLOUDSTACK_API_URL="https://painel-cloud.locaweb.com.br/client/api"  # Required
export AWS_ACCESS_KEY_ID="your-aws-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-aws-secret-access-key"
```

All variables above are required. Use your CloudStack provider's API URL (e.g., `https://painel-cloud.locaweb.com.br/client/api`).

### Cluster IDs (Source and Destination)

- **Source cluster (old)**: The previous cluster (possibly already destroyed) from which snapshots are taken.
- **Destination cluster (new/current)**: The cluster that will receive the recovered data. It must be created in a clean Terraform state that does not already contain the SOURCE cluster.

>⚠️ **Important**: If the SOURCE cluster is still present in Terraform state (for the same environment/backend), you cannot create the DESTINATION cluster in that same state using the standard process. Choose **one** of the following options:

- Destroy the SOURCE cluster first in that Terraform state.
- Create the DESTINATION cluster in a different environment (e.g., `dev-dr` or `prod-dr`). Each environment uses its own isolated state.
- Keep the same environment name, but reinitialize Terraform to use a different S3 backend (different bucket and/or a different key/prefix) so the DESTINATION cluster uses an isolated state.

Option 3 details (alternate backend while keeping the same ENV name):

- Edit `terraform/backend.tf` and set a different S3 `bucket` (and `region` if needed), following the instructions in the [Configure Backend](README.md#configure-backend) section of the README.

The DR process always restores data from the SOURCE (old) cluster to the DESTINATION (new) cluster. These IDs must be different.

```bash
# Identify the DESTINATION (new/current) cluster_id for a specific ENV
cd terraform
terraform init -backend-config="key=env/<ENV>/terraform.tfstate"
terraform output -raw cluster_id

# Use a DIFFERENT cluster_id than the one returned above for recovery
```

#### Identify the SOURCE (old) cluster_id

If you don't know the SOURCE (old) cluster_id, you can get it from existing snapshot tags.

The command below lists snapshots by worker name:

```bash
# Use the name of a worker in the cluster (example: mysql)
cmk list snapshots tags[0].key=name tags[0].value=<worker_name> \
  | jq '[.snapshot[]? | {id, name, created}] | sort_by(.created)'
```

And the command below returns the SOURCE (old) cluster_id for the snapshot ID obtained above:

```bash
cmk list tags resourceid=<snapshot_id> \
  | jq -r '.tag[] | select(.key=="cluster_id") | .value'
```

## Installation

1. Make the script executable:

```bash
chmod +x dr.sh
```

1. Verify dependencies are installed:

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install jq

# CentOS/RHEL
sudo yum install jq
```

### CloudMonkey installation

To install CloudMonkey, follow these steps:

1. **Open the official releases page**: [https://github.com/apache/cloudstack-cloudmonkey/releases](https://github.com/apache/cloudstack-cloudmonkey/releases)

2. **Download the appropriate build** for your OS:
   - Linux x86-64: `cmk.linux.x86-64`
   - Linux ARM64: `cmk.linux.arm64`
   - macOS x86-64: `cmk.darwin.x86-64`
   - macOS ARM64: `cmk.darwin.arm64`
   - Windows: `cmk.windows.x86-64.exe`

3. **Install the binary**:

   ```bash
   # Download (example for Linux x86-64)
   wget https://github.com/apache/cloudstack-cloudmonkey/releases/latest/download/cmk.linux.x86-64
   
   # Make executable
   chmod +x cmk.linux.x86-64
   
   # Move into PATH
   sudo mv cmk.linux.x86-64 /usr/local/bin/cmk
   
   # Verify installation
   cmk version
   ```

## Usage

### Basic syntax

```bash
./dr.sh -c <source_cluster_id> -e <env> [OPTIONS]
```

### Available options

- `-c, --cluster-id` - Source (old, snapshots) cluster ID (**REQUIRED**)
- `-e, --env` - Destination environment (dev, prod, etc.) (**REQUIRED**)
- `-d, --dry-run` - Run in dry-run mode (show commands without executing)
- `-h, --help` - Show help

### Usage examples

#### Normal recovery

```bash
# Recover data from the OLD cluster into the dev environment
./dr.sh -c cluster-old-xyz123 -e dev

# Recover data from the OLD cluster into the prod environment
./dr.sh -c cluster-old-xyz123 -e prod
```

#### Dry run

```bash
# Run in dry-run mode (no changes) targeting the dev environment
./dr.sh -c cluster-old-xyz123 -e dev --dry-run
```

**Recommendation**: Always run with `--dry-run` first to verify everything is correct before a real run.

## Recovery process

The script performs the following steps automatically:

### 1. Dependency checks

- Validates required environment variables (`CLOUDSTACK_API_KEY`, `CLOUDSTACK_SECRET_KEY`, `CLOUDSTACK_API_URL`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- Confirms presence of required tools (`jq`, `terraform`, `cmk`)
- Validates the Terraform directory
- Validates the provided environment (`-e`): `environments/<env>` directory and `environments/<env>/terraform.tfvars` file
- Validates that the `source cluster_id` is different from the `destination cluster_id` (queried from Terraform for the ENV)

### 2. CloudMonkey verification

- Checks that CloudMonkey is installed and available on PATH
- Shows installation instructions if not found

### 3. CloudMonkey configuration

- Configures the CloudStack API URL
- Sets API keys
- Tests connectivity

### 4. Stop VMs

- Identifies all cluster VMs
- Stops the VMs gracefully

### 5. Detach disks

- Locates worker data disks
- Detaches the disks from the VMs

### 6. Restore from snapshots

For each worker:

- Lists snapshots using the worker name tag (`name=<worker_name>`)
- Filters snapshots by the `source cluster_id`
- Sorts by creation date and selects the most recent
- Creates a new volume from the snapshot and attaches it to the worker VM

### 7. Update Terraform state

- Initializes Terraform with the S3 backend for the given `ENV`
- Removes old disk references from Terraform state (`terraform state rm 'cloudstack_disk.worker_data["<worker_name>"]'`)
- Imports the new disks into state (`terraform import ...`) using `-var-file=../environments/<env>/terraform.tfvars -var="env=<env>"`
- Keeps infrastructure and code in sync; VMs are restarted at the end of the process

## Script output

### Informational logs

The script prints colorized logs to make it easy to follow:

- **[INFO]** (blue) - General information
- **[SUCCESS]** (green) - Successful operations
- **[WARNING]** (yellow) - Warnings and dry-run mode
- **[ERROR]** (red) - Errors requiring attention

### Example output

```text
[INFO] Starting disaster recovery for cluster: cluster-old-xyz123
[WARNING] DRY-RUN MODE - No real changes will be made
[INFO] Checking dependencies...
[SUCCESS] Dependency checks passed
[INFO] Checking CloudMonkey...
[SUCCESS] CloudMonkey found
[INFO] Configuring CloudMonkey...
[SUCCESS] CloudMonkey configured successfully
[INFO] Destination (new) cluster: cluster-new-abc123
[INFO] Source (recovery) cluster: cluster-old-xyz123
[INFO] Getting VMs for destination cluster: cluster-new-abc123
[SUCCESS] Destination cluster VMs found: i-123-456-VM i-789-012-VM
...
[SUCCESS] Disaster recovery completed successfully!

Next steps:
  1. Run 'make plan ENV=<env>' to review changes
  2. Run 'make deploy ENV=<env>' to apply tags to the new worker data disks
  3. Verify your applications are healthy
```

## Post-recovery

After the script completes successfully:

### 1. Validate Terraform

```bash
make plan ENV=<env>
```

Confirm that the shown changes are correct (especially tags on the new disks).

### 2. Apply changes

```bash
make deploy ENV=<env>
```

Confirm applying tags to the new worker data disks.

### 3. Verify services

```bash
# Recommended: connect via Makefile (root user; default port 22001)
make ssh ENV=<env> [PORT=22001]
```

```bash
# On the manager, check Swarm and services
docker node ls
docker service ls
docker service logs <service-name>
```

### 4. Test applications

- Access the application, e.g., `https://portal.yourdomain.com`
- Access Traefik Dashboard: `https://traefik.yourdomain.com`
- Verify that data was restored correctly

## Troubleshooting

### Common errors

#### 1. CloudMonkey not installed

```text
[ERROR] CloudMonkey (cmk) is required but not installed.
```

**Solution**:

- Install CloudMonkey following the instructions at [https://github.com/apache/cloudstack-cloudmonkey/releases](https://github.com/apache/cloudstack-cloudmonkey/releases)
- Ensure the `cmk` binary is on PATH

#### 2. Invalid credentials

```text
[ERROR] CLOUDSTACK_API_KEY environment variable is required
[ERROR] CLOUDSTACK_SECRET_KEY environment variable is required
[ERROR] CLOUDSTACK_API_URL environment variable is required
[ERROR] AWS_ACCESS_KEY_ID environment variable is required for the S3 backend
[ERROR] AWS_SECRET_ACCESS_KEY environment variable is required for the S3 backend
```

**Solution**: Export the correct environment variables (CloudStack and AWS) before running the script.

#### 3. Invalid environment

```text
[ERROR] Environment directory not found: environments/<env>
[ERROR] terraform.tfvars file not found: environments/<env>/terraform.tfvars
```

**Solution**:

- Create the environment directory under `environments/<env>`
- Provide the `environments/<env>/terraform.tfvars` file with the required variables

#### 4. Cluster ID required

```text
[ERROR] The cluster_id is required for disaster recovery
```

**Solution**:

- Provide the `source cluster_id` using `-c` or `--cluster-id`
- This ID must be different from the `destination cluster_id` obtained from Terraform for the ENV
- For the `destination cluster_id`: `cd terraform && terraform init -backend-config="key=env/<env>/terraform.tfstate" && terraform output -raw cluster_id`
- For the `source cluster_id` from snapshots: see the section "Identify the SOURCE (old) cluster_id"

#### 5. Cluster VMs not found

```text
[ERROR] No VMs found for cluster: cluster-1-xyz
```

**Solution**:

- Verify the cluster ID is correct
- Confirm VMs have the appropriate tags
- If you specified a cluster ID manually, verify it is correct

#### 6. Snapshots not found

```text
[ERROR] No snapshot found for worker: mysql
```

**Solution**: Verify snapshots are being created automatically and that tags are correct.

#### 7. Connectivity issues

```text
[ERROR] Testing connectivity to CloudStack failed
```

**Solution**:

- Check network connectivity
- Confirm credentials are valid
- Test manually: `cmk list zones`

### Detailed logs

For additional debugging, run with verbose:

```bash
bash -x ./dr.sh --dry-run
```

### Manual recovery

If the script fails, you can run the commands manually following the process described in this guide (sections "Recovery process" and "Post-recovery").

## Known limitations

1. **Downtime**: VMs need to be stopped temporarily
2. **Snapshots**: Depends on the availability of recent snapshots
3. **Recovery order**: Workers are restored sequentially
