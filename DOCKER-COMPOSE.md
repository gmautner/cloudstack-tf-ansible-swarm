# Rules for adapting Docker Compose files for use with Docker Swarm Stacks

## Preamble

The goal of this document is to provide a set of rules for adapting Docker Compose files for use with Docker Swarm.

The rules are based on the following reference: [docs/Compose file reference (legacy)/version-3.md](https://github.com/docker/compose/blob/0d4edbbd19e263a4e86fae75ef6ef105a15aa46d/docs/Compose%20file%20reference%20(legacy)/version-3.md#secrets-configuration-reference)

Always check whether the stack is compatible with the above reference and fix it if it is not.

Also, mind that, since we're dealing with `.j2` files, care should be taken when pre-processing the file. For example, use double `$$` to escape the `$` character, etc.

## Rules

### Header

Always insert in the first line of the file:

```yaml
version: "3.8"
```

### Ignored options

Use the provided reference to determine which options are ignored in Docker Swarm, and strip them out of the Docker Compose file.

### Networks

Always create an overlay network for internal communication between services in the stack. Name it based on the defining component of the stack. For example, for the `nextcloud-postgres-redis` stack, the network should be named `nextcloud_network`:

```yaml
networks:
  nextcloud_network:
    driver: overlay
```

Then attach all services within the stack to this network.

### Services with persistent data

In the case of services which have persistent data, such as databases, always use a named volume to store the data. For example:

```yaml
services:
  postgres:
    volumes:
      - postgres_data:/var/lib/postgresql/data
```

In such cases, the service should have a 1:1 relationship with the node, and the placement constraints should be set to the node's hostname, in order to ensure that the data is stored on the node where the service is running. For example:

```yaml
services:
  postgres:
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.hostname == postgres
```

Don't forget to add the volume to the `volumes` section of the stack. For example:

```yaml
volumes:
  postgres_data:
```

### Services without persistent data

#### Service with only one replica

If the service has only one replica, follow the same rules as for services with persistent data.

#### Service with more than one replica

In this case, use a placement contraint that ensures the service is spread across all nodes in a pool named after the service. Example:

```yaml
services:
  myapp:    
    deploy:
      replicas: 2
      placement:
        constraints:
          - node.labels.pool == myapp
```

### Traefik

If a service is exposed to the public internet, it should be exposed through Traefik.

In order to accomplish this, connect the service to the `traefik_network` network besides the internal stack network, for example:

```yaml
services:
  nextcloud:
    networks:
      - traefik_network
      - nextcloud_network
```

Then, add the following labels to the service, using the externally provided variable `DOMAIN_SUFFIX` to set the domain name which will be templated by Jinja2:

```yaml
services:
  nextcloud:
      labels:
        - traefik.enable=true
        - traefik.http.routers.nextcloud.rule=Host(`nextcloud.${DOMAIN_SUFFIX}`)
        - traefik.http.routers.nextcloud.entrypoints=websecure
        - traefik.http.routers.nextcloud.tls.certresolver=letsencrypt
        - traefik.http.services.nextcloud.loadbalancer.server.port=80
```

### Secrets

As we're using Docker Swarm, we need to rely on file based secrets.

Declare the secrets in the `secrets` section of the `service` definition. For example:

```yaml
services:
  nextcloud:
    secrets:
      - nextcloud_admin_password
      - postgres_password
```

Then, use the `secrets` directive in the `environment` section of the `service` definition. For example:

```yaml
services:
  nextcloud:
    environment:
      - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password
      - NEXTCLOUD_ADMIN_PASSWORD_FILE=/run/secrets/nextcloud_admin_password
```

The secrets will always be externally provided, so they should be declared in the stack as:

```yaml
secrets:
  nextcloud_admin_password:
    external: true
  postgres_password:
    external: true
```

In the rare cases where the Docker image doesn't support a file based secret, use a startup script to set the secret, and then call the main process. For example:

```yaml
services:
  rocketchat:
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        export MONGO_URL="mongodb://rocketchat:$$(cat /run/secrets/mongodb_password)@mongo1:27017,mongo2:27017,mongo3:27017/rocketchat?authSource=admin&replicaSet=rs0"
        exec node main.js
```

