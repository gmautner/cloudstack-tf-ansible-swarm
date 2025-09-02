# Design and Architecture

This document outlines the key architectural decisions and implementation choices made in this repository. Its goal is to provide a DevOps engineer with a clear understanding of the project's structure, workflow, and rationale.

## Core Philosophy

The primary goal is to provide a **reusable, production-ready template** for deploying multiple, isolated Docker Swarm environments on CloudStack. The design prioritizes:

-   **Clarity over cleverness**: Solutions should be explicit and easy to understand. We avoid "magical" scripts in favor of clear, stateless commands.
-   **Separation of Concerns**: Core, reusable logic is strictly separated from environment-specific configuration.
-   **Security**: Sensitive information like private keys and passwords are never stored in version control and are handled securely.
-   **Automation**: The user experience is simplified through a central `Makefile` that orchestrates all complex operations.

## 1. Multi-Environment Management

The entire repository is built around a robust multi-environment strategy.

### Directory Structure

The core of this strategy is the top-level `environments/` directory.

```
environments/
├── dev/
│   ├── terraform.tfvars
│   ├── secrets.yaml
│   ├── inventory.yml  (Generated)
│   └── stacks/
└── prod/
    ├── terraform.tfvars
    ├── secrets.yaml
    ├── inventory.yml  (Generated)
    └── stacks/
```

-   **Rationale**: This structure centralizes all configuration for a given environment (`dev`, `prod`, etc.) in a single, predictable location. An engineer can look in one directory and understand everything about that environment's variables, secrets, and deployed applications. This is superior to scattering configuration files across the repository.

### Workflow Orchestration via `Makefile`

The `Makefile` is the primary entrypoint for all operations. It is environment-aware, using an `ENV` variable to target a specific configuration.

-   **Example**: `make deploy ENV=prod`
-   **Rationale**: Using a `Makefile` abstracts away the complexity of passing multiple environment-specific file paths and arguments to Terraform and Ansible. It provides a simple, consistent interface for users and the CI/CD pipeline.

## 2. Terraform State Isolation

To manage multiple environments safely, their Terraform states must be completely isolated.

-   **Implementation**: We use a **local backend** with a dynamic path for each environment.
    -   The backend is explicitly configured as `"local"` inside the `terraform {}` block in `terraform/main.tf`.
    -   The `Makefile` dynamically provides the state file path during initialization: `terraform init -backend-config="path=../environments/$(ENV)/terraform.tfstate"`.
-   **Decision Rationale**: This approach is meant for development purposes, as it simplifies the initial setup by avoiding the need to configure remote state storage and manage credentials. For production scenarios, state storage should be orchestrated through a CI/CD pipeline.

## 3. SSH Key Management (Fully Automated)

The management of SSH keys is designed to be secure and require zero manual user intervention.

-   **Implementation**:
    1.  **CloudStack Generation**: A `cloudstack_ssh_keypair` resource in Terraform instructs CloudStack to generate a new, unique key pair for each environment.
    2.  **State File Storage**: The resulting private key is stored securely in the Terraform state file.
    3.  **Just-in-Time Loading**: The `Makefile` uses `ssh-agent` to handle authentication. Before an `ansible-playbook` or `ssh` command is run, a script fetches the private key from the Terraform output and loads it directly into the `ssh-agent`.
    4.  **Robust Cleanup**: A `trap` is used to ensure the `ssh-agent` process is always killed and the key is unloaded from memory, even if the user interrupts the process (e.g., with Ctrl+C).
-   **Decision Rationale**: This is far superior to requiring users to create, name, and manage their own private key files. It eliminates a common source of user error, enhances security by keeping the key in memory for the shortest possible time, and makes the entire process seamless.

## 4. Ansible Configuration and Dynamics

The Ansible setup is designed to be generic and adaptable to any environment.

-   **Environment-Specific Inventory**: Terraform generates a unique inventory file for each environment (e.g., `environments/dev/inventory.yml`). The `Makefile` passes the correct inventory path to Ansible using the `-i` flag. The default `inventory` setting in `ansible.cfg` was explicitly removed to avoid confusion.
-   **Dynamic Configuration Paths**: The playbook itself does not contain hardcoded paths to configuration. The paths to the `secrets.yaml` and `stacks` directory are passed in as variables from the `Makefile` (`--extra-vars`).
    -   **Decision Rationale**: This was chosen over using symlinks. Symlinks would create a "magical" and stateful process where the contents of `ansible/stacks` would change. Passing explicit paths is stateless, clearer, and makes the playbook's behavior easier to trace.
-   **Docker Compose with Environment Variables**:
    -   The project uses standard `docker-compose.yml` files without a templating engine.
    -   Environment-specific values (like `domain_suffix`) are injected using standard Docker Compose environment variable substitution (e.g., `${DOMAIN_SUFFIX}`).
    -   The Ansible playbook, when running `community.docker.docker_stack`, passes these variables into the environment where the compose files are executed.
    -   **Decision Rationale**: This method aligns with standard Docker practices and eliminates a layer of abstraction, making the Compose files immediately usable with `docker-compose` locally for testing. It also simplifies the Ansible playbook, as it no longer needs a separate templating step.

## 5. Secrets Management

The secrets workflow is designed to be secure and flexible, leveraging Docker Swarm's native secret management.

-   **Secret Declaration in Compose**: Secret definitions are declared directly within each stack's `docker-compose.yml` file under the top-level `secrets:` key. This serves as the manifest of required secrets for a stack.
-   **Values from a Central File**: The actual secret values are loaded at runtime from a single, environment-specific `secrets.yaml` file (e.g., `environments/dev/secrets.yaml`).
-   **Ansible Orchestration**: The Ansible playbook is responsible for:
    1.  Finding all `docker-compose.yml` files to build a complete list of all declared secret names.
    2.  Verifying that the `secrets.yaml` file exists and has secure permissions (`600`).
    3.  Loading the values from the `secrets.yaml` file.
    4.  Using the `community.docker.docker_secret` module to create or update each secret in Docker Swarm.
-   **CI/CD Integration**: For CI/CD, the secret values can be passed directly to the playbook as an extra variable (`secrets_context`), bypassing the need for the `secrets.yaml` file on the runner.
    -   **Decision Rationale**: This pattern is robust and secure. It decouples the *declaration* of a secret (in the compose file) from its *value* (in the `secrets.yaml` or CI/CD store). It leverages Docker's native secret handling and enforces good security practice by checking file permissions.

## 6. CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/deploy.yml`) is the final piece of the automation.

-   **Manual Trigger**: It uses `workflow_dispatch` to allow users to trigger a deployment manually from the GitHub UI.
-   **Environment Selection**: It prompts the user for a text input to specify the target environment. This name must correspond to a configured GitHub Environment and a matching directory in `environments/`.
-   **Orchestration**: The workflow's primary job is to provide the secrets from the selected GitHub Environment and call the `Makefile`, passing in the chosen environment name. All complex logic remains in the `Makefile`, keeping the CI pipeline definition clean and simple.
