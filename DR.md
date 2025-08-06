# Distaster Recovery Procedure

## Shell Script

Make a shell script for disaster recovery. Document its usage in a DR-README.md file.

These are the steps that need to be followed:

- Test for existence of the `cmk` binary. If not:
  - Download the latest binary from <https://github.com/apache/cloudstack-cloudmonkey/releases>
  - Schematically:
  
  ```bash
    sudo wget <file link> -O /usr/local/bin/cmk
    sudo chmod +x /usr/local/bin/cmk
  ```

- Initialize `cmk` with the server details:

```bash
cmk set url https://painel-cloud.locaweb.com.br/client/api
cmk set apikey $CLOUDSTACK_API_KEY
cmk set secretkey $CLOUDSTACK_SECRET_KEY
```

- Test the connection:

```bash
cmk list zones
```

- Retrieve the list of VMs from the current `cluster_id` based on the following command (obtain the cluster ID from the Terraform output):

```bash
cmk list virtualmachines | jq -r '.virtualmachine[] | select(.tags[]? | .key=="cluster_id" and .value=="cluster-1-z1msjfjd") | .id'
```

- Stop the VMs:

```bash
cmk stop virtualmachine id=<id>
```

- Find all the worker disks from the current `cluster_id` based on the following command (obtain the cluster ID from the Terraform output):

```bash
cmk list volumes | jq -r '.volume[] | select(.tags[]? | .key=="cluster_id" and .value=="cluster-1-z1msjfjd") | select(.tags[]? | .key=="role" and .value=="worker") | .id'
```

- Detach the worker disks from the VMs:

```bash
cmk detach volume id=<id>
```

- For each worker VM:
  - Find its snapshots (substitute the name of the worker VM):

  ```bash
  cmk list snapshots | jq '.snapshot[] | select(.tags[]? | .key=="cluster_id" and .value=="cluster-1-z1msjfjd") | select(.name | test("^mysql_mysql-data")) | {id: .id, created: .created}' | jq -s 'sort_by(.created)'
  ```

  - Report the snapshots on the console
  - Retrieve the id of the most recent snapshot

  ```bash
  cmk list snapshots | jq '.snapshot[] | select(.tags[]? | .key=="cluster_id" and .value=="cluster-1-z1msjfjd") | select(.name | test("^mysql_mysql-data"))' | jq -sr 'sort_by(.created) | last | .id'
  ```

  - Restore the most recent snapshot of the respective VM and attach to it (timestamps shouldn't contain special characters, it can be for example `20250731-120000-0300`):

  ```bash
  cmk create volume name=<worker_name>-recovered-<timestamp> snapshotid=<id of snapshot> virtualmachineid=<id of worker vm>
  ```

  - Start the VMs:

  ```bash
  cmk start virtualmachine id=<id>
  ```

  - Remove the Terraform state associated with the former attached worker disk:

  ```bash
  terraform state rm 'cloudstack_disk.worker_data["<worker_name>"]'
  ```

  - Import the new worker disk into the Terraform state:

  ```bash
  terraform import 'cloudstack_disk.worker_data["<worker_name>"]' <id of worker disk>
  ```

- At the end, prompt the user to run `terraform plan` and `terraform apply` to apply tags to the new worker disks.

Add a dry-run option. If selected, print the commands that would be executed without actually executing them.
