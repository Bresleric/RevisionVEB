#!/bin/bash
#
# Met à jour /Applications/RevisionVEB.app après un commit.
#
# Appelé par le hook Git post-commit. Trois garde-fous, pour ne déclencher
# qu'une recompilation réellement utile :
#
#   1. Le commit ne touche pas le code de l'app  -> on ne fait rien.
#   2. Une compilation est déjà en cours          -> on ne fait rien.
#   3. L'application tourne                       -> on demande avant de la fermer.
#
# Sans le point 3, l'app serait fermée sous les doigts de l'utilisateur au
# milieu d'une saisie. La fermeture reste propre (les données sont enregistrées),
# mais l'interruption, elle, ne se rattrape pas.
#
set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
LOCK="/tmp/revisionveb-dock-update.lock"

# 1. Le commit touche-t-il l'application ?
CHANGED=$(git -C "$REPO" diff --name-only HEAD~1 HEAD 2>/dev/null \
          | grep -E '^(RevisionVEB/|RevisionVEB\.xcodeproj/)' || true)
[ -z "$CHANGED" ] && exit 0

# 2. Compilation déjà lancée par un commit précédent ?
if [ -e "$LOCK" ]; then
    PID=$(cat "$LOCK" 2>/dev/null || echo "")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

# 3. L'application tourne-t-elle ?
if pgrep -f "RevisionVEB.app/Contents/MacOS/RevisionVEB" > /dev/null; then
    SUBJECT=$(git -C "$REPO" log -1 --pretty=%s)
    ANSWER=$(osascript <<APPLESCRIPT 2>/dev/null
        display dialog "Une nouvelle version de RevisionVEB est prête.

$SUBJECT

L'application doit être fermée pour être remplacée. Elle enregistre ses données avant de se fermer, puis se rouvre automatiquement." \
            with title "Mettre à jour l'application du Dock" \
            buttons {"Plus tard", "Mettre à jour"} \
            default button "Mettre à jour" \
            with icon note
        button returned of result
APPLESCRIPT
)
    [ "$ANSWER" = "Mettre à jour" ] || exit 0
fi

"$REPO/install-app.sh" --quiet > /tmp/revisionveb-dock-update.log 2>&1 || {
    osascript -e 'display notification "Échec de la mise à jour — voir /tmp/revisionveb-dock-update.log" with title "RevisionVEB"' 2>/dev/null
    exit 1
}

osascript -e 'display notification "Application du Dock mise à jour" with title "RevisionVEB"' 2>/dev/null
