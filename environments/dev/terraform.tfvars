# SSH public key for instance access
ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN1TWAOpobnTgLV0qKPQbI48udaxSH3iYJroJmXlRu4c gmautner@Gilbertos-MacBook-Air.local"

# Cluster name
cluster_name = "cluster-2-dev"

# Opcional: Sufixo de domínio para o cluster
domain_suffix = "cluster-2-dev.giba.tech"

# Opcional: Restringir acesso SSH (default: ["0.0.0.0/0"])
# allowed_ssh_cidr_blocks = ["203.0.113.0/24", "198.51.100.0/24"]

# Opcional: Habilitar reinicializações automáticas após atualizações (default: false)
# automatic_reboot = true

# Opcional: Horário UTC para reinicializações automáticas (default: "05:00")
# automatic_reboot_time_utc = "05:00"

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
    data_size_gb = 90
  },
  "monitoring" = {
    plan         = "large",
    data_size_gb = 100
  },
  "shared-1" = {
    plan         = "micro",
    data_size_gb = 10,
    labels = {
      "pool" = "shared"
    }
  },
  "shared-2" = {
    plan         = "micro",
    data_size_gb = 10,
    labels = {
      "pool" = "shared"
    }
  },
  "shared-3" = {
    plan         = "micro",
    data_size_gb = 10,
    labels = {
      "pool" = "shared"
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
  dockprom = {
    ports = [
      {
        public        = 3000
        private       = 3000
        protocol      = "tcp"
        allowed_cidrs = ["0.0.0.0/0"]
      },
      {
        public        = 8080
        private       = 8080
        protocol      = "tcp"
        allowed_cidrs = ["0.0.0.0/0"]
      },
      {
        public        = 9090
        private       = 9090
        protocol      = "tcp"
        allowed_cidrs = ["0.0.0.0/0"]
      },
      {
        public        = 9093
        private       = 9093
        protocol      = "tcp"
        allowed_cidrs = ["0.0.0.0/0"]
      },
      {
        public        = 9091
        private       = 9091
        protocol      = "tcp"
        allowed_cidrs = ["0.0.0.0/0"]
      }
    ]
  },
  portainer = {
    ports = [
      {
        public        = 9443
        private       = 9443
        protocol      = "tcp"
        allowed_cidrs = ["0.0.0.0/0"]
      }
    ]
  }
}