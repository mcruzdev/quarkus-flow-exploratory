#!/usr/bin/env node
// Screenshots the Quarkus Dev UI so Area A runs get visual evidence instead
// of just an HTTP 200 reachability check (see README "Known limitations" —
// confirming the workflow is listed and its diagram renders previously
// needed a human opening a browser).
import { chromium } from "playwright";

const [, , url, outFile] = process.argv;

if (!url || !outFile) {
  console.error("Usage: screenshot-dev-ui.mjs <url> <outfile>");
  process.exit(2);
}

const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(url, { waitUntil: "load", timeout: 30000 });
  // Dev UI is a SPA that keeps a live websocket open (for hot-reload
  // notifications), so `networkidle` never fires — wait a fixed beat
  // instead for the extension cards to finish rendering.
  await page.waitForTimeout(3000);
  await page.screenshot({ path: outFile, fullPage: true });
} finally {
  await browser.close();
}
