# Importy do Optimy

Strona WWW, która uzupełnia **formę płatności** w plikach XML przed importem do Comarch Optima.
Optima nie przyjmuje dokumentów z pustym polem, np.:

```xml
<TERMIN_PLAT>…</TERMIN_PLAT><FORMA_PLATNOSCI_PLAT><![CDATA[]]></FORMA_PLATNOSCI_PLAT><WALUTA_PLAT><![CDATA[]]></WALUTA_PLAT>
```

Narzędzie wpisuje wybraną formę (domyślnie **gotówka**) w puste znaczniki `FORMA_PLATNOSCI` (dokument)
i `FORMA_PLATNOSCI_PLAT` (płatność). Reszta pliku zostaje bajt w bajt bez zmian — także kodowanie
(UTF-8 albo Windows-1250, wg nagłówka `<?xml … encoding=…?>`).

- wiele plików naraz, przeciąganie i upuszczanie, podgląd dokumentów (numer, kontrahent, forma),
- opcja „tylko puste pola” (domyślnie włączona) — wyłączona nadpisuje każdą formę,
- pliki **nie są wysyłane na serwer** — wszystko dzieje się w przeglądarce (serwer podaje tylko statyczną stronę).

Forma płatności musi istnieć w Optimie pod dokładnie tą nazwą (Konfiguracja firmy → Kasa/Bank → Formy płatności).

## Instalacja (Debian + Apache)

```bash
git clone https://github.com/wiilkuu/importy.git
cd importy
sudo bash deploy/instaluj-apache.sh             # zapyta: w witrynie bkcrm czy samodzielnie
sudo bash deploy/instaluj-apache.sh --w-bkcrm   # bez pytań: https://<host-bkcrm>/importy/ (jak /ksef/)
sudo bash deploy/instaluj-apache.sh importy.bk9.local   # samodzielnie: osobna witryna https://importy.bk9.local/importy/
```

- **z bkcrm** — instalator zapisuje `/etc/bkcrm/apache.d/importy.conf` (witryna bkcrm dołącza ten katalog, tak jak dla ksefprint).
- **samodzielnie** — witryna Apache `importy` (HTTPS, przekierowanie z 80 i z `/` na `/importy/`); bez podanego certyfikatu
  tworzy samopodpisany w `/etc/ssl/importy/`. Parametry: `<nazwa-hosta> [podsieć] [certyfikat.pem klucz.pem]`.
- Dostęp tylko z sieci biura (domyślnie `10.0.106.0/24`, w trybie bkcrm — sieci z witryny bkcrm).
- Pliki strony: `/opt/importy/www`, ustawienia instalacji: `/etc/importy/instalacja.conf`.

Aktualizacja: `sudo deploy/aktualizuj.sh` — pobiera nową wersję z GitHuba i instaluje ją z poprzednimi ustawieniami
(repozytorium prywatne — raz `gh auth login && gh auth setup-git` jako właściciel klonu).

Odinstalowanie: `sudo rm -rf /opt/importy /etc/importy /etc/bkcrm/apache.d/importy.conf; sudo a2dissite importy; sudo systemctl reload apache2`.

## Testy

```bash
node tests/test.js
```

## Pliki

| plik | |
|---|---|
| `www/popraw.js` | logika podmiany (działa na bajtach, zachowuje kodowanie) |
| `www/index.html`, `www/app.js` | strona |
| `deploy/instaluj-apache.sh`, `deploy/aktualizuj.sh` | instalacja i aktualizacja |
| `deploy/apache-importy-bkcrm.conf`, `deploy/apache-importy.conf` | konfiguracja Apache (szablony) |
