# Requirements

We will deploy an installation of WordPress plus MySQL from the ground up.

This must include:

- Infrastructure in CloudStack, using the CloudStack Terraform Provider, as documented in <https://registry.terraform.io/providers/cloudstack/cloudstack/latest/docs>

- Terraform must output an Ansible inventory file, which will be used by Ansible to install Docker Swarm.

- After the installation of Docker Swarm, Ansible must install WordPress and MySQL using a Docker Stack.

## Specifics

### CloudStack

- The CloudStack API URL should be set to `https://painel-cloud.locaweb.com.br/client/api`
- The CloudStack API and Secret Keys should be read from environment variables `CLOUDSTACK_API_KEY` and `CLOUDSTACK_SECRET_KEY`
- You should create an isolated network for the nodes. The name of the network offering to use should be configurable via a Terraform variable `network_offering_name`, with a default value of "Default Guest Network". Use `data "cloudstack_network_offering" ...` to find the offering by this name, and then create the network using its ID.
- Assign a new Public IP to the network.
  - Allow in its firewall traffic from `0.0.0.0/0` destined to the range of ports 80 and 443.
  - Allow in its firewall traffic from a CIDR block specified in a Terraform variable `allowed_ssh_cidr_blocks`, destined to the range of ports 22001-22100.
- The zone should be set to `ZP01` for all resources.
- Create an SSH public key, read from a Terraform variable.
- For all instances created below:
  - use the `data "cloudstack_template" ...` to find the template. The template name should be defined in a Terraform variable `template_name` with the default value "Ubuntu 24.04 (Noble Numbat)".
  - assign the SSH public key created above.
  - Create a load balancer in the public IP above, redirecting traffic from ports 80 and 443 to the `manager-1` instance.
  - Assign a port forwarding rule from the public IP for the port starting at 22001 and incrementing by 1, to each manager. Therefore, the managers will have port forwarding rules for ports 22001, 22002, and 22003. Continue on with the workers, starting at 22004 and so on.
- For all instances, managers and workers, create an hourly scheduled snapshot of each data disk replicated to zone `ZP02`.
- The disk offering for data disks should be defined in a Terraform variable `disk_offering_name`, with a default value "data.disk.general".

#### Managers

- Create three instances with the names "manager-1", "manager-2", and "manager-3", with the plan `large`. These nodes will be the managers of the Docker Swarm cluster.
- For each manager, attach a disk using the configured disk offering, with the size 50 GB.

#### Workers

- The workers should be retrieved from a Terraform variable, which should be preset to:

```hcl
workers = [
  { name = "wp", plan = "micro", data_size_gb = 75 },
  { name = "mysql", plan = "medium", data_size_gb = 90 },
]
```

- For each worker, attach a disk using the configured disk offering, with the size specified in `data_size_gb`.

#### Ansible inventory

At the end, create an Ansible inventory, with groups for managers and workers and their externally accessible IPs/ports for SSH as laid out above.

### Ansible

#### Docker Swarm

Create an Ansible playbook to install Docker Swarm. Use the module at <https://docs.ansible.com/ansible/latest/collections/community/docker/docker_swarm_module.html>. Pay attention to the requirements both at the client and at the target.

- The playbook should use the inventory file created by Terraform above.
- Install Docker Swarm, following the roles of managers and workers.
- The first manager should be the leader. Gather its token with Ansible facts and use it to join the other managers and workers.
- On each manager and worker node, the attached data disk (e.g., `/dev/vdb`) must be formatted with the `ext4` filesystem and mounted at `/data`. Ansible should ensure this mount is persistent by adding an entry to `/etc/fstab`.

#### Stacks

Then, create and deploy a stack with WordPress and MySQL.

- WordPress and MySQL should each be installed in a container, dedicated to the respective worker.
- Install a Traefik service with a single replica, constrained to run only on the `manager-1` node. It should be set up properly to recognize labels of containers to which it should proxy traffic.
  - The Traefik container should receive the traffic that the public IP sends to ports 80 and 443. Docker Swarm will act as a load balancer to send traffic to the Traefik container.
  - The WordPress container should be accessible at `https://portal.<domain_suffix>`, where `<domain_suffix>` is a Terraform variable that should be passed on to the playbook. This should be accomplished with a label in the WordPress container that Traefik can recognize.
  - Take care of possible network requirements for Traefik to reach the WordPress container.
  - The Traefik container should auto-renew the SSL certificates with Let's Encrypt. To persist the certificates, they should be stored in a volume mapped to `/data/letsencrypt` on the `manager-1` node's host filesystem.
  - The Traefik container should have a dashboard accessible at `https://traefik.<domain_suffix>`.
  - The DNS will be done externally. Inform the Public IP such that I can point `*.<domain_suffix>` to the it.
- Use the images `wordpress:php8.3-apache` and `mysql:8.4` for the containers.
- An overlay network should connect the containers of WordPress and MySQL.
- For the WordPress container, map `/var/www/html` to `/data/wp`, so that the WordPress files are stored in the data disk.
- For the MySQL container, map `/var/lib/mysql` to `/data/mysql`, so that the MySQL data is stored in the data disk.
- The Ansible playbook will create two Docker secrets for passwords: `mysql_root_password` and `wordpress_db_password`. The values for these secrets will be read from environment variables `MYSQL_ROOT_PASSWORD` and `WORDPRESS_DB_PASSWORD` on the machine where the `ansible-playbook` command is executed.
- Configure the MySQL container using environment variables and secrets. This will also create the `wordpress` database and user:
  - `MYSQL_ROOT_PASSWORD_FILE`: Set to `/run/secrets/mysql_root_password`.
  - `MYSQL_DATABASE`: Set to `wordpress`.
  - `MYSQL_USER`: Set to `wordpress`.
  - `MYSQL_PASSWORD_FILE`: Set to `/run/secrets/wordpress_db_password`.
- Configure the WordPress container to connect to the database using environment variables and secrets:
  - `WORDPRESS_DB_HOST`: Set to `mysql:3306`.
  - `WORDPRESS_DB_USER`: Set to `wordpress`.
  - `WORDPRESS_DB_PASSWORD_FILE`: Set to `/run/secrets/wordpress_db_password`.

## Notes

This code is meant to be used as a reference for developers. Therefore, it should be extremely concise, readable, well commented, and with an easy to follow, no-frills README.md companion. The `README.md` should contain clear instructions and also explain the following points:

- **Terraform State**: Explain that by default, Terraform stores the infrastructure state in a local `terraform.tfstate` file. This file contains sensitive information and must not be committed to version control. For collaboration or production use, it is highly recommended to configure a remote backend (e.g., S3, Terraform Cloud).
- **Dependency Versioning**: To ensure consistent deployments, the project should lock the versions of its dependencies.
  - For Terraform, this should be done using a `required_providers` block to pin the version of the CloudStack provider.
  - For Ansible, a `collections/requirements.yml` file should be used to specify versions for any used collections, like `community.docker`.
