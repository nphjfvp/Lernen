const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  const log = [];
  page.on('console', (m) => log.push(m.type() + ': ' + m.text().slice(0, 200)));
  page.on('pageerror', (e) => log.push('pageerror: ' + e.message.slice(0, 200)));
  if (process.argv[3] === 'offline') await page.addInitScript(() => Object.defineProperty(Navigator.prototype, 'onLine', { get: () => false }));
  const t0 = Date.now();
  await page.goto('http://localhost:8766/Lernen/');
  let state = '';
  for (let i = 0; i < 40; i++) {
    state = await page.evaluate(() => {
      const l = document.getElementById('lernen-loading');
      return (l ? 'loading-div:' + getComputedStyle(l).display : 'no-loading-div') + ' view:' + !!document.querySelector('flutter-view');
    });
    if (!state.startsWith('loading-div:block') && !state.startsWith('loading-div:flex')) break;
    await page.waitForTimeout(250);
  }
  console.log('after', Date.now() - t0, 'ms', state);
  await page.waitForTimeout(2000);
  await page.screenshot({ path: process.argv[2] + '/start.png' });
  console.log(log.join('\n'));
  await browser.close();
})();
