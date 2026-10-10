// The demo video flow, beat by beat, as written in docs/product/DEMO_SCRIPT.md ("The script").
// Each test gets a fresh browser session, so it works in its own workspace of RFQs.
// Tests marked test.fail() describe what the script says but the app does not do yet.
// They pass while the gap exists. When one starts failing, the gap is fixed: remove the test.fail line.
const { test, expect } = require('@playwright/test');
const { DEMO, createRfq, openLine, summaryValue, lineRow } = require('./helpers');

const NORTHLINE = 'Northline Fabrication';

async function createNorthline(page) {
  return createRfq(page, {
    title: 'RFQ 2026-1010, sheet, plate, blast media and ingot',
    buyer: NORTHLINE,
    text: DEMO.northlineEmail(),
    file: DEMO.northlinePdf,
  });
}

test.describe('Beat 1: the RFQ comes in and the run finishes', () => {
  test('home page shows the Quote Desk workspace', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Quotes', level: 1 })).toBeVisible();
    await expect(page.getByRole('link', { name: 'New RFQ' }).first()).toBeVisible();
    await expect(page.locator('table.data-table tbody tr').first()).toBeVisible();
  });

  test('pasting the Northline email and attaching its PDF reads eight lines', async ({ page }) => {
    const started = Date.now();
    const quotePath = await createNorthline(page);
    expect(Date.now() - started).toBeLessThan(60_000);
    await expect(page).toHaveURL(new RegExp(`${quotePath}`));
    await expect(summaryValue(page, 'Lines')).toHaveText('8');
    await expect(page.locator('.review__source')).toContainText('northline_rfq_2026-1010.pdf');
    await expect(page.locator('.review__source')).toContainText('Attachment text');
  });

  test('the Northline spreadsheet on its own (CSV) reads the same eight lines', async ({ page }) => {
    await createRfq(page, { title: 'Northline CSV', buyer: NORTHLINE, file: DEMO.northlineCsv });
    await expect(summaryValue(page, 'Lines')).toHaveText('8');
    await expect(summaryValue(page, 'Ready')).toHaveText('1');
  });
});

test.describe('Beat 2: the review screen with a status on every line', () => {
  test('RFQ and quote sit side by side, with Ready and held lines', async ({ page }) => {
    const quotePath = await createNorthline(page);
    await page.goto(`${quotePath}?status=all`);
    await expect(page.getByRole('heading', { name: 'Original RFQ' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Quote lines' })).toBeVisible();
    await expect(page.locator('tr[data-review-row]')).toHaveCount(8);
    await expect(lineRow(page, 4).locator('td').last()).toContainText('Ready');
    await expect(lineRow(page, 2).locator('td').last()).toContainText(/Question to send|Waiting on buyer/);
  });

  test('the abrasive demo pair shows four Ready (USD 1,810) and three Ready plus one held (USD 1,010)', async ({ page }) => {
    await createRfq(page, { title: 'Abrasive restock', buyer: NORTHLINE, text: DEMO.abrasiveComplete() });
    await expect(summaryValue(page, 'Ready')).toHaveText('4');
    await expect(summaryValue(page, 'Held')).toHaveText('0');
    await expect(summaryValue(page, 'Subtotal')).toHaveText('USD 1,810.00');

    await createRfq(page, { title: 'Abrasive restock, quantity missing', buyer: NORTHLINE, text: DEMO.abrasiveIncomplete() });
    await expect(summaryValue(page, 'Ready')).toHaveText('3');
    await expect(summaryValue(page, 'Held')).toHaveText('1');
    await expect(summaryValue(page, 'Subtotal')).toHaveText('USD 1,010.00');
  });

  test('GAP: the hex cap screw line shows the status No match', async ({ page }) => {
    test.fail(true, 'Line 8 (hex cap screws) is held as a question for the buyer, not labeled No match.');
    const quotePath = await createNorthline(page);
    await page.goto(`${quotePath}?status=all`);
    await expect(lineRow(page, 8).locator('td').last()).toContainText('No match', { timeout: 3_000 });
  });
});

test.describe('Beat 3: 16 gauge on stainless reads as 0.0625 in', () => {
  test('the thickness field shows the source words and names the stainless gauge table', async ({ page }) => {
    const quotePath = await createNorthline(page);
    await openLine(page, quotePath, 1);
    const thickness = page.locator('details.field-row', { hasText: 'Thickness' }).first();
    await expect(thickness.locator('.field-row__value')).toHaveText('0.0625');
    await thickness.locator('summary').click();
    await expect(thickness.locator('.evidence .quote-text')).toHaveText('16 ga');
    await expect(thickness).toContainText('16 gauge on the stainless steel table is 0.0625 in');
    await expect(page.locator('.review__source mark', { hasText: '16 ga' }).first()).toBeVisible();
  });
});

test.describe('Beat 4: a compliance flag with its trigger word', () => {
  test('the SA-240 plate line flags ASME code material and a 3.1 certificate', async ({ page }) => {
    const quotePath = await createNorthline(page);
    await openLine(page, quotePath, 3);
    const paperwork = page.locator('.compliance');
    await expect(paperwork).toContainText('ASME SA code material');
    await expect(paperwork).toContainText('EN 10204 3.1 certificate required');
    await expect(paperwork.locator('.quote-text', { hasText: 'SA-240' })).toBeVisible();
    await expect(page.locator('.review__source mark', { hasText: 'SA-240' }).first()).toBeAttached();
  });
});

test.describe('Beat 5: a sourced price, a held line, and an unmatched line', () => {
  test('steel shot S-330 is priced from the RudCo website list price', async ({ page }) => {
    const quotePath = await createNorthline(page);
    await openLine(page, quotePath, 4);
    await expect(lineRow(page, 4)).toContainText('USD 0.40');
    await expect(lineRow(page, 4)).toContainText('USD 800.00');
    await expect(page.locator('section.review__quote')).toContainText('RudCo website list price, rud-co.com');
  });

  test('the P1020 ingot line is held with no price', async ({ page }) => {
    const quotePath = await createNorthline(page);
    await openLine(page, quotePath, 5);
    await expect(lineRow(page, 5).locator('td').last()).toContainText(/Question to send|Waiting on buyer/);
    await expect(page.locator('section.review__quote')).toContainText('Not priced. Held lines carry no price');
  });

  test('the hex cap screw line has no catalog item', async ({ page }) => {
    const quotePath = await createNorthline(page);
    await page.goto(`${quotePath}?status=all`);
    await expect(lineRow(page, 8)).toContainText('No catalog item');
  });

  test('GAP: the stocked steel shot line shows a 24 to 48 hour lead time', async ({ page }) => {
    test.fail(true, 'Every line shows "Lead time: to confirm"; no sourced lead time reaches the screen.');
    const quotePath = await createNorthline(page);
    await page.goto(`${quotePath}?status=all`);
    await expect(lineRow(page, 4)).toContainText('24 to 48 hours', { timeout: 3_000 });
  });
});

test.describe('Beat 6: one question to the buyer, then the line turns Ready', () => {
  test('the held line gets a question in the local mail preview, and the answer makes it Ready', async ({ page }) => {
    const quotePath = await createRfq(page, {
      title: 'Abrasive restock, quantity missing', buyer: NORTHLINE, text: DEMO.abrasiveIncomplete(),
    });
    const reference = (await summaryValue(page, 'Reference').innerText()).trim();

    await page.getByRole('link', { name: /Review buyer questions \(1\)/ }).click();
    await expect(page.getByRole('heading', { name: 'Review buyer questions' })).toBeVisible();
    await expect(page.locator('.buyer-draft__message')).toContainText('Line 1');

    await page.getByRole('button', { name: 'Open local email preview' }).click();
    await expect(page.getByRole('heading', { name: 'Local email preview' })).toBeVisible();
    await expect(page.locator('main')).toContainText(`Questions about ${reference}`);
    await expect(page.locator('main')).toContainText('No email was sent to the buyer');

    await page.goto(`${quotePath}/buyer_questions`);
    await page.getByLabel("The buyer's answer").fill('2000 lb');
    await page.getByRole('button', { name: 'Apply buyer answer' }).click();
    await expect(page.locator('main')).toContainText('Answer applied');
    await expect(summaryValue(page, 'Ready')).toHaveText('4');
    await expect(summaryValue(page, 'Held')).toHaveText('0');
    await expect(summaryValue(page, 'Subtotal')).toHaveText('USD 1,810.00');
    await expect(lineRow(page, 1)).toContainText('2,000 lb');
  });

  test('GAP: the Northline question email asks only about what the buyer wrote', async ({ page }) => {
    test.fail(true, 'Six questions tell the buyer "The price is to be confirmed by the rep", an internal step.');
    const quotePath = await createNorthline(page);
    await page.goto(`${quotePath}/buyer_questions`);
    await expect(page.locator('.buyer-draft__message')).not.toContainText('price is to be confirmed by the rep', { timeout: 3_000 });
  });
});

test.describe('Beat 7: approve, then the PDF, CSV and email', () => {
  test('approving unlocks the documents and the local send carries PDF and CSV', async ({ page }) => {
    const quotePath = await createRfq(page, { title: 'Abrasive restock', buyer: NORTHLINE, text: DEMO.abrasiveComplete() });
    const reference = (await summaryValue(page, 'Reference').innerText()).trim();

    await page.locator('#reviewed').check();
    await page.getByRole('button', { name: 'Approve quote' }).click();
    await expect(page.locator('main')).toContainText('Quote approved');
    await expect(page.locator('section.approval')).toContainText('Approved');

    await page.getByRole('link', { name: 'Prepare email and PDF' }).click();
    await expect(page.getByRole('heading', { name: 'Email and quote documents' })).toBeVisible();
    await expect(page.locator('.final-quote__body')).toContainText('USD 1810.00');
    await expect(page.locator('.final-quote__body')).toContainText('Price source: RudCo website list price');

    const [pdf] = await Promise.all([page.waitForEvent('download'), page.getByRole('link', { name: 'Download quote PDF' }).click()]);
    expect(pdf.suggestedFilename()).toBe(`${reference}-quote.pdf`);
    const pdfBytes = require('fs').readFileSync(await pdf.path());
    expect(pdfBytes.subarray(0, 4).toString()).toBe('%PDF');

    const [csv] = await Promise.all([page.waitForEvent('download'), page.getByRole('link', { name: 'Download spreadsheet (.csv)' }).click()]);
    const csvText = require('fs').readFileSync(await csv.path(), 'utf8');
    expect(csvText).toContain('"Subtotal, Ready lines only (USD)","1810.00"');
    expect(csvText).toContain('RC-STEELSHOT-S330');

    await page.getByRole('button', { name: 'Send approved quote (local preview)' }).click();
    await expect(page.locator('main')).toContainText('Sent to the local preview inbox with PDF and CSV attachments');
    await expect(page.locator('main')).toContainText(`Quote ${reference}`);
    await expect(page.getByRole('link', { name: `${reference}-quote.pdf` })).toBeVisible();
    await expect(page.getByRole('link', { name: `${reference}-quote.csv` })).toBeVisible();

    await page.goto(quotePath);
    await expect(page.locator('header.page-header')).toContainText('Sent (local preview)');
  });

  test('an edit after approval clears it', async ({ page }) => {
    const quotePath = await createRfq(page, { title: 'Abrasive restock', buyer: NORTHLINE, text: DEMO.abrasiveComplete() });
    await page.locator('#reviewed').check();
    await page.getByRole('button', { name: 'Approve quote' }).click();
    await expect(page.locator('section.approval')).toContainText('Approved');

    await page.getByLabel('Internal note').fill('Confirm bag size with the warehouse');
    await page.getByRole('button', { name: 'Save line' }).click();
    await expect(page.locator('main')).toContainText('Approve the quote again');
    await expect(page.getByRole('button', { name: 'Approve quote' })).toBeVisible();

    await page.goto(`${quotePath}/final_quote`);
    await expect(page).toHaveURL(new RegExp(`${quotePath}$`));
  });
});

test.describe('Beat 8: learn the buyer', () => {
  test('a taught phrase reads right on the buyer\'s next RFQ, and not for another buyer', async ({ page }) => {
    const quotePath = await createNorthline(page);
    await openLine(page, quotePath, 2);
    await page.getByText('Teach a buyer phrase').click();
    await page.getByLabel('Buyer phrase').fill('0.060 in');
    await page.getByLabel('Field').selectOption('thickness');
    await page.getByLabel('Confirmed meaning').fill('0.0625');
    await page.getByRole('button', { name: 'Teach buyer phrase' }).click();
    await expect(page.locator('main')).toContainText('Saved "0.060 in" for Northline Fabrication');

    await createRfq(page, { title: 'RFQ 2026-1017, stainless sheet', buyer: NORTHLINE, text: DEMO.secondRfq() });
    const thickness = page.locator('details.field-row', { hasText: 'Thickness' }).first();
    await expect(thickness.locator('.field-row__value')).toHaveText('0.0625');
    await thickness.locator('summary').click();
    await expect(thickness).toContainText('as the rep taught on RFQ-');

    await createRfq(page, { title: 'Same words, other buyer', buyer: 'Harbor Fabrication', text: DEMO.secondRfq() });
    await expect(page.locator('details.field-row', { hasText: 'Thickness' }).first().locator('.field-row__value')).toHaveText('0.06');
  });

  test('GAP: the taught line on the second RFQ matches the 16 ga 2B sheet without a question', async ({ page }) => {
    test.fail(true, 'The thickness reads 0.0625, but the line stays held with "No catalog item" and asks the buyer to pick a SKU.');
    const quotePath = await createNorthline(page);
    await openLine(page, quotePath, 2);
    await page.getByText('Teach a buyer phrase').click();
    await page.getByLabel('Buyer phrase').fill('0.060 in');
    await page.getByLabel('Field').selectOption('thickness');
    await page.getByLabel('Confirmed meaning').fill('0.0625');
    await page.getByRole('button', { name: 'Teach buyer phrase' }).click();
    await createRfq(page, { title: 'RFQ 2026-1017, stainless sheet', buyer: NORTHLINE, text: DEMO.secondRfq() });
    await expect(lineRow(page, 1)).toContainText('SKU RC-SS304-SHT-16GA-48X96-2B', { timeout: 3_000 });
  });
});

test.describe('Beat 9: the close', () => {
  test('the header shows the RudCo mark and Quote Desk on the review screen', async ({ page }) => {
    await createRfq(page, { title: 'Abrasive restock', buyer: NORTHLINE, text: DEMO.abrasiveComplete() });
    const brand = page.getByRole('link', { name: 'RudCo Quote Desk home' });
    await expect(brand).toContainText('RudCo');
    await expect(brand).toContainText('QUOTE DESK');
    await expect(brand.locator('img.brand__mark')).toBeVisible();
    expect(await brand.locator('img.brand__mark').evaluate((img) => img.naturalWidth)).toBeGreaterThan(0);
  });
});
