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
- You should create an isolated network for the nodes. Use `data "cloudstack_network_offering" ...` to find the network offering. Search for the name "Default Guest Network" and then create the network using the ID of the found offering.
- Assign a new Public IP to the network.
  - Allow in its firewall traffic from `0.0.0.0/0` destined to the range of ports 80 and 443.
  - Allow in its firewall traffic from a CIDR block specified in a Terraform variable `allowed_ssh_cidr_blocks`, destined to the range of ports 22001-22100.
- The zone should be set to `ZP01` for all resources.
- Create an SSH public key, read from a Terraform variable.
- For all instances created below:
  - use the `data "cloudstack_template" ...` to find the template. Search for the name "Ubuntu 24.04 (Noble Numbat)".
  - assign the SSH public key created above.
  - Create a load balancer in the public IP above, redirecting traffic from ports 80 and 443 to all instances (Docker Swarm will act as a load balancer to the final target)
  - Assign a port forwarding rule from the public IP for the port starting at 22001 and incrementing by 1, to each manager. Therefore, the managers will have port forwarding rules for ports 22001, 22002, and 22003. Continue on with the workers, starting at 22004 and so on.
- For all instances, managers and workers, create an hourly scheduled snapshot of each data disk replicated to zone `ZP02`.

#### Managers

- Create three instances with the names "manager-1", "manager-2", and "manager-3", with the plan `large`. These nodes will be the managers of the Docker Swarm cluster.
- For each manager, attach a disk using offer `data.disk.general`, with the size 50 GB.

#### Workers

- The workers should be retrieved from a Terraform variable, which should be preset to:

```hcl
workers = [
  { name = "wp", plan = "micro", data_size_gb = 75 },
  { name = "mysql", plan = "medium", data_size_gb = 90 },
]
```

- For each worker, attach a disk using offer `data.disk.general`, with the size specified in `data_size_gb`. The data disk should be mounted at `/data` in the instances.

#### Ansible inventory

At the end, create an Ansible inventory, with groups for managers and workers and their externally accessible IPs/ports for SSH as laid out above.

### Ansible

#### Docker Swarm

Create an Ansible playbook to install Docker Swarm. Use the module at <https://docs.ansible.com/ansible/latest/collections/community/docker/docker_swarm_module.html>. Pay attention to the requirements both at the client and at the target.

- The playbook should use the inventory file created by Terraform above.
- Install Docker Swarm, following the roles of managers and workers.
- The first manager should be the leader. Gather its token with Ansible facts and use it to join the other managers and workers.

#### Stacks

Then, create and deploy a stack with WordPress and MySQL.

- WordPress and MySQL should each be installed in a container, dedicated to the respective worker.
- Install a Traefik container in the 3 managers, set up properly to recognize labels of containers to which it should proxy traffic.
  - The Traefik container should receive the traffic that the public IP sends to ports 80 and 443. Docker Swarm will act as a load balancer to send traffic to the Traefik container.
  - The WordPress container should be accessible at `https://portal.<domain_suffix>`, where `<domain_suffix>` is a Terraform variable that should be passed on to the playbook. This should be accomplished with a label in the WordPress container that Traefik can recognize.
  - Take care of possible network requirements for Traefik to reach the WordPress container.
  - The Traefik container should auto-renew the SSL certificates with Let's Encrypt.
  - The Traefik container should have a dashboard accessible at `https://traefik.<domain_suffix>`.
  - The DNS will be done externally. Inform the Public IP such that I can point `*.<domain_suffix>` to the it.
- Use the images `wordpress:php8.3-apache` and `mysql:8.4` for the containers.
- An overlay network should connect the containers of WordPress and MySQL.
- For the WordPress container, map `/var/www/html` to `/data/wp`, so that the WordPress files are stored in the data disk.
- For the MySQL container, map `/var/lib/mysql` to `/data/mysql`, so that the MySQL data is stored in the data disk.
- Define a secret for the MySQL root password, and use it in the MySQL container. The secret should be defined "out of band" with imperative Docker Swarm commands.
- Define a user and database in MySQL for WordPress, both named `wordpress`.
- Define a secret for the WordPress database user password, and use it in the MySQL and WordPress containers. The secret should be defined "out of band" with imperative Docker Swarm commands.
