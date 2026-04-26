#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# BugHound / SherleKhomes — installateur officiel
# -----------------------------------------------------------------------------
# Servi depuis L'Agence (GitHub Pages — repo public Slama-Consulting/agence).
# Usage attendu :
#
#   curl -fsSL https://slama-consulting.github.io/agence/install.sh | bash
#
# ou, avec pré-remplissage de la config Jira (généré par le formulaire web) :
#
#   JIRA_URL='https://jira.maboite.com' \
#   JIRA_MODE='browser' \
#   curl -fsSL https://slama-consulting.github.io/agence/install.sh | bash
#
# Variables d'environnement lues :
#   - JIRA_URL    (optionnel) → pré-remplit ~/.bughound/config.yaml
#   - JIRA_MODE   (optionnel) → 'browser' (Server/DC + SSO) | 'api' (Cloud)
#   - JIRA_EMAIL  (optionnel) → email Atlassian (mode api uniquement)
#   - BUGHOUND_BASE_URL (optionnel) → racine GitHub Pages.
#                                     Défaut : https://slama-consulting.github.io/agence
#   - BUGHOUND_VERSION  (optionnel) → version cible (par défaut : "latest").
# -----------------------------------------------------------------------------

set -euo pipefail

# ----- helpers ---------------------------------------------------------------
log_info()  { printf '\033[36m[*]\033[0m %s\n' "$*"; }
log_ok()    { printf '\033[32m[✓]\033[0m %s\n' "$*"; }
log_warn()  { printf '\033[33m[!]\033[0m %s\n' "$*" >&2; }
log_error() { printf '\033[31m[✗]\033[0m %s\n' "$*" >&2; }

die() { log_error "$*"; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 \
        || die "Commande requise non trouvée : $1"
}

# ----- configuration ---------------------------------------------------------
BUGHOUND_BASE_URL="${BUGHOUND_BASE_URL:-https://slama-consulting.github.io/agence}"
BUGHOUND_VERSION="${BUGHOUND_VERSION:-latest}"

JIRA_URL="${JIRA_URL:-}"
JIRA_MODE="${JIRA_MODE:-}"
JIRA_EMAIL="${JIRA_EMAIL:-}"

WHEEL_URL=""
if [[ "${BUGHOUND_VERSION}" == "latest" ]]; then
    WHEEL_URL="${BUGHOUND_BASE_URL}/dist/bughound-latest-py3-none-any.whl"
else
    WHEEL_URL="${BUGHOUND_BASE_URL}/dist/bughound-${BUGHOUND_VERSION}-py3-none-any.whl"
fi

TMP_DIR="$(mktemp -d -t bughound-install.XXXXXX)"
WHEEL_PATH="${TMP_DIR}/bughound.whl"

cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

# ----- pré-checks ------------------------------------------------------------
log_info "BugHound / SherleKhomes — installateur"

require_cmd curl
require_cmd python3

# Python ≥ 3.10 (cf. pyproject.toml).
PY_VER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
PY_MAJOR="${PY_VER%%.*}"
PY_MINOR="${PY_VER##*.}"
if (( PY_MAJOR < 3 )) || { (( PY_MAJOR == 3 )) && (( PY_MINOR < 10 )); }; then
    die "Python ≥ 3.10 requis (détecté : ${PY_VER}). \
Installez un Python plus récent puis relancez."
fi
log_ok "Python ${PY_VER} détecté."

# ----- téléchargement de la wheel -------------------------------------------
log_info "Téléchargement de la wheel : ${WHEEL_URL}"
if ! curl -fsSL "${WHEEL_URL}" -o "${WHEEL_PATH}"; then
    die "Impossible de télécharger ${WHEEL_URL}. \
Vérifiez votre connexion Internet et que la page \
${BUGHOUND_BASE_URL} est bien servie."
fi
WHEEL_SIZE="$(wc -c < "${WHEEL_PATH}" | tr -d ' ')"
if (( WHEEL_SIZE < 1024 )); then
    die "Wheel téléchargée suspectement petite (${WHEEL_SIZE} octets). \
Le serveur a peut-être renvoyé une page d'erreur."
fi
log_ok "Wheel téléchargée (${WHEEL_SIZE} octets)."

# ----- installation ----------------------------------------------------------
INSTALLER=""
if command -v pipx >/dev/null 2>&1; then
    INSTALLER="pipx"
elif python3 -m pipx --version >/dev/null 2>&1; then
    INSTALLER="python3 -m pipx"
else
    INSTALLER="python3 -m pip --user"
    log_warn "pipx introuvable — repli sur 'pip --user'. Pour une isolation \
propre, installez pipx (https://pipx.pypa.io)."
fi

log_info "Installation via : ${INSTALLER}"
case "${INSTALLER}" in
    *pipx*)
        # Force la réinstallation pour gérer les upgrades depuis le même URL.
        ${INSTALLER} install --force "${WHEEL_PATH}"
        ;;
    *)
        ${INSTALLER} install --upgrade "${WHEEL_PATH}"
        ;;
esac
log_ok "BugHound installé."

# ----- vérification rapide ---------------------------------------------------
if ! command -v bughound >/dev/null 2>&1; then
    log_warn "La commande 'bughound' n'est pas dans le PATH. \
Avec pipx : pensez à 'pipx ensurepath' puis relancez votre shell."
else
    BUGHOUND_VERSION_INSTALLED="$(bughound version 2>/dev/null || echo '?')"
    log_ok "Commande disponible : ${BUGHOUND_VERSION_INSTALLED}"
fi

# ----- configuration --------------------------------------------------------
if [[ -n "${JIRA_URL}" && -n "${JIRA_MODE}" ]]; then
    log_info "Configuration automatique : JIRA_URL=${JIRA_URL} (${JIRA_MODE})"

    SETUP_ARGS=(
        "--non-interactive"
        "--jira-url" "${JIRA_URL}"
        "--jira-mode" "${JIRA_MODE}"
    )
    if [[ "${JIRA_MODE}" == "api" && -n "${JIRA_EMAIL}" ]]; then
        SETUP_ARGS+=("--jira-email" "${JIRA_EMAIL}")
    fi

    if command -v bughound >/dev/null 2>&1; then
        bughound setup "${SETUP_ARGS[@]}" || \
            log_warn "bughound setup a échoué : configurez à la main \
en lançant 'bughound setup' plus tard."
    else
        log_warn "bughound non trouvé dans le PATH : configurez ensuite \
manuellement avec 'bughound setup'."
    fi
else
    log_warn "Pas de JIRA_URL/JIRA_MODE fournis. \
Configurez maintenant avec : bughound setup"
fi

# ----- récapitulatif ---------------------------------------------------------
cat <<'EOF'

────────────────────────────────────────────────────────────────────
  ✓ SherleKhomes est installé.

  Étapes suivantes :
    1. Renseignez vos secrets dans  ~/.bughound/.env
    2. Lancez votre première enquête :
         bughound analyze MON-TICKET-42
    3. Ou intégrez l'agent à votre client MCP (Claude Code,
       Copilot, Cursor) : voir la page de l'agent sur L'Agence.

  Documentation : voir la galerie des agents.
────────────────────────────────────────────────────────────────────
EOF
