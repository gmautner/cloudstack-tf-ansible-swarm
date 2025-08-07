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
Uso: $0 -c SOURCE_CLUSTER_ID [OPÇÕES]

Script de Recuperação de Desastres para Cluster Docker Swarm no CloudStack

CONCEITO:
    Este script recupera dados de um cluster ANTIGO (destruído) para um cluster NOVO (atual).
    
    - CLUSTER DE ORIGEM (-c): O cluster antigo/destruído de onde vêm os snapshots
    - CLUSTER DE DESTINO: O cluster novo/atual (obtido do Terraform) que receberá os dados

OPÇÕES:
    -c, --cluster-id SOURCE_ID     ID do cluster de origem (snapshots) - OBRIGATÓRIO
    -d, --dry-run                  Simular operações sem executá-las
    -t, --terraform-dir DIR        Caminho para o diretório do Terraform (padrão: terraform)
    -h, --help                     Exibir esta mensagem de ajuda

EXEMPLOS:
    $0 -c cluster-old-xyz123                   # Recuperar do cluster antigo para o novo
    $0 --cluster-id cluster-old-xyz123 --dry-run # Simular recuperação
    $0 -c cluster-old-xyz123 -t /caminho/para/terraform

FLUXO:
    1. Identifica VMs e discos do cluster NOVO (current Terraform state)
    2. Para as VMs do cluster novo
    3. Desanexa os discos novos (vazios)
    4. Recupera snapshots do cluster ANTIGO
    5. Cria volumes dos snapshots e anexa às VMs novas
    6. Reinicia as VMs com os dados recuperados

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
    log_info "Obtendo ID do cluster atual do Terraform..."
    
    # Mudar para o diretório do terraform temporariamente
    local current_dir=$(pwd)
    cd "$TERRAFORM_DIR"
    
    # Obter ID do cluster da saída do terraform
    if TERRAFORM_CLUSTER_ID=$(terraform output -raw cluster_id 2>/dev/null); then
        log_success "ID do cluster atual no Terraform: $TERRAFORM_CLUSTER_ID"
        cd "$current_dir"
    else
        log_error "Não foi possível obter o ID do cluster da saída do Terraform"
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
    local terraform_cluster_id="$1"
    log_info "Validando cluster_id fornecido..."
    
    # Validar que o cluster_id fornecido é diferente do atual
    if [[ "$CLUSTER_ID" == "$terraform_cluster_id" ]]; then
        log_error "O cluster_id de origem ($CLUSTER_ID) é o mesmo do cluster de destino no Terraform"
        echo ""
        echo "Para recuperação de desastre, você deve usar um cluster_id DIFERENTE do atual."
        echo "- Cluster de ORIGEM (-c): O cluster antigo/destruído (snapshots)"
        echo "- Cluster de DESTINO: O cluster novo/atual (Terraform)"
        echo ""
        echo "Cluster de destino (atual no Terraform): $terraform_cluster_id"
        echo "Cluster de origem fornecido: $CLUSTER_ID"
        echo ""
        echo "Use o ID do cluster antigo como parâmetro -c"
        exit 1
    fi
    
    log_success "Cluster_id de origem validado: $CLUSTER_ID (diferente do destino: $terraform_cluster_id)"
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
    
    log_info "Definindo URL da API do CloudStack"
    if cmk set url "$CLOUDSTACK_API_URL"; then
        log_success "URL da API definida com sucesso"
    else
        log_error "Falha ao definir URL da API"
        exit 1
    fi
    
    log_info "Definindo chave de API"
    if cmk set apikey "$CLOUDSTACK_API_KEY"; then
        log_success "Chave de API definida com sucesso"
    else
        log_error "Falha ao definir chave de API"
        exit 1
    fi
    
    log_info "Definindo chave secreta"
    if cmk set secretkey "$CLOUDSTACK_SECRET_KEY"; then
        log_success "Chave secreta definida com sucesso"
    else
        log_error "Falha ao definir chave secreta"
        exit 1
    fi
    
    log_info "Testando conexão com CloudStack..."
    if cmk list zones > /dev/null 2>&1; then
        log_success "Conexão com CloudStack testada com sucesso"
    else
        log_error "Falha ao testar conexão com CloudStack"
        exit 1
    fi
    
    log_success "CloudMonkey configurado com sucesso"
}

get_destination_cluster_vms() {
    local dest_cluster_id="$1"
    log_info "Obtendo VMs do cluster de destino: $dest_cluster_id"
    
    local cmd="cmk list virtualmachines | jq -r '.virtualmachine[]? | select(.tags[]? | .key==\"cluster_id\" and .value==\"$dest_cluster_id\") | .id'"
    VM_IDS=$(eval "$cmd")
    
    if [[ -z "$VM_IDS" ]]; then
        log_error "Nenhuma VM encontrada no cluster de destino: $dest_cluster_id"
        exit 1
    fi
    
    log_success "VMs do cluster de destino encontradas: $(echo "$VM_IDS" | tr '\n' ' ')"
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

start_vms() {
    local vm_ids="$1"
    log_info "Iniciando VMs..."
    
    while IFS= read -r vm_id; do
        [[ -n "$vm_id" ]] || continue
        execute_command "cmk start virtualmachine id='$vm_id'" "Iniciando VM: $vm_id"
    done <<< "$vm_ids"
    
    log_success "Todas as VMs iniciadas"
}

get_destination_worker_disks() {
    local dest_cluster_id="$1"
    log_info "Obtendo discos dos workers do cluster de destino: $dest_cluster_id"
    
    local cmd="cmk list volumes | jq -r '.volume[]? | select(.tags[]? | .key==\"cluster_id\" and .value==\"$dest_cluster_id\") | select(.tags[]? | .key==\"role\" and .value==\"worker\") | .id'"
    DISK_IDS=$(eval "$cmd")
    
    if [[ -z "$DISK_IDS" ]]; then
        log_error "Nenhum disco de worker encontrado no cluster de destino: $dest_cluster_id"
        exit 1
    fi
    
    log_success "Discos de workers do cluster de destino encontrados: $(echo "$DISK_IDS" | tr '\n' ' ')"
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

get_destination_worker_names() {
    local dest_cluster_id="$1"
    log_info "Obtendo nomes dos workers do cluster de destino: $dest_cluster_id"
    
    local cmd="cmk list virtualmachines | jq -r '.virtualmachine[]? | select(.tags[]? | .key==\"cluster_id\" and .value==\"$dest_cluster_id\") | select(.tags[]? | .key==\"role\" and .value==\"worker\") | .tags[] | select(.key==\"name\") | .value'"
    WORKER_NAMES=$(eval "$cmd")
    
    if [[ -z "$WORKER_NAMES" ]]; then
        log_error "Nenhum nome de worker encontrado no cluster de destino: $dest_cluster_id"
        exit 1
    fi
    
    log_success "Workers do cluster de destino encontrados: $(echo "$WORKER_NAMES" | tr '\n' ' ')"
}

recover_worker_snapshots() {
    local worker_names="$1"
    local source_cluster_id="$2"
    local dest_cluster_id="$3"
    
    log_info "Recuperando snapshots dos workers..."
    log_info "Cluster de origem (snapshots): $source_cluster_id"
    log_info "Cluster de destino (VMs): $dest_cluster_id"
    
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S%z")
    
    while IFS= read -r worker_name; do
        [[ -n "$worker_name" ]] || continue
        
        log_info "Processando worker: $worker_name"
        
        # Get worker VM ID from DESTINATION cluster
        local worker_vm_id
        local vm_cmd="cmk list virtualmachines | jq -r '.virtualmachine[]? | select(.tags[]? | .key==\"cluster_id\" and .value==\"$dest_cluster_id\") | select(.name==\"$worker_name\") | .id'"
        worker_vm_id=$(eval "$vm_cmd")
        
        if [[ -z "$worker_vm_id" ]]; then
            log_error "VM não encontrada para o worker: $worker_name no cluster de destino: $dest_cluster_id"
            continue
        fi
        
        # Listar snapshots do SOURCE cluster para este worker
        local snapshots_cmd="cmk list snapshots | jq '.snapshot[]? | select(.tags[]? | .key==\"cluster_id\" and .value==\"$source_cluster_id\") | select(.name | test(\"^${worker_name}_${worker_name}-data\")) | {id: .id, created: .created}' | jq -s 'sort_by(.created)'"
        
        log_info "Snapshots do cluster de origem ($source_cluster_id) para $worker_name:"
        local snapshot_list
        snapshot_list=$(eval "$snapshots_cmd")
        
        if [[ -n "$snapshot_list" && "$snapshot_list" != "[]" ]]; then
            echo "$snapshot_list" | jq -r '.[] | "  ID: \(.id), Criado: \(.created)"'
        else
            log_warning "Nenhum snapshot encontrado para $worker_name no cluster de origem: $source_cluster_id"
        fi
        
        # Get most recent snapshot ID from SOURCE cluster
        local latest_snapshot_cmd="cmk list snapshots | jq '.snapshot[]? | select(.tags[]? | .key==\"cluster_id\" and .value==\"$source_cluster_id\") | select(.name | test(\"^${worker_name}_${worker_name}-data\"))' | jq -sr 'sort_by(.created) | last | .id'"
        local latest_snapshot_id
        latest_snapshot_id=$(eval "$latest_snapshot_cmd")
        
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
            
            if [[ -z "$new_volume_id" ]]; then
                log_error "Não foi possível obter o ID do novo volume para $worker_name"
                continue
            fi
        fi
        
        log_info "Novo ID do volume para $worker_name: $new_volume_id"
        
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
        log_error "O cluster_id de origem é obrigatório para recuperação de desastre"
        echo ""
        echo "Use a opção -c ou --cluster-id para especificar o cluster de origem (antigo)."
        echo "Este deve ser o ID do cluster destruído de onde vêm os snapshots."
        echo ""
        show_usage
        exit 1
    fi
    
    # Get destination cluster ID from Terraform (call only once)
    get_terraform_cluster_id
    
    # Validar que o cluster_id é diferente do atual no Terraform
    validate_cluster_id "$TERRAFORM_CLUSTER_ID"
    
    log_info "Iniciando recuperação de desastre para o cluster: $CLUSTER_ID"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "MODO SIMULAÇÃO - Nenhuma alteração real será feita"
    fi
    
    # Execute disaster recovery steps
    check_dependencies
    check_cloudmonkey
    configure_cloudmonkey
    log_info "Cluster de destino (novo): $TERRAFORM_CLUSTER_ID"
    log_info "Cluster de origem (recuperação): $CLUSTER_ID"
    
    get_destination_cluster_vms "$TERRAFORM_CLUSTER_ID"
    stop_vms "$VM_IDS"
    
    get_destination_worker_disks "$TERRAFORM_CLUSTER_ID"
    detach_worker_disks "$DISK_IDS"
    
    get_destination_worker_names "$TERRAFORM_CLUSTER_ID"
    recover_worker_snapshots "$WORKER_NAMES" "$CLUSTER_ID" "$TERRAFORM_CLUSTER_ID"
    
    start_vms "$VM_IDS"
    
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