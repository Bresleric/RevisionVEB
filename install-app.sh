#!/bin/bash
#
# Installe RevisionVEB dans /Applications.
#
# La copie posée dans le Dock pointe vers /Applications/RevisionVEB.app, un
# emplacement stable — contrairement à DerivedData, dont le chemin change et
# dont le contenu est effacé par un Clean.
#
#   ./install-app.sh                installe
#   ./install-app.sh --relaunch     installe puis rouvre l'application
#   ./install-app.sh --quiet        sans redémarrage du Dock (usage automatisé)
#   ./install-app.sh --install-hook pose le hook Git qui propose la mise à jour
#                                   après chaque commit touchant l'application
#
set -euo pipefail

cd "$(dirname "$0")"

RELAUNCH=false
QUIET=false
for arg in "$@"; do
    case "$arg" in
        --relaunch) RELAUNCH=true ;;
        --quiet)    QUIET=true ;;
        --install-hook)
            HOOK="$(git rev-parse --git-dir)/hooks/post-commit"
            mkdir -p "$(dirname "$HOOK")"
            cat > "$HOOK" <<'HOOK_END'
#!/bin/bash
# Propose de mettre à jour l'application du Dock. Détaché du commit : le hook
# rend la main immédiatement, la compilation se fait en arrière-plan.
REPO="$(git rev-parse --show-toplevel)"
[ -x "$REPO/update-dock-app.sh" ] && nohup "$REPO/update-dock-app.sh" >/dev/null 2>&1 &
exit 0
HOOK_END
            chmod +x "$HOOK"
            echo "✅ Hook posé : $HOOK"
            echo "   Après chaque commit touchant l'app, une fenêtre proposera la mise à jour."
            echo "   Pour le retirer : rm \"$HOOK\""
            exit 0
            ;;
        *) echo "Option inconnue : $arg"; exit 2 ;;
    esac
done

DERIVED=$(mktemp -d /tmp/revisionveb-release.XXXXXX)
trap 'rm -rf "$DERIVED"' EXIT

echo "🔨 Compilation (Release)…"
xcodebuild -scheme RevisionVEB \
           -configuration Release \
           -destination 'platform=macOS' \
           -derivedDataPath "$DERIVED" \
           build > "$DERIVED/build.log" 2>&1 || {
    echo "❌ Échec de compilation. Détail :"
    grep -E "error:" "$DERIVED/build.log" | head -20
    exit 1
}

SRC="$DERIVED/Build/Products/Release/RevisionVEB.app"
[ -d "$SRC" ] || { echo "❌ Application introuvable après compilation"; exit 1; }

if [ -w /Applications ]; then
    DEST=/Applications
else
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
    echo "ℹ️  /Applications non accessible en écriture, installation dans $DEST"
fi

# L'application enregistre ses données avant de se fermer : on lui demande de
# quitter proprement plutôt que de la tuer.
WAS_RUNNING=false
if pgrep -f "RevisionVEB.app/Contents/MacOS/RevisionVEB" > /dev/null; then
    WAS_RUNNING=true
    echo "⏹  Fermeture de l'application en cours…"
    osascript -e 'quit app "RevisionVEB"' 2>/dev/null || true
    for _ in $(seq 1 10); do
        pgrep -f "RevisionVEB.app/Contents/MacOS/RevisionVEB" > /dev/null || break
        sleep 1
    done
fi

rm -rf "$DEST/RevisionVEB.app"
cp -R "$SRC" "$DEST/RevisionVEB.app"
touch "$DEST/RevisionVEB.app"

# Le Dock garde l'ancienne icône en cache. On ne le redémarre qu'en usage
# interactif : en boucle de déploiement ce serait perturbant à chaque mise à jour.
if [ "$QUIET" = false ]; then
    killall Dock 2>/dev/null || true
fi

echo "✅ Installée : $DEST/RevisionVEB.app"

if [ "$RELAUNCH" = true ] || [ "$WAS_RUNNING" = true ]; then
    open "$DEST/RevisionVEB.app"
    echo "🚀 Application relancée"
else
    echo "   Pour l'ajouter au Dock : ouvre le dossier et fais glisser l'icône dessus."
fi
