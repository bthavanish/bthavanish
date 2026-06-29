#!/usr/bin/env bash
set -euo pipefail

export CI=1

log() {
  printf '\n\033[1;36m==>\033[0m %s\n' "$*"
}

run() {
  log "$*"
  "$@"
}

log "Installing OpenCode"
bash -lc 'curl -fsSL https://opencode.ai/install | bash'

log "Installing skills"
run npx --yes skills add miguelspizza/skills --skill maintainable-typescript --agent '*' --yes
run npx --yes skills add miguelspizza/skills --skill webmcp-designer --agent '*' --yes
run npx --yes skills add miguelspizza/skills --skill write-good-docs --agent '*' --yes

run npx --yes skills add pbakaus/impeccable --agent '*' --yes
run npx --yes skills add JuliusBrussee/caveman --agent '*' --yes

log "Installing Caveman Code globally"
run npm install -g @juliusbrussee/caveman-code

log "Done"
