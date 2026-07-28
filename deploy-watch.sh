#!/bin/bash
#
# Maintient /Applications/RevisionVEB.app à jour sur le MacBook Air.
#
# Surveille la branche main sur GitHub. À chaque évolution poussée depuis le
# Mac mini, récupère, recompile en Release et réinstalle dans /Applications —
# l'icône du Dock pointe donc toujours vers la dernière version.
#
# Le script vit dans le dépôt : il se met à jour tout seul avec le reste.
#
#   ./deploy-watch.sh              surveille en continu (30 s)
#   ./deploy-watch.sh --once       une seule vérification puis sort
#   ./deploy-watch.sh --install    installe l'agent de démarrage (lancement
#                                  automatique à l'ouverture de session)
#   ./deploy-watch.sh --uninstall  retire l'agent de démarrage
#
set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
INTERVAL=30
BRANCH=main
LABEL="com.planb.revisionveb.deploy"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/revisionveb-deploy.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

install_agent() {
    mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
    cat > "$PLIST" <<PLIST_END
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$REPO/deploy-watch.sh</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$LOG</string>
    <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST_END
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    log "✅ Agent installé. Surveillance active à chaque ouverture de session."
    log "   Journal : $LOG"
    exit 0
}

uninstall_agent() {
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    log "✅ Agent retiré."
    exit 0
}

deploy() {
    log "📥 Récupération…"
    git -C "$REPO" pull --ff-only origin "$BRANCH" || { log "❌ Échec du pull"; return 1; }
    log "🔨 Compilation et installation…"
    if "$REPO/install-app.sh" --quiet; then
        log "✅ À jour : $(git -C "$REPO" log --oneline -1)"
    else
        log "❌ Échec de l'installation — la version précédente reste en place"
        return 1
    fi
}

case "${1:-}" in
    --install)   install_agent ;;
    --uninstall) uninstall_agent ;;
esac

ONCE=false
[ "${1:-}" = "--once" ] && ONCE=true

log "👁  Surveillance de $REPO (branche $BRANCH)"

# Première passe : aligne l'application installée sur le dépôt local.
if [ ! -d /Applications/RevisionVEB.app ] && [ ! -d "$HOME/Applications/RevisionVEB.app" ]; then
    log "📦 Aucune application installée, installation initiale…"
    "$REPO/install-app.sh" --quiet || log "❌ Installation initiale échouée"
fi

while true; do
    if git -C "$REPO" fetch -q origin "$BRANCH" 2>/dev/null; then
        LOCAL=$(git -C "$REPO" rev-parse HEAD)
        REMOTE=$(git -C "$REPO" rev-parse "origin/$BRANCH")
        if [ "$LOCAL" != "$REMOTE" ]; then
            log "🆕 Nouvelle version détectée (${LOCAL:0:7} → ${REMOTE:0:7})"
            deploy
        fi
    fi
    $ONCE && break
    sleep "$INTERVAL"
done
