# Disaster Recovery Guide

Este guia documenta o procedimento de recuperação de desastres para o cluster Docker Swarm no CloudStack.

## Visão Geral

O script de recuperação de desastres (`dr.sh`) automatiza o processo de restauração dos discos de dados dos workers a partir de snapshots armazenados no CloudStack. Este processo é necessário quando os discos de dados dos workers são corrompidos ou perdidos.

## Pré-requisitos

### Software Necessário

- **bash** (shell script)
- **jq** - Para processamento de JSON
- **terraform** - Para gerenciamento de estado
- **CloudMonkey (cmk)** - Cliente de linha de comando do CloudStack

### Credenciais de Ambiente

Antes de executar o script, defina as seguintes variáveis de ambiente:

```bash
export CLOUDSTACK_API_KEY="sua-api-key"
export CLOUDSTACK_SECRET_KEY="sua-secret-key"
export CLOUDSTACK_API_URL="https://painel-cloud.locaweb.com.br/client/api"  # Obrigatório
export AWS_ACCESS_KEY_ID="sua-aws-access-key-id"
export AWS_SECRET_ACCESS_KEY="sua-aws-secret-access-key"
```

Todas as variáveis acima são obrigatórias. Use a URL da API do seu provedor CloudStack (ex.: `https://painel-cloud.locaweb.com.br/client/api`).

### Cluster ID

O cluster_id é **obrigatório** e deve ser **diferente** do cluster atual no Terraform. Isso garante que a recuperação seja feita a partir de um cluster criado do zero, evitando confusão entre snapshots do cluster antigo e do novo cluster limpo.

```bash
# Para verificar o cluster ID atual no Terraform (para um ENV específico)
cd terraform
terraform init -backend-config="key=env/<ENV>/terraform.tfstate"
terraform output -raw cluster_id

# Use um cluster_id DIFERENTE do retornado acima para a recuperação
```

## Instalação

1. Torne o script executável:

```bash
chmod +x dr.sh
```

1. Verifique se as dependências estão instaladas:

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install jq

# CentOS/RHEL
sudo yum install jq
```

### Instalação do CloudMonkey

Para instalar o CloudMonkey, siga as instruções abaixo:

1. **Acesse o repositório oficial**: [https://github.com/apache/cloudstack-cloudmonkey/releases](https://github.com/apache/cloudstack-cloudmonkey/releases)

2. **Baixe a versão apropriada** para seu sistema operacional:
   - Linux x86-64: `cmk.linux.x86-64`
   - Linux ARM64: `cmk.linux.arm64`
   - macOS x86-64: `cmk.darwin.x86-64`
   - macOS ARM64: `cmk.darwin.arm64`
   - Windows: `cmk.windows.x86-64.exe`

3. **Instale o binário**:

   ```bash
   # Baixar (exemplo para Linux x86-64)
   wget https://github.com/apache/cloudstack-cloudmonkey/releases/latest/download/cmk.linux.x86-64
   
   # Tornar executável
   chmod +x cmk.linux.x86-64
   
   # Mover para diretório no PATH
   sudo mv cmk.linux.x86-64 /usr/local/bin/cmk
   
   # Verificar instalação
   cmk version
   ```

## Uso

### Sintaxe Básica

```bash
./dr.sh -c SOURCE_CLUSTER_ID -e ENV [OPÇÕES]
```

### Opções Disponíveis

- `-c, --cluster-id SOURCE_ID` - ID do cluster de origem (snapshots) (**OBRIGATÓRIO**)
- `-e, --env ENVIRONMENT` - Ambiente de destino (dev, prod, etc.) (**OBRIGATÓRIO**)
- `-d, --dry-run` - Executar em modo teste (mostra comandos sem executar)
- `-h, --help` - Exibir ajuda

### Exemplos de Uso

#### Recuperação Normal

```bash
# Recuperar dados do cluster ANTIGO para o ambiente dev
./dr.sh -c cluster-old-xyz123 -e dev

# Recuperar dados do cluster ANTIGO para o ambiente prod
./dr.sh -c cluster-old-xyz123 -e prod
```

#### Modo Teste (Dry Run)

```bash
# Executar em modo teste (sem alterações) para o ambiente dev
./dr.sh -c cluster-old-xyz123 -e dev --dry-run
```

**Recomendação**: Sempre execute primeiro em modo `--dry-run` para verificar se tudo está correto antes da execução real.

## Processo de Recuperação

O script executa os seguintes passos automaticamente:

### 1. Verificação de Dependências

- Verifica variáveis de ambiente necessárias (`CLOUDSTACK_API_KEY`, `CLOUDSTACK_SECRET_KEY`, `CLOUDSTACK_API_URL`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- Confirma presença de ferramentas requeridas (`jq`, `terraform`, `cmk`)
- Valida diretório do Terraform
- Valida o ambiente fornecido (`-e`): diretório `environments/<env>` e arquivo `environments/<env>/terraform.tfvars`
- Valida que o `cluster_id` de origem é diferente do cluster atual (destino) no Terraform

### 2. Verificação do CloudMonkey

- Verifica se o CloudMonkey está instalado e disponível no PATH
- Exibe instruções de instalação se não encontrado

### 3. Configuração do CloudMonkey

- Configura URL da API do CloudStack
- Define chaves de API
- Testa conectividade

### 4. Parada das VMs

- Identifica todas as VMs do cluster
- Para as VMs de forma controlada

### 5. Desanexação dos Discos

- Localiza discos de dados dos workers
- Desanexa os discos das VMs

### 6. Recuperação a partir de Snapshots

Para cada worker:

- Lista snapshots pela tag de nome do worker (`name=<worker_name>`)
- Filtra snapshots pelo `cluster_id` de origem
- Ordena por data de criação e seleciona o mais recente
- Cria um novo volume a partir do snapshot e o anexa à VM do worker

### 7. Atualização do Estado do Terraform

- Inicializa o Terraform com backend S3 específico do `ENV`
- Remove referências antigas dos discos no estado do Terraform (`terraform state rm 'cloudstack_disk.worker_data["<worker_name>"]'`)
- Importa os novos discos para o estado (`terraform import ...`) usando `-var-file=../environments/<env>/terraform.tfvars -var="env=<env>"`
- Mantém consistência entre infraestrutura e código; as VMs são reiniciadas no final do processo

## Saída do Script

### Logs Informativos

O script produz logs coloridos para facilitar o acompanhamento:

- **[INFO]** (azul) - Informações gerais
- **[SUCCESS]** (verde) - Operações bem-sucedidas
- **[WARNING]** (amarelo) - Avisos e modo dry-run
- **[ERROR]** (vermelho) - Erros que requerem atenção

### Exemplo de Saída

```text
[INFO] Starting disaster recovery for cluster: cluster-1-z1msjfjd
[INFO] Checking dependencies...
[SUCCESS] Dependencies check passed
[INFO] Validating provided cluster_id...
[SUCCESS] Cluster_id validated: cluster-1-z1msjfjd (different from current: cluster-2-abc123)
[INFO] CloudMonkey is already installed
[INFO] Configuring CloudMonkey...
[SUCCESS] CloudMonkey configured successfully
[INFO] Retrieving VMs for cluster: cluster-1-z1msjfjd
[SUCCESS] Found VMs: i-123-456-VM i-789-012-VM
...
[SUCCESS] Disaster recovery completed successfully!

Next steps:
  1. Run 'make plan ENV=<env>' to review changes
  2. Run 'make deploy ENV=<env>' to apply tags to new worker disks
  3. Verify your applications are running correctly
```

## Pós-Recuperação

Após a execução bem-sucedida do script:

### 1. Validação do Terraform

```bash
make plan ENV=<env>
```

Verifique se as mudanças mostradas estão corretas (principalmente tags nos novos discos).

### 2. Aplicação das Mudanças

```bash
make deploy ENV=<env>
```

Confirme a aplicação das tags nos novos discos de dados.

### 3. Verificação dos Serviços

```bash
# Recomendado: conectar via Makefile (usuário root; porta padrão 22001)
make ssh ENV=<env> [PORT=22001]
```

```bash
# Alternativa manual
cd terraform
terraform init -backend-config="key=env/<env>/terraform.tfstate"
eval $(ssh-agent -s)
terraform output -raw private_key | ssh-add -
MANAGER_IP=$(terraform output -raw main_public_ip)
ssh -o StrictHostKeyChecking=no -p 22001 root@$MANAGER_IP
```

```bash
# Dentro do manager, verifique o Swarm e serviços
docker node ls
docker service ls
docker service logs <nome-do-servico>
```

### 4. Teste das Aplicações

- Acesse a aplicação, por exemplo: `https://portal.seudominio.com`
- Acesse o Traefik Dashboard: `https://traefik.seudominio.com`
- Verifique se os dados foram restaurados corretamente

## Solução de Problemas

### Erros Comuns

#### 1. CloudMonkey Não Instalado

```text
[ERROR] CloudMonkey (cmk) é necessário mas não está instalado.
```

**Solução**:

- Instale o CloudMonkey seguindo as instruções em [https://github.com/apache/cloudstack-cloudmonkey/releases](https://github.com/apache/cloudstack-cloudmonkey/releases)
- Certifique-se de que o binário `cmk` está no PATH

#### 2. Credenciais Inválidas

```text
[ERROR] Variável de ambiente CLOUDSTACK_API_KEY é obrigatória
[ERROR] Variável de ambiente CLOUDSTACK_SECRET_KEY é obrigatória
[ERROR] Variável de ambiente CLOUDSTACK_API_URL é obrigatória
[ERROR] Variável de ambiente AWS_ACCESS_KEY_ID é obrigatória para acesso ao backend S3
[ERROR] Variável de ambiente AWS_SECRET_ACCESS_KEY é obrigatória para acesso ao backend S3
```

**Solução**: Defina as variáveis de ambiente corretas (CloudStack e AWS) antes de executar o script.

#### 3. Ambiente Inválido

```text
[ERROR] Diretório do ambiente não encontrado: environments/<env>
[ERROR] Arquivo terraform.tfvars não encontrado: environments/<env>/terraform.tfvars
```

**Solução**:

- Crie o diretório do ambiente em `environments/<env>`
- Forneça o arquivo `environments/<env>/terraform.tfvars` com as variáveis necessárias

#### 4. Cluster ID Obrigatório

```text
[ERROR] O cluster_id é obrigatório para recuperação de desastre
```

**Solução**:

- Forneça um cluster_id usando a opção `-c` ou `--cluster-id`
- O cluster_id deve ser diferente do cluster atual no Terraform
- Teste manualmente: `cd terraform && terraform output cluster_id` para ver o cluster atual

#### 5. VMs do Cluster Não Encontradas

```text
[ERROR] Nenhuma VM encontrada para o cluster: cluster-1-xyz
```

**Solução**:

- Verifique se o cluster ID está correto
- Confirme que as VMs têm as tags apropriadas
- Se especificou um cluster ID manualmente, verifique se está correto

#### 6. Snapshots Não Encontrados

```text
[ERROR] Nenhum snapshot encontrado para o worker: mysql
```

**Solução**: Verifique se os snapshots estão sendo criados automaticamente e se as tags estão corretas.

#### 7. Problemas de Conectividade

```text
[ERROR] Testando conexão com CloudStack falhou
```

**Solução**:

- Verifique conectividade de rede
- Confirme se as credenciais são válidas
- Teste manualmente: `cmk list zones`

### Logs Detalhados

Para depuração adicional, execute com verbose:

```bash
bash -x ./dr.sh --dry-run
```

### Recuperação Manual

Se o script falhar, você pode executar os comandos manualmente seguindo o processo descrito neste guia (seções "Processo de Recuperação" e "Pós-Recuperação").

## Alterações na Implementação

### Versão Atual

- **Cluster ID Obrigatório**: O script agora exige que o cluster_id seja fornecido explicitamente e seja diferente do cluster atual no Terraform. Isso garante que a recuperação seja feita a partir de um cluster criado do zero, evitando confusão entre snapshots.
- **Validação de Cluster**: O script valida automaticamente que o cluster_id fornecido é diferente do cluster atual antes de prosseguir com a recuperação.
- **Script Unificado**: Todas as funcionalidades foram consolidadas no script principal `dr.sh`, removendo a necessidade de scripts auxiliares separados.
- **Ambiente Obrigatório (-e)**: Agora é obrigatório informar o `ENV` (ex.: dev, prod). O script valida a existência de `environments/<env>` e do arquivo `terraform.tfvars` correspondente.
- **Credenciais AWS**: São necessárias (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) para inicializar o backend S3 do Terraform por ambiente.
- **Filtragem de Snapshots**: Snapshots são filtrados pelo nome do worker (tag `name`) e pelo `cluster_id` de origem, e o mais recente é utilizado.
- **Atualização de Estado do Terraform**: O backend é inicializado com `-backend-config="key=env/<env>/terraform.tfstate"` e o estado é atualizado com `terraform state rm` e `terraform import` usando `-var-file` e `-var="env=<env>"`.
- **Reinício de VMs ao Final**: Todas as VMs são reiniciadas após a recuperação e reimportação de discos.
- **Próximos Passos com Make**: Após a execução, utilize `make plan ENV=<env>` e `make deploy ENV=<env>`.

## Segurança e Boas Práticas

### Proteção de Credenciais

- **Nunca** commite as credenciais no controle de versão
- Use variáveis de ambiente ou arquivos de configuração seguros
- Considere usar ferramentas como `pass` ou `gpg` para armazenar credenciais

### Teste Regular

- Execute o script em modo `--dry-run` regularmente para verificar sua funcionalidade
- Teste o processo de recuperação em ambiente de desenvolvimento
- Mantenha documentação atualizada sobre mudanças na infraestrutura

### Backup das Credenciais

- Mantenha backup seguro das chaves de API
- Documente onde as credenciais estão armazenadas
- Implemente rotação regular das chaves de API

## Limitações Conhecidas

1. **Downtime**: O processo requer parada temporária das VMs
2. **Snapshots**: Depende da disponibilidade de snapshots recentes
3. **Ordem de Recuperação**: Workers são recuperados sequencialmente
4. **Estado do Terraform**: Requer sincronização manual do estado

## Contato e Suporte

Para problemas ou dúvidas sobre este processo de recuperação:

1. Verifique os logs do script para mensagens de erro específicas
2. Consulte a documentação do CloudStack
3. Revise este guia para detalhes técnicos dos comandos
