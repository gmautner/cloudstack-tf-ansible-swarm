SHELL := /bin/bash

.PHONY: help deploy destroy ssh

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  deploy   - Deploy the CloudStack infrastructure and Docker Swarm stacks."
	@echo "  destroy  - Destroy the CloudStack infrastructure."
	@echo "  ssh      - SSH into the first manager node."

deploy:
	@echo "Deploying infrastructure..."
	cd terraform && terraform init && terraform apply -auto-approve
	@echo "Deploying Docker Swarm and stacks..."
	cd ansible && ansible-playbook -i inventory.yml playbook.yml

destroy:
	@echo "Destroying infrastructure..."
	cd terraform && terraform destroy -auto-approve

ssh:
	@echo "Connecting to manager-1..."
	@MANAGER_IP=$$(cd terraform && terraform output -raw manager_ips | head -n 1) && \
	ssh -i ~/.ssh/cluster-1 debian@$$MANAGER_IP

