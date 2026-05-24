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
echo "  ║       Instalação do Google Chrome — Ubuntu 24.04      ║"
echo "  ║          Canal Stable · Repositório APT oficial        ║"
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
    warn "O Google Chrome para Linux só está disponível para amd64 (x86_64)."
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

if command -v google-chrome &>/dev/null; then
    VERSAO_ATUAL=$(google-chrome --version 2>/dev/null)
    warn "Google Chrome já está instalado: ${VERSAO_ATUAL}"
    echo -n -e "  ${YELLOW}Deseja reinstalar / atualizar? [s/N]:${RESET} "
    read -r RESPOSTA
    [[ "$RESPOSTA" =~ ^[sS]$ ]] || { info "Instalação cancelada pelo usuário."; exit 0; }
fi

info "Verificando conectividade com dl.google.com..."
if ! curl -fsSL --max-time 10 --head "https://dl.google.com" &>/dev/null; then
    erro "Sem acesso a dl.google.com. Verifique a conexão com a internet."
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

step "Passo 3/6 — Importando chave GPG do Google..."
KEYRING_FILE="/usr/share/keyrings/google-chrome.gpg"
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor --yes -o "$KEYRING_FILE"
ok "Chave GPG salva em: ${KEYRING_FILE}"

step "Passo 4/6 — Adicionando repositório do Google Chrome..."
SOURCE_FILE="/etc/apt/sources.list.d/google-chrome.sources"
CONFLITOS=$(grep -Ril "dl.google.com/linux/chrome/deb" /etc/apt/sources.list.d 2>/dev/null || true)
if [[ -n "$CONFLITOS" && "$CONFLITOS" != "$SOURCE_FILE" ]]; then
    warn "Removendo arquivos conflitantes..."
    echo "$CONFLITOS" | xargs rm -f
fi
printf '%s\n' 'Types: deb' 'URIs: https://dl.google.com/linux/chrome/deb/' 'Suites: stable' 'Components: main' 'Architectures: amd64' "Signed-By: ${KEYRING_FILE}" > "$SOURCE_FILE"
ok "Repositório configurado."

step "Passo 5/6 — Atualizando APT com novo repositório..."
apt-get update -qq
CANDIDATO=$(apt-cache policy google-chrome-stable 2>/dev/null | grep "Candidate:" | awk '{print $2}')
if [[ -z "$CANDIDATO" ]]; then
    erro "Pacote google-chrome-stable não encontrado."
    exit 1
fi
ok "Versão candidata: ${CANDIDATO}"

step "Passo 6/6 — Instalando Google Chrome Stable..."
apt-get install -y google-chrome-stable

separador
step "Validando instalação..."
if command -v google-chrome &>/dev/null; then
    VERSAO=$(google-chrome --version 2>/dev/null)
    ok "Google Chrome instalado com sucesso!"
    echo -e "  ${GREEN}Versão: ${VERSAO}${RESET}"
else
    erro "Google Chrome não encontrado após instalação."
    exit 1
fi

separador
echo -e "${BOLD}${GREEN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║              Instalação concluída com êxito!          ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  Terminal : ${CYAN}google-chrome${RESET}"
echo -e "  Workspace: Activities → Google Chrome"
echo -e "  Atualizar: ${CYAN}sudo apt update && sudo apt upgrade google-chrome-stable -y${RESET}"
separador
