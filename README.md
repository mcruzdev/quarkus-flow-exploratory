# Quarkus Flow Exploratory Automation

Bash automation for the [Quarkus Flow Exploratory Testing Guide](https://docs.quarkiverse.io/quarkus-flow/dev/). The guide has 19 areas (A–S); **this repo currently automates only Area A — Local Developer Workflow**, the local quickstart scenario. More areas may be added later following the same pattern (see [Adding a new area](#adding-a-new-area)).

Runs locally and in CI (GitHub Actions) — see [`.github/workflows/area-a.yml`](.github/workflows/area-a.yml).

## What Area A validates

1. Generate a Quarkus project via the Maven plugin (no Quarkus CLI dependency).
2. Add the `quarkus-flow` and `rest-jackson` extensions.
3. Write a minimal Java DSL "hello" workflow and a REST resource exposing it.
4. Compile the project.
5. Start `quarkus:dev` in the background and wait for it to become ready.
6. `GET /hello-flow` returns `{"message":"hello world!"}`.
7. `GET /hello-flow/debug` returns the raw workflow output map.
8. `POST /hello-flow` is rejected with `405 Method Not Allowed`.
9. Dev UI is reachable at `/q/dev-ui` (reachability only — see [Known limitations](#known-limitations)).
10. Live reload: edit the workflow's message while `quarkus:dev` is running and confirm the new message is served.

Every run always stops the background `quarkus:dev` process and writes a pass/fail/blocked summary, whether it succeeds, fails, or is interrupted.

## Prerequisites

- bash
- Java 17+
- Maven
- curl
- git
- `jq` recommended (assertions fall back to substring matching if absent)
- Network access to Maven Central (first run resolves the Quarkus platform + extensions)

## Quick start

```bash
./scripts/areas/area-a.sh
# or, via the dispatcher:
./scripts/run.sh area-a
```

Exit code is `0` only if every step passed or was a best-effort observation; `1` if anything failed or was blocked.

## Configuration

All variables are set with sane defaults in [`config/defaults.env`](config/defaults.env) and can be overridden via environment variables at invocation time:

```bash
QF_VERSION=1.2.0 QUARKUS_PLATFORM_VERSION=3.28.4 ./scripts/areas/area-a.sh
```

| Variable | Default | Notes |
|---|---|---|
| `QF_VERSION` | `1.1.0` | Quarkus Flow version to test. **Bump this first** if a run fails due to version drift — the guide is pinned to a released version that will lag behind `quarkus-flow`'s main branch. |
| `QUARKUS_PLATFORM_VERSION` | `3.37.4` | Quarkus platform version used to generate the project. **Bump this second** alongside `QF_VERSION`. |
| `TEST_GROUP_ID` | `org.acme` | Generated project's Java package / Maven group ID. |
| `TEST_ARTIFACT_ID` | `hello-flow` | Generated project's Maven artifact ID and directory name. |
| `APP_PORT` | `8080` | Port `quarkus:dev` listens on. |
| `READY_TIMEOUT_SECONDS` | `120` (doubled under CI) | How long to wait for `quarkus:dev` to become ready. |
| `LIVE_RELOAD_TIMEOUT_SECONDS` | `30` | How long to poll for the live-reload change to take effect. |
| `LIVE_RELOAD_POLL_INTERVAL_SECONDS` | `2` | Poll interval for the live-reload check. |
| `HTTP_TIMEOUT_SECONDS` | `10` | Per-request curl timeout. |
| `GRACEFUL_STOP_SECONDS` | `10` | How long to wait after `SIGTERM` before escalating to `SIGKILL`. |
| `RETRY_MAX_ATTEMPTS` | `3` (+2 under CI) | Retries for network-dependent Maven commands (project creation, extension add). |
| `RETRY_DELAY_SECONDS` | `5` | Delay between retries. |

`CI=true` or `GITHUB_ACTIONS` being set automatically widens timeouts and retry counts — GitHub Actions sets both by default, so no extra configuration is needed there.

## What it produces

- `work/area-a/<RUN_ID>/hello-flow/` — the generated Quarkus project (gitignored).
- `evidence/area-a/<RUN_ID>/` — logs, response bodies, and `SUMMARY.md` (gitignored locally; uploaded as a build artifact in CI).

Each run gets a fresh timestamped `RUN_ID`; nothing is ever overwritten, so runs can be repeated freely.

## Result Legend

| Result | Meaning |
|---|---|
| 🟢 Passed | Expected behavior was confirmed. |
| 🟡 Passed with observations | Main path worked, but notes, risks, or UX gaps were found. |
| 🔴 Failed | Expected behavior did not work and needs follow-up. |
| ⛔ Blocked | The scenario could not be completed due to environment, dependency, or access issues. |
| 🔁 Needs follow-up | More focused testing or automation is required. |

## Known limitations

- **Dev UI check is reachability-only.** It confirms `/q/dev-ui` returns `200`, always recorded as 🟡. Dev UI is a single-page app, so confirming the workflow is actually listed and its diagram renders correctly still requires a human opening a browser.
- Only Area A is automated. The other 18 areas in the guide (messaging, persistence, resilience, OpenShift, agentic/HITL, etc.) are still manual.

## Adding a new area

1. Copy `scripts/areas/area-a.sh` as a starting skeleton.
2. Add any Java/YAML fixtures the new area needs under `templates/area-<x>/`.
3. Reuse the helpers in `lib/` (`common.sh`, `http.sh`, `process.sh`, `evidence.sh`, `result.sh`) before adding new ones.
4. `scripts/run.sh` picks up any script placed in `scripts/areas/` automatically — no registration needed.

## Troubleshooting

| Symptom | Meaning | What the script does |
|---|---|---|
| `curl: (7) Failed to connect` (curl exit code, not HTTP status) | `quarkus:dev` isn't listening yet | Reported distinctly from HTTP status codes so it's clear the app never came up, not that an endpoint returned an error. |
| `{"message":null}` from `GET /hello-flow` | Typed response mapping issue | Automatically fetches `/hello-flow/debug` and attaches both bodies to the failure note for diagnosis. |
| Port already in use before start | Another process is on `APP_PORT` | Detected before launching `quarkus:dev`; reported as `⛔ Blocked` with the offending PID when `lsof` is available, rather than hanging. |
| `add-extension`/project creation fails after retries | Maven/network flakiness, or version incompatibility | Reported as `⛔ Blocked` (retries exhausted) vs. `🔴 Failed` (e.g. `pom.xml` malformed) — check `create-project.log` / `add-extension.log`, and consider bumping `QF_VERSION` / `QUARKUS_PLATFORM_VERSION`. |
| Live reload never observes the new message | Recompile taking longer than `LIVE_RELOAD_TIMEOUT_SECONDS`, or the edit broke compilation | Check `live-reload-devmode-log-tail.txt` and `hello-flow-response-after-reload.json`. |
