#!/bin/bash
set -euo pipefail

RESET="\033[0m"; BOLD="\033[1m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; RED="\033[0;31m"; CYAN="\033[0;36m"; BLUE="\033[0;34m"; WHITE="\033[1;37m"

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${RESET} $*"; }
erro()    { echo -e "${RED}[ERRO]${RESET}  $*"; }
step()    { echo -e "\n${BOLD}${BLUE}==>${RESET}${BOLD} $*${RESET}"; }
separador(){ echo -e "${BLUE}──────────────────────────────────────────────────────${RESET}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_PADRAO="${SCRIPT_DIR}/usuarios.csv"

CRIADOS=0; PULADOS=0; FALHAS=0
GRUPOS_FINAL=(); GRUPOS_INEXISTENTES=(); SUDO_IGNORADO=0

uso() {
    cat <<'EOF'
Uso:
  sudo bash criar_usuario_ubuntu.sh                              Detecção automática (usuarios.csv ou interativo)
  sudo bash criar_usuario_ubuntu.sh --interativo                 Força o modo interativo
  sudo bash criar_usuario_ubuntu.sh --csv arquivo.csv            CSV com confirmação (arquivo específico)
  sudo bash criar_usuario_ubuntu.sh <login> ["Nome"] [grupos]    Linha única (grupos separados por ;)

CSV: nome_completo,login,grupos_extras   (cabeçalho opcional; grupos separados por ;)
O usuário criado NUNCA é adicionado ao grupo sudo.
EOF
}

# ── Argumentos ────────────────────────────────────────────────────────────────
MODO="auto"; CSV_ARQUIVO=""
if [[ $# -eq 0 ]]; then
    MODO="auto"
else
    case "$1" in
        -h|--help)
            uso; exit 0 ;;
        --interativo)
            [[ $# -eq 1 ]] || { erro "--interativo não aceita argumentos adicionais."; uso; exit 1; }
            MODO="interativo" ;;
        --csv)
            [[ $# -eq 2 ]] || { erro "Uso: --csv arquivo.csv"; uso; exit 1; }
            MODO="csv"; CSV_ARQUIVO="$2" ;;
        --*)
            erro "Opção desconhecida: $1"; uso; exit 1 ;;
        *)
            [[ $# -le 3 ]] || { erro "Argumentos demais: informe <login> [\"Nome\"] [grupos]."; uso; exit 1; }
            for arg in "$@"; do
                [[ "$arg" != --* ]] || { erro "Argumento inválido no modo linha única: ${arg}"; uso; exit 1; }
            done
            MODO="linha" ;;
    esac
fi

# ── Funções auxiliares ────────────────────────────────────────────────────────
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

ler() {
    local -n _destino=$1
    IFS= read -r _destino || { echo; erro "Entrada encerrada."; exit 1; }
}

sem_acentos() {
    local s="$1" par
    local -a mapa=(
        "á:a" "à:a" "â:a" "ã:a" "ä:a" "é:e" "è:e" "ê:e" "ë:e" "í:i" "ì:i" "î:i" "ï:i"
        "ó:o" "ò:o" "ô:o" "õ:o" "ö:o" "ú:u" "ù:u" "û:u" "ü:u" "ç:c" "ñ:n"
        "Á:A" "À:A" "Â:A" "Ã:A" "Ä:A" "É:E" "È:E" "Ê:E" "Ë:E" "Í:I" "Ì:I" "Î:I" "Ï:I"
        "Ó:O" "Ò:O" "Ô:O" "Õ:O" "Ö:O" "Ú:U" "Ù:U" "Û:U" "Ü:U" "Ç:C" "Ñ:N"
    )
    for par in "${mapa[@]}"; do
        s="${s//"${par%%:*}"/"${par##*:}"}"
    done
    printf '%s' "$s"
}

# Primeira letra do primeiro nome + último sobrenome, minúsculo, sem acento.
sugerir_login() {
    local n base
    local -a partes
    n=$(sem_acentos "$1")
    n="${n,,}"
    read -ra partes <<< "$n"
    if (( ${#partes[@]} == 0 )); then
        return 0
    elif (( ${#partes[@]} == 1 )); then
        base="${partes[0]}"
    else
        base="${partes[0]:0:1}${partes[${#partes[@]}-1]}"
    fi
    base="${base//[^a-z0-9]/}"
    printf '%s' "${base:0:32}"
}

login_valido() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }

# O campo GECOS (-c) não pode conter ':' nem quebras de linha; ',' separa subcampos.
sanear_nome() {
    local s="$1"
    s="${s//[:,]/ }"
    s="${s//[$'\t\r\n']/ }"
    trim "$s"
}

# Regra absoluta: 'sudo' nunca é aplicado. Preenche GRUPOS_FINAL, GRUPOS_INEXISTENTES e SUDO_IGNORADO.
filtrar_grupos() {
    local raw="$1" g
    local -a lista
    GRUPOS_FINAL=(); GRUPOS_INEXISTENTES=(); SUDO_IGNORADO=0
    raw="${raw//[,;]/ }"
    read -ra lista <<< "$raw"
    for g in "${lista[@]}"; do
        if [[ "${g,,}" == "sudo" ]]; then
            SUDO_IGNORADO=1
            continue
        fi
        if ! getent group "$g" >/dev/null 2>&1; then
            GRUPOS_INEXISTENTES+=("$g")
            continue
        fi
        case " ${GRUPOS_FINAL[*]:-} " in *" ${g} "*) continue ;; esac
        GRUPOS_FINAL+=("$g")
    done
}

avisar_grupos() {
    if (( SUDO_IGNORADO )); then
        warn "O grupo 'sudo' foi ignorado: este script nunca concede privilégios de administrador."
    fi
    if (( ${#GRUPOS_INEXISTENTES[@]} > 0 )); then
        warn "Grupos inexistentes ignorados: ${GRUPOS_INEXISTENTES[*]}"
    fi
}

grupos_csv() { local IFS=,; printf '%s' "${GRUPOS_FINAL[*]:-}"; }

gerar_senha() {
    local senha=""
    if command -v openssl &>/dev/null; then
        senha=$(openssl rand -base64 12)
    else
        senha=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16 || true)
    fi
    [[ ${#senha} -ge 12 ]] || return 1
    printf '%s' "$senha"
}

desfazer_conta() {
    userdel -r "$1" &>/dev/null || true
    warn "Conta '${1}' removida (não foi possível concluir a configuração)."
}

# Retorno: 0 = criado · 1 = falha · 2 = ignorado (já existe)
criar_usuario() {
    local login="$1" nome="$2" grupos_raw="$3" nome_ok senha home

    if ! login_valido "$login"; then
        erro "Login inválido: '${login}' (minúsculas, números, '_' ou '-'; até 32 caracteres; começar com letra ou '_')."
        return 1
    fi
    if getent passwd "$login" >/dev/null 2>&1; then
        warn "Usuário '${login}' já existe — ignorado."
        return 2
    fi
    if getent group "$login" >/dev/null 2>&1; then
        warn "Já existe um grupo chamado '${login}' — ignorado."
        return 2
    fi

    nome_ok=$(sanear_nome "${nome:-$login}")
    [[ -n "$nome_ok" ]] || nome_ok="$login"
    if [[ "$nome_ok" != "${nome:-$login}" ]]; then
        warn "Caracteres ':' e ',' removidos do nome completo."
    fi

    filtrar_grupos "$grupos_raw"
    avisar_grupos

    step "Criando usuário '${login}'..."
    if ! useradd -m -c "$nome_ok" -s /bin/bash "$login"; then
        erro "Falha ao criar o usuário '${login}'."
        return 1
    fi
    home=$(getent passwd "$login" | cut -d: -f6)
    ok "Conta criada (home: ${home})."

    if (( ${#GRUPOS_FINAL[@]} > 0 )); then
        if usermod -aG "$(grupos_csv)" "$login"; then
            ok "Grupos extras aplicados: $(grupos_csv)"
        else
            warn "Não foi possível aplicar os grupos extras a '${login}'."
        fi
    fi

    if ! senha=$(gerar_senha); then
        erro "Não foi possível gerar a senha temporária."
        desfazer_conta "$login"
        return 1
    fi
    if ! printf '%s:%s\n' "$login" "$senha" | chpasswd; then
        erro "Falha ao definir a senha de '${login}'."
        desfazer_conta "$login"
        return 1
    fi
    if ! passwd -e "$login" >/dev/null; then
        erro "Falha ao expirar a senha de '${login}'."
        desfazer_conta "$login"
        return 1
    fi
    ok "Senha temporária definida e expirada (troca obrigatória no primeiro login)."

    if id -nG "$login" | tr ' ' '\n' | grep -qx "sudo"; then
        erro "O usuário '${login}' ficou no grupo sudo — operação desfeita."
        desfazer_conta "$login"
        return 1
    fi
    ok "Confirmado: '${login}' não pertence ao grupo sudo."

    separador
    echo -e "  ${BOLD}Credenciais de acesso${RESET}"
    printf "  Login : ${GREEN}%s${RESET}\n" "$login"
    printf "  Senha : ${YELLOW}%s${RESET}\n" "$senha"
    echo -e "  ${YELLOW}Anote agora: esta senha não será exibida novamente nem foi gravada em arquivo.${RESET}"
    separador
    senha=""
    return 0
}

processar_usuario() {
    local rc=0
    criar_usuario "$@" || rc=$?
    case "$rc" in
        0) CRIADOS=$((CRIADOS + 1)) ;;
        2) PULADOS=$((PULADOS + 1)) ;;
        *) FALHAS=$((FALHAS + 1)) ;;
    esac
    return 0
}

# ── Modo 1 — Interativo ───────────────────────────────────────────────────────
modo_interativo() {
    local nome login sugestao grupos resp

    step "Modo interativo — novo usuário"
    while true; do
        echo -n -e "  ${CYAN}Nome completo:${RESET} "
        ler nome
        nome=$(sanear_nome "$nome")
        [[ -n "$nome" ]] && break
        warn "O nome completo não pode ficar vazio."
    done

    sugestao=$(sugerir_login "$nome")
    while true; do
        if [[ -n "$sugestao" ]]; then
            echo -n -e "  ${CYAN}Login${RESET} [${GREEN}${sugestao}${RESET}] (Enter para aceitar ou digite outro): "
        else
            echo -n -e "  ${CYAN}Login:${RESET} "
        fi
        ler login
        login=$(trim "$login")
        login="${login:-$sugestao}"
        if ! login_valido "$login"; then
            warn "Login inválido (minúsculas, números, '_' ou '-'; até 32 caracteres; começar com letra ou '_')."
            continue
        fi
        if getent passwd "$login" >/dev/null 2>&1 || getent group "$login" >/dev/null 2>&1; then
            warn "O login '${login}' já está em uso. Escolha outro."
            continue
        fi
        break
    done

    echo -n -e "  ${CYAN}Grupos extras${RESET} (separados por vírgula ou ';' · Enter para nenhum): "
    ler grupos
    filtrar_grupos "$grupos"
    avisar_grupos

    separador
    echo -e "  ${BOLD}Resumo${RESET}"
    echo    "  Nome  : ${nome}"
    echo    "  Login : ${login}"
    echo    "  Grupos: ${GRUPOS_FINAL[*]:-(nenhum)}"
    echo    "  Sudo  : não (este script nunca concede sudo)"
    separador
    echo -n -e "  ${YELLOW}Confirmar criação? [s/N]:${RESET} "
    ler resp
    [[ "$resp" =~ ^[sS]$ ]] || { info "Operação cancelada."; exit 0; }

    processar_usuario "$login" "$nome" "${GRUPOS_FINAL[*]:-}"
}

# ── Modo 2 — CSV com confirmação ──────────────────────────────────────────────
modo_csv() {
    local arquivo="$1" linha f1 f2 f3 l1 l2 i total status a_criar=0 resp
    local numlinha=0 cab_verificado=0
    local -a NOMES=() LOGINS=() GRUPOS=() ESTADOS=()
    local -A vistos=()

    step "Modo CSV — lendo ${arquivo}"
    if [[ ! -f "$arquivo" || ! -r "$arquivo" ]]; then
        erro "Arquivo CSV não encontrado ou sem permissão de leitura: ${arquivo}"
        exit 1
    fi

    while IFS= read -r linha || [[ -n "$linha" ]]; do
        linha="${linha%$'\r'}"
        numlinha=$((numlinha + 1))
        (( numlinha == 1 )) && linha="${linha#$'\xef\xbb\xbf'}"
        [[ -n "$(trim "$linha")" ]] || continue
        [[ "$(trim "$linha")" != \#* ]] || continue

        f1=""; f2=""; f3=""
        IFS=, read -r f1 f2 f3 <<< "$linha" || true
        f1=$(trim "$f1"); f2=$(trim "$f2"); f3=$(trim "$f3")

        if (( ! cab_verificado )); then
            cab_verificado=1
            l1="${f1,,}"; l2="${f2,,}"
            if [[ "$l1" =~ ^(nome_completo|nome|nome\ completo)$ || "$l2" == "login" ]]; then
                info "Cabeçalho detectado na linha ${numlinha} — ignorado."
                continue
            fi
        fi

        NOMES+=("$f1"); LOGINS+=("$f2"); GRUPOS+=("$f3")
        if [[ -z "$f2" ]]; then
            ESTADOS+=("login ausente")
        elif ! login_valido "$f2"; then
            ESTADOS+=("login inválido")
        elif [[ -n "${vistos[$f2]:-}" ]]; then
            ESTADOS+=("duplicado no CSV")
        elif getent passwd "$f2" >/dev/null 2>&1 || getent group "$f2" >/dev/null 2>&1; then
            ESTADOS+=("já existe")
            vistos[$f2]=1
        else
            ESTADOS+=("criar")
            vistos[$f2]=1
        fi
    done < "$arquivo"

    total=${#LOGINS[@]}
    if (( total == 0 )); then
        warn "Nenhum usuário encontrado no arquivo."
        exit 0
    fi

    separador
    echo -e "  ${BOLD}Usuários no arquivo (${total})${RESET}"
    printf "  %-3s %-26s %-16s %-22s %s\n" "#" "Nome completo" "Login" "Grupos extras" "Situação"
    for (( i = 0; i < total; i++ )); do
        filtrar_grupos "${GRUPOS[i]}"
        status="${ESTADOS[i]}"
        if [[ "$status" == "criar" ]]; then
            a_criar=$((a_criar + 1))
            status="${GREEN}criar${RESET}"
        else
            status="${YELLOW}${status} — será ignorado${RESET}"
        fi
        (( SUDO_IGNORADO )) && status="${status} ${YELLOW}[sudo ignorado]${RESET}"
        printf "  %-3s %-26s %-16s %-22s %b\n" "$((i + 1))" "${NOMES[i]:-${LOGINS[i]}}" "${LOGINS[i]:--}" "${GRUPOS_FINAL[*]:--}" "$status"
    done
    separador
    echo -e "  Serão criados: ${BOLD}${a_criar}${RESET} de ${total} · Nenhum usuário recebe sudo."

    if (( a_criar == 0 )); then
        warn "Nada a criar."
        exit 0
    fi
    echo -n -e "  ${YELLOW}Processar o arquivo inteiro? [s/N]:${RESET} "
    ler resp
    [[ "$resp" =~ ^[sS]$ ]] || { info "Operação cancelada."; exit 0; }

    for (( i = 0; i < total; i++ )); do
        step "Usuário $((i + 1))/${total} — ${LOGINS[i]:-(sem login)}"
        processar_usuario "${LOGINS[i]}" "${NOMES[i]}" "${GRUPOS[i]}"
    done
}

# ── Modo 3 — Linha única ──────────────────────────────────────────────────────
modo_linha() {
    local login="$1" nome="${2:-}" grupos="${3:-}"
    step "Modo linha única — usuário '${login}'"
    processar_usuario "$login" "${nome:-$login}" "$grupos"
}

# ── Banner e pré-requisitos ───────────────────────────────────────────────────
[[ -t 1 ]] && clear
echo -e "${BOLD}${WHITE}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║ Criação de Usuários Comuns — Ubuntu 24.04 / 26.04     ║"
echo "  ║   Sem privilégios de administrador · Senha temporária ║"
echo "  ║                  ACMR Consultoria                     ║"
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

if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
    warn "Sistema operacional não identificado como Ubuntu."
    echo -n -e "  ${YELLOW}Deseja continuar mesmo assim? [s/N]:${RESET} "
    read -r RESPOSTA
    [[ "$RESPOSTA" =~ ^[sS]$ ]] || { info "Operação cancelada."; exit 0; }
fi

DISTRO_NAME=$(grep "^PRETTY_NAME" /etc/os-release | cut -d= -f2 | tr -d '"')
ok "Distribuição: ${DISTRO_NAME}"

for cmd in useradd usermod userdel chpasswd passwd getent; do
    if ! command -v "$cmd" &>/dev/null; then
        erro "Comando obrigatório não encontrado: ${cmd}"
        exit 1
    fi
done
ok "Ferramentas de gerenciamento de usuários disponíveis."

if command -v openssl &>/dev/null; then
    ok "Geração de senha: openssl."
else
    warn "openssl não encontrado — a senha temporária será gerada a partir de /dev/urandom."
fi

if [[ "$MODO" == "auto" ]]; then
    if [[ -f "$CSV_PADRAO" ]]; then
        info "Arquivo usuarios.csv detectado em ${SCRIPT_DIR} — usando o modo CSV."
        MODO="csv"; CSV_ARQUIVO="$CSV_PADRAO"
    else
        info "Nenhum usuarios.csv em ${SCRIPT_DIR} — usando o modo interativo."
        MODO="interativo"
    fi
fi

separador
echo -e "${BOLD}Todas as verificações passaram. Modo selecionado: ${MODO}${RESET}"
separador
sleep 1

case "$MODO" in
    interativo) modo_interativo ;;
    csv)        modo_csv "$CSV_ARQUIVO" ;;
    linha)      modo_linha "$@" ;;
esac

# ── Resumo ────────────────────────────────────────────────────────────────────
echo
if (( FALHAS == 0 )); then
    echo -e "${BOLD}${GREEN}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║                  Operação concluída!                  ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
else
    echo -e "${BOLD}${YELLOW}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║           Operação concluída com falhas               ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
fi
echo -e "  Criados  : ${GREEN}${CRIADOS}${RESET}"
echo -e "  Ignorados: ${YELLOW}${PULADOS}${RESET}"
echo -e "  Falhas   : ${RED}${FALHAS}${RESET}"
echo -e "  Cada usuário deve trocar a senha temporária no primeiro login."
separador

(( FALHAS == 0 )) || exit 1
