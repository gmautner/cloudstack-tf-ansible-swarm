# Regras para adaptar arquivos Docker Compose para uso com Docker Swarm Stacks

## Preâmbulo

O objetivo deste documento é fornecer um conjunto de regras para adaptar arquivos Docker Compose para uso com Docker Swarm.

As regras são baseadas na seguinte referência: [docs/Compose file reference (legacy)/version-3.md](https://github.com/docker/compose/blob/0d4edbbd19e263a4e86fae75ef6ef105a15aa46d/docs/Compose%20file%20reference%20(legacy)/version-3.md#secrets-configuration-reference)

Sempre verifique se o stack é compatível com a referência acima e corrija-o caso não seja.

## Regras

### Cabeçalho

Sempre insira na primeira linha do arquivo:

```yaml
version: "3.8"
```

### Tags de imagem

Quando não fornecidas, pesquise no registry correspondente pela tag estável mais recente e use os números de versão major e minor correspondentes.

### Opções ignoradas

Use a referência fornecida para determinar quais opções são ignoradas no Docker Swarm e remova-as do arquivo Docker Compose.

### Redes

Sempre crie uma rede overlay para comunicação interna entre os serviços no stack. Nomeie-a com base no componente definidor do stack. Por exemplo, para o stack `nextcloud-postgres-redis`, a rede deve se chamar `nextcloud_network`:

```yaml
networks:
  nextcloud_network:
    driver: overlay
```

Depois, conecte todos os serviços do stack a essa rede.

### Serviços com dados persistentes

Para serviços com dados persistentes, como bancos de dados, sempre use um volume nomeado para armazenar os dados. Por exemplo:

```yaml
services:
  postgres:
    volumes:
      - postgres_data:/var/lib/postgresql/data
```

Nestes casos, o serviço deve ter relação 1:1 com o nó, e as restrições de placement devem ser definidas para o hostname do nó, garantindo que os dados fiquem no nó onde o serviço executa. Por exemplo:

```yaml
services:
  postgres:
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.hostname == postgres
```

Não esqueça de declarar o volume na seção `volumes` do stack. Por exemplo:

```yaml
volumes:
  postgres_data:
```

### Serviços sem dados persistentes

#### Serviço com apenas uma réplica

Se o serviço tiver apenas uma réplica, siga as mesmas regras dos serviços com dados persistentes.

#### Serviço com mais de uma réplica

Neste caso, use uma restrição de placement que garanta a distribuição do serviço por todos os nós de um pool nomeado conforme o serviço. Exemplo:

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

Se um serviço for exposto à internet pública, ele deve ser exposto através do Traefik.

Para isso, conecte o serviço à rede `traefik_network` além da rede interna do stack, por exemplo:

```yaml
services:
  nextcloud:
    networks:
      - traefik_network
      - nextcloud_network
```

Em seguida, adicione os seguintes labels ao serviço, usando a variável externa `DOMAIN_SUFFIX` para definir o domínio, que será templateado pelo Ansible:

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

Por fim, declare a rede do Traefik como externa:

```yaml
networks:
  traefik_network:
    external: true
```

### Segredos

Como estamos usando Docker Swarm, precisamos depender de segredos baseados em arquivo.

Declare os segredos na seção `secrets` da definição do `service`. Por exemplo:

```yaml
services:
  nextcloud:
    secrets:
      - nextcloud_admin_password
      - postgres_password
```

Depois, use a diretiva `secrets` na seção `environment` da definição do `service`. Por exemplo:

```yaml
services:
  nextcloud:
    environment:
      - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password
      - NEXTCLOUD_ADMIN_PASSWORD_FILE=/run/secrets/nextcloud_admin_password
```

Os segredos serão sempre fornecidos externamente, então devem ser declarados no stack como:

```yaml
secrets:
  nextcloud_admin_password:
    external: true
  postgres_password:
    external: true
```

Nos raros casos em que a imagem não suporta segredo baseado em arquivo, use um script de inicialização para definir o segredo e depois chamar o processo principal. Por exemplo:

```yaml
services:
  rocketchat:
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        export MONGO_URL="mongodb://rocketchat:$$(cat /run/secrets/mongodb_password)@mongo1:27017,mongo2:27017,mongo3:27017/rocketchat?authSource=admin&replicaSet=rs0"
        exec node main.js
```


