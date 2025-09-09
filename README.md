# CloudStack Terraform & Ansible Swarm Template

**🇧🇷 Leia este README em Português (Brasil): [README.pt-BR.md](README.pt-BR.md)**

## Table of Contents

- [CloudStack Terraform \& Ansible Swarm Template](#cloudstack-terraform--ansible-swarm-template)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Project Structure](#project-structure)
  - [Quick Start](#quick-start)
    - [Prerequisites](#prerequisites)
    - [Fork this repository](#fork-this-repository)
    - [Configure S3 Backend](#configure-s3-backend)
      - [Create an S3 Bucket](#create-an-s3-bucket)
      - [Create an IAM User](#create-an-iam-user)
      - [Create and Attach IAM Policy](#create-and-attach-iam-policy)
      - [Save User Credentials](#save-user-credentials)
    - [Configure Your First Environment](#configure-your-first-environment)
      - [Customize Terraform Variables](#customize-terraform-variables)
      - [Configure Backend](#configure-backend)
      - [Define Application Stacks](#define-application-stacks)
      - [Define Application Secrets](#define-application-secrets)
      - [Define workers](#define-workers)
      - [Configure Public IPs (Optional)](#configure-public-ips-optional)
        - [Example: Exposing Portainer directly](#example-exposing-portainer-directly)
      - [Set Infrastructure Credentials (Local)](#set-infrastructure-credentials-local)
    - [Deploy](#deploy)
    - [Configure DNS](#configure-dns)
  - [CI/CD with GitHub Actions](#cicd-with-github-actions)
    - [Configuration](#configuration)
      - [Create Environments](#create-environments)
      - [Add Repository-Level Secrets](#add-repository-level-secrets)
      - [Add Environment-Specific Secrets](#add-environment-specific-secrets)
    - [Running the Workflow](#running-the-workflow)
  - [Example Makefile Commands](#example-makefile-commands)

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

### Prerequisites

- Terraform >= 1.0
- Ansible >= 2.10
- CloudStack API Credentials
- An AWS account
- A [Slack webhook](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/) for receiving alerts (use the "app from scratch" option when following the link)
- A DNS Zone that you can manage, for creating DNS records for your cluster, e.g. `infra.example.com`

### Fork this repository

Fork this repository to your own GitHub account.

### Configure S3 Backend

This template uses an S3 bucket to store the Terraform state.

#### Create an S3 Bucket

- Navigate to the S3 service.
- Create a new, private S3 bucket, accepting default settings. Choose a globally unique name (e.g., `your-company-terraform-states`).
- Take note of the bucket name and region.

#### Create an IAM User

- Navigate to the IAM service.
- Create a new user. Give it a descriptive name (e.g., `terraform-s3-backend-user`).
- In "Set permissions", select **Attach policies directly**, then click **Create policy**.

#### Create and Attach IAM Policy

- Go to the **JSON** tab and paste the following policy. Replace `your-company-terraform-states` with the name of the bucket you just created.

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
                "arn:aws:s3:::your-company-terraform-states",
                "arn:aws:s3:::your-company-terraform-states/*"
            ]
        }
    ]
}
```

- Review and create the policy. Give it a descriptive name (e.g., `TerraformS3BackendAccess`).
- Go back to the user creation screen, refresh the policy list, and attach your newly created policy to the user.

#### Save User Credentials

- Complete the user creation process and click on **View user**.
- On the summary screen, click on **Create access key** with use case **Command Line Interface (CLI)**. This will show you the **Access key** and **Secret access key**. Copy these and save them in a secure location.

### Configure Your First Environment

Let's configure a new environment called `dev`.

#### Customize Terraform Variables

Create the environment directory and copy the terraform.tfvars file:

```bash
# Create the environment directory first
mkdir -p environments/dev/

# Copy and customize the terraform variables
cp environments/example/terraform.tfvars environments/dev/terraform.tfvars
```

Then customize `environments/dev/terraform.tfvars` with your settings, including a unique `cluster_name` and a `base_domain` that you control for DNS management.

#### Configure Backend

Edit `terraform/backend.tf` and set the `bucket` to the name of the S3 bucket you created and the `region` to match your bucket's AWS region.

#### Define Application Stacks

The `environments/dev/stacks/` directory determines which applications are deployed. Each stack lives in a separate directory with a Docker Swarm compatible `docker-compose.yml` file and other files referenced by it.

**Base Infrastructure Stacks (Required)**: Always copy the numbered stacks from `environments/example/stacks/` as they contain the essential base infrastructure for the cluster:

```bash
# Create the stacks directory first
mkdir -p environments/dev/stacks/

# Copy base infrastructure stacks (required for cluster operation)
cp -r environments/example/stacks/00-socket-proxy environments/dev/stacks/
cp -r environments/example/stacks/01-traefik environments/dev/stacks/
cp -r environments/example/stacks/02-monitoring environments/dev/stacks/
```

**Application Stacks (Optional)**: The other stacks (kafka, wordpress, etc.) are examples to serve as inspiration for your own applications. You can use your own container images or any other externally provided ones:

```bash
# Example: Add optional application stacks
cp -r environments/example/stacks/wordpress-mysql environments/dev/stacks/
cp -r environments/example/stacks/nextcloud-postgres-redis environments/dev/stacks/
```

**Creating or adapting Docker Swarm Compose Files**: If you need to create Docker Compose files or adapt existing ones for use with Docker Swarm, refer to the [Docker Compose Guide](DOCKER-COMPOSE-GUIDE.md) file for detailed instructions. (🧠 **AI Tip**: Point your AI assistant to this guide for instant Docker Swarm expertise!)

#### Define Application Secrets

The secrets required by your stacks are automatically discovered from the `secrets:` block at the top level of each `docker-compose.yml` file. This includes secrets needed by the base infrastructure stacks (Traefik and monitoring) as well as your application stacks.

For local development, you must create an `environments/dev/secrets.yaml` file to provide the values for these secrets. This file is a simple key-value store and should be set with `chmod 600` permissions. The file is ignored by Git, and the deployment playbook will fail if the permissions are not correctly set.

```bash
# Set correct permissions for the secrets file
chmod 600 environments/dev/secrets.yaml
```

> 💡 **Remark**: in CI/CD, the secrets are passed directly to the playbook as environment-level secrets, bypassing the need for the `secrets.yaml` file (see more in the [CI/CD section](#cicd-with-github-actions)).

**Required secrets for base infrastructure stacks:**

- `traefik_basicauth`: HTTP Basic Auth password for accessing Traefik dashboard and other protected services
- `slack_api_url`: Slack webhook URL for receiving monitoring alerts

**Example `environments/dev/secrets.yaml`:**

```yaml
# Base infrastructure secrets (required)
traefik_basicauth: 'admin:$2y$05$Oi938xgiKuRIORHWv1KuBuGASePs1DjtNV3pux86SgOj.7h47W66u'
slack_api_url: "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"

# Application secrets (as needed for your stacks)
mysql_root_password: "your-dev-db-password"
wordpress_db_password: "your-dev-wp-password"
```

> 💡 **Tip**: You can generate the `traefik_basicauth` value using: `htpasswd -nB admin`
>
> ⚠️ **Important**: Always define secret names in lowercase, both in your stacks and in the `secrets.yaml` file.

**Correct naming:**

```yaml
mysql_root_password: "your-password"  # ✓ Correct
```

**Incorrect naming:**

```yaml
MYSQL_ROOT_PASSWORD: "your-password"  # ✗ Wrong
MySQL_root_Password: "your-password"  # ✗ Wrong
```

**Example file:** [environments/example/secrets.yaml.example](environments/example/secrets.yaml.example)

#### Define workers

Edit the `environments/dev/terraform.tfvars` file to provision infrastructure resources for the services defined in the `docker-compose.yml` stack files.

**Base Infrastructure Workers**: Keep the `traefik` and `monitoring` workers from the example file, as they are required for the base infrastructure stacks you copied earlier. You can adjust the plan and data size based on your cluster's expected load:

```hcl
workers = {
  # Workers for traefik stack (required)
  "traefik" = {
    plan         = "medium",    # Adjust based on traffic load
    data_size_gb = 10
  },

  # Workers for monitoring stack (required)
  "monitoring" = {
    plan         = "large",     # Adjust based on metrics volume
    data_size_gb = 100          # Adjust based on retention needs
  },

  # Add your application-specific workers below...
}
```

**Application-Specific Workers**: Add additional workers based on your application stacks' requirements.

For example, if the stack has the constraint `node.hostname == mongo1`, add the following to the `terraform.tfvars` file:

```hcl
...
  "mongo1" = {
    plan         = "small",
    data_size_gb = 40
  },
...
```

If a pool label is used, like in the constraint `node.labels.pool == myapp`, add the following to the `terraform.tfvars` file, matching the number of replicas required by the service to the number of nodes in the pool:

```hcl
...
  "myapp-1" = {
    plan         = "small",
    data_size_gb = 40
    labels = {
      "pool" = "myapp"
    }
  },
  "myapp-2" = {
    plan         = "small",
    data_size_gb = 40
    labels = {
      "pool" = "myapp"
    }
  },
...
```

> Reference: See [Locaweb Cloud plans](https://www.locaweb.com.br/locaweb-cloud/) for vCPU and RAM for each plan.
>
> Note: `data_size_gb` configures only an additional attached volume for data; it is not the root disk.

#### Configure Public IPs (Optional)

The `public_ips` variable in `terraform.tfvars` is used for exposing services directly to the internet with dedicated public IP addresses and load balancer rules. Since Traefik is included in the base infrastructure stacks, most services should be exposed through Traefik using domain names, which is the recommended approach.

However, `public_ips` can be useful in specific situations where you need to:

- Expose services that don't work well behind a reverse proxy
- Provide direct access to services on non-standard ports
- Bypass Traefik for performance or compatibility reasons

##### Example: Exposing Portainer directly

```hcl
public_ips = {
  portainer = {
    ports = [
      {
        public        = 9443
        private       = 9443
        protocol      = "tcp"
        allowed_cidrs = ["203.0.113.0/24"]  # Restrict access to your IP range
      }
    ]
  }
}
```

> 💡 **Recommendation**: Use Traefik for most services (accessible via `https://service-name.{domain_suffix}`) and only use `public_ips` when direct exposure is specifically needed.

#### Set Infrastructure Credentials (Local)

For local deployments, provide your infrastructure credentials as environment variables.

> 💡 **Remark**: Unlike infrastructure credentials, application secrets should be placed in the `secrets.yaml` file as described above.

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

> 🚀 **Pro Tip**: A quick and easy way to set up your environment is to use a `.env` file. Copy the example file, edit it with your credentials, set the correct permissions, and source it:

```bash
cp .env.example .env
nano .env  # Or your favorite editor
chmod 600 .env
source .env
```

> 💡 **Remark**: in CI/CD, the infrastructure credentials are passed directly to the playbook as repository-level variables, bypassing the need for exporting them locally (see more in the [CI/CD section](#cicd-with-github-actions)).

### Deploy

Use the `Makefile` to deploy your environment. The `ENV` variable specifies which environment to target. It defaults to `dev`.

```bash
# Deploy the 'dev' environment
make deploy

# Deploy the 'prod' environment
make deploy ENV=prod
```

This command will automatically use the correct S3 state file path and configuration files for the specified environment.

### Configure DNS

During deployment, you'll need to configure DNS records to make your services accessible. The `make deploy` command will output the necessary DNS configuration information:

```text
📋 REQUIRED DNS CONFIGURATION:

   Create a DNS A record for: *.dev.mycluster.company.tech
   Point it to Traefik IP: 1.1.1.1

   Example DNS record:
   *.dev.mycluster.company.tech  →  1.1.1.1
```

Once DNS is configured, your services will be accessible at:

- **Traefik Dashboard**: `https://traefik.{domain_suffix}`
- **Grafana Dashboard**: `https://grafana.{domain_suffix}` (⚠️ Change the default password from "admin" on first access)
- **Prometheus**: `https://prometheus.{domain_suffix}`
- **Alertmanager**: `https://alertmanager.{domain_suffix}`
- **Other services**: `https://{service-name}.{domain_suffix}`

> 💡 **Remark**: DNS propagation can take a few minutes. You can test if DNS is working by running `nslookup traefik.{domain_suffix}` and verifying it returns the correct IP address.

## CI/CD with GitHub Actions

This project uses GitHub Actions to automate deployments. The workflow is configured to use **GitHub Environments**, which allows you to define distinct sets of secrets for each of your environments (e.g., `dev`, `prod`).

> ⚠️ **Important**: GitHub Environments are only available for public repositories or private repositories on paid GitHub plans (Pro, Team, or Enterprise). If you're using a free GitHub plan with a private repository, you'll need to make your repository public to use environments. This shouldn't be a security concern as your secrets remain protected and are not accessible through the public repository.

### Configuration

#### Create Environments

In your GitHub repository, go to **Settings > Environments**. Create an environment for each of your deployment targets (e.g., `dev`, `prod`). The names must match the directory names under `environments/`.

#### Add Repository-Level Secrets

Go to **Settings > Secrets and variables > Actions** and add the infrastructure credentials as repository secrets. These are shared across all environments:

**Required Repository Secrets:**

- `CLOUDSTACK_API_URL`
- `CLOUDSTACK_API_KEY`
- `CLOUDSTACK_SECRET_KEY`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `DOCKER_REGISTRY_URL` (optional)
- `DOCKER_REGISTRY_USERNAME` (optional)
- `DOCKER_REGISTRY_PASSWORD` (optional)

#### Add Environment-Specific Secrets

**For each environment** created in GitHub, add the application-specific secrets defined in your `docker-compose.yml` files (e.g., `mysql_root_password`, `nextcloud_admin_password`, etc.). Remember also to add, in each environment, the base application secrets (Traefik and monitoring).

> 💡 **Remark**: GitHub will automatically convert secret names to uppercase in the UI, but the deployment process will convert them back to lowercase to match your `secrets.yaml` format. For example, if you define `mysql_root_password` in your stack, GitHub will display it as `MYSQL_ROOT_PASSWORD`, but it will be correctly applied as `mysql_root_password` during deployment.

### Running the Workflow

- Go to the **Actions** tab in your GitHub repository.
- Select the **Deploy Infrastructure** or **Destroy Infrastructure** workflow.
- Click **Run workflow**, enter the name of the environment you wish to target, and click **Run workflow**.

The deploy pipeline will deploy the selected environment using the secrets you've configured for that specific GitHub Environment, while the destroy pipeline will destroy the infrastructure for the selected environment.

## Example Makefile Commands

Locally (not in CI/CD), you can use the following Makefile commands:

- `make deploy`: Deploy the `dev` environment.
- `make deploy ENV=prod`: Deploy the `prod` environment.
- `make plan ENV=prod`: Show the Terraform execution plan for the `prod` environment.
- `make destroy ENV=prod`: Destroy the `prod` environment.
- `make ssh`: SSH into the first manager of the `dev` environment.
- `make ssh ENV=prod PORT=22010`: SSH into the node with port `22010` of the `prod` environment (see the generated `environments/prod/inventory.yml` for mapping between ports and nodes).

> ⚠️ **Important**: Be careful when using local `make deploy` commands and CI/CD pipelines at the same time. Since the variables and secrets are passed from different sources, you will get different results if they aren't equal.
