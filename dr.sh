#!/bin/bash

# Disaster Recovery Script for CloudStack Terraform + Ansible Docker Swarm
# This script recovers worker data disks from snapshots and updates Terraform state

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
DRY_RUN=false
CLUSTER_ID=""
TERRAFORM_DIR="terraform"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
Uso: $0 -c CLUSTER_ID [OPÇÕES]

Script de Recuperação de Desastres para Cluster Docker Swarm no CloudStack

OPÇÕES:
    -c, --cluster-id CLUSTER_ID    ID do cluster a ser recuperado (OBRIGATÓRIO - deve ser diferente do cluster atual)
    -d, --dry-run                  Exibir comandos sem executá-los
    -t, --terraform-dir DIR        Caminho para o diretório do Terraform (padrão: terraform)
    -h, --help                     Exibir esta mensagem de ajuda

EXEMPLOS:
    $0 -c cluster-1-z1msjfjd                   # Usar ID do cluster específico para recuperação
    $0 --cluster-id cluster-1-z1msjfjd --dry-run # Modo teste com cluster específico
    $0 -c cluster-1-z1msjfjd -t /caminho/para/terraform

IMPORTANTE:
    O cluster_id fornecido deve ser DIFERENTE do cluster atual no Terraform.
    Isso evita confusão entre snapshots do cluster antigo e do novo cluster limpo.

VARIÁVEIS DE AMBIENTE:
    CLOUDSTACK_API_KEY      Chave de API do CloudStack
    CLOUDSTACK_SECRET_KEY   Chave secreta do CloudStack
    CLOUDSTACK_API_URL      URL da API do CloudStack (padrão: https://painel-cloud.locaweb.com.br/client/api)

EOF
}

execute_command() {
    local cmd="$1"
    local description="$2"
    
    log_info "$description"
    echo "  Comando: $cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[SIMULAÇÃO] Executaria: $cmd"
        return 0
    fi
    
    if eval "$cmd"; then
        log_success "$description concluído"
        return 0
    else
        log_error "$description falhou"
        return 1
    fi
}

check_dependencies() {
    log_info "Verificando dependências..."
    
    # Verificar variáveis de ambiente obrigatórias
    if [[ -z "${CLOUDSTACK_API_URL:-}" ]]; then
        log_error "Variável de ambiente CLOUDSTACK_API_URL é obrigatória"
        exit 1
    fi
    
    if [[ -z "${CLOUDSTACK_API_KEY:-}" ]]; then
        log_error "Variável de ambiente CLOUDSTACK_API_KEY é obrigatória"
        exit 1
    fi
    
    if [[ -z "${CLOUDSTACK_SECRET_KEY:-}" ]]; then
        log_error "Variável de ambiente CLOUDSTACK_SECRET_KEY é obrigatória"
        exit 1
    fi
    
    # Verificar jq
    if ! command -v jq &> /dev/null; then
        log_error "jq é necessário mas não está instalado. Por favor, instale o jq primeiro."
        exit 1
    fi
    
    # Verificar terraform
    if ! command -v terraform &> /dev/null; then
        log_error "terraform é necessário mas não está instalado. Por favor, instale o terraform primeiro."
        exit 1
    fi
    
    # Verificar CloudMonkey
    if ! command -v cmk &> /dev/null; then
        log_error "CloudMonkey (cmk) é necessário mas não está instalado."
        echo ""
        echo "Para instalar o CloudMonkey:"
        echo "1. Acesse: https://github.com/apache/cloudstack-cloudmonkey/releases"
        echo "2. Baixe a versão apropriada para seu sistema"
        echo "3. Torne o arquivo executável: chmod +x cmk"
        echo "4. Mova para um diretório no PATH: sudo mv cmk /usr/local/bin/"
        exit 1
    fi
    
    # Verificar diretório do terraform
    if [[ ! -d "$TERRAFORM_DIR" ]]; then
        log_error "Diretório do Terraform não encontrado: $TERRAFORM_DIR"
        exit 1
    fi
    
    log_success "Verificação de dependências aprovada"
}

get_terraform_cluster_id() {
    log_info "Obtendo ID do cluster atual do Terraform..." >&2
    
    # Mudar para o diretório do terraform temporariamente
    local current_dir=$(pwd)
    cd "$TERRAFORM_DIR"
    
    # Obter ID do cluster da saída do terraform
    local cluster_id
    if cluster_id=$(terraform output -raw cluster_id 2>/dev/null); then
        log_success "ID do cluster atual no Terraform: $cluster_id" >&2
        cd "$current_dir"
        # Apenas enviar o valor do ID do cluster para stdout
        echo "$cluster_id"
    else
        log_error "Não foi possível obter o ID do cluster da saída do Terraform" >&2
        echo "" >&2
        echo "Verifique se:" >&2
        echo "- A infraestrutura foi implantada com 'terraform apply'" >&2
        echo "- O output 'cluster_id' está definido no Terraform" >&2
        echo "- O backend do Terraform está configurado corretamente" >&2
        echo "" >&2
        echo "Saídas disponíveis:" >&2
        terraform output >&2 2>/dev/null || echo "Nenhuma saída disponível" >&2
        cd "$current_dir"
        exit 1
    fi
}

validate_cluster_id() {
    log_info "Validando cluster_id fornecido..."
    
    # Obter o cluster_id atual do terraform
    local terraform_cluster_id
    terraform_cluster_id=$(get_terraform_cluster_id)
    
    # Validar que o cluster_id fornecido é diferente do atual
    if [[ "$CLUSTER_ID" == "$terraform_cluster_id" ]]; then
        log_error "O cluster_id fornecido ($CLUSTER_ID) é o mesmo do cluster atual no Terraform"
        echo ""
        echo "Para recuperação de desastre, você deve usar um cluster_id DIFERENTE do atual."
        echo "Isso evita confusão entre snapshots do cluster antigo sendo recuperado"
        echo "e snapshots que serão gerados pelo novo cluster limpo."
        echo ""
        echo "Cluster atual no Terraform: $terraform_cluster_id"
        echo "Cluster fornecido para recuperação: $CLUSTER_ID"
        echo ""
        echo "Efetue a recuperação a partir de um cluster criado do zero, num novo estado do Terraform."
        exit 1
    fi
    
    log_success "Cluster_id validado: $CLUSTER_ID (diferente do atual: $terraform_cluster_id)"
}

check_cloudmonkey() {
    log_info "Verificando CloudMonkey..."
    
    if command -v cmk &> /dev/null; then
        log_success "CloudMonkey encontrado"
        return 0
    else
        log_error "CloudMonkey (cmk) não foi encontrado no PATH"
        echo ""
        echo "Para instalar o CloudMonkey:"
        echo "1. Acesse: https://github.com/apache/cloudstack-cloudmonkey/releases"
        echo "2. Baixe a versão apropriada para seu sistema"
        echo "3. Torne o arquivo executável: chmod +x cmk"
        echo "4. Mova para um diretório no PATH: sudo mv cmk /usr/local/bin/"
        exit 1
    fi
}

configure_cloudmonkey() {
    log_info "Configurando CloudMonkey..."
    
    execute_command "cmk set url '$CLOUDSTACK_API_URL'" "Definindo URL da API do CloudStack"
    execute_command "cmk set apikey '$CLOUDSTACK_API_KEY'" "Definindo chave de API"
    execute_command "cmk set secretkey '$CLOUDSTACK_SECRET_KEY'" "Definindo chave secreta"
    
    log_info "Testando conexão com CloudStack..."
    execute_command "cmk list zones" "Testando conexão com CloudStack"
    
    log_success "CloudMonkey configurado com sucesso"
}

get_cluster_vms() {
    log_info "Obtendo VMs para o cluster: $CLUSTER_ID"
    
    local cmd="cmk list virtualmachines | jq -r '.virtualmachine[]? | select(.tags[]? | .key==\"cluster_id\" and .value==\"$CLUSTER_ID\") | .id'"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[SIMULAÇÃO] Obteria VMs com: $cmd"
        echo "vm-dummy-1"$'\n'"vm-dummy-2" # Retornar IDs fictícios para simulação
        return 0
    fi
    
    local vm_ids
    vm_ids=$(eval "$cmd")
    
    if [[ -z "$vm_ids" ]]; then
        log_error "Nenhuma VM encontrada para o cluster: $CLUSTER_ID"
        exit 1
    fi
    
    log_success "VMs encontradas: $(echo "$vm_ids" | tr '\n' ' ')"
    echo "$vm_ids"
}

stop_vms() {
    local vm_ids="$1"
    log_info "Parando VMs..."
    
    while IFS= read -r vm_id; do
        [[ -n "$vm_id" ]] || continue
        execute_command "cmk stop virtualmachine id='$vm_id'" "Parando VM: $vm_id"
    done <<< "$vm_ids"
    
    log_success "Todas as VMs paradas"
}

get_worker_disks() {
    log_info "Obtendo discos dos workers para o cluster: $CLUSTER_ID"
    
    local cmd="cmk list volumes | jq -r '.volume[]? | select(.tags[]? | .key==\"cluster_id\" and .value==\"$CLUSTER_ID\") | select(.tags[]? | .key==\"role\" and .value==\"worker\") | .id'"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[SIMULAÇÃO] Obteria discos dos workers com: $cmd"
        echo "disk-dummy-1"$'\n'"disk-dummy-2" # Retornar IDs fictícios para simulação
        return 0
    fi
    
    local disk_ids
    disk_ids=$(eval "$cmd")
    
    if [[ -z "$disk_ids" ]]; then
        log_error "Nenhum disco de worker encontrado para o cluster: $CLUSTER_ID"
        exit 1
    fi
    
    log_success "Discos de workers encontrados: $(echo "$disk_ids" | tr '\n' ' ')"
    echo "$disk_ids"
}

detach_worker_disks() {
    local disk_ids="$1"
    log_info "Desanexando discos dos workers..."
    
    while IFS= read -r disk_id; do
        [[ -n "$disk_id" ]] || continue
        execute_command "cmk detach volume id='$disk_id'" "Desanexando disco: $disk_id"
    done <<< "$disk_ids"
    
    log_success "Todos os discos de workers desanexados"
}

get_worker_names() {
    log_info "Obtendo nomes dos workers para o cluster: $CLUSTER_ID"
    
    local cmd="cmk list virtualmachines | jq -r '.virtualmachine[]? | select(.tags[]? | .key==\"cluster_id\" and .value==\"$CLUSTER_ID\") | select(.tags[]? | .key==\"role\" and .value==\"worker\") | .tags[] | select(.key==\"name\") | .value'"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[SIMULAÇÃO] Obteria nomes dos workers com: $cmd"
        echo "wp"$'\n'"mysql" # Retornar nomes fictícios para simulação
        return 0
    fi
    
    local worker_names
    worker_names=$(eval "$cmd")
    
    if [[ -z "$worker_names" ]]; then
        log_error "Nenhum nome de worker encontrado para o cluster: $CLUSTER_ID"
        exit 1
    fi
    
    log_success "Workers encontrados: $(echo "$worker_names" | tr '\n' ' ')"
    echo "$worker_names"
}

recover_worker_snapshots() {
    local worker_names="$1"
    
    log_info "Recuperando snapshots dos workers..."
    
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S%z")
    
    while IFS= read -r worker_name; do
        [[ -n "$worker_name" ]] || continue
        
        log_info "Processando worker: $worker_name"
        
        # Get worker VM ID
        local worker_vm_id
        local vm_cmd="cmk list virtualmachines | jq -r '.virtualmachine[]? | select(.tags[]? | .key==\"cluster_id\" and .value==\"$CLUSTER_ID\") | select(.name==\"$worker_name\") | .id'"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            worker_vm_id="vm-dummy-$worker_name"
        else
            worker_vm_id=$(eval "$vm_cmd")
        fi
        
        # Listar snapshots para este worker
        local snapshots_cmd="cmk list snapshots | jq '.snapshot[]? | select(.tags[]? | .key==\"cluster_id\" and .value==\"$CLUSTER_ID\") | select(.name | test(\"^${worker_name}_${worker_name}-data\")) | {id: .id, created: .created}' | jq -s 'sort_by(.created)'"
        
        log_info "Snapshots para $worker_name:"
        if [[ "$DRY_RUN" == "true" ]]; then
            log_warning "[SIMULAÇÃO] Listaria snapshots com: $snapshots_cmd"
            echo "  [dados fictícios de snapshot]"
        else
            eval "$snapshots_cmd" | jq -r '.[] | "  ID: \(.id), Criado: \(.created)"'
        fi
        
        # Get most recent snapshot ID
        local latest_snapshot_cmd="cmk list snapshots | jq '.snapshot[]? | select(.tags[]? | .key==\"cluster_id\" and .value==\"$CLUSTER_ID\") | select(.name | test(\"^${worker_name}_${worker_name}-data\"))' | jq -sr 'sort_by(.created) | last | .id'"
        
        local latest_snapshot_id
        if [[ "$DRY_RUN" == "true" ]]; then
            latest_snapshot_id="snapshot-dummy-$worker_name"
        else
            latest_snapshot_id=$(eval "$latest_snapshot_cmd")
        fi
        
        if [[ -z "$latest_snapshot_id" || "$latest_snapshot_id" == "null" ]]; then
            log_error "Nenhum snapshot encontrado para o worker: $worker_name"
            continue
        fi
        
        log_info "Snapshot mais recente para $worker_name: $latest_snapshot_id"
        
        # Criar volume a partir do snapshot
        local volume_name="${worker_name}_${worker_name}-data-recovered-${timestamp}"
        execute_command "cmk create volume name='$volume_name' snapshotid='$latest_snapshot_id' virtualmachineid='$worker_vm_id'" "Criando volume a partir do snapshot para $worker_name"
        
        # Get the new volume ID
        local new_volume_cmd="cmk list volumes | jq -r '.volume[]? | select(.name==\"$volume_name\") | .id'"
        local new_volume_id
        
        if [[ "$DRY_RUN" == "true" ]]; then
            new_volume_id="volume-dummy-$worker_name"
        else
            sleep 5 # Wait for volume creation
            new_volume_id=$(eval "$new_volume_cmd")
        fi
        
        log_info "Novo ID do volume para $worker_name: $new_volume_id"
        
        # Iniciar a VM
        execute_command "cmk start virtualmachine id='$worker_vm_id'" "Iniciando VM do worker: $worker_name"
        
        # Atualizar estado do Terraform
        log_info "Atualizando estado do Terraform para $worker_name..."
        
        cd "$TERRAFORM_DIR"
        
        # Remover estado antigo
        execute_command "terraform state rm 'cloudstack_disk.worker_data[\"$worker_name\"]'" "Removendo disco antigo do estado do Terraform"
        
        # Importar novo estado
        execute_command "terraform import 'cloudstack_disk.worker_data[\"$worker_name\"]' '$new_volume_id'" "Importando novo disco para o estado do Terraform"
        
        cd - > /dev/null
        
        log_success "Recuperação do worker $worker_name concluída"
        
    done <<< "$worker_names"
    
    log_success "Todos os snapshots dos workers recuperados"
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--cluster-id)
                CLUSTER_ID="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -t|--terraform-dir)
                TERRAFORM_DIR="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Opção desconhecida: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Verificar se cluster_id foi fornecido (obrigatório)
    if [[ -z "$CLUSTER_ID" ]]; then
        log_error "O cluster_id é obrigatório para recuperação de desastre"
        echo ""
        echo "Use a opção -c ou --cluster-id para especificar o cluster a ser recuperado."
        echo "O cluster_id deve ser DIFERENTE do cluster atual no Terraform."
        echo ""
        show_usage
        exit 1
    fi
    
    # Validar que o cluster_id é diferente do atual no Terraform
    validate_cluster_id
    
    log_info "Iniciando recuperação de desastre para o cluster: $CLUSTER_ID"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "MODO SIMULAÇÃO - Nenhuma alteração real será feita"
    fi
    
    # Execute disaster recovery steps
    check_dependencies
    check_cloudmonkey
    configure_cloudmonkey
    
    local vm_ids
    vm_ids=$(get_cluster_vms)
    
    stop_vms "$vm_ids"
    
    local disk_ids
    disk_ids=$(get_worker_disks)
    
    detach_worker_disks "$disk_ids"
    
    local worker_names
    worker_names=$(get_worker_names)
    
    recover_worker_snapshots "$worker_names"
    
    log_success "Recuperação de desastre concluída com sucesso!"
    
    echo ""
    log_info "Próximos passos:"
    echo "  1. Execute 'cd $TERRAFORM_DIR && terraform plan' para revisar as mudanças"
    echo "  2. Execute 'cd $TERRAFORM_DIR && terraform apply' para aplicar tags aos novos discos dos workers"
    echo "  3. Verifique se suas aplicações estão funcionando corretamente"
}

# Capturar erros e limpeza
trap 'log_error "Script falhou na linha $LINENO"' ERR

# Run main function
main "$@"