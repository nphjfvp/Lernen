// Ablauf im echten Web-Build: Fach anlegen, öffnen, neue Lernmodi aufrufen.
const { chromium } = require('playwright');
const out = process.argv[2];
const width = +(process.argv[3] || 1280), height = +(process.argv[4] || 800);
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width, height } });
  const errors = [];
  page.on('pageerror', (e) => { if (!e.message.includes('firebasejs')) errors.push('pageerror: ' + e.message.slice(0, 200)); });
  page.on('console', (m) => { if (m.type() === 'error' && !m.text().includes('ERR_TUNNEL')) errors.push('console: ' + m.text().slice(0, 300)); });
  await page.goto('http://localhost:8766/Lernen/');
  await page.waitForFunction(() => !document.getElementById('lernen-loading'), null, { timeout: 60000 });
  await page.waitForTimeout(1500);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(1500);
  const steps = [];
  const shot = (name) => page.screenshot({ path: `${out}/${width}-${name}.png` });
  const has = async (text) => { for (let k = 0; k < 4; k++) { if (await hasNow(text)) return true; await page.mouse.move(width / 2, height / 2); await page.mouse.wheel(0, height * 0.7); await page.waitForTimeout(500); } return false; };
  const hasNow = async (text) => (await page.locator('flt-semantics', { hasText: text }).count()) + (await page.locator(`flt-semantics[aria-label*="${text}"]`).count()) > 0;
  async function tap(text) {
    let el;
    for (let scroll = 0; scroll < 6; scroll++) {
      el = page.locator(`flt-semantics[aria-label*="${text}"]`);
      if (await el.count() === 0) el = page.locator('flt-semantics', { hasText: text });
      if (await el.count() > 0) break;
      await page.mouse.move(width / 2, height / 2);
      await page.mouse.wheel(0, height * 0.7);
      await page.waitForTimeout(600);
    }
    if (await el.count() === 0) { steps.push('FEHLT: ' + text); return false; }
    await el.last().click({ force: true });
    await page.waitForTimeout(1300);
    steps.push('ok: ' + text);
    return true;
  }
  await tap('Erstes Fach anlegen');
  // Name eintippen: das Namensfeld oben anklicken (Flutter legt dann ein Eingabefeld an).
  await page.locator('input[aria-label*="Name des Fachs"]').first().focus();
  await page.waitForTimeout(800);
  steps.push('Fokus: ' + await page.evaluate(() => document.activeElement?.tagName + '/' + (document.activeElement?.getAttribute('aria-label') || '').slice(0, 20)));
  await page.keyboard.type('Physik E2E', { delay: 40 });
  await page.waitForTimeout(800);
  await page.waitForTimeout(500);
  await shot('form');
  await tap('Fach anlegen');
  await shot('after-create');
  await tap('Physik E2E');
  await shot('module');
  steps.push('Laut denken sichtbar: ' + await has('Laut denken'));
  steps.push('Einstufen sichtbar: ' + await has('Einstufen'));
  await tap('Einstufen');
  steps.push('Einstufen-Hinweis: ' + await has('nichts einzustufen'));
  await shot('placement');
  await page.goBack().catch(() => {});
  await page.keyboard.press('Escape');
  await page.waitForTimeout(800);
  for (const t of ['Zurück', 'Back']) { if (await has(t)) { await tap(t); break; } }
  await tap('Laut denken');
  steps.push('Laut-denken ohne Key: ' + await has('OpenRouter-Key'));
  await shot('think');
  console.log(JSON.stringify({ steps, errors }, null, 1));
  await browser.close();
})();
