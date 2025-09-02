# Design e Arquitetura

Este documento descreve as principais decisões de arquitetura e escolhas de implementação feitas neste repositório. Seu objetivo é fornecer a um engenheiro de DevOps uma compreensão clara da estrutura, fluxo de trabalho e lógica do projeto.

## Filosofia Principal

O objetivo principal é fornecer um **template reutilizável e pronto para produção** para implantar múltiplos ambientes Docker Swarm isolados no CloudStack. O design prioriza:

-   **Clareza em vez de complexidade**: As soluções devem ser explícitas e fáceis de entender. Evitamos scripts "mágicos" em favor de comandos claros e sem estado.
-   **Separação de Responsabilidades**: A lógica principal e reutilizável é estritamente separada da configuração específica do ambiente.
-   **Segurança**: Informações sensíveis, como chaves privadas e senhas, nunca são armazenadas no controle de versão e são tratadas de forma segura.
-   **Automação**: A experiência do usuário é simplificada através de um `Makefile` central que orquestra todas as operações complexas.

## 1. Gerenciamento de Múltiplos Ambientes

Todo o repositório é construído em torno de uma estratégia robusta de múltiplos ambientes.

### Estrutura de Diretórios

O núcleo desta estratégia é o diretório de nível superior `environments/`.

```
environments/
├── dev/
│   ├── terraform.tfvars
│   ├── secrets.yaml
│   ├── inventory.yml  (Gerado)
│   └── stacks/
└── prod/
    ├── terraform.tfvars
    ├── secrets.yaml
    ├── inventory.yml  (Gerado)
    └── stacks/
```

-   **Justificativa**: Esta estrutura centraliza toda a configuração para um determinado ambiente (`dev`, `prod`, etc.) em um local único e previsível. Um engenheiro pode olhar para um diretório e entender tudo sobre as variáveis, segredos e aplicações implantadas desse ambiente. Isso é superior a espalhar arquivos de configuração pelo repositório.

### Orquestração do Fluxo de Trabalho via `Makefile`

O `Makefile` é o ponto de entrada principal para todas as operações. Ele é ciente do ambiente, usando uma variável `ENV` para direcionar uma configuração específica.

-   **Exemplo**: `make deploy ENV=prod`
-   **Justificativa**: Usar um `Makefile` abstrai a complexidade de passar múltiplos caminhos de arquivo e argumentos específicos do ambiente para o Terraform e o Ansible. Ele fornece uma interface simples e consistente para os usuários e para o pipeline de CI/CD.

## 2. Isolamento de Estado do Terraform

Para gerenciar múltiplos ambientes com segurança, seus estados do Terraform devem ser completamente isolados.

-   **Implementação**: Usamos um **backend local** com um caminho dinâmico para cada ambiente.
    -   O backend é explicitamente configurado como `"local"` dentro do bloco `terraform {}` em `terraform/main.tf`.
    -   O `Makefile` fornece dinamicamente o caminho do arquivo de estado durante a inicialização: `terraform init -backend-config="path=../environments/$(ENV)/terraform.tfstate"`.
-   **Justificativa da Decisão**: Esta abordagem é destinada para fins de desenvolvimento, pois simplifica a configuração inicial ao evitar a necessidade de configurar armazenamento de estado remoto e gerenciar credenciais. Para cenários de produção, o armazenamento de estado deve ser orquestrado por meio de um pipeline de CI/CD.

## 3. Gerenciamento de Chaves SSH (Totalmente Automatizado)

O gerenciamento de chaves SSH é projetado para ser seguro e não exigir intervenção manual do usuário.

-   **Implementação**:
    1.  **Geração no CloudStack**: Um recurso `cloudstack_ssh_keypair` no Terraform instrui o CloudStack a gerar um novo par de chaves único para cada ambiente.
    2.  **Armazenamento no Arquivo de Estado**: A chave privada resultante é armazenada de forma segura no arquivo de estado do Terraform.
    3.  **Carregamento Just-in-Time**: O `Makefile` usa o `ssh-agent` para lidar com a autenticação. Antes de um comando `ansible-playbook` ou `ssh` ser executado, um script busca a chave privada da saída do Terraform e a carrega diretamente no `ssh-agent`.
    4.  **Limpeza Robusta**: Um `trap` é usado para garantir que o processo `ssh-agent` seja sempre finalizado e a chave descarregada da memória, mesmo que o usuário interrompa o processo (ex: com Ctrl+C).
-   **Justificativa da Decisão**: Isso é muito superior a exigir que os usuários criem, nomeiem e gerenciem seus próprios arquivos de chave privada. Elimina uma fonte comum de erro do usuário, aumenta a segurança mantendo a chave na memória pelo menor tempo possível e torna todo o processo contínuo.

## 4. Configuração e Dinâmica do Ansible

A configuração do Ansible é projetada para ser genérica e adaptável a qualquer ambiente.

-   **Inventário Específico do Ambiente**: O Terraform gera um arquivo de inventário único para cada ambiente (ex: `environments/dev/inventory.yml`). O `Makefile` passa o caminho correto do inventário para o Ansible usando a flag `-i`. A configuração padrão de `inventory` no `ansible.cfg` foi explicitamente removida para evitar confusão.
-   **Caminhos de Configuração Dinâmicos**: O playbook em si não contém caminhos de configuração fixos. Os caminhos para o `secrets.yaml` e o diretório `stacks` são passados como variáveis pelo `Makefile` (`--extra-vars`).
    -   **Justificativa da Decisão**: Isso foi escolhido em vez de usar links simbólicos. Links simbólicos criariam um processo "mágico" e com estado, onde o conteúdo de `ansible/stacks` mudaria. Passar caminhos explícitos é sem estado, mais claro e torna o comportamento do playbook mais fácil de rastrear.
-   **Docker Compose com Variáveis de Ambiente**:
    -   O projeto utiliza arquivos `docker-compose.yml` padrão, sem um motor de templates.
    -   Valores específicos do ambiente (como `domain_suffix`) são injetados usando a substituição de variáveis de ambiente padrão do Docker Compose (ex: `${DOMAIN_SUFFIX}`).
    -   O playbook do Ansible, ao executar `community.docker.docker_stack`, passa essas variáveis para o ambiente onde os arquivos do Compose são executados.
    -   **Justificativa da Decisão**: Este método está alinhado com as práticas padrão do Docker e elimina uma camada de abstração, tornando os arquivos do Compose imediatamente utilizáveis com `docker-compose` localmente para testes. Também simplifica o playbook do Ansible, que não precisa mais de uma etapa separada de templating.

## 5. Gerenciamento de Segredos

O fluxo de trabalho de segredos é projetado para ser seguro e flexível, aproveitando o gerenciamento de segredos nativo do Docker Swarm.

-   **Declaração de Segredos no Compose**: As definições dos segredos são declaradas diretamente dentro do arquivo `docker-compose.yml` de cada stack, sob a chave de nível superior `secrets:`. Isso serve como o manifesto de segredos necessários para uma stack.
-   **Valores de um Arquivo Central**: Os valores reais dos segredos são carregados em tempo de execução a partir de um único arquivo `secrets.yaml` específico do ambiente (ex: `environments/dev/secrets.yaml`).
-   **Orquestração do Ansible**: O playbook do Ansible é responsável por:
    1.  Encontrar todos os arquivos `docker-compose.yml` para construir uma lista completa de todos os nomes de segredos declarados.
    2.  Verificar se o arquivo `secrets.yaml` existe e tem permissões seguras (`600`).
    3.  Carregar os valores do arquivo `secrets.yaml`.
    4.  Usar o módulo `community.docker.docker_secret` para criar ou atualizar cada segredo no Docker Swarm.
-   **Integração com CI/CD**: Para CI/CD, os valores dos segredos podem ser passados diretamente para o playbook como uma variável extra (`secrets_context`), contornando a necessidade do arquivo `secrets.yaml` no runner.
    -   **Justificativa da Decisão**: Este padrão é robusto e seguro. Ele desacopla a *declaração* de um segredo (no arquivo compose) de seu *valor* (no `secrets.yaml` ou no cofre de CI/CD). Ele aproveita o tratamento nativo de segredos do Docker e impõe boas práticas de segurança, verificando as permissões do arquivo.

## 6. Pipeline de CI/CD

O workflow do GitHub Actions (`.github/workflows/deploy.yml`) é a peça final da automação.

-   **Gatilho Manual**: Ele usa `workflow_dispatch` para permitir que os usuários acionem uma implantação manualmente a partir da interface do GitHub.
-   **Seleção de Ambiente**: Ele solicita ao usuário uma entrada de texto para especificar o ambiente de destino. O nome deve corresponder a um Ambiente GitHub configurado e a um diretório correspondente em `environments/`.
-   **Orquestração**: O trabalho principal do workflow é fornecer os segredos do Ambiente GitHub selecionado e chamar o `Makefile`, passando o nome do ambiente escolhido. Toda a lógica complexa permanece no `Makefile`, mantendo a definição do pipeline de CI limpa e simples.
