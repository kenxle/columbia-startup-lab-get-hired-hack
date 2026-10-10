const { chromium } = require(process.env.HOME + '/.claude/skills/playwright-skill/node_modules/playwright');
const path = require('path'); const fs = require('fs');
(async () => {
  const mode = process.argv[2]; // 'stills' or 'frames'
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  await p.goto('file://' + path.resolve('promo.html') + '?t=0');
  await p.waitForTimeout(500);
  if (mode === 'stills') {
    for (const t of [4.8, 10.5, 15, 22.5, 25, 29.5]) {
      await p.evaluate(t => render(t), t);
      await p.screenshot({ path: `still_${t}.png` });
    }
  } else {
    fs.mkdirSync('frames', { recursive: true });
    const fps = 30, total = 30 * fps;
    for (let i = 0; i < total; i++) {
      await p.evaluate(t => render(t), i / fps);
      await p.screenshot({ path: `frames/f${String(i).padStart(4, '0')}.jpg`, type: 'jpeg', quality: 95 });
    }
  }
  await b.close();
})();
