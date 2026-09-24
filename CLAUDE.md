# Site ti.raimundo.com.br — ACMR Consultoria

Criado em 24/09/2026 10:21 (BRT) a partir da conversa "ACMR - raimundo.com.br via Claude Chat e Code" (Projeto TI, Claude Chat).

## O que é
- Site de suporte de TI da ACMR Consultoria (MEI de Antonio Carlos Moledo Raimundo).
- Hospedado no GitHub Pages: repositório AntonioCMRaimundo/AntonioCMRaimundo.github.io, branch main, raiz. Push publica em 1-2 min.
- Domínio personalizado: ti.raimundo.com.br (arquivo CNAME na raiz, HTTPS forçado).
- raimundo.com.br (raiz) continua no Google Sites como cartão pessoal neutro; não mexer daqui.

## Como trabalhar comigo
- Sempre responder em português do Brasil.
- Um passo de cada vez: mostrar o que fazer, aguardar o resultado, só então o próximo.
- Antes de datar qualquer arquivo, rodar a hora real em BRT (America/Sao_Paulo); nunca inventar horário.
- Esperar um push terminar antes de iniciar outro commit/push.
- Usar sempre a documentação oficial do fabricante (Google, Microsoft, Canonical/Ubuntu, Ubiquiti, TeamViewer) como fonte dos procedimentos.

## Identidade visual
- Azul escuro #12376B (primária), amarelo #F0BC00 (destaque), fonte system-ui/Arial.
- Logo: logo_ACMR.jpg (feito pelo filho do Antonio Carlos); não substituir por texto.

## Estrutura
- Menu: Início (index.html), Suporte Remoto (suporte-remoto.html), Procedimentos (procedimentos.html), Referências Rápidas (referencias.html).
- Procedimentos em procedimentos/<sistema>/<nome>.html; scripts em scripts/.
- Suporte Remoto: TeamViewer Host (get.teamviewer.com/acmrhost) e Quick Support (get.teamviewer.com/acmrsuporterapido).

## Padrões dos procedimentos
- Título no formato "Sistema/Versão - Ação" (ex.: "Ubuntu 24.04 LTS - Instalação do Google Chrome"), atualizado em <title>, <h1> e na lista; breadcrumb fica curto.
- Lista de procedimentos.html sempre em ordem alfabética pelo título.
- Cada procedimento tem: passos com botão Copiar; seção "Instalação automática via script" com `curl -fsSL https://ti.raimundo.com.br/scripts/<arquivo>.sh | sudo bash`; seção "Baixar e executar manualmente" com botão de download (caminho absoluto /scripts/...) e `sudo bash ~/Downloads/<arquivo>.sh`.
- Mesmo layout visual de procedimentos/linux/chrome-ubuntu.html.

## Regras dos scripts .sh
- Cabeçalho `#!/bin/bash` + `set -euo pipefail`; mensagens [INFO]/[ OK ]/[AVISO]/[ERRO] coloridas.
- Verificar sudo, arquitetura, distribuição, instalação prévia e conectividade antes de instalar.
- Todo comando cuja saída é interpretada deve usar `LANG=C` (o Ubuntu em português traduz "Candidate:" para "Candidato:").
- Usar `|| true` onde um retorno não-zero é esperado e tratado.
- Nunca adicionar usuários ao grupo sudo.

## Histórico relevante
- Script do Edge validado de ponta a ponta em Ubuntu 24.04.4 em português (06/06/2026).
- Script do Chrome corrigido com LANG=C, ainda não re-executado depois da correção.
- suporte.raimundo.com.br e consultoria.raimundo.com.br têm CNAME para antoniocmraimundo.github.io, mas o GitHub Pages aceita um só domínio por site: em 24/09/2026 ambos retornavam 404 (HTTP) e falha de HTTPS.

## Pendências (em 24/09/2026)
1. Decidir o destino de suporte. e consultoria. (repositórios próprios só com redirecionamento, ou remover os CNAMEs).
2. Página Referências Rápidas: ainda "em construção" (tomadas, ferramentas).
3. Procedimentos de Windows e de Redes/Ubiquiti.
4. Script de criação de usuários comuns (sem sudo, senha criada pelo próprio usuário no 1º login via `passwd --expire`), com modos: interativo, CSV com confirmação, linha única e detecção automática.
5. Re-executar o script do Chrome num Ubuntu limpo para validar o LANG=C.
6. Procedimento TeamViewer Terminal Remoto: só publicar depois de resolver a divergência de licença (documentação exige Premium/Corporate/Tensor; na prática funciona com Business).
