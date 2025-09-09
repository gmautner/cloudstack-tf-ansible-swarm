# Template de CloudStack com Terraform e Ansible Swarm

## Sumário

- [Template de CloudStack com Terraform e Ansible Swarm](#template-de-cloudstack-com-terraform-e-ansible-swarm)
  - [Sumário](#sumário)
  - [Recursos](#recursos)
  - [Estrutura do Projeto](#estrutura-do-projeto)
  - [Início Rápido](#início-rápido)
    - [Pré-requisitos](#pré-requisitos)
    - [Faça um Fork deste repositório](#faça-um-fork-deste-repositório)
    - [Configurar o Backend S3](#configurar-o-backend-s3)
      - [Criar um Bucket S3](#criar-um-bucket-s3)
      - [Criar um Usuário IAM](#criar-um-usuário-iam)
      - [Criar e Anexar a Política IAM](#criar-e-anexar-a-política-iam)
      - [Salvar Credenciais do Usuário](#salvar-credenciais-do-usuário)
    - [Configurar Seu Primeiro Ambiente](#configurar-seu-primeiro-ambiente)
      - [Personalizar Variáveis do Terraform](#personalizar-variáveis-do-terraform)
      - [Configurar o Backend](#configurar-o-backend)
      - [Definir Stacks de Aplicação](#definir-stacks-de-aplicação)
      - [Definir Segredos de Aplicação](#definir-segredos-de-aplicação)
      - [Definir workers](#definir-workers)
      - [Configurar IPs Públicos (Opcional)](#configurar-ips-públicos-opcional)
        - [Exemplo: Expondo Portainer diretamente](#exemplo-expondo-portainer-diretamente)
      - [Definir Credenciais de Infraestrutura (Local)](#definir-credenciais-de-infraestrutura-local)
    - [Deploy](#deploy)
    - [Configurar DNS](#configurar-dns)
  - [CI/CD com GitHub Actions](#cicd-com-github-actions)
    - [Configuração](#configuração)
      - [Criar Ambientes](#criar-ambientes)
      - [Adicionar Segredos no Nível do Repositório](#adicionar-segredos-no-nível-do-repositório)
      - [Adicionar Segredos Específicos por Ambiente](#adicionar-segredos-específicos-por-ambiente)
    - [Executando o Workflow](#executando-o-workflow)
  - [Exemplos de Comandos do Makefile](#exemplos-de-comandos-do-makefile)

Este repositório fornece um template para implantar múltiplos clusters Docker Swarm específicos por ambiente no CloudStack usando Terraform e Ansible.

## Recursos

- **Multi-Ambiente**: Gerencie `dev`, `prod` ou qualquer outro ambiente a partir de um único repositório.
- **Configuração Centralizada**: Toda a configuração de um ambiente (variáveis do Terraform, segredos, stacks) fica em um só lugar.
- **Infraestrutura como Código**: Toda a infraestrutura é definida com Terraform.
- **Isolamento de Estado**: O estado do Terraform para cada ambiente é armazenado em um arquivo separado em um backend S3 compartilhado, garantindo isolamento completo.
- **Configuração Automatizada**: Ansible configura o cluster Swarm e faz o deploy dos seus stacks.
- **Pronto para CI/CD**: Faça deploy de qualquer ambiente no CloudStack usando GitHub Actions.
- **Fluxo Simplificado**: Um `Makefile` oferece comandos simples com reconhecimento de ambiente.

## Estrutura do Projeto

```text
.
├── environments/
│   ├── dev/
│   │   ├── terraform.tfvars
│   │   ├── secrets.yaml
│   │   └── stacks/
│   ├── prod/
│   │   ├── terraform.tfvars
│   │   ├── secrets.yaml
│   │   └── stacks/
│   └── example/
│       └── stacks/
│
├── ansible/
│   └── ... (lógica principal do Ansible)
│
├── terraform/
│   └── ... (lógica principal do Terraform)
│
└── Makefile
```

- `environments/`: Contém todas as configurações específicas de cada ambiente.
- `example/stacks/`: Coleção de stacks de exemplo para copiar para seus ambientes.
- `ansible/`: Contém o playbook central e reutilizável do Ansible.
- `terraform/`: Contém a configuração central e reutilizável do Terraform.

## Início Rápido

### Pré-requisitos

- Terraform >= 1.0
- Ansible >= 2.10
- Credenciais da API do CloudStack
- Uma conta AWS
- Um webhook do [Slack](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/) para receber alertas (use a opção "app from scratch" ao seguir o link)
- Uma zona DNS sob seu controle para criar registros dos serviços do cluster, por exemplo `infra.example.com`

### Faça um Fork deste repositório

Faça um fork deste repositório para sua conta do GitHub.

### Configurar o Backend S3

Este template usa um bucket S3 para armazenar o estado do Terraform.

#### Criar um Bucket S3

- Acesse o serviço S3.
- Crie um novo bucket S3 privado aceitando os padrões. Escolha um nome globalmente único (ex.: `sua-empresa-terraform-states`).
- Guarde o nome do bucket e a região.

#### Criar um Usuário IAM

- Acesse o serviço IAM.
- Crie um novo usuário. Dê um nome descritivo (ex.: `terraform-s3-backend-user`).
- Em "Permissões", selecione **Anexar políticas diretamente** e clique em **Criar política**.

#### Criar e Anexar a Política IAM

- Na aba **JSON**, cole a política abaixo. Substitua `your-company-terraform-states` pelo nome do bucket que você criou.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::your-company-terraform-states",
                "arn:aws:s3:::your-company-terraform-states/*"
            ]
        }
    ]
}
```

- Revise e crie a política. Dê um nome descritivo (ex.: `TerraformS3BackendAccess`).
- Volte à tela de criação do usuário, atualize a lista de políticas e anexe sua nova política ao usuário.

#### Salvar Credenciais do Usuário

- Conclua a criação do usuário e clique em **View user**.
- Na tela de resumo, clique em **Create access key** com o caso de uso **Command Line Interface (CLI)**. Serão exibidos a **Access key** e o **Secret access key**. Copie e salve em local seguro.

### Configurar Seu Primeiro Ambiente

Vamos configurar um ambiente chamado `dev`.

#### Personalizar Variáveis do Terraform

Crie o diretório do ambiente e copie o arquivo terraform.tfvars:

```bash
# Crie primeiro o diretório do ambiente
mkdir -p environments/dev/

# Copie e personalize as variáveis do terraform
cp environments/example/terraform.tfvars environments/dev/terraform.tfvars
```

Em seguida, personalize `environments/dev/terraform.tfvars` com suas configurações, incluindo um `cluster_name` único e um `base_domain` que você controla para gerenciamento de DNS.

#### Configurar o Backend

Edite `terraform/backend.tf` e defina o `bucket` com o nome do bucket S3 criado e `region` com a região do bucket.

#### Definir Stacks de Aplicação

O diretório `environments/dev/stacks/` determina quais aplicações serão implantadas. Cada stack fica em um diretório próprio com um `docker-compose.yml` compatível com Docker Swarm e outros arquivos referenciados.

**Stacks de Infraestrutura Base (Obrigatórios)**: Sempre copie os stacks numerados de `environments/example/stacks/`, pois contêm a infraestrutura essencial do cluster:

```bash
# Crie primeiro o diretório de stacks
mkdir -p environments/dev/stacks/

# Copiar stacks de infraestrutura base (obrigatórios para operação do cluster)
cp -r environments/example/stacks/00-socket-proxy environments/dev/stacks/
cp -r environments/example/stacks/01-traefik environments/dev/stacks/
cp -r environments/example/stacks/02-monitoring environments/dev/stacks/
```

**Stacks de Aplicação (Opcionais)**: Os demais stacks (kafka, wordpress, etc.) são exemplos para servir de inspiração. Você pode usar suas próprias imagens ou quaisquer outras disponíveis:

```bash
# Exemplo: adicionar stacks de aplicação opcionais
cp -r environments/example/stacks/wordpress-mysql environments/dev/stacks/
cp -r environments/example/stacks/nextcloud-postgres-redis environments/dev/stacks/
```

**Criando ou adaptando arquivos Docker Compose para Docker Swarm**: Se precisar criar arquivos Docker Compose para uso no Docker Swarm, ou adaptar arquivos existentes, consulte o [Guia de Docker Compose](DOCKER-COMPOSE-GUIDE.pt-BR.md) para instruções detalhadas. (🧠 **Dica de IA**: Aponte seu assistente de IA para este guia para expertise instantânea em Docker Swarm!)

#### Definir Segredos de Aplicação

Os segredos necessários pelos seus stacks são descobertos automaticamente a partir do bloco `secrets:` no nível superior de cada `docker-compose.yml`. Isso inclui segredos necessários pelos stacks de infraestrutura base (Traefik e monitoramento) bem como pelos seus stacks de aplicação.

Para desenvolvimento local, crie o arquivo `environments/dev/secrets.yaml` para fornecer os valores destes segredos. Este arquivo é um simples key-value e deve ser configurado com permissões `chmod 600`. Ele é ignorado pelo Git, e o playbook de deploy falhará se as permissões não estiverem configuradas corretamente.

```bash
# Definir permissões corretas para o arquivo de segredos
chmod 600 environments/dev/secrets.yaml
```

> 💡 **Observação**: no CI/CD, os segredos são passados diretamente ao playbook como segredos no nível do ambiente, dispensando o arquivo `secrets.yaml` (veja mais em [CI/CD com GitHub Actions](#cicd-com-github-actions)).

**Segredos obrigatórios para stacks de infraestrutura base:**

- `traefik_basicauth`: Senha HTTP Basic Auth para acessar o dashboard do Traefik e outros serviços protegidos
- `slack_api_url`: URL do webhook do Slack para receber alertas de monitoramento

**Exemplo de `environments/dev/secrets.yaml`:**

```yaml
# Segredos de infraestrutura base (obrigatórios)
traefik_basicauth: 'admin:$2y$05$Oi938xgiKuRIORHWv1KuBuGASePs1DjtNV3pux86SgOj.7h47W66u'
slack_api_url: "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"

# Segredos de aplicação (conforme necessário para seus stacks)
mysql_root_password: "your-dev-db-password"
wordpress_db_password: "your-dev-wp-password"
```

> 💡 **Dica**: Você pode gerar o valor `traefik_basicauth` usando: `htpasswd -nB admin`
>
> ⚠️ **Importante**: Sempre defina nomes de segredos em minúsculas, tanto nos stacks quanto no arquivo `secrets.yaml`.

**Nome correto:**

```yaml
mysql_root_password: "your-password"  # ✓ Correto
```

**Nome incorreto:**

```yaml
MYSQL_ROOT_PASSWORD: "your-password"  # ✗ Errado
MySQL_root_Password: "your-password"  # ✗ Errado
```

**Arquivo de exemplo:** [environments/example/secrets.yaml.example](environments/example/secrets.yaml.example)

#### Definir workers

Edite o arquivo `environments/dev/terraform.tfvars` para provisionar recursos de infraestrutura para os serviços definidos nos arquivos `docker-compose.yml` dos stacks.

**Workers de Infraestrutura Base**: Mantenha os workers `traefik` e `monitoring` do arquivo de exemplo, pois são necessários para os stacks de infraestrutura base que você copiou anteriormente. Você pode ajustar o plano e o tamanho dos dados baseado na carga esperada do seu cluster:

```hcl
workers = {
  # Workers para o stack traefik (obrigatório)
  "traefik" = {
    plan         = "medium",    # Ajuste baseado na carga de tráfego
    data_size_gb = 10
  },

  # Workers para o stack monitoring (obrigatório)
  "monitoring" = {
    plan         = "large",     # Ajuste baseado no volume de métricas
    data_size_gb = 100          # Ajuste baseado nas necessidades de retenção
  },

  # Adicione seus workers específicos de aplicação abaixo...
}
```

**Workers Específicos de Aplicação**: Adicione workers adicionais baseados nos requisitos dos seus stacks de aplicação.

Por exemplo, se o stack possui a restrição `node.hostname == mongo1`, adicione o seguinte ao `terraform.tfvars`:

```hcl
...
  "mongo1" = {
    plan         = "small",
    data_size_gb = 40
  },
...
```

Se um rótulo de pool for usado, como na restrição `node.labels.pool == myapp`, adicione o seguinte ao `terraform.tfvars`, combinando o número de réplicas do serviço com o número de nós no pool:

```hcl
...
  "myapp-1" = {
    plan         = "small",
    data_size_gb = 40
    labels = {
      "pool" = "myapp"
    }
  },
  "myapp-2" = {
    plan         = "small",
    data_size_gb = 40
    labels = {
      "pool" = "myapp"
    }
  },
...
```

> Referência: veja os [planos da Locaweb Cloud](https://www.locaweb.com.br/locaweb-cloud/) para tamanhos de vCPU e RAM de cada plano.
>
> Observação: `data_size_gb` configura apenas um volume adicional anexado para dados; não é o disco root.

#### Configurar IPs Públicos (Opcional)

A variável `public_ips` no `terraform.tfvars` é usada para expor serviços diretamente à internet com endereços IP públicos dedicados e regras de load balancer. Como o Traefik está incluído nos stacks de infraestrutura base, a maioria dos serviços deve ser exposta através do Traefik usando nomes de domínio, que é a abordagem recomendada.

No entanto, `public_ips` pode ser útil em situações específicas onde você precisa:

- Expor serviços que não funcionam bem atrás de um proxy reverso
- Fornecer acesso direto a serviços em portas não-padrão
- Contornar o Traefik por razões de performance ou compatibilidade

##### Exemplo: Expondo Portainer diretamente

```hcl
public_ips = {
  portainer = {
    ports = [
      {
        public        = 9443
        private       = 9443
        protocol      = "tcp"
        allowed_cidrs = ["203.0.113.0/24"]  # Restrinja o acesso ao seu range de IP
      }
    ]
  }
}
```

> 💡 **Recomendação**: Use Traefik para a maioria dos serviços (acessíveis via `https://nome-do-serviço.{domain_suffix}`) e use `public_ips` apenas quando exposição direta for especificamente necessária.

#### Definir Credenciais de Infraestrutura (Local)

Para deploys locais, forneça suas credenciais de infraestrutura como variáveis de ambiente.

> 💡 **Lembrete**: Diferentemente das credenciais de infraestrutura, os segredos de aplicação devem ser colocados no arquivo `secrets.yaml` conforme descrito acima.

- **Localmente**: Exporte as credenciais de infraestrutura como variáveis de ambiente.

```bash
# Credenciais de Infraestrutura
export CLOUDSTACK_API_URL="..."
export CLOUDSTACK_API_KEY="..."
export CLOUDSTACK_SECRET_KEY="..."
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

Para registries privados, você também pode opcionalmente fornecer suas credenciais:

```bash
export DOCKER_REGISTRY_URL="your-registry-url"
export DOCKER_REGISTRY_USERNAME="your-username"
export DOCKER_REGISTRY_PASSWORD="your-password-or-token"
```

> 🚀 **Dica Pro**: Uma forma rápida de configurar seu ambiente é usar um arquivo `.env`. Copie o arquivo de exemplo, edite com suas credenciais, ajuste as permissões e faça o source:

```bash
cp .env.example .env
nano .env  # Ou seu editor favorito
chmod 600 .env
source .env
```

> 💡 **Observação**: no CI/CD, as credenciais de infraestrutura são passadas diretamente ao playbook como variáveis no nível do repositório, dispensando a exportação local (veja mais em [CI/CD com GitHub Actions](#cicd-com-github-actions)).

### Deploy

Use o `Makefile` para fazer o deploy do seu ambiente. A variável `ENV` especifica qual ambiente será alvo. O padrão é `dev`.

```bash
# Deploy do ambiente 'dev'
make deploy

# Deploy do ambiente 'prod'
make deploy ENV=prod
```

Este comando utilizará automaticamente o caminho correto do estado no S3 e os arquivos de configuração para o ambiente especificado.

### Configurar DNS

Durante o deploy, você precisará configurar registros DNS para tornar seus serviços acessíveis. O comando `make deploy` exibirá as informações necessárias de configuração DNS:

```text
📋 CONFIGURAÇÃO DNS OBRIGATÓRIA:

   Crie um registro DNS A para: *.dev.mycluster.company.tech
   Aponte para o IP do Traefik: 1.1.1.1

   Exemplo de registro DNS:
   *.dev.mycluster.company.tech  →  1.1.1.1
```

Após configurar o DNS, seus serviços estarão acessíveis em:

- **Traefik Dashboard**: `https://traefik.{domain_suffix}`
- **Grafana Dashboard**: `https://grafana.{domain_suffix}` (⚠️ Altere a senha padrão "admin" no primeiro acesso)
- **Prometheus**: `https://prometheus.{domain_suffix}`
- **Alertmanager**: `https://alertmanager.{domain_suffix}`
- **Outros serviços**: `https://{service-name}.{domain_suffix}`

> 💡 **Observação**: A propagação de DNS pode levar alguns minutos. Você pode testar se o DNS está funcionando executando `nslookup traefik.{domain_suffix}` e verificando se retorna o IP correto.

## CI/CD com GitHub Actions

Este projeto usa GitHub Actions para automatizar deploys. O workflow é configurado para usar **Ambientes do GitHub**, permitindo definir conjuntos distintos de segredos para cada ambiente (por exemplo, `dev`, `prod`).

> ⚠️ **Importante**: Ambientes do GitHub estão disponíveis para repositórios públicos ou repositórios privados em planos pagos do GitHub (Pro, Team ou Enterprise). Se você usa um plano gratuito com repositório privado, será necessário torná-lo público para usar ambientes. Isso não deve ser um problema de segurança pois seus segredos permanecem protegidos e não ficam acessíveis pelo repositório público.

### Configuração

#### Criar Ambientes

No seu repositório do GitHub, vá em **Settings > Environments**. Crie um ambiente para cada alvo de deploy (por exemplo, `dev`, `prod`). Os nomes devem corresponder aos diretórios em `environments/`.

#### Adicionar Segredos no Nível do Repositório

Vá em **Settings > Secrets and variables > Actions** e adicione as credenciais de infraestrutura como segredos do repositório. Eles são compartilhados entre todos os ambientes:

**Segredos obrigatórios do repositório:**

- `CLOUDSTACK_API_URL`
- `CLOUDSTACK_API_KEY`
- `CLOUDSTACK_SECRET_KEY`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `DOCKER_REGISTRY_URL` (opcional)
- `DOCKER_REGISTRY_USERNAME` (opcional)
- `DOCKER_REGISTRY_PASSWORD` (opcional)

#### Adicionar Segredos Específicos por Ambiente

Para cada ambiente criado, adicione os segredos específicos da aplicação definidos nos seus arquivos `docker-compose.yml` (por exemplo, `mysql_root_password`, `nextcloud_admin_password`, etc.)

> 💡 **Observação**: O GitHub converte automaticamente os nomes dos segredos para maiúsculas na UI, mas o processo de deploy os converterá de volta para minúsculas para corresponder ao formato do `secrets.yaml`. Por exemplo, se você definir `mysql_root_password` no seu stack, o GitHub exibirá como `MYSQL_ROOT_PASSWORD`, mas ele será aplicado corretamente como `mysql_root_password` durante o deploy.

### Executando o Workflow

- Acesse a aba **Actions** do seu repositório.
- Selecione o workflow **Deploy Infrastructure** ou **Destroy Infrastructure**.
- Clique em **Run workflow**, informe o nome do ambiente que deseja atingir e clique em **Run workflow**.

O pipeline de deploy fará o deploy do ambiente selecionado usando os segredos configurados para aquele Ambiente do GitHub, enquanto o pipeline de destruição destruirá a infraestrutura do ambiente selecionado.

## Exemplos de Comandos do Makefile

Localmente (fora do CI/CD), você pode usar os seguintes comandos:

- `make deploy`: Faz o deploy do ambiente `dev`.
- `make deploy ENV=prod`: Faz o deploy do ambiente `prod`.
- `make plan ENV=prod`: Mostra o plano do Terraform para o ambiente `prod`.
- `make destroy ENV=prod`: Destroi a infraestrutura do ambiente `prod`.
- `make ssh`: SSH no primeiro manager do ambiente `dev`.
- `make ssh ENV=prod PORT=22010`: SSH no nó com porta `22010` do ambiente `prod` (veja o `environments/prod/inventory.yml` gerado para o mapeamento entre portas e nós).

> ⚠️ **Importante**: Tenha cuidado ao usar comandos locais `make deploy` e pipelines de CI/CD ao mesmo tempo. Como as variáveis e segredos são passados de fontes diferentes, você terá resultados distintos se eles não forem iguais.
