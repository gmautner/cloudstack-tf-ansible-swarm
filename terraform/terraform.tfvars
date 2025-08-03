# SSH public key for instance access
ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN1TWAOpobnTgLV0qKPQbI48udaxSH3iYJroJmXlRu4c gmautner@Gilbertos-MacBook-Air.local"

# Cluster name
cluster_name = "cluster-1"



# Opcional: Restringir acesso SSH (default: ["0.0.0.0/0"])
# allowed_ssh_cidr_blocks = ["203.0.113.0/24", "198.51.100.0/24"]

# Opcional: Número de managers (default: 3, permitido: 1 ou 3)
manager_count = 1

# Workers configuration
workers = {
  "wp" = {
    plan         = "medium",
    data_size_gb = 120,
  },
  "mysql" = {
    plan         = "large",
    data_size_gb = 90,
    labels = {
      "type"        = "database"
      "db_category" = "mysql"
    }
  },
  "prometheus" = {
    plan         = "medium",
    data_size_gb = 50,
    labels = {
      "type" = "monitoring"
    }
  },
}

# Public IPs and load balancer configuration
public_ips = {
  traefik = {
    ports = [
      {
        public        = 80
        private       = 80
        protocol      = "tcp-proxy"
        allowed_cidrs = ["0.0.0.0/0"]
      },
      {
        public        = 443
        private       = 443
        protocol      = "tcp-proxy"
        allowed_cidrs = ["0.0.0.0/0"]
      }
    ]
  }
  prometheus = {
    ports = [
      {
        public        = 9090
        private       = 9090
        protocol      = "tcp"
        allowed_cidrs = ["177.188.158.169/32", "191.252.224.0/24"]
      }
    ]
  }
}