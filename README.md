# CloudStack Terraform + Ansible Docker Swarm

Este projeto implanta uma infraestrutura completa de WordPress + MySQL no CloudStack usando Terraform para provisionamento de infraestrutura e Ansible para configuração do Docker Swarm.

## Arquitetura

A infraestrutura consiste em:

- **3 nós Manager** (instâncias `large` com discos de dados de 50GB) - Gerenciadores do Docker Swarm
- **2 nós Worker** (configuráveis) - WordPress (`micro` + 75GB) e MySQL (`medium` + 90GB)
- **Rede isolada** com IP público e balanceamento de carga
- **Proxy reverso Traefik** com certificados SSL Let's Encrypt

## Pré-requisitos

- Terraform >= 1.0
- Ansible com coleção `community.docker`
- As credenciais da API CloudStack devem ser fornecidas através das variáveis de ambiente `CLOUDSTACK_API_KEY` e `CLOUDSTACK_SECRET_KEY`.
- Par de chaves SSH
- Nome de domínio com acesso ao gerenciamento de DNS

## Início Rápido

### 1. Definir Variáveis de Ambiente

```bash
export CLOUDSTACK_API_KEY="sua-api-key"
export CLOUDSTACK_SECRET_KEY="sua-secret-key"
export MYSQL_ROOT_PASSWORD="senha-root-segura"
export WORDPRESS_DB_PASSWORD="senha-wordpress-segura"
```

### 2. Configurar Variáveis do Terraform

Copie o arquivo de exemplo e edite as variáveis em `terraform/terraform.tfvars`:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edite terraform/terraform.tfvars com sua chave pública SSH e domínio
```

### 3. Implantar Infraestrutura

Execute os comandos do Terraform dentro do diretório `terraform`:

```bash
cd terraform

# Validar Terraform
terraform validate

# Inicializar Terraform
terraform init

# Planejar implantação
terraform plan

# Aplicar configuração
terraform apply
```

### 4. Configurar DNS

Aponte o DNS wildcard do seu domínio (`*.seudominio.com`) para o IP público mostrado na saída do Terraform.

### 5. Implantar Docker Swarm e Aplicações

O inventário do Ansible é gerado automaticamente pelo Terraform em `ansible/inventory.ini`.

```bash
# Instalar dependências do Ansible
ansible-galaxy collection install -r ansible/collections/requirements.yml

# Implantar Docker Swarm
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml
```

## Configuração

### Variáveis do Terraform

| Variável | Descrição | Padrão |
|----------|-----------|--------|
| `ssh_public_key` | Chave pública SSH para acesso às instâncias | **Obrigatório** |
| `domain_suffix` | Sufixo de domínio para serviços | **Obrigatório** |
| `network_offering_name` | Oferta de rede CloudStack | `"Default Guest Network"` |
| `template_name` | Nome do template do SO | `"Ubuntu 24.04 (Noble Numbat)"` |
| `disk_offering_name` | Oferta de disco de dados | `"data.disk.general"` |
| `allowed_ssh_cidr_blocks` | Restrição de acesso SSH | `["0.0.0.0/0"]` |
| `workers` | Configuração dos nós worker | Veja `terraform/variables.tf` |

### Acesso à Rede

- **HTTP/HTTPS**: Portas 80, 443 → Balanceamento de carga para `manager-1`
- **Acesso SSH**:
  - `manager-1`: porta 22001
  - `manager-2`: porta 22002  
  - `manager-3`: porta 22003
  - worker `wp`: porta 22004
  - worker `mysql`: porta 22005

## Serviços

Após a implantação, os seguintes serviços estarão disponíveis:

- **WordPress**: `https://portal.seudominio.com`
- **Dashboard Traefik**: `https://traefik.seudominio.com`

## Notas Importantes de Segurança

### Estado do Terraform

Por padrão, o Terraform armazena o estado da infraestrutura em um arquivo local `terraform/terraform.tfstate`. Este arquivo contém informações sensíveis e **não deve ser commitado no controle de versão**.

Para colaboração ou uso em produção, configure um backend remoto no arquivo `terraform/main.tf`:

```hcl
terraform {
  backend "s3" {
    bucket = "seu-bucket-terraform-state"
    key    = "cloudstack-swarm/terraform.tfstate"
    region = "us-west-2"
  }
}
```

### Versionamento de Dependências

Para garantir implantações consistentes, este projeto trava as versões das dependências:

- **Terraform**: Versão do provider CloudStack fixada em `terraform/main.tf`
- **Ansible**: Versões das coleções especificadas em `ansible/collections/requirements.yml`

## Persistência de Dados

- **Discos de dados**: Montados em `/data` em cada nó
- **Arquivos WordPress**: Armazenados em `/data/wp` no worker wp
- **Dados MySQL**: Armazenados em `/data/mysql` no worker mysql
- **Certificados SSL**: Armazenados em `/data/letsencrypt` no manager-1

## Solução de Problemas

### Problemas de Conexão SSH

```bash
# Testar conexão SSH para manager-1
ssh -p 22001 ubuntu@<ip-publico>
```

### Status do Docker Swarm

```bash
# Verificar status do swarm em qualquer manager
docker node ls
```

### Logs dos Serviços

```bash
# Visualizar logs dos serviços
docker service logs <nome-do-servico>
```

## Limpeza

```bash
# Destruir toda a infraestrutura
cd terraform
terraform destroy
```

**Aviso**: Isso irá deletar permanentemente todas as instâncias e dados.
