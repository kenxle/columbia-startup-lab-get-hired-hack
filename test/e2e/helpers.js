const fs = require('fs');
const path = require('path');
const { expect } = require('@playwright/test');

const ROOT = path.resolve(__dirname, '../..');
const read = (relative) => fs.readFileSync(path.join(ROOT, relative), 'utf8');

const DEMO = {
  northlineEmail: () => read('docs/product/demo_rfq/email.txt'),
  northlinePdf: path.join(ROOT, 'docs/product/demo_rfq/northline_rfq_2026-1010.pdf'),
  northlineCsv: path.join(ROOT, 'docs/product/demo_rfq/northline_rfq_2026-1010.csv'),
  secondRfq: () => read('docs/product/demo_rfq/second_rfq_email.txt'),
  // The abrasive demo pair behind RFQ-0014 (complete) and RFQ-0017 (quantity missing).
  abrasiveComplete: () => read('tools/rfq_processing/spec/fixtures/demo_pair/complete.txt'),
  abrasiveIncomplete: () => read('tools/rfq_processing/spec/fixtures/demo_pair/incomplete.txt'),
};

// Paste an RFQ (and optionally attach one file) through the New RFQ form.
// Waits until processing reports Succeeded. Returns the quote path, like /quotes/42.
async function createRfq(page, { title, buyer, text, file }) {
  await page.goto('/quotes/new');
  await page.getByLabel('RFQ title').fill(title);
  await page.getByLabel('Buyer').fill(buyer);
  if (text) await page.getByLabel('RFQ text').fill(text);
  if (file) await page.getByLabel('Or upload the original file').setInputFiles(file);
  await page.getByRole('button', { name: 'Save RFQ' }).click();
  await expect(page).toHaveURL(/\/quotes\/\d+/);
  const quotePath = new URL(page.url()).pathname;
  await expect(async () => {
    await page.reload();
    await expect(page.locator('.processing-run__status')).toContainText('Succeeded', { timeout: 1_000 });
  }).toPass({ timeout: 60_000 });
  return quotePath;
}

// Open one line by its position in the RFQ (1-based) on the review screen.
async function openLine(page, quotePath, position) {
  await page.goto(`${quotePath}?status=all`);
  const row = page.locator('tr[data-review-row]').filter({
    has: page.locator('td:first-child', { hasText: new RegExp(`^\\s*${position}\\s*$`) }),
  });
  await row.locator('a[data-review-link]').click();
  await expect(page.locator('section.review__quote')).toContainText(`Line ${position}:`);
}

// The value cell of one item in the quote summary strip (Lines, Ready, Held, Subtotal...).
function summaryValue(page, label) {
  return page.locator('.summary__item').filter({ has: page.locator('dt', { hasText: new RegExp(`^${label}`) }) }).locator('dd');
}

// The row for one line (1-based position) in the quote lines table.
function lineRow(page, position) {
  return page.locator('tr[data-review-row]').filter({
    has: page.locator('td:first-child', { hasText: new RegExp(`^\\s*${position}\\s*$`) }),
  });
}

module.exports = { DEMO, createRfq, openLine, summaryValue, lineRow, ROOT };
