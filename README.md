# CloudStack Terraform & Ansible Swarm Template

This repository provides a template for deploying multiple, environment-specific Docker Swarm clusters on CloudStack using Terraform and Ansible.

## Features

- **Multi-Environment**: Manage `dev`, `prod`, or any other environment from a single repository.
- **Centralized Configuration**: All configuration for an environment (Terraform variables, secrets, stacks) is stored in one place.
- **Infrastructure as Code**: The entire infrastructure is defined with Terraform.
- **State Isolation**: Terraform state for each environment is stored in a separate local file, ensuring complete isolation.
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

### 2. Configure Your First Environment

This template comes with a `dev` and `prod` environment. Let's configure `dev`.

1. **Customize Terraform Variables**: Edit `environments/dev/terraform.tfvars` with your settings, including a unique `cluster_name`.

2. **Define Application Stacks**: The `environments/dev/stacks/` directory determines which applications are deployed. Copy stacks from `environments/example/stacks/` into this directory to select them for deployment.

    ```bash
    # Example: Deploy Traefik and Portainer to the 'dev' environment
    cp -r environments/example/stacks/00-networks environments/dev/stacks/
    cp -r environments/example/stacks/01-traefik environments/dev/stacks/
    cp -r environments/example/stacks/portainer environments/dev/stacks/
    ```

3. **Define Application Secrets**: The secrets required by your application stacks are automatically discovered from the `secrets:` block at the top level of each `docker-compose.yml` file.

   For local development, you must create a `environments/dev/secrets.yaml` file to provide the values for these secrets. This file is a simple key-value store. The file is ignored by Git, and the deployment playbook will fail if its permissions are not `600`.

   **Example `environments/dev/secrets.yaml`:**
   ```yaml
   mysql_root_password: "your-dev-db-password"
   wordpress_db_password: "your-dev-wp-password"
   ```

4. **Set Infrastructure Credentials (Local)**: For local deployments, provide your infrastructure credentials as environment variables. Application secrets should be placed in the `secrets.yaml` file as described above.

    - **Locally**: Export infrastructure credentials as environment variables.

      ```bash
      # Infrastructure Credentials
      export CLOUDSTACK_API_URL="..."
      export CLOUDSTACK_API_KEY="..."
      export CLOUDSTACK_SECRET_KEY="..."
      ```

      For private container registries, you can also optionally provide your credentials:

      ```bash
      export DOCKER_REGISTRY_URL="your-registry-url"
      export DOCKER_REGISTRY_USERNAME="your-username"
      export DOCKER_REGISTRY_PASSWORD="your-password-or-token"
      ```

    - **In CI/CD**: Add them to your GitHub repository secrets.

### 3. Deploy

Use the `Makefile` to deploy your environment. The `ENV` variable specifies which environment to target. It defaults to `dev`.

```bash
# Deploy the 'dev' environment
make deploy

# Deploy the 'prod' environment
make deploy ENV=prod
```

This command will automatically use the correct state file path and configuration files for the specified environment.

## CI/CD with GitHub Actions

This project uses GitHub Actions to automate deployments. The workflow is configured to use **GitHub Environments**, which allows you to define distinct sets of secrets for each of your environments (e.g., `dev`, `prod`).

### Configuration

1.  **Create Environments**: In your GitHub repository, go to **Settings > Environments**. Create an environment for each of your deployment targets (e.g., `dev`, `prod`). The names must match the directory names under `environments/`.
2.  **Add Secrets**: For each environment you create, add the required secrets. These include your CloudStack and S3 credentials, as well as any application-specific secrets discovered in your `docker-compose.yml` files.

    **Required Environment Secrets:**
    -   `CLOUDSTACK_API_URL`
    -   `CLOUDSTACK_API_KEY`
    -   `CLOUDSTACK_SECRET_KEY`
    -   Any application secrets (e.g., `mysql_root_password`).
    -   `DOCKER_REGISTRY_URL` (optional)
    -   `DOCKER_REGISTRY_USERNAME` (optional)
    -   `DOCKER_REGISTRY_PASSWORD` (optional)

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
