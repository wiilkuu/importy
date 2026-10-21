/* Importy do Optimy — uzupełnianie formy płatności w pliku XML (eksport rejestrów VAT Comarch Optima).
 * Działa na bajtach pliku: nie zmienia kodowania, wcięć, kolejności ani innych pól — podmienia tylko wskazane znaczniki.
 * Używane w przeglądarce (window.Importy) i w testach (node: require). */
(function (root) {
  'use strict';

  var TAGI = ['FORMA_PLATNOSCI', 'FORMA_PLATNOSCI_PLAT'];

  // Bajty → "ciąg binarny" (1 znak = 1 bajt) i z powrotem.
  function naBinarny(bajty) {
    var s = '', KAWAL = 0x8000;
    for (var i = 0; i < bajty.length; i += KAWAL) {
      s += String.fromCharCode.apply(null, bajty.subarray(i, i + KAWAL));
    }
    return s;
  }
  function zBinarnego(s) {
    var b = new Uint8Array(s.length);
    for (var i = 0; i < s.length; i++) b[i] = s.charCodeAt(i) & 0xff;
    return b;
  }

  function wykryjKodowanie(bajty) {
    if (bajty[0] === 0xef && bajty[1] === 0xbb && bajty[2] === 0xbf) return 'utf-8';
    if ((bajty[0] === 0xff && bajty[1] === 0xfe) || (bajty[0] === 0xfe && bajty[1] === 0xff)) {
      throw new Error('Plik w UTF-16 — zapisz go jako UTF-8 albo Windows-1250.');
    }
    var poczatek = naBinarny(bajty.subarray(0, 300));
    var m = /^\s*<\?xml[^>]*?encoding\s*=\s*["']([^"']+)["']/i.exec(poczatek);
    var enc = (m ? m[1] : 'utf-8').toLowerCase();
    if (enc === 'utf8') enc = 'utf-8';
    if (enc === 'cp1250' || enc === 'win-1250') enc = 'windows-1250';
    return enc;
  }

  // Tekst → ciąg binarny w danym kodowaniu (dla jednobajtowych: odwrócona tablica dekodera).
  function zakoduj(tekst, enc) {
    if (enc === 'utf-8') return naBinarny(new TextEncoder().encode(tekst));
    var dek;
    try { dek = new TextDecoder(enc); } catch (e) { throw new Error('Nieobsługiwane kodowanie pliku: ' + enc); }
    var mapa = {};
    for (var b = 0; b < 256; b++) {
      var ch = dek.decode(new Uint8Array([b]));
      if (!(ch in mapa)) mapa[ch] = b;
    }
    var wynik = '';
    for (var i = 0; i < tekst.length; i++) {
      var z = tekst.charAt(i);
      if (!(z in mapa) || z === '�') throw new Error('Znaku „' + z + '” nie da się zapisać w kodowaniu ' + enc + '.');
      wynik += String.fromCharCode(mapa[z]);
    }
    return wynik;
  }

  function pusta(zawartosc) {
    return zawartosc.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').trim() === '';
  }

  /**
   * popraw(bajty, {forma: 'gotówka', tylkoPuste: true, tagi: [...]})
   * → {bajty, kodowanie, zmienione: {TAG: n}, znalezione: {TAG: n}, razem}
   */
  function popraw(bajty, opcje) {
    opcje = opcje || {};
    var forma = (opcje.forma == null ? 'gotówka' : String(opcje.forma)).trim();
    if (!forma) throw new Error('Podaj formę płatności.');
    if (/]]>|[<>&]/.test(forma)) throw new Error('Forma płatności nie może zawierać znaków < > & ani „]]>”.');
    var tylkoPuste = opcje.tylkoPuste !== false;
    var tagi = opcje.tagi || TAGI;

    var kodowanie = wykryjKodowanie(bajty);
    var bin = naBinarny(bajty);
    var wartosc = zakoduj(forma, kodowanie);

    var zmienione = {}, znalezione = {};
    tagi.forEach(function (t) { zmienione[t] = 0; znalezione[t] = 0; });
    var alt = tagi.join('|');
    var re = new RegExp('<(' + alt + ')(\\s[^>]*?)?\\s*/>|<(' + alt + ')(\\s[^>]*)?>([\\s\\S]*?)</\\3\\s*>', 'g');

    var wynik = bin.replace(re, function (cale, tagSam, atrSam, tag, atr, zaw) {
      var t = tagSam || tag;
      znalezione[t]++;
      var jestPusta = tagSam ? true : pusta(zaw);
      if (tylkoPuste && !jestPusta) return cale;
      zmienione[t]++;
      return '<' + t + (tagSam ? (atrSam || '') : (atr || '')) + '><![CDATA[' + wartosc + ']]></' + t + '>';
    });

    var razem = 0;
    tagi.forEach(function (t) { razem += zmienione[t]; });
    return { bajty: razem ? zBinarnego(wynik) : bajty, kodowanie: kodowanie, zmienione: zmienione, znalezione: znalezione, razem: razem };
  }

  var api = { popraw: popraw, wykryjKodowanie: wykryjKodowanie, TAGI: TAGI };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.Importy = api;
})(this);
