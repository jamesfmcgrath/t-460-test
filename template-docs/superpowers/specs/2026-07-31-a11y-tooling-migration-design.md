# Replace pa11y-ci with Playwright + axe-core (Design)

**Goal:** Remove `pa11y-ci` from the CI accessibility gate and replace it with `@axe-core/playwright` (Deque's official Playwright integration), eliminating an unfixable upstream dependency chain and aligning the automated gate with the WCAG 2.2 AA standard already declared in `AGENTS.md`.

## Background

`pa11y-ci@4.1.1` (its latest release) depends on `globby@6.1.0` → `glob@7.2.3` → `minimatch@3.1.5` → `brace-expansion@1.1.18`, which trips 5 high-severity `npm audit` findings rooted in [GHSA-mh99-v99m-4gvg](https://github.com/advisories/GHSA-mh99-v99m-4gvg) (patched only at `brace-expansion@5.0.8+`). Testing an `npm overrides` workaround confirmed it is not viable: `brace-expansion@5.x` is a rewritten package whose export shape breaks `minimatch@3.1.5` at runtime (`TypeError: expand is not a function`). `npm audit fix --force`'s own suggested fix is a three-major-version downgrade of `pa11y-ci` to `1.2.0`, which is a regression, not a fix. There is no safe upstream remediation.

Separately, `pa11y-ci`'s `WCAG2AA` standard only covers WCAG 2.0/2.1 AA rules; it has no 2.2 mode. `AGENTS.md` already states this project must build and review to WCAG 2.2 AA. The interactive `/a11y-check` command already scans with axe-core tags `wcag2a, wcag2aa, wcag21aa, wcag22aa` (via CDN injection in the browser, or `npx @axe-core/cli` as a fallback) — so `pa11y-ci`'s CI gate and `/a11y-check`'s interactive scan currently enforce two different, inconsistent standards.

`pa11y-ci` has exactly one integration point: the `a11y` job in `.github/workflows/ci.yml`, driven by the `.pa11yci` URL/config file. It is not referenced from `scripts/setup.sh`, the `Makefile`, or `/a11y-check`; those only need doc-string updates.

## Tool choice

Compared two axe-core-based replacements by installing each in isolation and running `npm audit`:

| | `@axe-core/cli` | `@axe-core/playwright` |
|---|---|---|
| Dependencies | `chromedriver`, `selenium-webdriver`, `@axe-core/webdriverjs`, etc. | `axe-core` only (peer: `playwright`) |
| Install footprint | large, legacy Selenium/chromedriver stack | 9 packages total |
| `npm audit` | not tested (stack known for chromedriver flakiness/supply-chain history) | 0 vulnerabilities, 0 deprecation warnings |
| Maintenance | Selenium-based | Actively maintained by Microsoft (Playwright) and Deque (axe-core) |

**Decision: `@axe-core/playwright` + `@playwright/test`.**

## Architecture

```
ci.yml (a11y job)
  ... existing steps: checkout, PHP setup, composer install,
      install sqlite site, create test node, serve on 127.0.0.1:8888
      (all unchanged)
  -> setup-node@v5                              (unchanged)
  -> npm install                                 (unchanged step, new deps)
  -> npx playwright install --with-deps chromium (NEW)
  -> node scripts/a11y-scan.mjs                  (NEW, replaces `npx pa11y-ci`)
```

`scripts/a11y-scan.mjs` is a standalone Node ESM script (not templated with `{{TOKENS}}` — it is site-wide, not module-scoped, matching the existing `a11y` job's lack of a module-glob guard):

1. Read the URL list from `a11y-urls.json` (repo root, replaces `.pa11yci`).
2. Accept an optional `--base-url` flag, defaulting to `http://127.0.0.1:8888` (the address the CI job's `drush rs`/`php -S` fallback already serves on). This makes the script reusable against `{{DDEV_URL}}` later without code changes, at no extra cost now.
3. Launch one Chromium instance via `playwright.chromium.launch()`, reusing it across URLs (not one browser per URL) for speed.
4. For each URL: `page.goto(base + path)`, then `new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa']).analyze()`.
5. Collect violations across all URLs. Print each grouped by rule id: `id`, `impact`, `wcag` tags, node `count`, and a sample `target` selector — the same shape `/a11y-check`'s axe-core snippet already logs, so CI output and interactive-scan output read the same way.
6. Exit `1` if any URL produced any violation (parity with `pa11y-ci`'s current all-or-nothing gate; no severity-based filtering, so the gate does not get quietly weaker). Exit `0` and print a short "no violations" summary otherwise.
7. Always close the browser (`try/finally`), so a mid-scan failure doesn't leak the Chromium process in CI.

## Data flow / config

- **`a11y-urls.json`** (new, replaces `.pa11yci`): a flat JSON array of paths, e.g. `["/", "/search", "/node/1"]`. Same 3 paths as today, same meaning (front page, listing/search page, one node page) — the standard/timeout/chromeLaunchConfig fields `.pa11yci` needed for pa11y's own runner are no longer meaningful once Playwright drives the browser directly, so they're dropped rather than carried over as dead config.
- **`package.json`**: remove `pa11y-ci` from `devDependencies`; add `@axe-core/playwright` and `@playwright/test`.
- **`.github/workflows/ci.yml`**: in the `a11y` job, replace the `pa11y-ci (WCAG2AA)` step with a `Install Playwright browsers` step (`npx playwright install --with-deps chromium`) and an `Accessibility scan (axe-core via Playwright)` step (`node scripts/a11y-scan.mjs`). No other step in this job changes — the sqlite install, node creation, and server steps are untouched.
- **Docs**: `README.md`, `PROJECT.md`, `PROMPTS.md` — update prose from "pa11y-ci (WCAG2AA)" to "axe-core via Playwright (WCAG 2.2 AA)" wherever the CI pipeline is described.

## Error handling

- If `a11y-urls.json` is missing or unparsable, the script exits non-zero with a clear message rather than silently scanning zero URLs (a silent no-op would be a worse failure mode than a loud one, since it would make the gate always pass).
- If a page fails to load, that is treated as a scan failure for that URL (reported and counted toward the non-zero exit), not silently skipped — matching the existing job's `Show server logs` failure step, which already assumes the a11y step can fail meaningfully. Two distinct cases are covered: `page.goto` throwing (network-level failures such as SSL errors, invalid URLs, timeouts, or an unreachable server), and an HTTP-level failure where `page.goto` resolves normally but the response status is missing or >= 400 (e.g. a 404) — Playwright does not throw on non-2xx/3xx responses, so the script checks the response status explicitly.
- Playwright's own browser-install step failing (network, missing system deps) fails the job outright via normal CI step failure; no special handling needed beyond what `--with-deps` already provides on `ubuntu-latest`.

## Testing

- `./scripts/test-template.sh` must still pass (it validates `ci.yml` stays valid YAML and that token substitution is unaffected; it does not execute the `a11y` job itself, so it won't catch scan-logic bugs, only structural breakage).
- No new automated test for `a11y-scan.mjs` itself: the existing regression suite is explicitly "no network, no DDEV" (per its own header comment), and this script's entire purpose requires a live server and a real browser. Its correctness is proven by the CI job actually running it — same "needs live verification" caveat already documented in `PROMPTS.md` for the original pa11y-ci job. Note the outcome the first time this job runs for real (pass/fail, and whether WCAG 2.2 AA surfaces any new violations beyond the old 2.1 AA scope).

## Out of scope

- `dev-drupal-11`: a disposable test install of this template. Not migrated; it will be deleted and re-scaffolded from the template once this change lands, rather than patched in place.
- Changing `/a11y-check`'s own workflow (it already uses axe-core; not touched).
- Running the a11y scan locally via DDEV/Makefile (no such integration exists today; not being added).
- Any other CI job (`php`, `frontend_check`, `prettier`, `guard`) — untouched.
