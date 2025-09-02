# CloudStack Terraform & Ansible Swarm Template

This repository provides a template for deploying multiple, environment-specific Docker Swarm clusters on CloudStack using Terraform and Ansible.

## Features

- **Multi-Environment**: Manage `dev`, `prod`, or any other environment from a single repository.
- **Centralized Configuration**: All configuration for an environment (Terraform variables, secrets, stacks) is stored in one place.
- **Infrastructure as Code**: The entire infrastructure is defined with Terraform.
- **State Isolation**: Terraform state for each environment is stored in a separate file in a shared S3 backend, ensuring complete isolation.
- **Automated Configuration**: Ansible configures the Swarm cluster and deploys your application stacks.
- **CI/CD Ready**: Deploy any environment to CloudStack using GitHub Actions.
- **Simplified Workflow**: A `Makefile` provides simple, environment-aware commands.

## Project Structure

```text
.
├── environments/
│   ├── dev/
│   │   ├── terraform.tfvars
│   │   ├── secrets.yaml
│   │   └── stacks/
│   ├── prod/
│   │   ├── terraform.tfvars
│   │   ├── secrets.yaml
│   │   └── stacks/
│   └── example/
│       └── stacks/
│
├── ansible/
│   └── ... (core Ansible logic)
│
├── terraform/
│   └── ... (core Terraform logic)
│
└── Makefile
```

- `environments/`: Contains all environment-specific configurations.
  - `example/stacks/`: A collection of sample stacks to copy into your environments.
- `ansible/`: Contains the core, reusable Ansible playbook.
- `terraform/`: Contains the core, reusable Terraform configuration.

## Quick Start

### 1. Prerequisites

- Terraform >= 1.0
- Ansible >= 2.10
- CloudStack API Credentials & SSH Key Pair

### 2. Configure S3 Backend

This template uses an S3 bucket to store the Terraform state.

#### Bucket and IAM Policy Setup

1.  **Create an IAM User**:
    -   In your AWS account, navigate to the IAM service.
    -   Create a new user. Give it a descriptive name (e.g., `terraform-s3-backend-user`).
    -   For "Access type", select **Programmatic access**.
    -   Proceed to the permissions step.

2.  **Create an S3 Bucket**:
    -   Navigate to the S3 service.
    -   Create a new, private S3 bucket. Choose a globally unique name (e.g., `your-company-terraform-states`).

3.  **Create and Attach IAM Policy**:
    -   Go back to the IAM user you are creating.
    -   Choose **Attach existing policies directly**, then click **Create policy**.
    -   Go to the **JSON** tab and paste the following policy. Replace `<bucket_name>` with the name of the bucket you just created.

        ```json
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:*"
                    ],
                    "Resource": [
                        "arn:aws:s3:::<bucket_name>",
                        "arn:aws:s3:::<bucket_name>/*"
                    ]
                }
            ]
        }
        ```
    -   Review and create the policy. Give it a descriptive name (e.g., `TerraformS3BackendAccess`).
    -   Go back to the user creation screen, refresh the policy list, and attach your newly created policy to the user.

4.  **Save User Credentials**:
    -   Complete the user creation process.
    -   **Important**: On the final screen, you will see the user's **Access key ID** and **Secret access key**. Copy these and save them in a secure location. You will not be able to see the secret key again.

#### Backend and Credential Configuration

1.  **Configure Backend**: Edit `terraform/backend.tf` and set the `bucket` to the name of the S3 bucket you created and the `region` to match your bucket's AWS region.

2.  **Set Credentials**: Provide your S3 credentials.
    -   **Locally**: Export the Access Key ID and Secret Access Key you saved as environment variables.

        ```bash
        export AWS_ACCESS_KEY_ID="your-s3-access-key"
        export AWS_SECRET_ACCESS_KEY="your-s3-secret-key"
        ```

    -   **In CI/CD**: Add `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` to your GitHub repository secrets.

### 3. Configure Your First Environment

This template comes with a `dev` and `prod` environment. Let's configure `dev`.

1. **Customize Terraform Variables**: Edit `environments/dev/terraform.tfvars` with your settings, including a unique `cluster_name`.

2. **Define Application Stacks**: The `environments/dev/stacks/` directory determines which applications are deployed.

   **Base Infrastructure Stacks (Required)**: Always copy the numbered stacks from `environments/example/stacks/` as they contain the essential base infrastructure for the cluster:

    ```bash
    # Copy base infrastructure stacks (required for cluster operation)
    cp -r environments/example/stacks/00-socket-proxy environments/dev/stacks/
    cp -r environments/example/stacks/01-traefik environments/dev/stacks/
    cp -r environments/example/stacks/02-monitoring environments/dev/stacks/
    ```

   **Application Stacks (Optional)**: The other stacks (kafka, wordpress, etc.) are examples to serve as inspiration for your own applications. You can use your own container images or any other externally provided ones:

    ```bash
    # Example: Add optional application stacks
    cp -r environments/example/stacks/portainer environments/dev/stacks/
    cp -r environments/example/stacks/nextcloud-postgres-redis environments/dev/stacks/
    ```

   **Adapting Docker Compose Files**: If you need to adapt existing Docker Compose files for use with Docker Swarm, refer to the [Docker Compose Guide](DOCKER-COMPOSE-GUIDE.md) file for detailed conversion guidelines and best practices.

3. **Define Application Secrets**: The secrets required by your application stacks are automatically discovered from the `secrets:` block at the top level of each `docker-compose.yml` file.

   For local development, you must create a `environments/dev/secrets.yaml` file to provide the values for these secrets. This file is a simple key-value store. The file is ignored by Git, and the deployment playbook will fail if its permissions are not `600`.

   **Example `environments/dev/secrets.yaml`:**
   ```yaml
   mysql_root_password: "your-dev-db-password"
   wordpress_db_password: "your-dev-wp-password"
   ```

   **Important**: Always define secret names in lowercase, both in your stacks and in the `secrets.yaml` file.

   **Correct naming:**

   ```yaml
   mysql_root_password: "your-password"  # ✓ Correct
   ```

   **Incorrect naming:**

   ```yaml
   MYSQL_ROOT_PASSWORD: "your-password"  # ✗ Wrong
   MySQL_root_Password: "your-password"  # ✗ Wrong
   ```

4. **Set Infrastructure Credentials (Local)**: For local deployments, provide your infrastructure credentials as environment variables. Application secrets should be placed in the `secrets.yaml` file as described above.

    - **Locally**: Export infrastructure credentials as environment variables.

      ```bash
      # Infrastructure Credentials
      export CLOUDSTACK_API_URL="..."
      export CLOUDSTACK_API_KEY="..."
      export CLOUDSTACK_SECRET_KEY="..."
      export AWS_ACCESS_KEY_ID="..."
      export AWS_SECRET_ACCESS_KEY="..."
      ```

      For private container registries, you can also optionally provide your credentials:

      ```bash
      export DOCKER_REGISTRY_URL="your-registry-url"
      export DOCKER_REGISTRY_USERNAME="your-username"
      export DOCKER_REGISTRY_PASSWORD="your-password-or-token"
      ```

    - **In CI/CD**: Add them to your GitHub repository secrets.

### 4. Deploy

Use the `Makefile` to deploy your environment. The `ENV` variable specifies which environment to target. It defaults to `dev`.

```bash
# Deploy the 'dev' environment
make deploy

# Deploy the 'prod' environment
make deploy ENV=prod
```

This command will automatically use the correct S3 state file path and configuration files for the specified environment.

## CI/CD with GitHub Actions

This project uses GitHub Actions to automate deployments. The workflow is configured to use **GitHub Environments**, which allows you to define distinct sets of secrets for each of your environments (e.g., `dev`, `prod`).

**⚠️ Important**: GitHub Environments are only available for public repositories or private repositories on paid GitHub plans (Pro, Team, or Enterprise). If you're using a free GitHub plan with a private repository, you'll need to make your repository public to use environments. This shouldn't be a security concern as your secrets remain protected and are not accessible through the public repository.

### Configuration

1.  **Create Environments**: In your GitHub repository, go to **Settings > Environments**. Create an environment for each of your deployment targets (e.g., `dev`, `prod`). The names must match the directory names under `environments/`.

2.  **Add Repository-Level Secrets**: Go to **Settings > Secrets and variables > Actions** and add the infrastructure credentials as repository secrets. These are shared across all environments:

    **Required Repository Secrets:**
    -   `CLOUDSTACK_API_URL`
    -   `CLOUDSTACK_API_KEY`
    -   `CLOUDSTACK_SECRET_KEY`
    -   `AWS_ACCESS_KEY_ID`
    -   `AWS_SECRET_ACCESS_KEY`
    -   `DOCKER_REGISTRY_URL` (optional)
    -   `DOCKER_REGISTRY_USERNAME` (optional)
    -   `DOCKER_REGISTRY_PASSWORD` (optional)

3.  **Add Environment-Specific Secrets**: For each environment you created, add the application-specific secrets discovered in your `docker-compose.yml` files.

    **Note**: GitHub will automatically convert secret names to uppercase in the UI, but the deployment process will convert them back to lowercase to match your `secrets.yaml` format. For example, if you define `mysql_root_password` in your stack, GitHub will display it as `MYSQL_ROOT_PASSWORD`, but it will be correctly applied as `mysql_root_password` during deployment.

    **Environment Secrets (per environment):**
    -   Any application secrets (e.g., `mysql_root_password`, `nextcloud_admin_password`, etc.)

### Running the Workflow

1.  Go to the **Actions** tab in your GitHub repository.
2.  Select the **Deploy Infrastructure** or **Destroy Infrastructure** workflow.
3.  Click **Run workflow**, enter the name of the environment you wish to target, and click **Run workflow**.

The pipeline will deploy the selected environment using the secrets you've configured for that specific GitHub Environment.

## Makefile Commands

- `make deploy ENV=prod`: Deploy the `prod` environment.
- `make plan ENV=prod`: Show the Terraform execution plan for the `prod` environment.
- `make destroy ENV=prod`: Destroy the `prod` environment.
- `make ssh ENV=prod`: SSH into the first manager of the `prod` environment.
