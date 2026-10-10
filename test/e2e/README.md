# End-to-end tests: the demo flow

Playwright tests that walk the demo video script in [DEMO_SCRIPT.md](../../docs/product/DEMO_SCRIPT.md), one `describe` block per beat. The findings from the walk are in [FLOW_WALK.md](../../docs/product/FLOW_WALK.md).

## Run them

From the repo root, after `script/setup`:

```sh
npm install
npm run test:e2e
```

The config starts its own Rails server on port 3211 (set `E2E_PORT` to change it; 3100 is refused). It runs with `LAUNCHY_DRY_RUN=true` and `BROWSER=/usr/bin/true`, so letter_opener never opens a browser tab, and with live models off. No real email is sent.

Each test opens a fresh browser session, so it gets its own workspace of RFQs in the development database. Those records are not visible from your own browser session.

The browser is Playwright's Chromium headless shell. If it is not installed, run `npx playwright install chromium`.

## Reading the results

Tests named `GAP: ...` are marked `test.fail()`. Each one describes something the script says that the app does not do yet. The list reporter shows them with a cross, and they count as passed while the gap exists. When one starts to fail, the gap is closed: remove its `test.fail` line.

The HTML report and failure traces go to `tmp/playwright/`.
