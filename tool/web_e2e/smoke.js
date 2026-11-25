// Web-Smoke-Test der echten App (Release-Build): Start, Semantik, Navigation.
const { chromium } = require('playwright');
const base = 'http://localhost:8766/Lernen/';
const out = process.argv[2];
const width = +(process.argv[3] || 1280), height = +(process.argv[4] || 800);
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width, height } });
  const errors = [];
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message.slice(0, 200)));
  page.on('console', (m) => { if (m.type() === 'error' && !m.text().includes('ERR_TUNNEL')) errors.push('console: ' + m.text().slice(0, 300)); });
  await page.goto(base);
  await page.waitForFunction(() => !document.getElementById('lernen-loading'), null, { timeout: 60000 });
  await page.waitForTimeout(1500);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(1500);
  const labels = () => page.evaluate(() => [...document.querySelectorAll('flt-semantics')]
    .map((e) => (e.getAttribute('aria-label') || [...e.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join('')).trim())
    .filter((t) => t && t.length < 80));
  const shot = (name) => page.screenshot({ path: `${out}/${width}-${name}.png` });
  const result = { start: [...new Set(await labels())].slice(0, 40) };
  await shot('start');
  async function tap(text) {
    const el = page.locator('flt-semantics', { hasText: text }).or(page.locator(`flt-semantics[aria-label*="${text}"]`)).last();
    if (await el.count() === 0) return false;
    await el.click({ force: true });
    await page.waitForTimeout(1200);
    return true;
  }
  for (const tab of ['Daily Quiz', 'Kalender', 'Fortschritt', 'Einstellungen', 'Fächer']) {
    result['tab:' + tab] = await tap(tab);
    await shot('tab-' + tab.replace(' ', '_'));
  }
  result.errors = errors;
  console.log(JSON.stringify(result, null, 1));
  await browser.close();
})();
