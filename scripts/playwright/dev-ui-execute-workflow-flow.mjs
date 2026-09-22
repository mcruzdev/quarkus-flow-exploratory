#!/usr/bin/env node
// Drives the Quarkus Dev UI's "Run workflow" view: opens the Workflows
// list, clicks the target workflow's row-level Run (▶) button, replaces
// the input editor's content, clicks "Start workflow", and reports the
// output panel's value before and after — as raw text, not a screenshot
// guess, since Dev UI keeps the full result in an attribute.
//
// Selectors confirmed against a live Dev UI instance running this repo's
// own generated project, not guessed:
//   - workflow list rows expose a stable button id
//     `play-diagramEditor-<namespace>-<name>-<version-with-dashes>`
//   - the run view is a <qwc-flow-workflow-execution> element with an
//     editable input <qui-themed-code-block id="code"> (CodeMirror 6
//     underneath — the actual contenteditable is `.cm-content`) and a
//     second, unlabeled <qui-themed-code-block> whose `value` attribute
//     holds the raw output text; `#execute-workflow` runs it.
// One empirically-observed finding this script exists to evidence: Dev UI
// does NOT show any visible error for malformed JSON input — the output
// panel silently keeps whatever it last held. Reused for both the valid-
// and invalid-input steps rather than writing two near-identical scripts.
import { writeFile } from "node:fs/promises";
import { chromium } from "playwright";

const [, , baseUrl, namespace, name, version, inputText, outDir, screenshotName, outputTextFile] = process.argv;

if (!baseUrl || !namespace || !name || !version || inputText === undefined || !outDir || !screenshotName || !outputTextFile) {
  console.error(
    "Usage: dev-ui-execute-workflow-flow.mjs <base_url> <namespace> <name> <version> <input_text> <out_dir> <screenshot_name> <output_text_file>",
  );
  process.exit(2);
}

const versionSlug = version.replace(/\./g, "-");
const playButtonId = `play-diagramEditor-${namespace}-${name}-${versionSlug}`;

const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  await page.goto(`${baseUrl}/q/dev-ui/quarkus-flow/workflows`, { waitUntil: "load", timeout: 30000 });
  await page.waitForTimeout(3000);

  await page.locator(`#${playButtonId}`).click();
  await page.waitForSelector("qui-themed-code-block#code", { timeout: 10000 });

  const outputBlock = page.locator("qui-themed-code-block:not(#code)").first();
  const outputValueBefore = (await outputBlock.getAttribute("value")) ?? "";

  const inputEditor = page.locator("qui-themed-code-block#code .cm-content");
  await inputEditor.click();
  await page.keyboard.press(process.platform === "darwin" ? "Meta+A" : "Control+A");
  if (inputText.length > 0) {
    await page.keyboard.type(inputText);
  } else {
    await page.keyboard.press("Delete");
  }

  await page.locator("#execute-workflow").click();
  // No loading indicator to wait on reliably (see the silent-failure
  // finding above) — a fixed settle beat is the honest choice here.
  await page.waitForTimeout(2000);

  const outputValueAfter = (await outputBlock.getAttribute("value")) ?? "";

  await page.screenshot({ path: `${outDir}/${screenshotName}`, fullPage: true });
  await writeFile(outputTextFile, outputValueAfter, "utf8");

  console.log(JSON.stringify({ outputValueBefore, outputValueAfter }));
} finally {
  await browser.close();
}
