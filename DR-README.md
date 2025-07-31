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
export CLOUDSTACK_API_URL="https://painel-cloud.locaweb.com.br/client/api"  # Opcional
```

**Nota**: Se `CLOUDSTACK_API_URL` não for definida, o script usará a URL padrão da Locaweb. Para outros provedores CloudStack, defina a URL apropriada.

### Cluster ID

O script pode detectar automaticamente o ID do cluster a partir da saída do Terraform. Se necessário, você também pode especificar manualmente:

```bash
# Para verificar o cluster ID manualmente (opcional)
cd terraform
terraform output cluster_id
```

## Instalação

1. Torne o script executável:

```bash
chmod +x dr.sh
```

2. Verifique se as dependências estão instaladas:

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
./dr.sh [OPÇÕES]
```

### Opções Disponíveis

- `-c, --cluster-id CLUSTER_ID` - ID do cluster a ser recuperado (auto-detectado se não fornecido)
- `-d, --dry-run` - Executar em modo teste (mostra comandos sem executar)
- `-t, --terraform-dir DIR` - Caminho para o diretório do Terraform (padrão: terraform)
- `-h, --help` - Exibir ajuda

### Exemplos de Uso

#### Recuperação Normal

```bash
# Recuperar cluster com ID auto-detectado (recomendado)
./dr.sh

# Recuperar cluster com ID específico
./dr.sh -c cluster-1-z1msjfjd

# Especificar diretório customizado do Terraform
./dr.sh -t /caminho/para/terraform
```

#### Modo Teste (Dry Run)

```bash
# Executar em modo teste com cluster ID auto-detectado (recomendado)
./dr.sh --dry-run

# Executar em modo teste com cluster ID específico
./dr.sh -c cluster-1-z1msjfjd --dry-run
```

**Recomendação**: Sempre execute primeiro em modo `--dry-run` para verificar se tudo está correto antes da execução real.

## Processo de Recuperação

O script executa os seguintes passos automaticamente:

### 1. Verificação de Dependências
- Verifica variáveis de ambiente necessárias
- Confirma presença de ferramentas requeridas
- Valida diretório do Terraform
- Auto-detecta cluster ID do Terraform (se não fornecido)

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
- Lista snapshots disponíveis
- Identifica o snapshot mais recente
- Cria novo volume a partir do snapshot
- Inicia a VM do worker

### 7. Atualização do Estado do Terraform
- Remove referências antigas dos discos no estado do Terraform
- Importa os novos discos para o estado
- Mantém consistência entre infraestrutura e código

## Saída do Script

### Logs Informativos

O script produz logs coloridos para facilitar o acompanhamento:

- **[INFO]** (azul) - Informações gerais
- **[SUCCESS]** (verde) - Operações bem-sucedidas
- **[WARNING]** (amarelo) - Avisos e modo dry-run
- **[ERROR]** (vermelho) - Erros que requerem atenção

### Exemplo de Saída

```
[INFO] Starting disaster recovery for cluster: cluster-1-z1msjfjd
[INFO] Checking dependencies...
[SUCCESS] Dependencies check passed
[INFO] Auto-detecting cluster ID from Terraform output...
[SUCCESS] Auto-detected cluster ID: cluster-1-z1msjfjd
[INFO] CloudMonkey is already installed
[INFO] Configuring CloudMonkey...
[SUCCESS] CloudMonkey configured successfully
[INFO] Retrieving VMs for cluster: cluster-1-z1msjfjd
[SUCCESS] Found VMs: i-123-456-VM i-789-012-VM
...
[SUCCESS] Disaster recovery completed successfully!

Next steps:
  1. Run 'cd terraform && terraform plan' to review changes
  2. Run 'cd terraform && terraform apply' to apply tags to new worker disks
  3. Verify your applications are running correctly
```

## Pós-Recuperação

Após a execução bem-sucedida do script:

### 1. Validação do Terraform

```bash
cd terraform
terraform plan
```

Verifique se as mudanças mostradas estão corretas (principalmente tags nos novos discos).

### 2. Aplicação das Mudanças

```bash
terraform apply
```

Confirme a aplicação das tags nos novos discos de dados.

### 3. Verificação dos Serviços

```bash
# Conectar ao manager principal
ssh -p 22001 ubuntu@<ip-publico>

# Verificar status do swarm
docker node ls

# Verificar serviços
docker service ls

# Verificar logs se necessário
docker service logs <nome-do-servico>
```

### 4. Teste das Aplicações

- Acesse a aplicação, por exemplo: `https://portal.seudominio.com`
- Acesse o Traefik Dashboard: `https://traefik.seudominio.com`
- Verifique se os dados foram restaurados corretamente

## Solução de Problemas

### Erros Comuns

#### 1. CloudMonkey Não Instalado

```
[ERROR] CloudMonkey (cmk) é necessário mas não está instalado.
```

**Solução**: 
- Instale o CloudMonkey seguindo as instruções em [https://github.com/apache/cloudstack-cloudmonkey/releases](https://github.com/apache/cloudstack-cloudmonkey/releases)
- Certifique-se de que o binário `cmk` está no PATH

#### 2. Credenciais Inválidas

```
[ERROR] Variável de ambiente CLOUDSTACK_API_KEY é obrigatória
```

**Solução**: Defina as variáveis de ambiente corretas.

#### 3. Cluster ID Não Encontrado

```
[ERROR] Não foi possível obter o ID do cluster da saída do Terraform
```

**Solução**: 
- Verifique se a infraestrutura foi implantada com `terraform apply`
- Confirme que o output `cluster_id` está definido no Terraform
- Verifique se o backend do Terraform está configurado corretamente
- Teste manualmente: `cd terraform && terraform output cluster_id`

#### 4. VMs do Cluster Não Encontradas

```
[ERROR] Nenhuma VM encontrada para o cluster: cluster-1-xyz
```

**Solução**: 
- Verifique se o cluster ID está correto
- Confirme que as VMs têm as tags apropriadas
- Se especificou um cluster ID manualmente, verifique se está correto

#### 5. Snapshots Não Encontrados

```
[ERROR] Nenhum snapshot encontrado para o worker: mysql
```

**Solução**: Verifique se os snapshots estão sendo criados automaticamente e se as tags estão corretas.

#### 6. Problemas de Conectividade

```
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

Se o script falhar, você pode executar os comandos manualmente seguindo o processo descrito em `DR.md`.

## Alterações na Implementação

### Versão Atual

- **Auto-detecção de Cluster ID**: O script agora detecta automaticamente o cluster ID a partir da saída do Terraform, eliminando a necessidade de especificar manualmente na maioria dos casos.
- **Script Unificado**: Todas as funcionalidades foram consolidadas no script principal `dr.sh`, removendo a necessidade de scripts auxiliares separados.

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
3. Revise o arquivo `DR.md` para detalhes técnicos dos comandos
