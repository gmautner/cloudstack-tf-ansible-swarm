# Writing Docker Compose files for Docker Swarm Stacks (step-by-step)

## Preamble

This guide teaches you how to write a Docker Compose file that is ready to be deployed as a Docker Swarm stack.

Reference for Swarm-compatible Compose v3: [docs/Compose file reference (legacy)/version-3.md](https://github.com/docker/compose/blob/0d4edbbd19e263a4e86fae75ef6ef105a15aa46d/docs/Compose%20file%20reference%20(legacy)/version-3.md#secrets-configuration-reference)

Always verify your stack is compatible with the reference above and strip/adjust any unsupported options.

## Examples

The directory [environments/example/stacks/](environments/example/stacks/) contains working Swarm stacks.

- [environments/example/stacks/nextcloud-postgres-redis/docker-compose.yml](environments/example/stacks/nextcloud-postgres-redis/docker-compose.yml): typical app stack with volumes, secrets, Traefik, and databases.
- [environments/example/stacks/minio/docker-compose.yml](environments/example/stacks/minio/docker-compose.yml): typical infra stack.

Throughout this guide we will use the Nextcloud stack as the running example.

## 1) Version

Always start with the Compose file version supported by Swarm:

```yaml
version: "3.8"
```

Why: Swarm uses the v3 schema. Features under `deploy:` (replicas, placement, resources, labels for Swarm) only work with `docker stack deploy`.

## 2) Services

Define your application containers under `services:`. In the Nextcloud stack these are `postgres`, `redis`, `nextcloud` and `pgadmin`.

```yaml
services:
  postgres: { }
  redis: { }
  nextcloud: { }
  pgadmin: { }
```

### 2.1 Images and tags

Always pin images to a stable major.minor. If a tag is missing, look up the latest stable tag in the registry and use its major/minor.

```yaml
services:
  postgres:
    image: postgres:17.6-alpine
  redis:
    image: redis:8.2-alpine
  nextcloud:
    image: nextcloud:31.0
  pgadmin:
    image: dpage/pgadmin4:9
```

### 2.2 Environment and configuration

Configure apps using env vars. Prefer file-based secrets for sensitive values (see 2.3 and section 5).

```yaml
services:
  postgres:
    environment:
      - POSTGRES_DB=nextcloud
      - POSTGRES_USER=nextcloud
      - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password

  nextcloud:
    environment:
      - POSTGRES_HOST=postgres
      - POSTGRES_USER=nextcloud
      - POSTGRES_DB=nextcloud
      - REDIS_HOST=redis
      - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password
      - NEXTCLOUD_ADMIN_PASSWORD_FILE=/run/secrets/nextcloud_admin_password
      - NEXTCLOUD_ADMIN_USER=nextcloud
      - NEXTCLOUD_TRUSTED_DOMAINS=nextcloud.${DOMAIN_SUFFIX}
```

### 2.3 Using secrets inside services

In Swarm, sensitive values should come from Swarm secrets, mounted at `/run/secrets/...` and referenced via `*_FILE` env vars when supported by the image. See section 5 for how to declare secrets at the top level.

```yaml
services:
  nextcloud:
    secrets:
      - nextcloud_admin_password
      - postgres_password
    environment:
      - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password
      - NEXTCLOUD_ADMIN_PASSWORD_FILE=/run/secrets/nextcloud_admin_password
```

If an image does not support file-based secrets, wrap the startup with a tiny entrypoint script that reads secrets and then execs the main process:

```yaml
services:
  rocketchat:
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        export MONGO_URL="mongodb://rocketchat:$$(cat /run/secrets/mongodb_password)@mongo1:27017,mongo2:27017,mongo3:27017/rocketchat?authSource=admin&replicaSet=rs0"
        exec node main.js
```

### 2.4 Volumes for persistent data (stateful services)

For services with persistent data (e.g., databases), use named volumes and pin them to a single node with a 1:1 placement to keep data co-located with the container.

```yaml
services:
  postgres:
    volumes:
      - postgres_data:/var/lib/postgresql/data
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.hostname == postgres
```

Add the volume name under the top-level `volumes:` section (see section 3).

For single-replica stateless services, use the same rule (replicas: 1 with hostname constraint) to keep them on a specific node.

### 2.5 Stateless services with more than one replica

For N>1 replicas, spread across a pool using a node label. Name the pool after the service to keep conventions consistent.

```yaml
services:
  myapp:
    deploy:
      replicas: 2
      placement:
        constraints:
          - node.labels.pool == myapp
```

### 2.6 Internal service network

Each service must be attached to the stack's internal network for inter-service communication. In the Nextcloud example this is `nextcloud_network`. See section 4 for how to declare networks at the top level.

```yaml
services:
  nextcloud:
    networks:
      - nextcloud_network
```

### 2.7 Public exposure with Traefik

Public services should be exposed via Traefik. Attach the service to the external `traefik_network` and add the appropriate labels. The service should already be attached to its internal network (see 2.6). The domain is templated with the externally provided `DOMAIN_SUFFIX` (will be provided by Ansible).

```yaml
services:
  nextcloud:
    networks:
      - nextcloud_network
      - traefik_network
    deploy:
      labels:
        - traefik.enable=true
        - traefik.http.routers.nextcloud.rule=Host(`nextcloud.${DOMAIN_SUFFIX}`)
        - traefik.http.routers.nextcloud.entrypoints=websecure
        - traefik.http.routers.nextcloud.tls.certresolver=letsencrypt
        - traefik.http.services.nextcloud.loadbalancer.server.port=80
```

Declare `traefik_network` as external (see section 4).

### 2.8 Swarm-specific and ignored Compose options

When targeting Swarm:

- Use `deploy:` for replicas, placement, labels (for Swarm), restart policy, and resources.
- Do not rely on `depends_on` ordering semantics; Swarm does not guarantee startup order. Use healthchecks and retries in apps.
- Avoid `container_name` and `links` (not meaningful in Swarm). Use service names for DNS-based discovery.
- Do not use `build:` with `docker stack deploy`; images must be pre-built and pushed to a registry.
- Prefer `restart_policy` under `deploy:` instead of `restart:` at the service root.

Consult the reference to strip any unsupported keys.

## 3) Volumes (top-level)

Declare named volumes used by services. For Nextcloud:

```yaml
volumes:
  nextcloud:
  postgres_data:
  pgadmin_data:
```

These default to the local driver unless specified otherwise.

## 4) Networks (top-level)

Create an internal overlay network for the stack and connect all services to it. Name it after the stack’s defining component (e.g., `nextcloud_network`). Also declare the Traefik network as external as it is provided in a separate stack.

```yaml
networks:
  nextcloud_network:
    driver: overlay
  traefik_network:
    external: true
```

## 5) Secrets (top-level)

Declare secrets as external; they will be provided by the environment (e.g., Ansible creating Swarm secrets beforehand).

```yaml
secrets:
  nextcloud_admin_password:
    external: true
  postgres_password:
    external: true
```

Use them inside services as shown in section 2.3.

## 6) Minimal skeleton putting it all together

```yaml
version: "3.8"

services:
  postgres:
    image: postgres:17.6-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=nextcloud
      - POSTGRES_USER=nextcloud
      - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password
    secrets:
      - postgres_password
    networks:
      - nextcloud_network
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.hostname == postgres

  redis:
    image: redis:8.2-alpine
    networks:
      - nextcloud_network
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.hostname == redis

  nextcloud:
    image: nextcloud:31.0
    volumes:
      - nextcloud:/var/www/html
    environment:
      - POSTGRES_HOST=postgres
      - POSTGRES_USER=nextcloud
      - POSTGRES_DB=nextcloud
      - REDIS_HOST=redis
      - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password
      - NEXTCLOUD_ADMIN_PASSWORD_FILE=/run/secrets/nextcloud_admin_password
      - NEXTCLOUD_ADMIN_USER=nextcloud
      - NEXTCLOUD_TRUSTED_DOMAINS=nextcloud.${DOMAIN_SUFFIX}
    secrets:
      - nextcloud_admin_password
      - postgres_password
    networks:
      - nextcloud_network
      - traefik_network
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.hostname == nextcloud
      labels:
        - traefik.enable=true
        - traefik.http.routers.nextcloud.rule=Host(`nextcloud.${DOMAIN_SUFFIX}`)
        - traefik.http.routers.nextcloud.entrypoints=websecure
        - traefik.http.routers.nextcloud.tls.certresolver=letsencrypt
        - traefik.http.services.nextcloud.loadbalancer.server.port=80

volumes:
  nextcloud:
  postgres_data:

networks:
  nextcloud_network:
    driver: overlay
  traefik_network:
    external: true

secrets:
  nextcloud_admin_password:
    external: true
  postgres_password:
    external: true
```

## 7) Notes and pitfalls

- Placement matters for stateful services. Keep a 1:1 node mapping using hostname constraints.
- For multi-replica stateless services, spread across a pool via `node.labels.pool`.
- Expose only through Traefik, attach both networks, and set Traefik labels.
- Remove unsupported/ignored options when targeting Swarm.

## 8) Where to look next

- Full example: [environments/example/stacks/nextcloud-postgres-redis/docker-compose.yml](environments/example/stacks/nextcloud-postgres-redis/docker-compose.yml)
- Replicated stateless service stack: [environments/example/stacks/echo/docker-compose.yml](environments/example/stacks/echo/docker-compose.yml)
- Compose v3 reference for Swarm: see the link in the Preamble
