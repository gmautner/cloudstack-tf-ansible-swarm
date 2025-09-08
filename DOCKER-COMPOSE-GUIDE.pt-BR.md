# Escrevendo arquivos Docker Compose para Docker Swarm Stacks (passo a passo)

## Preâmbulo

Este guia ensina como escrever um arquivo Docker Compose pronto para ser implantado como um stack do Docker Swarm.

Referência para Compose v3 compatível com Swarm: [docs/Compose file reference (legacy)/version-3.md](https://github.com/docker/compose/blob/0d4edbbd19e263a4e86fae75ef6ef105a15aa46d/docs/Compose%20file%20reference%20(legacy)/version-3.md#secrets-configuration-reference)

Sempre verifique a compatibilidade do seu stack com a referência acima e ajuste/remova opções não suportadas.

## Exemplos

O diretório [environments/example/stacks/](environments/example/stacks/) contém stacks Swarm funcionais.

- [environments/example/stacks/nextcloud-postgres-redis/docker-compose.yml](environments/example/stacks/nextcloud-postgres-redis/docker-compose.yml): stack típico de aplicação com volumes, segredos, Traefik e bancos de dados.
- [environments/example/stacks/minio/docker-compose.yml](environments/example/stacks/minio/docker-compose.yml): stack típico de infraestrutura.

Ao longo deste guia usaremos o stack do Nextcloud como exemplo.

## 1) Versão

Sempre comece com a versão do Compose suportada pelo Swarm:

```yaml
version: "3.8"
```

Por quê: o Swarm usa o schema v3. Recursos sob `deploy:` (réplicas, placement, recursos, labels para Swarm) só funcionam com `docker stack deploy`.

## 2) Serviços

Defina seus contêineres de aplicação em `services:`. No stack do Nextcloud estes são `postgres`, `redis`, `nextcloud` e `pgadmin`.

```yaml
services:
  postgres: { }
  redis: { }
  nextcloud: { }
  pgadmin: { }
```

### 2.1 Imagens e tags

Sempre fixe as imagens em uma versão major.minor estável. Se uma tag não existir, procure no registry a tag estável mais recente e use seu major/minor.

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

### 2.2 Variáveis de ambiente e configuração

Configure os apps usando variáveis de ambiente. Prefira segredos baseados em arquivo para valores sensíveis (veja 2.3 e seção 5).

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

### 2.3 Uso de segredos nos serviços

No Swarm, valores sensíveis devem vir de segredos do Swarm, montados em `/run/secrets/...` e referenciados via variáveis `*_FILE` quando suportado pela imagem. Veja a seção 5 para como declarar segredos no nível superior.

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

Se uma imagem não suportar segredos baseados em arquivo, envolva a inicialização com um pequeno script de entrypoint que leia os segredos e depois execute o processo principal:

```yaml
services:
  rocketchat:
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        export MONGO_URL="mongodb://rocketchat:$$(cat /run/secrets/mongodb_password)@mongo1:27017,mongo2:27017,mongo3:27017/rocketchat?authSource=admin&replicaSet=rs0"
        exec node main.js
```

### 2.4 Volumes para dados persistentes (serviços com estado)

Para serviços com dados persistentes (por exemplo, bancos de dados), use volumes nomeados e prenda-os a um único nó com relação 1:1 para manter os dados co-localizados com o contêiner.

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

Adicione o nome do volume na seção `volumes:` do nível superior (veja a seção 3).

Para serviços sem estado de uma única réplica, use a mesma regra (réplicas: 1 com restrição de hostname) para mantê-los em um nó específico.

### 2.5 Serviços sem estado com mais de uma réplica

Para N>1 réplicas, distribua em um pool usando um rótulo de nó. Nomeie o pool com o nome do serviço para manter a convenção.

```yaml
services:
  myapp:
    deploy:
      replicas: 2
      placement:
        constraints:
          - node.labels.pool == myapp
```

### 2.6 Rede interna do serviço

Cada serviço deve estar conectado à rede interna do stack para comunicação entre serviços. No exemplo do Nextcloud esta rede é `nextcloud_network`. Veja a seção 4 para como declarar redes no nível superior.

```yaml
services:
  nextcloud:
    networks:
      - nextcloud_network
```

### 2.7 Exposição pública com Traefik

Serviços públicos devem ser expostos via Traefik. Anexe o serviço à rede externa `traefik_network` e adicione os labels apropriados. O serviço já deve estar ligado à sua rede interna (veja 2.6). O domínio é parametrizado pela variável externa `DOMAIN_SUFFIX` (será fornecida pelo Ansible).

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

Declare `traefik_network` como externa (veja a seção 4).

### 2.8 Opções específicas do Swarm e opções ignoradas no Compose

Ao mirar no Swarm:

- Use `deploy:` para réplicas, placement, labels (para Swarm), política de restart e recursos.
- Não confie na semântica de ordenação de `depends_on`; o Swarm não garante ordem de inicialização. Use healthchecks e tentativas no próprio app.
- Evite `container_name` e `links` (não têm significado no Swarm). Use nomes de serviço para descoberta baseada em DNS.
- Não use `build:` com `docker stack deploy`; as imagens devem estar pré-construídas e publicadas em um registry.
- Prefira `restart_policy` em `deploy:` em vez de `restart:` na raiz do serviço.

Consulte a referência para remover quaisquer chaves não suportadas.

## 3) Volumes (nível superior)

Declare volumes nomeados usados pelos serviços. Para o Nextcloud:

```yaml
volumes:
  nextcloud:
  postgres_data:
  pgadmin_data:
```

Esses volumes usam o driver local por padrão, salvo especificação em contrário.

## 4) Redes (nível superior)

Crie uma rede overlay interna para o stack e conecte todos os serviços a ela. Nomeie-a a partir do componente definidor do stack (por exemplo, `nextcloud_network`). Também declare a rede do Traefik como externa, pois ela é fornecida em um stack separado.

```yaml
networks:
  nextcloud_network:
    driver: overlay
  traefik_network:
    external: true
```

## 5) Segredos (nível superior)

Declare segredos como externos; eles serão fornecidos pelo ambiente (por exemplo, Ansible criando segredos do Swarm antes).

```yaml
secrets:
  nextcloud_admin_password:
    external: true
  postgres_password:
    external: true
```

Use-os dentro dos serviços conforme mostrado na seção 2.3.

## 6) Esqueleto mínimo juntando tudo

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

## 7) Notas e cuidados

- Placement importa para serviços com estado. Mantenha o mapeamento 1:1 com o nó usando restrições por hostname.
- Para serviços sem estado com múltiplas réplicas, distribua via `node.labels.pool`.
- Exponha apenas via Traefik, conecte ambas as redes e defina os labels do Traefik.
- Remova opções não suportadas/ignoradas ao mirar no Swarm.

## 8) Para saber mais

- Exemplo completo: [environments/example/stacks/nextcloud-postgres-redis/docker-compose.yml](environments/example/stacks/nextcloud-postgres-redis/docker-compose.yml)
- Stack de serviço sem estado replicado: [environments/example/stacks/echo/docker-compose.yml](environments/example/stacks/echo/docker-compose.yml)
- Referência do Compose v3 para Swarm: veja o link no Preâmbulo
