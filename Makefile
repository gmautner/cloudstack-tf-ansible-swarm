SHELL := /bin/bash

ENV ?= dev
TF_VARS_FILE := ../../environments/$(ENV)/terraform.tfvars
ANSIBLE_VARS := secrets_file=../../environments/$(ENV)/secrets.yaml stacks_dir=../../environments/$(ENV)/stacks

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
	@echo "Deploying infrastructure for environment '$(ENV)'..."
	cd terraform && terraform init -backend-config="key=env/$(ENV)/terraform.tfstate" && terraform apply -var-file=$(TF_VARS_FILE) -auto-approve
	@echo "Deploying Docker Swarm and stacks for environment '$(ENV)'..."
	cd ansible && ansible-playbook -i inventory.yml playbook.yml --extra-vars "$(ANSIBLE_VARS)" --extra-vars "secrets_context=$(SECRETS_CONTEXT)"

destroy:
	@echo "Destroying infrastructure for environment '$(ENV)'..."
	cd terraform && terraform init -backend-config="key=env/$(ENV)/terraform.tfstate" && terraform destroy -var-file=$(TF_VARS_FILE) -auto-approve

ssh:
	@echo "Connecting to manager-1 in environment '$(ENV)'..."
	@MANAGER_IP=$$(cd terraform && terraform output -raw manager_ips | head -n 1) && \
	ssh -i ~/.ssh/cluster-1 debian@$$MANAGER_IP

