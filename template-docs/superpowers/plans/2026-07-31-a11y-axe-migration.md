# Replace pa11y-ci with Playwright + axe-core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `pa11y-ci` (5 unfixable high-severity npm audit findings, WCAG 2.1 AA only) from the CI accessibility gate and replace it with `@axe-core/playwright`, enforcing WCAG 2.2 AA to match `AGENTS.md`.

**Architecture:** A new standalone Node ESM script (`scripts/a11y-scan.mjs`) launches one Chromium instance via Playwright, reads a list of paths from a new `a11y-urls.json` (replacing `.pa11yci`), runs `AxeBuilder` against each with the WCAG 2.2 AA tag set, and exits non-zero if any URL has any violation. The CI `a11y` job in `.github/workflows/ci.yml` swaps its `npx pa11y-ci` step for a Playwright-browser-install step plus `node scripts/a11y-scan.mjs`; every other step in that job (sqlite install, node creation, server startup) is untouched.

**Tech Stack:** Node.js (ESM, no build step), `@axe-core/playwright`, `@playwright/test`, GitHub Actions YAML. No new PHP dependencies.

## Global Constraints

- Fail the build on **any** axe violation, at any impact level, on any scanned URL. No severity-based filtering. This preserves `pa11y-ci`'s current all-or-nothing gate; do not quietly weaken it.
- axe tag set is exactly `['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa']`, matching `.claude/commands/a11y-check.md`'s existing scan scope (WCAG 2.2 AA).
- `--base-url` flag, defaulting to `http://127.0.0.1:8888` (the address the `a11y` job's `drush rs`/`php -S` fallback already serves on).
- The browser must always close, even on a mid-scan failure (`try`/`finally` around the scan loop, not around the whole `main()`).
- `browser.newContext()` + `context.newPage()`, not `browser.newPage()`. Verified directly: `browser.newPage()` throws `Error: Please use browser.newContext()` from `AxeBuilder.analyze()` (see https://github.com/dequelabs/axe-core-npm/blob/develop/packages/playwright/error-handling.md). This is not optional.
- No em dashes anywhere in code, comments, docs, or script output.
- Scripts stay executable (100755), consistent with every other file under `scripts/`.
- Run `./scripts/test-template.sh` before calling any task done. It is network-free and DDEV-free by design; it validates `ci.yml` stays valid YAML and that template-token substitution is unaffected. It cannot exercise the scan script itself (that needs a live browser and a live server).
- Only `{{UPPER_SNAKE}}` names are template tokens; GitHub Actions `${{ }}` expressions in `ci.yml` must never be touched.
- `dev-drupal-11` migration is explicitly out of scope (disposable test install, will be re-scaffolded from the template).

---

### Task 1: Swap npm dependencies in package.json

**Files:**
- Modify: `package.json`

**Interfaces:**
- Produces: `@axe-core/playwright` and `@playwright/test` available as devDependencies for Task 2's script to import.

- [ ] **Step 1: Edit `devDependencies`**

Current `package.json`:

```json
{
  "name": "{{PACKAGE_NAME}}",
  "private": true,
  "description": "{{PACKAGE_DESCRIPTION}}",
  "scripts": {
    "format": "prettier --write \"{{MODULE_PATH}}/**/*.{css,js,json,yml,yaml,md}\"",
    "format:check": "prettier --check \"{{MODULE_PATH}}/**/*.{css,js,json,yml,yaml,md}\"",
    "spell": "cspell \"{{MODULE_PATH}}/**\""
  },
  "devDependencies": {
    "cspell": "^9.8.0",
    "pa11y-ci": "^4.1.1",
    "prettier": "^3.3.0"
  }
}
```

Replace the `devDependencies` block so the file reads:

```json
{
  "name": "{{PACKAGE_NAME}}",
  "private": true,
  "description": "{{PACKAGE_DESCRIPTION}}",
  "scripts": {
    "format": "prettier --write \"{{MODULE_PATH}}/**/*.{css,js,json,yml,yaml,md}\"",
    "format:check": "prettier --check \"{{MODULE_PATH}}/**/*.{css,js,json,yml,yaml,md}\"",
    "spell": "cspell \"{{MODULE_PATH}}/**\""
  },
  "devDependencies": {
    "@axe-core/playwright": "^4.12.1",
    "@playwright/test": "^1.62.1",
    "cspell": "^9.8.0",
    "prettier": "^3.3.0"
  }
}
```

- [ ] **Step 2: Verify JSON is well-formed**

Run: `node -e "JSON.parse(require('fs').readFileSync('package.json', 'utf8')); console.log('valid')"`
Expected: `valid`

- [ ] **Step 3: Commit**

```bash
git add package.json
git commit -m "package.json: swap pa11y-ci for axe-core/playwright deps"
```

---

### Task 2: Write the accessibility scan script and its URL config

**Files:**
- Create: `scripts/a11y-scan.mjs`
- Create: `a11y-urls.json`
- Delete: `.pa11yci`

**Interfaces:**
- Consumes: `@axe-core/playwright` (default export `AxeBuilder`), `@playwright/test` (named export `chromium`) from Task 1.
- Produces: an executable script invoked as `node scripts/a11y-scan.mjs [--base-url=URL]`, exit code 0 (no violations) or 1 (violations found, or a config/load error). Task 3's CI step depends on this exact invocation and exit-code contract.

- [ ] **Step 1: Create `a11y-urls.json`**

Same 3 paths `.pa11yci` already scans (front page, `/search`, one node page):

```json
[
  "/",
  "/search",
  "/node/1"
]
```

- [ ] **Step 2: Delete `.pa11yci`**

```bash
git rm .pa11yci
```

- [ ] **Step 3: Create `scripts/a11y-scan.mjs`**

```javascript
#!/usr/bin/env node
import { chromium } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const WCAG_TAGS = ['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'];

function parseArgs(argv) {
  let baseUrl = 'http://127.0.0.1:8888';
  for (const arg of argv) {
    if (arg.startsWith('--base-url=')) {
      baseUrl = arg.slice('--base-url='.length);
    }
  }
  return { baseUrl };
}

function loadUrls() {
  const configPath = path.join(__dirname, '..', 'a11y-urls.json');
  const raw = readFileSync(configPath, 'utf8');
  const paths = JSON.parse(raw);
  if (!Array.isArray(paths) || paths.length === 0) {
    throw new Error(`${configPath} must contain a non-empty JSON array of paths`);
  }
  return paths;
}

function reportViolations(url, violations) {
  for (const violation of violations) {
    const sample = violation.nodes[0]?.target?.join(' ') ?? '(no selector)';
    console.log(
      `[VIOLATION] ${url} - ${violation.id} (${violation.impact}) ` +
      `tags=${violation.tags.join(',')} count=${violation.nodes.length} sample="${sample}"`
    );
  }
}

async function main() {
  const { baseUrl } = parseArgs(process.argv.slice(2));
  const paths = loadUrls();

  const browser = await chromium.launch();
  let totalViolations = 0;

  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    for (const urlPath of paths) {
      const url = new URL(urlPath, baseUrl).toString();
      await page.goto(url, { waitUntil: 'load' });
      const results = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze();
      reportViolations(url, results.violations);
      totalViolations += results.violations.length;
    }
  } finally {
    await browser.close();
  }

  if (totalViolations > 0) {
    console.error(`\n${totalViolations} accessibility violation(s) found across ${paths.length} page(s).`);
    process.exitCode = 1;
  } else {
    console.log(`\nNo accessibility violations found across ${paths.length} page(s) (${WCAG_TAGS.join(', ')}).`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```

- [ ] **Step 4: Make it executable**

```bash
chmod 755 scripts/a11y-scan.mjs
```

- [ ] **Step 5: Verify syntax**

Run: `node --check scripts/a11y-scan.mjs`
Expected: no output, exit code 0.

- [ ] **Step 6: Manual end-to-end dry run (not part of the committed test suite; this is a one-time local check that the script actually works before it goes into CI)**

This needs real npm packages and a real Chromium download, so it cannot run inside `scripts/test-template.sh`'s no-network suite. Run it once by hand:

```bash
npm install
npx playwright install chromium
```

Create a throwaway HTML fixture with a known violation and one without, and a tiny static server, outside the repo (e.g. under a scratch directory):

```bash
mkdir -p /tmp/a11y-dry-run/testsite
cat > /tmp/a11y-dry-run/testsite/bad.html <<'EOF'
<!doctype html><html lang="en"><head><title>Bad</title></head>
<body><img src="x.png"><p>no alt text on that image</p></body></html>
EOF
cat > /tmp/a11y-dry-run/serve.mjs <<'EOF'
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
createServer((req, res) => {
  res.writeHead(200, { 'content-type': 'text/html' });
  res.end(readFileSync(new URL('./testsite/bad.html', import.meta.url)));
}).listen(9999, () => console.log('up'));
EOF
node /tmp/a11y-dry-run/serve.mjs &
SERVER_PID=$!
sleep 1
cp a11y-urls.json /tmp/a11y-dry-run/a11y-urls.json.orig
echo '["/anything"]' > a11y-urls.json
node scripts/a11y-scan.mjs --base-url=http://127.0.0.1:9999
echo "exit code: $?"
cp /tmp/a11y-dry-run/a11y-urls.json.orig a11y-urls.json
kill $SERVER_PID
cat a11y-urls.json
```

The final `cat` must show the original 3-path array from Step 1, confirming the swap was fully reverted before committing.

Expected: a line starting `[VIOLATION] http://127.0.0.1:9999/anything - image-alt (critical) ...`, then `1 accessibility violation(s) found across 1 page(s).`, exit code `1`. This exact scenario (missing-`alt` image, `browser.newContext()` + `context.newPage()` pattern, `--base-url` override) was verified during design research; re-run it here to confirm the committed file matches.

Also confirm the config-missing-file failure path is loud, not silent:

```bash
mv a11y-urls.json a11y-urls.json.tmp
node scripts/a11y-scan.mjs
echo "exit code: $?"
mv a11y-urls.json.tmp a11y-urls.json
```

Expected: an `ENOENT` error printed to stderr, exit code `1` (never a silent pass).

- [ ] **Step 7: Commit**

```bash
git add scripts/a11y-scan.mjs a11y-urls.json .pa11yci
git commit -m "Add scripts/a11y-scan.mjs (axe-core via Playwright), replace .pa11yci"
```

---

### Task 3: Wire the new scan into the CI a11y job

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `node scripts/a11y-scan.mjs` (Task 2's script, no flags needed since the job's own server already runs on the script's default `http://127.0.0.1:8888`).

- [ ] **Step 1: Replace the `pa11y-ci` step**

In the `a11y` job, find:

```yaml
      - run: npm install --no-audit --no-fund

      - name: pa11y-ci (WCAG2AA)
        run: npx pa11y-ci

      - name: Show server logs
        if: failure()
        run: cat /tmp/drush-rs.log /tmp/php-s.log 2>/dev/null || true
```

Replace with:

```yaml
      - run: npm install --no-audit --no-fund

      - name: Install Playwright browsers
        run: npx playwright install --with-deps chromium

      - name: Accessibility scan (axe-core via Playwright)
        run: node scripts/a11y-scan.mjs

      - name: Show server logs
        if: failure()
        run: cat /tmp/drush-rs.log /tmp/php-s.log 2>/dev/null || true
```

Do not touch any other step in this job (PHP setup, composer install, sqlite site install, node creation, server startup, `setup-node`).

- [ ] **Step 2: Verify YAML validity and token safety**

Run: `./scripts/test-template.sh 2>&1 | tail -15`
Expected: `ci.yml is valid YAML` passes for every flavour/version combo, `${{ count in ci.yml unchanged` passes (confirms no GitHub Actions expression was accidentally touched). Some unrelated pre-existing failures about a stray `dev-drupal-11/` directory under the repo root are expected and not caused by this change (confirmed in an earlier session by stashing changes and re-running: identical failure count with or without the change in the tree).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci.yml: run axe-core via Playwright instead of pa11y-ci"
```

---

### Task 4: Update documentation and verify

**Files:**
- Modify: `README.md`
- Modify: `PROJECT.md`
- Modify: `PROMPTS.md`

**Interfaces:**
- None (documentation only; no other task depends on this one).

- [ ] **Step 1: Update `README.md`**

Find (line 12):

```
- A GitHub Actions CI workflow (`.github/workflows/ci.yml`) running PHPCS, PHPStan, Twig CS Fixer, PHPUnit (unit + kernel), the Prettier check, and a pa11y-ci accessibility job (WCAG2AA, against an installed sqlite site) on push and pull request.
```

Replace with:

```
- A GitHub Actions CI workflow (`.github/workflows/ci.yml`) running PHPCS, PHPStan, Twig CS Fixer, PHPUnit (unit + kernel), the Prettier check, and an axe-core (via Playwright) accessibility job (WCAG 2.2 AA, against an installed sqlite site) on push and pull request.
```

- [ ] **Step 2: Update `PROJECT.md`'s living "What the template contains" section**

Find (lines 57-62):

```
- CI: .github/workflows/ci.yml runs phpcs, phpstan, twig-cs-fixer (guarded to
  skip cleanly when the module has no .twig files), phpunit (unit+kernel,
  sqlite), a prettier check, and an a11y job. The a11y job installs the site
  with drush si and sqlite, serves it with drush rs (falling back to php -S if
  that misbehaves), creates a node via drush, then runs pa11y-ci (WCAG2AA)
  against the URLs in .pa11yci (front page, /search, one node page). A guard
```

Replace with:

```
- CI: .github/workflows/ci.yml runs phpcs, phpstan, twig-cs-fixer (guarded to
  skip cleanly when the module has no .twig files), phpunit (unit+kernel,
  sqlite), a prettier check, and an a11y job. The a11y job installs the site
  with drush si and sqlite, serves it with drush rs (falling back to php -S if
  that misbehaves), creates a node via drush, then runs scripts/a11y-scan.mjs
  (axe-core via Playwright, WCAG 2.2 AA) against the URLs in a11y-urls.json
  (front page, /search, one node page). A guard
```

Leave the dated "Status (2026-07)" log entry at line 135 (`...The a11y (pa11y-ci) CI job needs live verification...`) untouched: it is a historical record of what was true on that date, not a description of current behaviour.

- [ ] **Step 3: Add a new status entry to `PROMPTS.md`**

Find the last bullet of the `## Status (2026-07-29)` block (currently ending with the "Vanilla + Drupal 10 live run" entry, immediately before the `---` separator). Append a new bullet after it:

```
- Stage 9, replace pa11y-ci with axe-core + Playwright: DONE. pa11y-ci's
  dependency chain (globby/glob/minimatch/brace-expansion) had 5 unfixable
  high-severity npm audit findings and only covered WCAG 2.1 AA; the a11y CI
  job now runs scripts/a11y-scan.mjs (@axe-core/playwright), enforcing WCAG
  2.2 AA to match AGENTS.md. .pa11yci replaced by a11y-urls.json (same 3
  paths). Needs live verification: only checked for YAML syntax and a local
  dry run, not run against GitHub Actions infrastructure.
```

- [ ] **Step 4: Confirm no stray "pa11y" references remain outside the two intentional historical mentions**

Run: `grep -rn "pa11y" --include="*.md" --include="*.json" --include="*.yml" . 2>/dev/null | grep -v node_modules | grep -v "^./dev-drupal-11"`
Expected output: exactly two lines, both historical log entries left alone on purpose:
- `PROJECT.md:135:...The a11y (pa11y-ci) CI job`
- `PROMPTS.md:22:- Stage 3, pa11y-ci accessibility CI job: COMMITTED...`

If any other line appears, go back and update it.

- [ ] **Step 5: Full regression suite**

Run: `./scripts/test-template.sh 2>&1 | tail -15`
Expected: same pass/fail counts as Task 3 Step 2 (the pre-existing `dev-drupal-11/` stray-directory failures only; nothing new).

- [ ] **Step 6: Commit**

```bash
git add README.md PROJECT.md PROMPTS.md
git commit -m "Update docs: pa11y-ci to axe-core via Playwright, WCAG 2.2 AA"
```
