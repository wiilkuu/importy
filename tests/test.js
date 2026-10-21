// node tests/test.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const { popraw } = require('../www/popraw.js');
const F = (n) => fs.readFileSync(path.join(__dirname, 'fixtures', n));

for (const [plik, enc] of [['rejestr.xml', 'utf-8'], ['rejestr-1250.xml', 'windows-1250']]) {
  const we = new Uint8Array(F(plik));
  const r = popraw(we, { forma: 'gotówka' });
  assert.strictEqual(r.kodowanie, enc);
  assert.deepStrictEqual(r.zmienione, { FORMA_PLATNOSCI: 1, FORMA_PLATNOSCI_PLAT: 2 });
  const txt = new TextDecoder(enc).decode(r.bajty);
  const org = new TextDecoder(enc).decode(we);
  assert.ok(txt.includes('<FORMA_PLATNOSCI_PLAT><![CDATA[gotówka]]></FORMA_PLATNOSCI_PLAT><WALUTA_PLAT>'));
  assert.ok(txt.includes('<FORMA_PLATNOSCI><![CDATA[przelew]]>'), 'istniejąca forma nienaruszona');
  assert.ok(txt.includes('<FORMA_PLATNOSCI_ID><![CDATA[]]></FORMA_PLATNOSCI_ID>'), 'inne znaczniki nienaruszone');
  assert.ok(txt.includes('Żółć Sp. z o.o.'), 'polskie znaki nienaruszone');
  // poza podmienionymi znacznikami plik identyczny
  const norm = (s) => s.replace(/<FORMA_PLATNOSCI(_PLAT)?(\/>|>[\s\S]*?<\/FORMA_PLATNOSCI(_PLAT)?>)/g, 'X');
  assert.strictEqual(norm(txt), norm(org));
  // nadpisywanie wszystkich
  const r2 = popraw(we, { forma: 'gotówka', tylkoPuste: false });
  assert.strictEqual(r2.razem, 4);
  // drugi przebieg — nic do zmiany
  assert.strictEqual(popraw(r.bajty, {}).razem, 0);
  console.log('OK', plik);
}
assert.throws(() => popraw(new Uint8Array(F('rejestr.xml')), { forma: 'a<b' }));
console.log('wszystkie testy OK');
