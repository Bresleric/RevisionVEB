#!/bin/bash
# Lance le téléchargement des bulletins Combo Pay (Arhia).
# Installe Playwright localement au premier lancement. Voir --help.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js est absent. Installez-le depuis https://nodejs.org (version LTS)"
  echo "ou avec Homebrew : brew install node"
  exit 1
fi

if [ ! -d node_modules/playwright ]; then
  echo "Installation de Playwright (une seule fois)…"
  npm install --no-audit --no-fund --silent
fi

exec node telecharger-bulletins.mjs "$@"
