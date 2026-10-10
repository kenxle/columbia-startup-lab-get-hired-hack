// Captures the real app screens used in promo v2 (shots 2, 5, 6, 8).
// VIEW ONLY. It does not create, approve, send or answer anything: opening quote pages and
// clicking buttons in the app can fire its auto-send job. It reuses a browser session that
// already holds the demo RFQ (pasted once by hand from docs/product/demo_rfq/email.txt).
// Usage: node capture_app_v2.js <playwright storageState.json> <quote url>
const { chromium } = require(process.env.HOME + '/.claude/skills/playwright-skill/node_modules/playwright');
const fs = require('fs'), path = require('path');
const APP = 'http://127.0.0.1:3100', OUT = path.resolve(__dirname, 'captures_v2');
const RFQ = path.resolve(__dirname, '../demo_rfq/email.txt');
fs.mkdirSync(OUT, { recursive: true });
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 2, storageState: process.argv[2] });
  await ctx.route(/127\.0\.0\.1:7817/, r => r.abort()); // keep the LAHE review layer out of the shots
  const p = await ctx.newPage();
  const shot = async (loc, name) => { await loc.scrollIntoViewIfNeeded(); await loc.screenshot({ path: `${OUT}/${name}.png` }); console.log('saved', name); };

  // Shot 2: Quotes list. Overdue rows are hidden (the shot list asks for rows that are not overdue).
  await p.goto(APP + '/quotes'); await p.waitForTimeout(800);
  await p.evaluate(() => document.querySelectorAll('tbody tr').forEach(tr => { if (/Overdue|Sent/.test(tr.innerText)) tr.style.display = 'none'; }));
  await shot(p.locator('table').first(), 'shot2_quotes_list');

  const quoteUrl = process.argv[3].split('?')[0];
  await p.goto(quoteUrl + '?status=all');
  const ids = [...new Set((await p.$$eval('tbody a[href*="line="]', as => as.map(a => new URL(a.href).searchParams.get('line')))))];
  console.log('line ids', ids);
  const lineUrl = n => `${quoteUrl}?line=${ids[n - 1]}&status=all`;
  const sourcePanel = () => p.locator('section, .panel').filter({ has: p.getByRole('heading', { name: 'Original RFQ' }) }).last();

  // Shot 5: line 1, thickness field closed then opened.
  await p.goto(lineUrl(1));
  await shot(sourcePanel(), 'shot5_source_line1');
  const th = p.locator('details.field-row').filter({ has: p.locator('.field-row__label', { hasText: /^Thickness$/ }) });
  await shot(th, 'shot5_thickness_closed');
  await th.locator('summary').click(); await p.waitForTimeout(300);
  await shot(th, 'shot5_thickness_open');
  await shot(p.locator('details.field-row').first().locator('xpath=..'), 'shot5_fields_open');

  // Shot 6: line 3, SA-240 paperwork.
  await p.goto(lineUrl(3));
  await shot(sourcePanel(), 'shot6_source_line3');
  await shot(p.locator('.detail-block').filter({ hasText: 'Paperwork requested' }).first(), 'shot6_paperwork');

  // Shot 8a: the drafted buyer question.
  await p.goto(quoteUrl + '/buyer_questions');
  const pv = p.getByText('Question preview', { exact: true });
  const card = pv.locator('xpath=ancestor::*[self::section or self::div][.//*[contains(text(),"Please clarify")]][1]');
  const cb = await card.boundingBox();
  const clar = await p.getByText(/Please clarify the following/).boundingBox();
  const l2h = p.getByText(/^Line 2: /).first();
  const l2b = await l2h.boundingBox();
  const pvb = await pv.boundingBox();
  await p.screenshot({ path: `${OUT}/shot8_question_head.png`, fullPage: true, clip: { x: cb.x, y: pvb.y - 24, width: cb.width, height: clar.y + clar.height + 18 - (pvb.y - 24) } });
  await p.screenshot({ path: `${OUT}/shot8_question_line2.png`, fullPage: true, clip: { x: cb.x, y: l2b.y - 58, width: cb.width, height: l2b.height + 58 + 18 } });
  console.log('saved shot8 question');
  // Shot 8b: the Approve quote button, viewed, not clicked. The approval itself is drawn in the animation.
  await p.goto(quoteUrl + '?status=all');
  await shot(p.locator('section.approval .approval__form'), 'shot8_approve_before');
  await b.close();
})();
