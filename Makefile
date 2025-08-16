SHELL := /bin/bash

ENV ?= dev
TF_VARS_FILE := ../environments/$(ENV)/terraform.tfvars
ANSIBLE_VARS := secrets_file=../environments/$(ENV)/secrets.yaml stacks_dir=../environments/$(ENV)/stacks

.PHONY: help deploy destroy ssh

help:
	@echo "Usage: make [target] [ENV=environment_name]"
	@echo ""
	@echo "Arguments:"
	@echo "  ENV      - The environment to target (e.g., dev, prod). Defaults to 'dev'."
	@echo ""
	@echo "Targets:"
	@echo "  deploy   - Deploy the CloudStack infrastructure and Docker Swarm stacks."
	@echo "  destroy  - Destroy the CloudStack infrastructure."
	@echo "  ssh      - SSH into the first manager node."

deploy:
	@echo "Initializing and applying Terraform for '$(ENV)'..."
	@cd terraform && terraform init -backend-config="key=env/$(ENV)/terraform.tfstate" && terraform apply -var-file=$(TF_VARS_FILE) -var="env=$(ENV)" -auto-approve
	@echo "Starting ssh-agent and running playbook for '$(ENV)'..."
	@eval `ssh-agent -s` > /dev/null; \
	trap 'echo "Killing ssh-agent..."; ssh-agent -k > /dev/null' EXIT; \
	echo "Adding key to agent..."; \
	terraform -chdir=terraform output -raw private_key | ssh-add - > /dev/null && \
	echo "Running Ansible playbook..." && \
	cd ansible && ansible-playbook -i inventory.yml playbook.yml --extra-vars "$(ANSIBLE_VARS)" --extra-vars "secrets_context=$(SECRETS_CONTEXT)";
	@echo "Playbook finished."

destroy:
	@echo "Initializing and destroying infrastructure for '$(ENV)'..."
	@cd terraform && terraform init -backend-config="key=env/$(ENV)/terraform.tfstate" && terraform destroy -var-file=$(TF_VARS_FILE) -var="env=$(ENV)" -auto-approve

ssh:
	@echo "Initializing Terraform for '$(ENV)'..."
	@cd terraform && terraform init -backend-config="key=env/$(ENV)/terraform.tfstate"
	@echo "Starting ssh-agent and connecting to manager-1 in '$(ENV)'..."
	@eval `ssh-agent -s` > /dev/null; \
	trap 'echo "Killing ssh-agent..."; ssh-agent -k > /dev/null' EXIT; \
	echo "Adding key to agent..."; \
	terraform -chdir=terraform output -raw private_key | ssh-add - > /dev/null && \
	MANAGER_IP=$$(terraform -chdir=terraform output -raw main_public_ip); \
	echo "Connecting to $$MANAGER_IP..."; \
	ssh root@$$MANAGER_IP;
	@echo "SSH session closed."

