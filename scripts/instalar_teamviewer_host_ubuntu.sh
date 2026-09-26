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
echo "  ║ Instalação do TeamViewer Host — Ubuntu 24.04 / 26.04  ║"
echo "  ║         Acesso remoto não assistido · Pacote .deb      ║"
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
    warn "Este script instala o pacote teamviewer-host_amd64.deb (amd64 / x86_64)."
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

if dpkg-query -W -f='${Status}' teamviewer 2>/dev/null | grep -q "install ok installed"; then
    warn "TeamViewer completo (pacote 'teamviewer') está instalado."
    warn "Ele não pode conviver com o TeamViewer Host e será removido antes da instalação."
    CONFLITO_TEAMVIEWER=1
else
    CONFLITO_TEAMVIEWER=0
fi

info "Verificando conectividade com download.teamviewer.com..."
if ! wget --spider --timeout=10 -q "https://download.teamviewer.com"; then
    erro "Sem acesso a download.teamviewer.com. Verifique a conexão com a internet."
    exit 1
fi
ok "Conectividade confirmada."

separador
echo -e "${BOLD}Todas as verificações passaram. Iniciando instalação...${RESET}"
separador
sleep 1

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
chmod 755 "$TMP_DIR"
DEB_FILE="${TMP_DIR}/teamviewer-host_amd64.deb"

step "Passo 1/5 — Atualizando lista de pacotes..."
apt-get update -qq
ok "Lista de pacotes atualizada."

step "Passo 2/5 — Removendo TeamViewer completo (se instalado)..."
if [[ "$CONFLITO_TEAMVIEWER" -eq 1 ]]; then
    apt-get remove -y teamviewer
    ok "TeamViewer completo removido."
else
    ok "TeamViewer completo não está instalado — nada a remover."
fi

step "Passo 3/5 — Baixando o pacote do TeamViewer Host..."
wget -q --show-progress -O "$DEB_FILE" https://download.teamviewer.com/download/linux/teamviewer-host_amd64.deb
chmod 644 "$DEB_FILE"
ok "Pacote baixado."

step "Passo 4/5 — Instalando o TeamViewer Host..."
apt-get install -y "$DEB_FILE"
ok "Pacote instalado."

step "Passo 5/5 — Verificando o serviço teamviewerd..."
systemctl enable --now teamviewerd &>/dev/null || true
sleep 2

separador
step "Validando instalação..."
if systemctl is-active --quiet teamviewerd; then
    ok "Serviço teamviewerd ativo."
else
    erro "Serviço teamviewerd não está ativo após a instalação."
    echo -e "  Diagnóstico: ${CYAN}systemctl status teamviewerd${RESET}"
    exit 1
fi

TV_ID=$(teamviewer info 2>/dev/null | grep -i "TeamViewer ID" | grep -oE '[0-9]{6,}' | head -n1 || true)

separador
echo -e "${BOLD}${GREEN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║              Instalação concluída com êxito!          ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"
if [[ -n "$TV_ID" ]]; then
    echo -e "  ID       : ${GREEN}${TV_ID}${RESET}"
else
    echo -e "  ID       : ${CYAN}sudo teamviewer info${RESET}  (o ID pode levar alguns segundos para aparecer)"
fi
echo -e "  Serviço  : ${CYAN}systemctl status teamviewerd${RESET}"
echo -e "  Atualizar: ${CYAN}sudo apt update && sudo apt upgrade teamviewer-host -y${RESET}"
separador
