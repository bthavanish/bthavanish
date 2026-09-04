#!/usr/bin/env bash
set -euo pipefail
export CI=1


RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[1;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

log()  { printf "\n${CYAN}==> ${BOLD}%s${RESET}\n" "$*"; }
ok()   { printf "  ${GREEN}✓${RESET} %s\n" "$*"; }
skip() { printf "  ${DIM}↓ %s — already installed${RESET}\n" "$*"; }
warn() { printf "  ${YELLOW}! %s${RESET}\n" "$*"; }
die()  { printf "\n${RED}✗ %s${RESET}\n" "$*" >&2; exit 1; }

has() { command -v "$1" &>/dev/null; }

START=$(date +%s)

log "OpenCode"
if has opencode; then
  skip "opencode"
else
  bash -lc 'curl -fsSL https://opencode.ai/install | bash'
  ok "opencode"
fi


log "Skills (global)"


add_skill() {
  local repo="$1"; shift
  npx --yes skills add "$repo" --global "$@" --yes
  ok "$repo"
}

add_skill miguelspizza/skills --skill write-good-docs
add_skill pbakaus/impeccable
add_skill JuliusBrussee/caveman
add_skill blader/humanizer
add_skill ghaida/intent

log "LSPs (npm)"


npm install -g \
  vscode-langservers-extracted \
  typescript-language-server \
  yaml-language-server \
  tailwindcss-language-server \
  bash-language-server \
  svelte-language-server \
  "@vue/language-server" \
  "@astrojs/language-server" \
  graphql-language-service-cli \
  "@prisma/language-server" \
  dockerfile-language-server-nodejs \
  intelephense \
  pyright \
  "@taplo/cli"

ok "npm LSPs"


log "Python tools (pipx)"

if ! has pipx; then
  sudo apt-get install -y --no-install-recommends pipx
  ok "pipx installed"
fi


pipx ensurepath --force &>/dev/null


for pkg in ruff ruff-lsp python-lsp-server; do
  bin="${pkg/python-lsp-server/pylsp}" 
  if has "$bin"; then
    skip "$pkg"
  else
    pipx install "$pkg"
    ok "$pkg"
  fi
done


log "Marksman"

MARKSMAN="$HOME/.local/bin/marksman"
if [[ -x "$MARKSMAN" ]]; then
  skip "marksman"
else
  mkdir -p "$HOME/.local/bin"


  case "$(uname -m)" in
    x86_64)  asset="marksman-linux-x64"   ;;
    aarch64) asset="marksman-linux-arm64" ;;
    *)       die "unsupported arch: $(uname -m)" ;;
  esac

  wget -qO "$MARKSMAN" \
    "https://github.com/artempyanykh/marksman/releases/latest/download/$asset"
  chmod +x "$MARKSMAN"
  ok "marksman ($asset)"
fi

log "Toolchain LSPs (optional)"

if has rustup; then
  rustup component add rust-analyzer --quiet 2>/dev/null && ok "rust-analyzer" || skip "rust-analyzer"
else
  warn "rustup not found — skipping rust-analyzer (install rustup first)"
fi

if has go; then
  go install golang.org/x/tools/gopls@latest
  ok "gopls"
else
  warn "go not found — skipping gopls (install go first)"
fi

if has clangd; then
  ok "clangd already present"
else
  warn "clangd not found — run: sudo apt install clangd"
fi

END=$(date +%s)

printf "\n${GREEN}${BOLD}✓ done in $((END - START))s${RESET}\n"
printf "\n${DIM}paths to have in your shell:${RESET}\n"
printf "  ~/.local/bin        ${DIM}← marksman${RESET}\n"
printf "  ~/.local/share/pipx/venvs/*/bin  ${DIM}← ruff, pylsp, ruff-lsp${RESET}\n"
printf "\n${DIM}run \`source ~/.bashrc\` or open a new terminal if anything isn't found${RESET}\n\n"

# ~ https://github.com/thavanish made this shitty code
