// Zeichnet mit Stift-Events (CDP, pointerType "pen") ein großes "x" und misst,
// wie lange der Browser nach dem 1. Strich blockiert ist.
const { chromium } = require('playwright');
const url = process.argv[2] || 'http://localhost:8765/';
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1000, height: 900 }, deviceScaleFactor: 2 });
  const logs = [];
  page.on('console', (m) => { if (m.text().startsWith('BENCH')) logs.push(m.text()); });
  await page.addInitScript(() => {
    window.__long = [];
    new PerformanceObserver((l) => l.getEntries().forEach((e) => window.__long.push(Math.round(e.duration)))).observe({ type: 'longtask', buffered: true });
  });
  await page.goto(url);
  await page.waitForTimeout(6000);
  const cdp = await page.context().newCDPSession(page);
  const pen = (type, x, y) => cdp.send('Input.dispatchMouseEvent', {
    type, x, y, button: 'left', buttons: type === 'mouseReleased' ? 0 : 1, clickCount: 1,
    pointerType: 'pen', force: type === 'mouseReleased' ? 0 : 0.5,
  });
  const frame = () => page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(() => r()))));
  async function stroke(x0, y0, x1, y1) {
    const t0 = Date.now();
    await pen('mousePressed', x0, y0);
    for (let i = 1; i <= 20; i++) await pen('mouseMoved', x0 + (x1 - x0) * i / 20, y0 + (y1 - y0) * i / 20);
    await pen('mouseReleased', x1, y1);
    const tUp = Date.now();
    await frame();
    return { draw: tUp - t0, afterUp: Date.now() - tUp };
  }
  // Blatt beginnt ganz oben links; Zeilen 64 px (Blatt) – das "x" in Zeile 10,
  // groß geschrieben: der 2. Strich setzt eine Zeile höher an.
  const box = await page.evaluate(() => { const r = document.querySelector('flutter-view, flt-glass-pane')?.getBoundingClientRect(); return r ? { x: r.x, y: r.y } : { x: 0, y: 0 }; });
  const results = [];
  for (let rep = 0; rep < 2; rep++) {
    const bx = 300 + rep * 120, by = 600;
    await page.evaluate(() => (window.__long = []));
    const a = await stroke(bx, by, bx + 60, by + 70);
    const tDown = Date.now();
    const b = await stroke(bx + 60, by - 25, bx, by + 70); // 2. Strich setzt höher an
    const long = await page.evaluate(() => window.__long);
    results.push({ first: a, second: b, longTasksMs: long });
    await page.waitForTimeout(800);
  }
  console.log(JSON.stringify(results.map(r => ({first: r.first, second: r.second, longCount: r.longTasksMs.length, longAvg: Math.round(r.longTasksMs.reduce((a,b)=>a+b,0)/Math.max(1,r.longTasksMs.length)), longMax: Math.max(0, ...r.longTasksMs)}))));
  console.log(logs.slice(-12).join('\n'));
  await browser.close();
})();
