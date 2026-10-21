#!/bin/bash
# Importy do Optimy — aktualizacja: pobiera nową wersję z GitHuba i instaluje ją bez pytań, z poprzednimi ustawieniami.
#   sudo ./deploy/aktualizuj.sh            # najnowsze wydanie (tag vX.Y.Z); na gałęzi — git pull tej gałęzi
#   sudo ./deploy/aktualizuj.sh v1.0.1     # konkretne wydanie
set -euo pipefail
# Całość w funkcji: bash wczytuje ją przed startem, więc git pull, który podmienia ten plik, nie zmieni działania.
main() {
[[ $EUID -eq 0 ]] || { echo "Uruchom jako root (sudo)."; exit 1; }
SRC="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
[[ -f /etc/importy/instalacja.conf ]] || { echo "Nie znalazłem poprzedniej instalacji — użyj deploy/instaluj-apache.sh."; exit 1; }

echo "==> Pobieram nową wersję"
WLASCICIEL="$(stat -c %U "$SRC/.git")"
DOM="$(getent passwd "$WLASCICIEL" | cut -d: -f6)"
G=(runuser -u "$WLASCICIEL" -- env HOME="$DOM" git -C "$SRC")
if ! "${G[@]}" fetch --tags --quiet origin; then
  echo "!! Nie udało się pobrać z GitHuba jako $WLASCICIEL."
  [[ "$WLASCICIEL" == root ]] && echo "   Raz: sudo gh auth login && sudo gh auth setup-git" \
                              || echo "   Raz (jako $WLASCICIEL): gh auth login && gh auth setup-git"
  exit 1
fi
if [[ -n "${1:-}" ]]; then
  CEL="$1"
elif "${G[@]}" symbolic-ref -q HEAD >/dev/null; then
  CEL=""
else
  CEL="$("${G[@]}" tag --list 'v*' --sort=-v:refname | head -n1)"
fi
if [[ -n "$CEL" ]]; then
  echo "    wersja: $CEL (było: $("${G[@]}" describe --tags --always))"
  "${G[@]}" -c advice.detachedHead=false checkout --quiet "$CEL"
else
  "${G[@]}" pull --ff-only
fi
exec "$SRC/deploy/instaluj-apache.sh" --tak
}
main "$@"
