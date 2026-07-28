#!/bin/bash
#
# Installe RevisionVEB dans /Applications.
#
# La copie posée dans le Dock pointe vers /Applications/RevisionVEB.app, un
# emplacement stable — contrairement à DerivedData, dont le chemin change et
# dont le contenu est effacé par un Clean. Relancer ce script après une
# évolution de l'app met à jour l'icône du Dock.
#
#   ./install-app.sh
#
set -euo pipefail

cd "$(dirname "$0")"

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

# L'application est peut-être en cours d'exécution : on la ferme proprement.
if pgrep -f "$DEST/RevisionVEB.app/Contents/MacOS/RevisionVEB" > /dev/null; then
    echo "⏹  Fermeture de l'application en cours…"
    osascript -e 'quit app "RevisionVEB"' 2>/dev/null || true
    sleep 2
fi

rm -rf "$DEST/RevisionVEB.app"
cp -R "$SRC" "$DEST/RevisionVEB.app"

# Force le Finder et le Dock à relire l'icône, sinon l'ancienne reste affichée.
touch "$DEST/RevisionVEB.app"
killall Dock 2>/dev/null || true

echo "✅ Installée : $DEST/RevisionVEB.app"
echo "   Pour l'ajouter au Dock : ouvre le dossier et fais glisser l'icône dessus."
