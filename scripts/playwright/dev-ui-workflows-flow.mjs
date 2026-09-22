#!/usr/bin/env node
// Clicks through the Quarkus Dev UI the way a human exploring it would:
// Extensions landing page -> the Flow extension's "Workflows" link -> the
// workflows list actually rendering a row. Two screenshots, one per page.
//
// This is deliberately not "navigate straight to /q/dev-ui/quarkus-flow/workflows":
// the point (see README "Known limitations") is evidence that the *link*
// works and the list *renders*, not just that the URL responds.
//
// Selectors below were confirmed against a live Dev UI instance, not
// guessed: the Flow card's link is `<a class="extensionLink">Workflows</a>`,
// and the workflow list is a plain `<table><tbody><tr>` (both live inside
// open Lit shadow roots, which Playwright's locators pierce automatically).
import { chromium } from "playwright";

const [, , baseUrl, outDir] = process.argv;

if (!baseUrl || !outDir) {
  console.error("Usage: dev-ui-workflows-flow.mjs <base_url> <out_dir>");
  process.exit(2);
}

const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  await page.goto(`${baseUrl}/q/dev-ui/extensions`, { waitUntil: "load", timeout: 30000 });
  // Dev UI is a SPA that keeps a live websocket open (hot-reload
  // notifications), so `networkidle` never fires — wait a fixed beat for
  // the extension cards to finish rendering instead.
  await page.waitForTimeout(3000);
  await page.screenshot({ path: `${outDir}/01-dev-ui-extensions.png`, fullPage: true });

  await page.getByText("Workflows", { exact: true }).click();
  await page.waitForURL(/quarkus-flow\/workflows/, { timeout: 10000 });
  // The real assertion: wait for the table to actually render a data row,
  // not just its "no data yet" placeholder row (`#emptystaterow`, present
  // and hidden in the DOM from the start), before calling the page "loaded".
  await page.locator("table tbody tr:not(#emptystaterow)").first().waitFor({ timeout: 10000 });
  await page.screenshot({ path: `${outDir}/02-dev-ui-workflows.png`, fullPage: true });
} finally {
  await browser.close();
}
