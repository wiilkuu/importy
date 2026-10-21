#!/bin/bash
# Importy do Optimy — instalacja na Debianie z Apache. Strona zawsze pod adresem https://<host>/importy/.
#
#   sudo ./deploy/instaluj-apache.sh                       # zapyta o tryb
#   sudo ./deploy/instaluj-apache.sh --w-bkcrm [podsieć]   # pod /importy/ w witrynie bkcrm (jak /ksef/)
#   (kilka podsieci w cudzysłowie, po spacji lub przecinku: "10.0.106.0/24 172.16.0.0/24")
#   sudo ./deploy/instaluj-apache.sh <nazwa-hosta> [podsieć] [certyfikat.pem klucz.pem]   # samodzielnie
#   sudo ./deploy/instaluj-apache.sh --tak                 # bez pytań, jak poprzednio (tak działa aktualizuj.sh)
#
# Tryby:
#   współpraca z bkcrm — https://<host-bkcrm>/importy/ w witrynie bkcrm. Wymaga zainstalowanego bkcrm.
#   samodzielnie — osobna witryna https://<nazwa-hosta>/importy/. Bez podanego certyfikatu HTTPS tworzy
#     samopodpisany w /etc/ssl/importy/.
#
# To sama strona statyczna (bez usługi w tle) — pliki XML są przetwarzane w przeglądarce.
# Ponowne uruchomienie aktualizuje pliki. Ustawienia zapamiętuje w /etc/importy/instalacja.conf.
set -euo pipefail

pomoc() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; }
W_BKCRM=0; HOST=""; NET="10.0.106.0/24"; CERT=""; KEY=""
BKCRM_SITE=/etc/apache2/sites-available/bkcrm.conf
sieci_bledy() {  # sieci_bledy "lista" → opis błędów (pusto = w porządku)
  local s adres maska o bledy=""
  for s in ${1//,/ }; do
    adres="${s%%/*}"; maska=""; [[ "$s" == */* ]] && maska="${s#*/}"
    if [[ "$adres" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
      for o in "${BASH_REMATCH[@]:1}"; do ((10#$o <= 255)) || { bledy+=" $s (liczba $o > 255);"; continue 2; }; done
      if [[ -n "$maska" ]] && { [[ ! "$maska" =~ ^[0-9]{1,2}$ ]] || ((10#$maska > 32)); }; then
        bledy+=" $s (maska 0–32);"; continue
      fi
    elif [[ ! "$adres" =~ ^[0-9a-fA-F:]+$ || "$adres" != *:* ]] || { [[ -n "$maska" ]] && [[ ! "$maska" =~ ^[0-9]{1,3}$ ]]; }; then
      bledy+=" $s (to nie adres sieci);"; continue
    fi
    if [[ -n "$maska" ]] && ((10#$maska < 8)); then
      bledy+=" $s (/$maska to prawie cały internet — chodziło o np. ${adres%.*}.0/24?);"
    fi
  done
  [[ -z "${1//[ ,]/}" ]] && bledy=" pusta lista;"
  echo "${bledy# }"
}
BK_HOST=""; BK_NET=""
if [[ -f "$BKCRM_SITE" ]]; then
  BK_HOST="$(awk '$1=="ServerName"{print $2; exit}' "$BKCRM_SITE")"
  BK_NET="$(awk '$1=="Require" && $2=="ip"{for(i=3;i<=NF;i++) if($i!="127.0.0.1" && $i!="::1") printf "%s%s", (n++?" ":""), $i; exit}' "$BKCRM_SITE")"
fi

KONF=/etc/importy/instalacja.conf
P_TRYB=""; P_HOST=""; P_NET=""; P_CERT=""; P_KEY=""
if [[ -f "$KONF" ]]; then
  while IFS='=' read -r k v; do
    case "$k" in TRYB) P_TRYB="$v" ;; HOST) P_HOST="$v" ;; NET) P_NET="$v" ;; CERT) P_CERT="$v" ;; KEY) P_KEY="$v" ;; esac
  done < "$KONF"
fi
case "${1:-}" in
  -h|--help) pomoc; exit 0 ;;
  --w-bkcrm) W_BKCRM=1; NET="${2:-${P_NET:-${BK_NET:-$NET}}}" ;;
  --tak)
    case "$P_TRYB" in
      bkcrm) W_BKCRM=1; NET="${P_NET:-${BK_NET:-$NET}}" ;;
      samodzielnie) HOST="$P_HOST"; NET="${P_NET:-$NET}"; CERT="$P_CERT"; KEY="$P_KEY" ;;
      *) echo "Brak poprzedniej instalacji — uruchom bez --tak (kreator)."; exit 1 ;;
    esac ;;
  "")
    [[ -t 0 ]] || { pomoc; exit 1; }
    echo "Jak zainstalować Importy do Optimy?"
    echo "  1) współpraca z bkcrm  — https://<adres bkcrm>/importy/ (tak jak /ksef/)"
    echo "  2) samodzielnie        — osobna witryna https://<nazwa-hosta>/importy/"
    DOMYSLNY=2; [[ -f "$BKCRM_SITE" ]] && DOMYSLNY=1
    [[ "$P_TRYB" == bkcrm ]] && DOMYSLNY=1; [[ "$P_TRYB" == samodzielnie ]] && DOMYSLNY=2
    [[ -n "$P_TRYB" ]] && echo "(poprzednia instalacja: ${P_TRYB}${P_NET:+, sieci $P_NET} — Enter zostawia bez zmian)"
    read -r -p "Wybór [$DOMYSLNY]: " WYBOR; WYBOR="${WYBOR:-$DOMYSLNY}"
    if [[ "$WYBOR" == "1" ]]; then
      W_BKCRM=1
    else
      D="${P_HOST:-importy.bk9.local}"
      read -r -p "Nazwa hosta [$D]: " HOST; HOST="${HOST:-$D}"
      [[ "$HOST" == "$P_HOST" ]] && { CERT="$P_CERT"; KEY="$P_KEY"; }
    fi
    if [[ -n "$P_NET" && ( "$P_TRYB" == bkcrm && $W_BKCRM -eq 1 || "$P_TRYB" == samodzielnie && $W_BKCRM -eq 0 ) ]]; then
      NET="$P_NET"
    elif ((W_BKCRM)) && [[ -n "$BK_NET" ]]; then
      NET="$BK_NET"
    fi
    echo "(kilka sieci oddziel spacją, np. 10.0.106.0/24 172.16.0.0/24)"
    while true; do
      read -r -p "Sieci, z których wolno wejść [$NET]: " N; N="${N:-$NET}"
      B="$(sieci_bledy "$N")"; [[ -z "$B" ]] && break
      echo "  !! popraw: $B" >&2
    done
    NET="$N"
    ;;
  -*) echo "Nieznana opcja: $1"; pomoc; exit 1 ;;
  *) HOST="$1"; NET="${2:-$NET}"; CERT="${3:-}"; KEY="${4:-}" ;;
esac
if ((W_BKCRM)); then
  [[ -f "$BKCRM_SITE" ]] || { echo "Nie znalazłem witryny bkcrm ($BKCRM_SITE) — najpierw zainstaluj bkcrm albo wybierz tryb samodzielny."; exit 1; }
  HOST="$BK_HOST"
  [[ -n "$HOST" ]] || { echo "W $BKCRM_SITE nie ma dyrektywy ServerName — uruchom ponownie instalator bkcrm."; exit 1; }
fi
NET="$(echo ${NET//,/ })"
B="$(sieci_bledy "$NET")"; [[ -z "$B" ]] || { echo "Nieprawidłowa sieć: $B (np. 10.0.106.0/24)"; exit 1; }
[[ -n "$HOST" ]] || { pomoc; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Uruchom jako root (sudo)."; exit 1; }

SRC="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
DEST=/opt/importy
SITE=/etc/apache2/sites-available/importy.conf
SNIPPET=/etc/bkcrm/apache.d/importy.conf

echo "==> Sprawdzam pakiety"
missing=()
command -v apache2ctl >/dev/null || missing+=(apache2)
command -v openssl   >/dev/null || missing+=(openssl)
command -v curl      >/dev/null || missing+=(curl)
if ((${#missing[@]})); then apt-get update && apt-get install -y "${missing[@]}"; fi

echo "==> Kopiuję stronę do $DEST"
install -d -m 755 "$DEST"
if [[ "$(readlink -f "$SRC")" != "$(readlink -f "$DEST")" ]]; then
  rm -rf "$DEST/www.new"
  cp -r "$SRC/www" "$DEST/www.new"
  rm -rf "$DEST/www" && mv "$DEST/www.new" "$DEST/www"
  chown -R root:root "$DEST/www"
else
  echo "    (repozytorium jest w $DEST — strona serwowana prosto z niego)"
fi
# Tylko katalog strony — nie ruszamy reszty (repozytorium może leżeć w $DEST, skrypty muszą zostać wykonywalne).
find "$DEST/www" -type d -exec chmod 755 {} + ; find "$DEST/www" -type f -exec chmod 644 {} +

if ! ((W_BKCRM)); then
  echo "==> Certyfikat HTTPS"
  if [[ -n "$CERT" ]]; then
    [[ -r "$CERT" && -r "$KEY" ]] || { echo "Nie mogę odczytać $CERT / $KEY"; exit 1; }
  else
    CERT=/etc/ssl/importy/cert.pem
    KEY=/etc/ssl/importy/key.pem
    if [[ ! -s "$CERT" ]]; then
      install -d -m 755 /etc/ssl/importy
      IP="$(hostname -I | awk '{print $1}')"
      SAN="DNS:$HOST"; [[ -n "$IP" ]] && SAN="$SAN,IP:$IP"
      openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
        -keyout "$KEY" -out "$CERT" -subj "/CN=$HOST/O=Importy do Optimy" \
        -addext "subjectAltName=$SAN" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
        -addext "keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign" \
        -addext "extendedKeyUsage=serverAuth" 2>/dev/null
      chmod 600 "$KEY"; chmod 644 "$CERT"
      echo "    Utworzono samopodpisany certyfikat dla: $SAN"
      echo "    Aby przeglądarki nie ostrzegały, zaimportuj $CERT na stanowiskach (GPO → Zaufane główne urzędy)."
    else
      echo "    Używam istniejącego $CERT"
    fi
  fi
fi

echo "==> Konfiguracja Apache"
a2enmod -q alias headers >/dev/null
if ((W_BKCRM)); then
  install -d -m 755 /etc/bkcrm/apache.d
  sed -e "s#@NET@#$NET#g" "$SRC/deploy/apache-importy-bkcrm.conf" > "$SNIPPET"
  grep -q 'IncludeOptional /etc/bkcrm/apache.d/' "$BKCRM_SITE" || {
    echo "!! Witryna bkcrm nie dołącza /etc/bkcrm/apache.d/ — zaktualizuj bkcrm (deploy/aktualizuj.sh) i powtórz."; rm -f "$SNIPPET"; exit 1; }
  BYLA_WITRYNA=0
  if [[ -e /etc/apache2/sites-enabled/importy.conf ]]; then BYLA_WITRYNA=1; a2dissite -q importy >/dev/null; fi
  if ! apache2ctl configtest; then
    echo "!! Błąd konfiguracji Apache — usuwam /importy/ z bkcrm, nic nie zostało przeładowane."
    rm -f "$SNIPPET"; ((BYLA_WITRYNA)) && a2ensite -q importy >/dev/null
    exit 1
  fi
  ((BYLA_WITRYNA)) && echo "    osobna witryna importy wyłączona (narzędzie jest teraz pod https://$HOST/importy/)"
else
  a2enmod -q ssl >/dev/null
  sed -e "s#@HOST@#$HOST#g" -e "s#@NET@#$NET#g" -e "s#@CERT@#$CERT#g" -e "s#@KEY@#$KEY#g" \
    "$SRC/deploy/apache-importy.conf" > "$SITE"
  BYL_SNIPPET=0
  if [[ -f "$SNIPPET" ]]; then BYL_SNIPPET=1; mv "$SNIPPET" "$SNIPPET.wylaczony"; fi
  a2ensite -q importy >/dev/null
  if ! apache2ctl configtest; then
    echo "!! Błąd konfiguracji Apache — wyłączam witrynę importy, nic nie zostało przeładowane."
    a2dissite -q importy >/dev/null || true
    ((BYL_SNIPPET)) && mv "$SNIPPET.wylaczony" "$SNIPPET"
    exit 1
  fi
  ((BYL_SNIPPET)) && rm -f "$SNIPPET.wylaczony"
fi
if [[ -d /run/systemd/system ]]; then systemctl reload apache2; else apache2ctl -k graceful; fi

install -d -m 755 /etc/importy
{ echo "TRYB=$( ((W_BKCRM)) && echo bkcrm || echo samodzielnie)"; echo "HOST=$( ((W_BKCRM)) || echo "$HOST")"
  echo "NET=$NET"; echo "CERT=$( ((W_BKCRM)) || [[ "$CERT" == /etc/ssl/importy/cert.pem ]] || echo "$CERT")"
  echo "KEY=$( ((W_BKCRM)) || [[ "$CERT" == /etc/ssl/importy/cert.pem ]] || echo "$KEY")"; } > "$KONF"

echo "==> Test"
sleep 1
BAZA="https://$HOST/importy/"
if curl -sk --resolve "$HOST:443:127.0.0.1" "${BAZA}popraw.js" | grep -q 'FORMA_PLATNOSCI_PLAT'; then
  echo "    Apache serwuje /importy/: OK"
else
  echo "!! Apache nie serwuje /importy/ — sprawdź /var/log/apache2/error.log"
fi

echo
echo "Gotowe. Otwórz na stanowisku:  $BAZA"
((W_BKCRM)) || echo "(nazwa $HOST musi wskazywać na ten serwer w DNS biura)"
