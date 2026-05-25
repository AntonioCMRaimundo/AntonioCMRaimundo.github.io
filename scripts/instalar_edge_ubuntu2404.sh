#!/bin/bash
set -euo pipefail

RESET="\033[0m"; BOLD="\033[1m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; RED="\033[0;31m"; CYAN="\033[0;36m"; BLUE="\033[0;34m"; WHITE="\033[1;37m"

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${RESET} $*"; }
erro()    { echo -e "${RED}[ERRO]${RESET}  $*"; }
step()    { echo -e "\n${BOLD}${BLUE}==>${RESET}${BOLD} $*${RESET}"; }
separador(){ echo -e "${BLUE}──────────────────────────────────────────────────────${RESET}"; }

clear
echo -e "${BOLD}${WHITE}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║      Instalação do Microsoft Edge — Ubuntu 24.04      ║"
echo "  ║       Canal Stable · Repositório APT oficial           ║"
echo "  ║                  ACMR Consultoria                      ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"
separador

step "Verificando pré-requisitos..."

if [[ $EUID -ne 0 ]]; then
    erro "Este script precisa ser executado com sudo."
    echo -e "  Execute: ${YELLOW}sudo bash $0${RESET}"
    exit 1
fi
ok "Executando com privilégios de superusuário."

ARCH=$(dpkg --print-architecture)
if [[ "$ARCH" != "amd64" ]]; then
    erro "Arquitetura não suportada: ${ARCH}"
    warn "O Microsoft Edge para Linux só está disponível para amd64 (x86_64)."
    exit 1
fi
ok "Arquitetura: ${ARCH} — compatível."

if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
    warn "Sistema operacional não identificado como Ubuntu."
    echo -n -e "  ${YELLOW}Deseja continuar mesmo assim? [s/N]:${RESET} "
    read -r RESPOSTA
    [[ "$RESPOSTA" =~ ^[sS]$ ]] || { info "Instalação cancelada."; exit 0; }
fi

DISTRO_NAME=$(grep "^PRETTY_NAME" /etc/os-release | cut -d= -f2 | tr -d '"')
ok "Distribuição: ${DISTRO_NAME}"

if command -v microsoft-edge &>/dev/null; then
    VERSAO_ATUAL=$(microsoft-edge --version 2>/dev/null)
    warn "Microsoft Edge já está instalado: ${VERSAO_ATUAL}"
    echo -n -e "  ${YELLOW}Deseja reinstalar / atualizar? [s/N]:${RESET} "
    read -r RESPOSTA
    [[ "$RESPOSTA" =~ ^[sS]$ ]] || { info "Instalação cancelada pelo usuário."; exit 0; }
fi

info "Verificando conectividade com packages.microsoft.com..."
if ! curl -fsSL --max-time 10 --head "https://packages.microsoft.com" &>/dev/null; then
    erro "Sem acesso a packages.microsoft.com. Verifique a conexão com a internet."
    exit 1
fi
ok "Conectividade confirmada."

separador
echo -e "${BOLD}Todas as verificações passaram. Iniciando instalação...${RESET}"
separador
sleep 1

step "Passo 1/6 — Atualizando lista de pacotes..."
apt-get update -qq
ok "Lista de pacotes atualizada."

step "Passo 2/6 — Instalando dependências..."
apt-get install -y -qq ca-certificates curl
ok "Dependências instaladas."

step "Passo 3/6 — Importando chave GPG da Microsoft..."
KEYRING_FILE="/usr/share/keyrings/microsoft-edge.gpg"
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor --yes -o "$KEYRING_FILE"
ok "Chave GPG salva em: ${KEYRING_FILE}"

step "Passo 4/6 — Adicionando repositório do Microsoft Edge..."
SOURCE_FILE="/etc/apt/sources.list.d/microsoft-edge.sources"
printf '%s\n' 'Types: deb' 'URIs: https://packages.microsoft.com/repos/edge' 'Suites: stable' 'Components: main' 'Architectures: amd64' "Signed-By: ${KEYRING_FILE}" > "$SOURCE_FILE"
ok "Repositório configurado em: ${SOURCE_FILE}"

step "Passo 5/6 — Atualizando APT com novo repositório..."
apt-get update -qq
CANDIDATO=$(apt-cache policy microsoft-edge-stable 2>/dev/null | grep "Candidate:" | awk '{print $2}')
if [[ -z "$CANDIDATO" ]]; then
    erro "Pacote microsoft-edge-stable não encontrado."
    exit 1
fi
ok "Versão candidata: ${CANDIDATO}"

step "Passo 6/6 — Instalando Microsoft Edge Stable..."
apt-get install -y microsoft-edge-stable

separador
step "Validando instalação..."
if command -v microsoft-edge &>/dev/null; then
    VERSAO=$(microsoft-edge --version 2>/dev/null)
    ok "Microsoft Edge instalado com sucesso!"
    echo -e "  ${GREEN}Versão: ${VERSAO}${RESET}"
else
    erro "Microsoft Edge não encontrado após instalação."
    exit 1
fi

separador
echo -e "${BOLD}${GREEN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║              Instalação concluída com êxito!          ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  Terminal : ${CYAN}microsoft-edge${RESET}"
echo -e "  Workspace: Activities → Microsoft Edge"
echo -e "  Atualizar: ${CYAN}sudo apt update && sudo apt upgrade microsoft-edge-stable -y${RESET}"
separador
