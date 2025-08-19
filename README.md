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
│   └── prod/
│       ├── terraform.tfvars
│       ├── secrets.yaml
│       └── stacks/
│
├── ansible/
│   ├── example_stacks/
│   └── ... (core Ansible logic)
│
├── terraform/
│   └── ... (core Terraform logic)
│
└── Makefile
```

- `environments/`: Contains all environment-specific configurations.
- `ansible/`: Contains the core, reusable Ansible playbook.
  - `example_stacks/`: A collection of sample stacks to copy into your environments.
- `terraform/`: Contains the core, reusable Terraform configuration.

## Quick Start

### 1. Prerequisites

- Terraform >= 1.0
- Ansible >= 2.10
- CloudStack API Credentials & SSH Key Pair

### 2. Configure S3 Backend

This template uses an S3 bucket to store the Terraform state.

1. **Create an S3 Bucket**: Create an S3-compatible bucket to store your Terraform state files.
2. **Configure Backend**: Edit `terraform/backend.tf` and set the `bucket`, `region`, and `endpoint` for your S3 provider.
3. **Set Credentials**: Provide your S3 credentials.
    - **Locally**: Export them as environment variables.

      ```bash
      export AWS_ACCESS_KEY_ID="your-s3-access-key"
      export AWS_SECRET_ACCESS_KEY="your-s3-secret-key"
      ```

    - **In CI/CD**: Add `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` to your GitHub repository secrets.

### 3. Configure Your First Environment

This template comes with a `dev` and `prod` environment. Let's configure `dev`.

1. **Customize Terraform Variables**: Edit `environments/dev/terraform.tfvars` with your settings, including a unique `cluster_name`.

2. **Define Application Stacks**: The `environments/dev/stacks/` directory determines which applications are deployed. Copy stacks from `ansible/example_stacks/` into this directory to select them for deployment.

    ```bash
    # Example: Deploy Traefik and Portainer to the 'dev' environment
    cp -r ansible/example_stacks/00-networks environments/dev/stacks/
    cp -r ansible/example_stacks/01-traefik environments/dev/stacks/
    cp -r ansible/example_stacks/portainer environments/dev/stacks/
    ```

3. **Define Application Secrets**: Edit `environments/dev/secrets.yaml` to list the Docker secrets your applications require. This file maps secret names to the environment variables that will provide their values.

4. **Set Secret Values**: Provide the actual secret values.
    - **Locally**: Export them as environment variables.

      ```bash
      export CLOUDSTACK_API_URL="..."
      export CLOUDSTACK_API_KEY="..."
      export CLOUDSTACK_SECRET_KEY="..."
      export AWS_ACCESS_KEY_ID="..."
      export AWS_SECRET_ACCESS_KEY="..."
      export MYSQL_ROOT_PASSWORD="your-dev-db-password"
      export WORDPRESS_DB_PASSWORD="your-dev-db-password"
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

- Go to the **Actions** tab in your GitHub repository.
- Select the **Deploy Infrastructure** workflow.
- Click **Run workflow**, choose the environment (`dev` or `prod`), and click **Run workflow**.

The pipeline will deploy the selected environment using the secrets you've configured in your repository's **Settings > Secrets and variables > Actions**. For every `env_var` in your environment's `secrets.yaml`, you must create a corresponding secret in GitHub. You must also provide your `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` as secrets.

**Required GitHub Secrets:**

- `CLOUDSTACK_API_URL`
- `CLOUDSTACK_API_KEY`
- `CLOUDSTACK_SECRET_KEY`
- Any application secrets defined in `ansible/secrets/secrets.yaml` (e.g., `MYSQL_ROOT_PASSWORD`, `WORDPRESS_DB_PASSWORD`).
- `DOCKER_REGISTRY_URL` (optional)
- `DOCKER_REGISTRY_USERNAME` (optional)
- `DOCKER_REGISTRY_PASSWORD` (optional)

## Makefile Commands

- `make deploy ENV=prod`: Deploy the `prod` environment.
- `make plan ENV=prod`: Show the Terraform execution plan for the `prod` environment.
- `make destroy ENV=prod`: Destroy the `prod` environment.
- `make ssh ENV=prod`: SSH into the first manager of the `prod` environment.
