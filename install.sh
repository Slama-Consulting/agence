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
#   curl -fsSL https://slama-consulting.github.io/agence/install.sh \
#     | JIRA_URL='https://jira.maboite.com' JIRA_MODE='browser' bash
#
# ⚠️  Mettre 'JIRA_URL=… curl … | bash' attache les variables à *curl*,
#     pas à *bash* : install.sh ne les verrait pas. Toujours placer les
#     variables côté droit du pipe (ou les exporter avant).
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
# Tous les logs vont sur stderr pour ne pas polluer stdout (utilisé par les
# fonctions qui retournent une valeur via $(...) ).
log_info()  { printf '\033[36m[*]\033[0m %s\n' "$*" >&2; }
log_ok()    { printf '\033[32m[✓]\033[0m %s\n' "$*" >&2; }
log_warn()  { printf '\033[33m[!]\033[0m %s\n' "$*" >&2; }
log_error() { printf '\033[31m[✗]\033[0m %s\n' "$*" >&2; }

die() { log_error "$*"; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 \
        || die "Commande requise non trouvée : $1"
}

# Renvoie le répertoire 'scripts' du scheme user de Python (où pipx pose ses
# binaires). Robuste aux schemes Debian custom (posix_local, etc.) en
# essayant plusieurs schemes connus puis en repliant sur ~/.local/bin.
user_scripts_dir() {
    python3 - <<'PY' 2>/dev/null
import os, sys, sysconfig
for scheme in ("posix_user", "nt_user", "osx_framework_user"):
    try:
        p = sysconfig.get_path("scripts", scheme)
        if p:
            print(p); sys.exit(0)
    except (KeyError, Exception):
        pass
print(os.path.expanduser("~/.local/bin"))
PY
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
# pipx valide le nom de fichier selon PEP 491 :
# {distribution}-{version}-{python tag}-{abi tag}-{platform tag}.whl
# On conserve donc le nom d'origine de l'URL.
WHEEL_FILENAME="$(basename "${WHEEL_URL}")"
WHEEL_PATH="${TMP_DIR}/${WHEEL_FILENAME}"

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

# pipx exige un nom de wheel conforme PEP 491 : `latest` n'est pas une
# version PEP 440 valide. On lit le vrai nom canonique depuis le
# dist-info de la wheel et on la renomme avant de la passer à pipx.
CANONICAL_WHEEL_NAME="$(WHEEL_FILE="${WHEEL_PATH}" python3 - <<'PY' 2>/dev/null
import os, sys, zipfile
path = os.environ["WHEEL_FILE"]
try:
    with zipfile.ZipFile(path) as z:
        name = version = None
        for n in z.namelist():
            if n.endswith(".dist-info/METADATA"):
                with z.open(n) as f:
                    for raw in f:
                        line = raw.decode("utf-8", errors="replace").rstrip()
                        if line.startswith("Name: "):
                            name = line[len("Name: "):].strip().replace("-", "_")
                        elif line.startswith("Version: "):
                            version = line[len("Version: "):].strip()
                        if name and version:
                            break
                break
        if name and version:
            print(f"{name}-{version}-py3-none-any.whl")
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
PY
)"
if [ -n "${CANONICAL_WHEEL_NAME}" ] \
   && [ "${CANONICAL_WHEEL_NAME}" != "${WHEEL_FILENAME}" ]; then
    CANONICAL_WHEEL_PATH="${TMP_DIR}/${CANONICAL_WHEEL_NAME}"
    mv "${WHEEL_PATH}" "${CANONICAL_WHEEL_PATH}"
    WHEEL_PATH="${CANONICAL_WHEEL_PATH}"
    log_info "Wheel renommée : ${CANONICAL_WHEEL_NAME}"
fi

# ----- installation ----------------------------------------------------------
# Stratégie : on installe TOUJOURS via pipx, qui isole BugHound dans son
# propre venv et évite les conflits avec les paquets système (PEP 668). Si
# pipx n'est pas dispo, on l'installe via 'pip install --user pipx' (avec
# --break-system-packages si l'environnement Python est externally-managed).

ensure_pipx() {
    if command -v pipx >/dev/null 2>&1; then
        printf 'pipx'
        return
    fi
    if python3 -m pipx --version >/dev/null 2>&1; then
        printf 'python3 -m pipx'
        return
    fi
    log_info "pipx absent — installation via pip --user."
    PIP_FLAGS=("install" "--user" "--upgrade")
    if python3 -c "import sysconfig,os; p=sysconfig.get_paths()['stdlib']+'/EXTERNALLY-MANAGED'; raise SystemExit(0 if os.path.exists(p) else 1)" 2>/dev/null; then
        log_warn "Python externally-managed (PEP 668) → --break-system-packages pour pipx."
        PIP_FLAGS+=("--break-system-packages")
    fi
    if ! python3 -m pip "${PIP_FLAGS[@]}" pipx >&2; then
        die "Impossible d'installer pipx. Installez-le manuellement \
(https://pipx.pypa.io) puis relancez ce script."
    fi
    USER_BIN="$(user_scripts_dir)"
    if [ -n "${USER_BIN}" ] && [ -d "${USER_BIN}" ]; then
        export PATH="${USER_BIN}:${PATH}"
    fi
    if command -v pipx >/dev/null 2>&1; then
        log_ok "pipx installé dans ${USER_BIN}."
        printf 'pipx'
        return
    fi
    if python3 -m pipx --version >/dev/null 2>&1; then
        log_ok "pipx installé (via 'python3 -m pipx')."
        printf 'python3 -m pipx'
        return
    fi
    die "pipx installé mais introuvable. Relancez votre shell puis ré-exécutez."
}

INSTALLER="$(ensure_pipx)"
log_info "Installation via : ${INSTALLER}"
# --force pour gérer les upgrades depuis le même URL "latest".
${INSTALLER} install --force "${WHEEL_PATH}"
${INSTALLER} ensurepath >/dev/null 2>&1 || true
USER_BIN="$(user_scripts_dir)"
if [ -n "${USER_BIN}" ] && [ -d "${USER_BIN}" ]; then
    export PATH="${USER_BIN}:${PATH}"
fi
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
# Détection du TTY. Quand le script est lancé via `curl … | bash`, stdin du
# bash pointe sur le pipe (pas sur un TTY), mais l'utilisateur a quand même
# un terminal disponible sur /dev/tty. On bascule stdin sur /dev/tty pour
# pouvoir poser des questions interactivement, même sous curl-pipe.
HAS_TTY=0
if [ -e /dev/tty ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
    HAS_TTY=1
fi

run_setup_interactive() {
    # Lancer 'bughound setup' avec stdin rattaché au TTY de l'utilisateur.
    if (( HAS_TTY )); then
        bughound setup < /dev/tty
    else
        bughound setup
    fi
}

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
elif (( HAS_TTY )) && command -v bughound >/dev/null 2>&1; then
    log_info "Pas de JIRA_URL/JIRA_MODE en env → setup interactif."
    log_info "Astuce : pour pré-remplir, exporter avant le pipe :"
    log_info "  curl …/install.sh | JIRA_URL='…' JIRA_MODE='browser' bash"
    if ! run_setup_interactive; then
        log_warn "bughound setup interrompu : relancez 'bughound setup' \
quand vous voudrez configurer."
    fi
else
    log_warn "Pas de JIRA_URL/JIRA_MODE fournis et pas de TTY détecté."
    log_warn "Piège fréquent : 'JIRA_URL=… JIRA_MODE=… curl … | bash' attache \
les variables à curl, pas à bash."
    log_warn "Forme correcte : 'curl …/install.sh | JIRA_URL=… JIRA_MODE=… bash'"
    log_warn "Configurez maintenant avec : bughound setup"
fi

# ----- enregistrement MCP ---------------------------------------------------
# Idempotent grâce au merge prudent : préserve les autres serveurs MCP de
# l'utilisateur, et ne réécrit l'entrée 'sherlekhomes' que si elle change.
# Migre automatiquement l'ancienne clé 'bughound' vers 'sherlekhomes'.
if command -v bughound >/dev/null 2>&1; then
    log_info "Enregistrement de BugHound comme serveur MCP (Claude / VS Code / Cursor)."
    if ! bughound mcp-install --yes --overwrite >&2; then
        log_warn "bughound mcp-install a échoué : enregistrez à la main \
en relançant 'bughound mcp-install'."
    fi
fi

# ----- récapitulatif ---------------------------------------------------------
cat <<'EOF'

────────────────────────────────────────────────────────────────────
  ✓ SherleKhomes est installé.

  Étapes suivantes :
    1. Vérifiez/renseignez vos secrets dans  ~/.bughound/.env
       (JIRA_API_TOKEN, ARTIFACTORY_USER/TOKEN, LLM_API_KEY).
    2. Lancez votre première enquête :
         bughound analyze MON-TICKET-42
    3. Dans votre IDE (VS Code, Cursor) ou Claude Code, le serveur
       MCP 'sherlekhomes' est déjà enregistré — relancez l'IDE et
       appelez-le depuis le chat.

  Documentation : voir la galerie des agents sur L'Agence.
────────────────────────────────────────────────────────────────────
EOF
