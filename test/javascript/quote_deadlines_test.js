const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

test("deadline updater crosses the warning and overdue boundaries without rewriting sent receipts", () => {
  let now = Date.parse("2026-10-10T14:00:00Z");
  let tick;
  const makeBadge = (kind, due, text) => {
    const classes = new Set();
    return {
      dataset: { quoteDeadline: kind, deadlineAt: due },
      textContent: text,
      classes,
      classList: { toggle: (value, enabled) => enabled ? classes.add(value) : classes.delete(value) }
    };
  };
  const pending = makeBadge("due", "2026-10-10T17:20:00Z", "Server value");
  const sent = makeBadge("sent", "2026-10-10T10:00:00Z", "Sent in 1h 05m");
  const malformed = makeBadge("due", "not a date", "Keep server value");
  const context = {
    Date: { now: () => now, parse: Date.parse },
    document: {
      readyState: "complete",
      querySelectorAll: (selector) => {
        assert.equal(selector, '[data-quote-deadline="due"]');
        return [pending, sent, malformed].filter((badge) => badge.dataset.quoteDeadline === "due");
      }
    },
    window: { setInterval: (callback, interval) => { assert.equal(interval, 60000); tick = callback; } }
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../../app/assets/javascripts/quote_deadlines.js"), "utf8"), context);
  assert.equal(pending.textContent, "Due in 3h 20m");
  assert.deepEqual([...pending.classes], ["deadline--calm"]);

  now = Date.parse("2026-10-10T14:20:00Z");
  tick();
  assert.equal(pending.textContent, "Due in 3h 00m");
  assert.deepEqual([...pending.classes], ["deadline--soon"]);

  now = Date.parse("2026-10-10T18:25:00Z");
  tick();
  assert.equal(pending.textContent, "Overdue by 1h 05m");
  assert.deepEqual([...pending.classes], ["deadline--overdue"]);
  assert.equal(sent.textContent, "Sent in 1h 05m");
  assert.equal(malformed.textContent, "Keep server value");
});
