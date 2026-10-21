(function () {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };
  var pliki = [];  // {nazwa, oryginal: Uint8Array, wynik, blad}

  function opcje() {
    return { forma: $('forma').value, tylkoPuste: $('tylkoPuste').checked };
  }

  function przetworz(p) {
    p.blad = null; p.wynik = null;
    try { p.wynik = Importy.popraw(p.oryginal, opcje()); } catch (e) { p.blad = e.message; }
  }

  function el(tag, klasa, tekst) {
    var e = document.createElement(tag);
    if (klasa) e.className = klasa;
    if (tekst != null) e.textContent = tekst;
    return e;
  }

  // Podgląd dokumentów: elementy z bezpośrednim dzieckiem NUMER (rejestry VAT, dokumenty).
  function podglad(p) {
    var tekst;
    try { tekst = new TextDecoder(p.wynik.kodowanie).decode(p.wynik.bajty); } catch (e) { return null; }
    var doc = new DOMParser().parseFromString(tekst, 'application/xml');
    if (doc.getElementsByTagName('parsererror').length) return { blad: true };
    var wiersze = [];
    var wszystkie = doc.getElementsByTagName('*');
    function dziecko(e, nazwa) {
      for (var c = e.firstElementChild; c; c = c.nextElementSibling) if (c.nodeName === nazwa) return c;
      return null;
    }
    for (var i = 0; i < wszystkie.length && wiersze.length < 1000; i++) {
      var e = wszystkie[i];
      var numer = dziecko(e, 'NUMER');
      if (!numer || !dziecko(e, 'FORMA_PLATNOSCI') && !e.getElementsByTagName('FORMA_PLATNOSCI_PLAT').length) continue;
      var nazwa = e.getElementsByTagName('NAZWA1')[0] || e.getElementsByTagName('NAZWA')[0];
      var fd = dziecko(e, 'FORMA_PLATNOSCI');
      var fp = [].map.call(e.getElementsByTagName('FORMA_PLATNOSCI_PLAT'), function (x) { return x.textContent.trim(); });
      wiersze.push({ numer: numer.textContent.trim(), kontrahent: nazwa ? nazwa.textContent.trim() : '',
                     forma: fd ? fd.textContent.trim() : '', platnosci: fp.join(', ') });
    }
    return { wiersze: wiersze };
  }

  function rysuj() {
    var w = $('wyniki');
    w.textContent = '';
    pliki.forEach(function (p, idx) {
      var box = el('div', 'plik');
      var gl = el('div', 'gl');
      gl.appendChild(el('span', 'nazwa', p.nazwa));
      if (p.blad) {
        gl.appendChild(el('span', 'pill err', 'błąd'));
        box.appendChild(gl);
        box.appendChild(el('div', 'opis', p.blad));
      } else {
        var r = p.wynik;
        gl.appendChild(el('span', 'pill', r.kodowanie));
        gl.appendChild(r.razem ? el('span', 'pill ok', 'uzupełniono: ' + r.razem)
                               : el('span', 'pill warn', 'nic do zmiany'));
        gl.appendChild(el('span', 'spacer'));
        var b = el('button', null, 'Pobierz');
        b.onclick = function () { pobierz(p); };
        gl.appendChild(b);
        box.appendChild(gl);
        var opis = Importy.TAGI.map(function (t) {
          return t + ': ' + r.zmienione[t] + ' z ' + r.znalezione[t];
        }).join(' · ');
        if (!r.znalezione.FORMA_PLATNOSCI && !r.znalezione.FORMA_PLATNOSCI_PLAT) {
          opis = 'W pliku nie ma znaczników FORMA_PLATNOSCI ani FORMA_PLATNOSCI_PLAT — czy to na pewno plik importu Optimy?';
        }
        box.appendChild(el('div', 'opis', opis));
        var pg = podglad(p);
        if (pg && pg.blad) {
          box.appendChild(el('div', 'opis', 'Uwaga: przeglądarka zgłasza błąd składni XML — plik mógł być uszkodzony już wcześniej.'));
        } else if (pg && pg.wiersze.length) {
          var d = el('details');
          d.appendChild(el('summary', null, 'Podgląd dokumentów (' + pg.wiersze.length + ')'));
          var t = el('table'), th = el('tr');
          ['Numer', 'Kontrahent', 'Forma (dokument)', 'Forma (płatności)'].forEach(function (h) { th.appendChild(el('th', null, h)); });
          t.appendChild(th);
          var forma = $('forma').value.trim();
          pg.wiersze.forEach(function (x) {
            var tr = el('tr');
            tr.appendChild(el('td', null, x.numer));
            tr.appendChild(el('td', null, x.kontrahent));
            tr.appendChild(el('td', x.forma === forma ? 'nowa' : '', x.forma));
            tr.appendChild(el('td', null, x.platnosci));
            t.appendChild(tr);
          });
          d.appendChild(t);
          box.appendChild(d);
        }
      }
      w.appendChild(box);
    });
    $('akcje').hidden = !pliki.length;
    $('pobierzWszystkie').disabled = !pliki.some(function (p) { return p.wynik; });
  }

  function pobierz(p) {
    var blob = new Blob([p.wynik.bajty], { type: 'application/xml' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = p.nazwa;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 5000);
  }

  function dodaj(lista) {
    var czekaj = [].map.call(lista, function (f) {
      return f.arrayBuffer().then(function (buf) {
        var p = { nazwa: f.name, oryginal: new Uint8Array(buf) };
        przetworz(p);
        pliki = pliki.filter(function (x) { return x.nazwa !== p.nazwa; });
        pliki.push(p);
      });
    });
    Promise.all(czekaj).then(rysuj);
  }

  function odswiez() { pliki.forEach(przetworz); rysuj(); }

  $('pliki').addEventListener('change', function () { dodaj(this.files); this.value = ''; });
  var drop = $('drop');
  ['dragenter', 'dragover'].forEach(function (ev) {
    drop.addEventListener(ev, function (e) { e.preventDefault(); drop.classList.add('over'); });
  });
  ['dragleave', 'drop'].forEach(function (ev) {
    drop.addEventListener(ev, function (e) { e.preventDefault(); drop.classList.remove('over'); });
  });
  drop.addEventListener('drop', function (e) { dodaj(e.dataTransfer.files); });
  $('forma').addEventListener('input', odswiez);
  $('tylkoPuste').addEventListener('change', odswiez);
  $('pobierzWszystkie').addEventListener('click', function () {
    pliki.filter(function (p) { return p.wynik; }).forEach(function (p, i) {
      setTimeout(function () { pobierz(p); }, i * 300);
    });
  });
  $('wyczysc').addEventListener('click', function () { pliki = []; rysuj(); });
})();
