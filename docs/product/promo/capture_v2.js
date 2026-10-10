// Records promo_v2.html. Usage:
//   node capture_v2.js stills <outdir>   -> one PNG at each shot's midpoint
//   node capture_v2.js frames <outdir>   -> 900 JPEG frames at 30 fps
const { chromium } = require(process.env.HOME + '/.claude/skills/playwright-skill/node_modules/playwright');
const path = require('path'); const fs = require('fs');
const MID = [1.5, 4.25, 9.0, 14.5, 17.5, 20.0, 22.5, 24.5, 27.75];
(async () => {
  const mode = process.argv[2], out = path.resolve(process.argv[3] || 'frames_v2');
  fs.mkdirSync(out, { recursive: true });
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  await p.goto('file://' + path.resolve(__dirname, 'promo_v2.html') + '?t=0');
  await p.waitForTimeout(800);
  if (mode === 'stills') {
    const ts = process.argv[4] ? process.argv[4].split(',').map(Number) : MID;
    for (const t of ts) { await p.evaluate(t => render(t), t); await p.screenshot({ path: `${out}/still_${t}.png` }); }
  } else {
    const fps = 30, total = 30 * fps;
    for (let i = 0; i < total; i++) {
      await p.evaluate(t => render(t), i / fps);
      await p.screenshot({ path: `${out}/f${String(i).padStart(4, '0')}.jpg`, type: 'jpeg', quality: 92 });
    }
  }
  await b.close();
})();
