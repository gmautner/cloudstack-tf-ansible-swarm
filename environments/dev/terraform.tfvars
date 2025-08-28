# Cluster name
cluster_name = "cluster-2"

# domain_suffix será derivado a partir de env, cluster_name e base_domain, exemplo: dev.cluster-2.giba.tech
base_domain = "giba.tech"

# Opcional: Restringir acesso SSH (default: ["0.0.0.0/0"])
# allowed_ssh_cidr_blocks = ["203.0.113.0/24", "198.51.100.0/24"]

# Opcional: Habilitar reinicializações automáticas após atualizações (default: false)
automatic_reboot = true

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

  # Workers for nextcloud-postgres-redis
  "nextcloud" = {
    plan         = "micro",
    data_size_gb = 20,
  },
  "postgres" = {
    plan         = "micro",
    data_size_gb = 20
  },
  "redis" = {
    plan         = "micro",
    data_size_gb = 10
  },

  # Workers for rocketchat-mongodb
  "rocketchat" = {
    plan         = "medium",
    data_size_gb = 20
  },
  "mongo1" = {
    plan         = "small",
    data_size_gb = 40
  },
  "mongo2" = {
    plan         = "small",
    data_size_gb = 40
  },
  "mongo3" = {
    plan         = "small",
    data_size_gb = 40
  },

  # Workers for kafka stack
  "kafbat" = {
    plan         = "micro",
    data_size_gb = 10
  },
  "controller-1" = {
    plan         = "small",
    data_size_gb = 40
  },
  "controller-2" = {
    plan         = "small",
    data_size_gb = 40
  },
  "controller-3" = {
    plan         = "small",
    data_size_gb = 40
  },
  "broker-1" = {
    plan         = "medium",
    data_size_gb = 100
  },
  "broker-2" = {
    plan         = "medium",
    data_size_gb = 100
  },
  "broker-3" = {
    plan         = "medium",
    data_size_gb = 100
  },

  # Minio worker
  "minio" = {
    plan         = "small",
    data_size_gb = 40
  }
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