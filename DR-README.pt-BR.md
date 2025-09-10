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

### Cluster IDs (Origem e Destino)

- **Cluster de ORIGEM (antigo)**: É o cluster anterior (possivelmente já destruído) de onde vêm os snapshots.
- **Cluster de DESTINO (novo/atual)**: É o cluster que receberá os dados recuperados. Deve ser criado em um estado limpo do Terraform que não contenha o cluster de ORIGEM.

>⚠️ **Importante**: Se o cluster de ORIGEM ainda estiver presente no estado do Terraform (para o mesmo ambiente/backend), você não poderá criar o cluster de DESTINO nesse mesmo estado usando o processo normal. Escolha **uma** das seguintes opções:

- Destrua o cluster de ORIGEM primeiro nesse estado do Terraform.
- Crie o cluster de DESTINO em um ambiente diferente (ex.: `dev-dr` ou `prod-dr`). Cada ambiente usa seu próprio estado isolado.
- Mantenha o mesmo nome de ambiente, mas altere o bucket do backend S3 no arquivo `terraform/backend.tf` para que o cluster de DESTINO utilize um estado isolado.

Detalhes da opção 3 (backend alternativo mantendo o mesmo nome de ENV):

- Edite `terraform/backend.tf` e defina um `bucket` S3 diferente (e `region` se necessário), seguindo as instruções na seção [Configurar o Backend](README.pt-BR.md#configurar-o-backend) do README.

O processo de DR sempre recupera dados do cluster de ORIGEM (antigo) para o cluster de DESTINO (novo). Esses IDs devem ser diferentes.

```bash
# Identificar o cluster_id de DESTINO (novo/atual) para um ENV específico
cd terraform
terraform init -backend-config="key=env/<ENV>/terraform.tfstate"
terraform output -raw cluster_id

# Use um cluster_id DIFERENTE do retornado acima para a recuperação
```

#### Identificar o cluster_id de ORIGEM (antigo)

Caso não saiba o cluster_id de ORIGEM (antigo), você pode obtê-lo pelas tags dos snapshots existentes.

O comando abaixo retorna snapshots pelo nome do worker:

```bash
# Use o nome de algum worker do cluster (exemplo: mysql)
cmk list snapshots tags[0].key=name tags[0].value=<worker_name> \
  | jq '[.snapshot[]? | {id, name, created}] | sort_by(.created)'
```

E o comando abaixo retorna o cluster_id de ORIGEM (antigo) em função do ID do snapshot obtido acima:

```bash
cmk list tags resourceid=<snapshot_id> \
  | jq -r '.tag[] | select(.key=="cluster_id") | .value'
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
./dr.sh -c <cluster_id_origem> -e <env> [OPÇÕES]
```

### Opções Disponíveis

- `-c, --cluster-id` - ID do cluster de origem (antigo, snapshots) (**OBRIGATÓRIO**)
- `-e, --env` - Ambiente de destino (dev, prod, etc.) (**OBRIGATÓRIO**)
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
- Valida que o `cluster_id de origem` é diferente do `cluster_id de destino` (obtido do Terraform para o ENV)

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
- Filtra snapshots pelo `cluster_id de origem`
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
[INFO] Iniciando recuperação de desastre para o cluster: cluster-old-xyz123
[WARNING] MODO SIMULAÇÃO - Nenhuma alteração real será feita
[INFO] Verificando dependências...
[SUCCESS] Verificação de dependências aprovada
[INFO] Verificando CloudMonkey...
[SUCCESS] CloudMonkey encontrado
[INFO] Configurando CloudMonkey...
[SUCCESS] CloudMonkey configurado com sucesso
[INFO] Cluster de destino (novo): cluster-new-abc123
[INFO] Cluster de origem (recuperação): cluster-old-xyz123
[INFO] Obtendo VMs do cluster de destino: cluster-new-abc123
[SUCCESS] VMs do cluster de destino encontradas: i-123-456-VM i-789-012-VM
...
[SUCCESS] Recuperação de desastre concluída com sucesso!

Próximos passos:
  1. Execute 'make plan ENV=<env>' para revisar as mudanças
  2. Execute 'make deploy ENV=<env>' para aplicar tags aos novos discos dos workers
  3. Verifique se suas aplicações estão funcionando corretamente
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

- Forneça o `cluster_id de origem` usando a opção `-c` ou `--cluster-id`
- Esse ID deve ser diferente do `cluster_id de destino` obtido do Terraform para o ENV
- Para o `cluster_id de destino`: `cd terraform && terraform init -backend-config="key=env/<env>/terraform.tfstate" && terraform output -raw cluster_id`
- Para o `cluster_id de origem` a partir de snapshots: veja a seção "Identificar o cluster_id de ORIGEM (antigo)"

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

## Limitações Conhecidas

1. **Downtime**: O processo requer parada temporária das VMs
2. **Snapshots**: Depende da disponibilidade de snapshots recentes
3. **Ordem de Recuperação**: Workers são recuperados sequencialmente
