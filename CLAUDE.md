# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Bash automation for the [Quarkus Flow Exploratory Testing Guide](https://docs.quarkiverse.io/quarkus-flow/dev/). The guide has 19 areas (A–S); this repo currently automates only **Area A — Local Developer Workflow** (generate a project, add `quarkus-flow` + `rest-jackson`, write a DSL workflow, compile, run `quarkus:dev`, verify endpoints and live reload). More areas are meant to be added later following the same pattern.

There is no application code to build here — the "product" is the automation script itself, plus the evidence/report it produces each run.

## Commands

Run the automation:
```bash
./scripts/areas/area-a.sh
# or via the dispatcher (scripts/run.sh <area>, picks up any script under scripts/areas/ automatically):
./scripts/run.sh area-a
```
Override config via env vars, e.g.:
```bash
QF_VERSION=1.2.0 QUARKUS_PLATFORM_VERSION=3.28.4 ./scripts/areas/area-a.sh
```
Exit code is `0` only if every step passed or was a best-effort observation, `1` if anything failed or was blocked (see `worst_status_exit_code` in `lib/result.sh`).

There is no separate test suite — running the script *is* the test; it validates itself end-to-end against a real generated Quarkus project. Before committing shell changes, sanity-check with:
```bash
bash -n scripts/areas/area-a.sh lib/*.sh    # syntax check
shellcheck scripts/areas/area-a.sh lib/*.sh # if installed
```
For the Playwright Dev UI flow:
```bash
node --check scripts/playwright/area-a-dev-ui-flow.mjs
npm install && npx playwright install chromium   # one-time local setup
```

Render an HTML report from an existing evidence run (used by CI, also runnable by hand):
```bash
./scripts/render-report-html.sh evidence/area-a/<RUN_ID> /path/to/out.html
```

## Architecture

**Orchestration pattern**: each area is a standalone, non-`set -e` script under `scripts/areas/*.sh` (e.g. `area-a.sh`). It sources shared helpers from `lib/`, defines one `step_*` function per guide step, and a `main()` that calls them in order — the first six steps (through `compile` and `start_devmode`) are fatal (`|| exit 1`); everything after that is independent and runs regardless of siblings' outcomes (`|| true`), because those checks don't depend on each other. A `trap cleanup EXIT INT TERM` always stops the background `quarkus:dev` process and renders the summary, even on failure or Ctrl-C.

**`lib/` helpers** (sourced, never executed directly — bash 3.2-compatible for macOS's stock `/bin/bash`):
- `common.sh` — logging, `require_cmd`, `render_template` (simple `@@KEY@@` substitution), `retry`, `is_ci`.
- `http.sh` — curl wrappers recording `HTTP_STATUS`/`CURL_EXIT`, JSON assertions via `jq` with substring-grep fallback when `jq` is absent, TCP port checks using bash's `/dev/tcp` (no `lsof`/`nc` dependency), and `http_poll_until_json_equals` for live-reload polling.
- `process.sh` — background process lifecycle for `mvnw quarkus:dev`: starts it as its own process-group leader (`set -m` in the caller), stops via `SIGTERM` to the group then `SIGKILL` after a grace period, plus a PID-tree sweep as defense-in-depth against orphaned JVM children.
- `evidence.sh` — `init_evidence_dir` (refuses to reuse a non-empty dir), `capture_cmd` (wraps a command's output with a header into a file), `capture_dev_ui_flow` (best-effort call into `scripts/playwright/area-a-dev-ui-flow.mjs` — degrades silently to skipped, never fails the caller, if `node` isn't installed).
- `result.sh` — result tracking. Results are appended to a TSV file (`results.tsv`), not an in-memory associative array, specifically for bash 3.2 compatibility and so the file doubles as an evidence artifact. Statuses follow the guide's own legend: `PASS`/`OBSERVATION`/`FAIL`/`BLOCKED`/`FOLLOWUP` (🟢/🟡/🔴/⛔/🔁). `render_summary` builds `SUMMARY.md` from the TSV at the end of every run.

**Run/evidence layout**: every invocation gets a fresh `RUN_ID` (UTC timestamp, `run_id()` in `common.sh`) — nothing is ever overwritten.
- `work/area-a/<RUN_ID>/` — the generated Quarkus project (gitignored).
- `evidence/area-a/<RUN_ID>/` — logs, response bodies, `01-dev-ui-extensions.png` + `02-dev-ui-workflows.png`, `results.tsv`, and `SUMMARY.md` (gitignored locally; uploaded as a CI artifact; the latest run on `main` is also rendered to HTML and published to GitHub Pages).

**Templates**: `templates/area-<x>/*.java` are fixture source files copied into the generated project via `render_template` (`@@KEY@@` token substitution, e.g. `@@PACKAGE@@`). `HelloFlow.live-reload.java` is a second version of the workflow file swapped in mid-run to exercise live reload, diffed against the original for the evidence trail.

**Dev UI Playwright flow** (`scripts/playwright/area-a-dev-ui-flow.mjs`): not a single screenshot — it clicks from the Extensions landing page into the Flow extension's "Workflows" link (`<a class="extensionLink">`, confirmed against a live Dev UI instance, not guessed) and waits for the list's `<table>` to render an actual data row (excluding the always-present, initially-hidden `#emptystaterow` placeholder) before screenshotting either page. This is the actual visual gap called out in Known limitations — proving the link works and the list renders, not just that the URL responds.

**CI** (`.github/workflows/area-a.yml`): two jobs.
1. `area-a` — runs on `push`/`pull_request`/`workflow_dispatch`. Installs Java 21 + Node 22 + Playwright Chromium, runs the script, uploads the full evidence dir as a build artifact, and separately uploads just the latest `RUN_ID`'s dir (for the next job). `CI=true`/`GITHUB_ACTIONS` auto-widen timeouts/retries via `is_ci()` in the area script.
2. `publish-report` — only on `push` to `main`. Downloads the latest run's evidence, renders it with `scripts/render-report-html.sh` (styled with IBM's Carbon Design System, `carbon-components` CSS loaded from a CDN — safe here since this is a real published page, not a sandboxed artifact), and deploys to GitHub Pages (https://mcruzdev.github.io/quarkus-flow-exploratory/) via `actions/deploy-pages`. Publishes even a failed run — a red result is still useful signal.

Config precedence in CI (see comments in the workflow file): manual `workflow_dispatch` input > repository/org Actions Variable > the script's own default in `config/defaults.env`. Only `QF_VERSION`, `QUARKUS_PLATFORM_VERSION`, `TEST_GROUP_ID`, `TEST_ARTIFACT_ID`, `APP_PORT` are exposed as manual inputs; the rest (timeouts, retries) are Variables-only to keep the trigger form short.

## Adding a new area

1. Copy `scripts/areas/area-a.sh` as a starting skeleton.
2. Add any Java/YAML fixtures the new area needs under `templates/area-<x>/`.
3. Reuse the helpers in `lib/` before adding new ones.
4. `scripts/run.sh` picks up any script placed in `scripts/areas/` automatically — no registration needed.

## Known limitations

- The Dev UI flow confirms the Workflows list renders a row after clicking through from Extensions (best-effort — degrades to a plain `200` reachability check, not a failure, if Node/Playwright aren't available). It does not open the individual workflow to confirm its diagram renders; that judgment is still manual.
- Only Area A is automated; the other 18 areas in the guide are still manual.
