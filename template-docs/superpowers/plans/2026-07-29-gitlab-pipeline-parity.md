# Stage 8: drupal.org (GitLab CI) Pipeline Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a ready `.gitlab-ci.yml` for modules pushed to git.drupalcode.org, and give the template's own `make check` local parity with that pipeline's default jobs (cspell, ESLint, Stylelint alongside the existing PHPCS/PHPStan/Twig CS Fixer), so a module that passes locally also passes there.

**Architecture:** A static pipeline asset (`assets/module.gitlab-ci.yml`) ships the canonical `gitlab_templates` include block plus a documented variables block; a Makefile target copies it into the module. Three new Makefile targets (`spell`, `lint-js`, `lint-css`) reuse Drupal core's own installed tooling (`web/core/node_modules`) the same way the drupalcode CI jobs do, so there is exactly one source of truth for lint rules. GitHub Actions gets matching guarded steps so the GitHub side of a project repo enforces the same standards.

**Tech Stack:** GNU Make, Bash, GitLab CI YAML (consumed by git.drupalcode.org, not run by us), GitHub Actions YAML, cspell (Node/npm), Drupal core's own ESLint/Stylelint config and installed binaries.

## Global Constraints

- No em dashes anywhere in any file this plan touches.
- Scripts stay executable (mode 100755); this plan adds no new scripts, but `scripts/test-template.sh` gets edited in place and must keep its mode.
- GitHub Actions `${{ }}` expressions and the GitLab `$VAR` / `${_VAR}` references inside `assets/module.gitlab-ci.yml` must both survive `scripts/init.sh` untouched.
- `assets/module.gitlab-ci.yml` carries no `{{UPPER_SNAKE}}` template tokens (verified design decision, see Task 1) and is never added to `init.sh`'s `FILES` array; it must survive `init.sh` byte-for-byte identical. The regression suite must assert this explicitly (this is what "extend the token regex checks to cover the new file" resolves to here, since the existing recursive `{{[A-Z_]+}}` scan already covers any new file with no code change needed).
- Keep both flavours (`localgov`, `vanilla`), both Drupal versions (`10`, `11`), and both usage modes (module, site-only) working. Nothing in this plan changes flavour/version/mode logic, but every new Makefile target must behave sensibly (skip with a message, not crash) in site-only mode, where `MODULE_NAME` is empty and `MODULE` is the bare `web/modules/custom` directory.
- Verified-live facts below come from the live `gitlab_templates` docs and raw source files fetched 2026-07-29 (via direct `curl`, not the lossy WebFetch summarizer), which the Stage 8 prompt itself says to treat as authoritative over the prompt text:
  - The canonical include block (from `https://git.drupalcode.org/project/gitlab_templates/-/raw/main/gitlab-ci/template.gitlab-ci.yml`) uses **three** include files (main, variables, workflows), not four; the fourth (`hidden-variables`) is only needed for cross-instance remote use, not on git.drupalcode.org itself.
  - Confirmed from `includes/include.drupalci.variables.yml`: `SKIP_COMPOSER_LINT`, `SKIP_PHPCS`, `SKIP_PHPSTAN`, `SKIP_STYLELINT`, `SKIP_ESLINT`, `SKIP_CSPELL`, `SKIP_PHPUNIT`, `SKIP_NIGHTWATCH` all default to `'0'` (job runs).
  - **Surprising, verified fact:** `SKIP_TWIG_CS_FIXER` defaults to `'1'` (job is SKIPPED by default upstream as of 2026-07), contradicting both the Stage 8 prompt text and PROMPTS.md's Stage 8 description. Since this template already treats Twig CS Fixer as a first-class local/CI check (`make twig-lint`, wired into `.github/workflows/ci.yml`), `assets/module.gitlab-ci.yml` must actively set `SKIP_TWIG_CS_FIXER: '0'` (uncommented, not just documented) or a module pushed to drupalcode would silently stop linting Twig there while still linting it locally, defeating the parity goal.
  - `_CSPELL_DICTIONARY` defaults to `'.cspell-project-words.txt'`; using that exact filename for our own root cspell word list keeps it drop-in compatible if a module's own separate drupalcode repo later wants the same file.
  - `_ESLINT_EXTRA` defaults to `'--quiet'`, matching Drupal core's own `lint:core-js-passing` script.
  - `_TARGET_PHP` defaults to `'$CORE_PHP_MIN'` (Drupal core's minimum supported PHP for the variant under test); overridable per-variant, not a skip/opt-in flag.
  - Drupal core ships `core/.eslintrc.passing.json` and `core/.stylelintrc.json`; the documented contrib-module recipe (verified against `web/core/package.json`'s own `lint:core-js-passing` / `lint:css` scripts, and cross-checked against a working third-party writeup) is to invoke core's own installed `node_modules/.bin/eslint` / `.../stylelint` binaries with `--resolve-plugins-relative-to=web/core` and `-c web/core/.eslintrc.passing.json` / `--config web/core/.stylelintrc.json`, targeting the module path. This requires `web/core/node_modules` to exist (i.e. `npm ci` or `yarn install` has run inside `web/core`), which is out of scope for `scripts/setup.sh` in this plan; the new Makefile targets print a clear message when `web/core` or its `node_modules` are missing rather than a raw ENOENT.
  - **Verified conflict (empirical, not assumed):** formatting a CSS custom property value with `prettier --write` using this template's `.prettierrc.json` (e.g. `--foo-color: #FF0000;`) produces `#ff0000` (lowercased only), but Drupal core's Stylelint config (`stylelint-config-standard`) enforces `color-hex-length: short` and fails on anything longer than `#f00`. Prettier has no option to shorten hex colors, so this cannot be fixed by adjusting `.prettierrc.json`; the fix is procedural (write short hex from the start, or run `stylelint --fix` after `prettier --write`), documented in Task 4 and the docs task, not a config change. No other conflict was found in a broader sample covering logical properties, `clamp()`, `gap`, quoted `content`, and `!important`; the JS side already avoids this class of problem because Drupal core's own `.eslintrc.passing.json` is paired with `eslint-config-prettier` (disables stylistic rules that would fight Prettier) and `eslint-plugin-prettier` (resolves the nearest `.prettierrc.json` dynamically, which is exactly ours when linting a module directory).
  - Nightwatch (browser JS functional tests) has no local equivalent in this template's tooling and is explicitly out of scope; it stays CI-only on drupalcode, same as this template's own a11y/functional test gaps.

---

## File Structure

| File | Responsibility |
|---|---|
| `assets/module.gitlab-ci.yml` (new) | Static asset: canonical `gitlab_templates` include block plus a documented, mostly-commented `variables:` block. Not tokenised, ships verbatim. |
| `Makefile` | New targets `module-ci`, `spell`, `lint-js`, `lint-css`; `check` and `.PHONY` updated. |
| `cspell.json` (new, repo root) | cspell config: points at the project word list, ignores vendor/build directories. |
| `.cspell-project-words.txt` (new, repo root) | Seeded custom dictionary (localgov, drush, ddev, and other project terms). |
| `package.json` | Add `cspell` devDependency and a `spell` npm script (mirrors the existing `format`/`format:check` pattern). |
| `.github/workflows/ci.yml` | `prettier` job gains a guarded CSpell step; `php` job gains Node setup, `web/core` frontend deps, and guarded ESLint/Stylelint steps. |
| `scripts/test-template.sh` | New assertions: `assets/module.gitlab-ci.yml` survives `init.sh` byte-identical, `make -n module-ci` parses. |
| `README.md`, `PROJECT.md`, `AGENTS.md`, `PROMPTS.md` | Docs and status updates. |

No file needs splitting; nothing here grows large enough to warrant it.

---

## Task 1: Ship the module GitLab CI pipeline asset and `make module-ci`

**Files:**
- Create: `assets/module.gitlab-ci.yml`
- Modify: `Makefile` (add `module-ci` target, update `.PHONY`, add an `== drupal.org pipeline parity ==` section header)

**Interfaces:**
- Produces: `make module-ci` — copies `assets/module.gitlab-ci.yml` to `$(MODULE)/.gitlab-ci.yml`, refuses (exit 1, message) if that file already exists, and reuses the existing `guard-module-name` prerequisite so it fails cleanly in site-only mode.

- [ ] **Step 1: Create `assets/module.gitlab-ci.yml`**

```yaml
# GitLab CI pipeline for this module on git.drupalcode.org.
# Copy into the module with `make module-ci` (see Makefile).
#
# Canonical include block from
# https://git.drupalcode.org/project/gitlab_templates/-/blob/main/gitlab-ci/template.gitlab-ci.yml
# Full variable list and defaults:
# https://git.drupalcode.org/project/gitlab_templates/-/blob/main/includes/include.drupalci.variables.yml
include:
  - project: $_GITLAB_TEMPLATES_REPO
    ref: $_GITLAB_TEMPLATES_REF
    file:
      - '/includes/include.drupalci.main.yml'
      - '/includes/include.drupalci.variables.yml'
      - '/includes/include.drupalci.workflows.yml'

variables:
  # Twig CS Fixer is SKIPPED by default upstream (SKIP_TWIG_CS_FIXER
  # defaults to '1'). This template lints Twig locally (make twig-lint) and
  # in GitHub Actions, so keep it enabled here too.
  SKIP_TWIG_CS_FIXER: '0'

  # --- Validation jobs, all enabled by default upstream. Uncomment to skip. ---
  # SKIP_COMPOSER_LINT: '1'  # Composer Lint (composer validate + normalize check).
  # SKIP_PHPCS: '1'          # PHP Coding Standards (Drupal, DrupalPractice).
  # SKIP_PHPSTAN: '1'        # PHPStan static analysis.
  # SKIP_ESLINT: '1'         # ESLint against .js and .yml files.
  # SKIP_STYLELINT: '1'      # Stylelint against .css files.
  # SKIP_CSPELL: '1'         # CSpell spell-check of code and comments.

  # --- Test jobs, enabled by default upstream (current Drupal core only). ---
  # SKIP_PHPUNIT: '1'        # PHPUnit (unit/kernel/functional per test group).
  # SKIP_NIGHTWATCH: '1'     # Nightwatch JS functional tests.

  # --- Opt-in jobs, disabled by default. Uncomment to run. ---
  # RUN_JOB_UPGRADE_STATUS: '1'   # Experimental: check against next major core via upgrade_status.
  # RUN_JOB_SECRET_DETECTION: '1' # GitLab secret detection scan.

  # --- Variant testing, disabled by default. Uncomment to opt in. ---
  # OPT_IN_TEST_NEXT_MAJOR: '1'      # Test against the next major Drupal core version.
  # OPT_IN_TEST_NEXT_MINOR: '1'      # Test against the next minor Drupal core version.
  # OPT_IN_TEST_PREVIOUS_MINOR: '1'  # Test against the previous minor Drupal core version.
  # OPT_IN_TEST_PREVIOUS_MAJOR: '1'  # Test against the previous major Drupal core version.
  # OPT_IN_TEST_MAX_PHP: '1'         # Test against the maximum supported PHP version.

  # --- PHP version target for the default (current) variant. ---
  # _TARGET_PHP: '8.3'  # Defaults to Drupal core's own minimum supported PHP version.
```

- [ ] **Step 2: Add the `module-ci` Makefile target**

In `Makefile`, add a new section after `## == Maintainer (module git) ==` (or before it, either is fine; keep it visually separate):

```makefile
## == drupal.org pipeline parity ===============================================

module-ci: guard-module-name ## Copy the drupal.org GitLab CI pipeline into the module
	@if [ -f "$(MODULE)/.gitlab-ci.yml" ]; then \
	  echo "$(MODULE)/.gitlab-ci.yml already exists, not overwriting."; \
	  exit 1; \
	fi
	cp assets/module.gitlab-ci.yml "$(MODULE)/.gitlab-ci.yml"
	@echo "Copied assets/module.gitlab-ci.yml to $(MODULE)/.gitlab-ci.yml"
```

- [ ] **Step 3: Update `.PHONY`**

In `Makefile`, the `.PHONY` line currently reads:

```makefile
.PHONY: help start stop restart open logs si install enable cr \
        test lint lint-fix stan check format format-check twig-lint twig-fix \
        mod-log mod-status mod-fetch mod-branch tag switch mr \
        guard-module-name guard-module-git
```

Change it to:

```makefile
.PHONY: help start stop restart open logs si install enable cr \
        test lint lint-fix stan check format format-check twig-lint twig-fix \
        spell lint-js lint-css module-ci \
        mod-log mod-status mod-fetch mod-branch tag switch mr \
        guard-module-name guard-module-git
```

(`spell`, `lint-js`, `lint-css` are added here even though they land in Task 2-4, so this single edit covers all of them and later tasks do not need to touch this line again.)

- [ ] **Step 4: Verify with a dry run**

Run: `make -n module-ci`
Expected: prints the `cp assets/module.gitlab-ci.yml ...` line (or the guard's echo/exit if `MODULE_NAME` happens to be empty in your working copy) without a Make syntax error. In this template repo itself `MODULE_NAME` is still the literal token `{{MODULE_NAME}}` (non-empty), so the guard passes and the `cp` line prints.

- [ ] **Step 5: Commit**

```bash
git add assets/module.gitlab-ci.yml Makefile
git commit -m "Ship drupal.org GitLab CI pipeline asset and make module-ci"
```

---

## Task 2: Local cspell parity (`make spell`)

**Files:**
- Create: `cspell.json`
- Create: `.cspell-project-words.txt`
- Modify: `package.json` (add `cspell` devDependency and `spell`/`spell:check` scripts, matching the existing `format`/`format:check` pattern)
- Modify: `Makefile` (add `spell` target)

**Interfaces:**
- Produces: `make spell` — runs `ddev exec npx cspell` scoped to `$(MODULE)`, skipping with a message when `$(MODULE)` has no files at all.

- [ ] **Step 1: Create `cspell.json`**

```json
{
  "version": "0.2",
  "language": "en",
  "ignorePaths": [
    "vendor/**",
    "node_modules/**",
    "web/core/**",
    "web/modules/contrib/**",
    "web/themes/contrib/**",
    "**/*.min.js",
    "**/*.min.css",
    "composer.lock",
    "package-lock.json"
  ],
  "dictionaryDefinitions": [
    {
      "name": "project-words",
      "path": "./.cspell-project-words.txt",
      "addWords": true
    }
  ],
  "dictionaries": ["project-words"]
}
```

- [ ] **Step 2: Create `.cspell-project-words.txt`**

```
localgov
drush
ddev
composer
phpcs
phpstan
phpunit
prettier
eslint
stylelint
cspell
nightwatch
twig
```

(One word per line, matching the drupalcode CSpell job's own `_CSPELL_DICTIONARY` file format, and using its exact default filename so a module's own separate repo can reuse this file unmodified if it is ever copied over.)

- [ ] **Step 3: Add `cspell` to `package.json`**

Current `package.json`:

```json
{
  "name": "{{PACKAGE_NAME}}",
  "private": true,
  "description": "{{PACKAGE_DESCRIPTION}}",
  "scripts": {
    "format": "prettier --write \"{{MODULE_PATH}}/**/*.{css,js,json,yml,yaml,md}\"",
    "format:check": "prettier --check \"{{MODULE_PATH}}/**/*.{css,js,json,yml,yaml,md}\""
  },
  "devDependencies": {
    "pa11y-ci": "^4.1.1",
    "prettier": "^3.3.0"
  }
}
```

Change to:

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
    "cspell": "^10.0.1",
    "pa11y-ci": "^4.1.1",
    "prettier": "^3.3.0"
  }
}
```

(Version `^10.0.1` is the current published `cspell` major as of 2026-07-29, confirmed via `npm view cspell version`; keep the caret range so patch/minor updates flow in.)

- [ ] **Step 4: Add the `spell` Makefile target**

In `Makefile`, in the `## == Quality ==` section, after `twig-fix`:

```makefile
spell: ## Spell-check the module with cspell
	@if find $(MODULE) -type f -print -quit | grep -q .; then \
	  ddev exec npx cspell --no-progress "$(MODULE)/**"; \
	else \
	  echo "No files found under $(MODULE); skipping cspell."; \
	fi
```

- [ ] **Step 5: Verify JSON/config validity and dry run**

```bash
python3 -c "import json; json.load(open('cspell.json'))"
python3 -c "import json; json.load(open('package.json'))"
make -n spell
```

Expected: both `python3 -c` calls print nothing (valid JSON); `make -n spell` prints the `find`/`ddev exec` line without a Make syntax error.

- [ ] **Step 6: Commit**

```bash
git add cspell.json .cspell-project-words.txt package.json Makefile
git commit -m "Add cspell config and make spell target for local drupal.org parity"
```

---

## Task 3: Local ESLint parity (`make lint-js`)

**Files:**
- Modify: `Makefile` (add `lint-js` target)

**Interfaces:**
- Consumes: Drupal core's own `web/core/.eslintrc.passing.json` and `web/core/node_modules/.bin/eslint`, once a project has been scaffolded and `web/core`'s own npm dependencies installed (this Makefile target does not install them; see the note below).
- Produces: `make lint-js` — lints `.js` and `.yml` files under `$(MODULE)` with core's "passing" ESLint config, skipping with a message when `$(MODULE)` has no `.js` files.

- [ ] **Step 1: Add the `lint-js` Makefile target**

In `Makefile`, in `## == Quality ==`, after the new `spell` target:

```makefile
lint-js: ## Lint module JS/YAML with Drupal core's ESLint config
	@if find $(MODULE) -name '*.js' -print -quit | grep -q .; then \
	  ddev exec node web/core/node_modules/.bin/eslint $(MODULE) \
	    --no-error-on-unmatched-pattern \
	    --ignore-pattern='*.es6.js' \
	    --resolve-plugins-relative-to=web/core \
	    --ext=.js,.yml \
	    -c web/core/.eslintrc.passing.json; \
	else \
	  echo "No .js files found under $(MODULE); skipping eslint."; \
	fi
```

This is the same recipe Drupal core's own `.eslintrc.passing.json` plus `--resolve-plugins-relative-to=web/core` combination uses for contrib modules: it runs core's already-installed `eslint` binary (no separate template-level `eslint` devDependency needed) against the module path, using core's own "passing" ruleset (the same one the drupalcode `eslint` CI job runs, whose `_ESLINT_EXTRA` default is `--quiet`; core's own `lint:core-js-passing` script already bakes in the equivalent of `--quiet` via its ruleset, so no extra flag is added here beyond what core's script itself uses).

- [ ] **Step 2: Verify with a dry run**

Run: `make -n lint-js`
Expected: prints the `find`/`ddev exec node ...` line without a Make syntax error. Note in the task summary that actually *running* this target (not just dry-running it) needs a live DDEV project with `web/core/node_modules` already installed (e.g. via `ddev exec sh -c "cd web/core && npm ci"`), which is out of scope here; mark that "needs live verification" like the rest of this template's DDEV-dependent tooling.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "Add make lint-js using Drupal core's ESLint config"
```

---

## Task 4: Local Stylelint parity (`make lint-css`)

**Files:**
- Modify: `Makefile` (add `lint-css` target)

**Interfaces:**
- Consumes: Drupal core's own `web/core/.stylelintrc.json` and `web/core/node_modules/.bin/stylelint`.
- Produces: `make lint-css` — lints `.css` files under `$(MODULE)` with core's Stylelint config, skipping with a message when `$(MODULE)` has no `.css` files.

- [ ] **Step 1: Add the `lint-css` Makefile target**

In `Makefile`, in `## == Quality ==`, after `lint-js`:

```makefile
lint-css: ## Lint module CSS with Drupal core's Stylelint config
	@if find $(MODULE) -name '*.css' -print -quit | grep -q .; then \
	  ddev exec web/core/node_modules/.bin/stylelint --config web/core/.stylelintrc.json "$(MODULE)/**/*.css"; \
	else \
	  echo "No .css files found under $(MODULE); skipping stylelint."; \
	fi
```

- [ ] **Step 2: Update the `check` aggregate target**

Current:

```makefile
check: lint stan test twig-lint ## Run all quality checks (lint + stan + test + twig-lint)
```

Change to:

```makefile
check: lint stan test twig-lint spell lint-js lint-css ## Run all quality checks (lint + stan + test + twig-lint + spell + lint-js + lint-css)
```

- [ ] **Step 3: Verify with a dry run**

```bash
make -n lint-css
make -n check
```

Expected: both print their command chains (including the newly-added `spell`/`lint-js`/`lint-css` lines inside `check`) with no Make syntax error.

Known, verified caveat to record in the docs task: formatting CSS with `make format` (Prettier, this template's `.prettierrc.json`) does not shorten hex color codes, but Drupal core's Stylelint config (`stylelint-config-standard`'s `color-hex-length: short` rule) requires the shortest form. This was confirmed empirically (not assumed): `prettier --write` on `--foo-color: #FF0000;` produces `#ff0000` (lowercased only), which `stylelint --config web/core/.stylelintrc.json` then flags as an error, fixable with `stylelint --fix` but not by any Prettier option. Document this as "write short hex from the start, or run `lint-css`'s underlying stylelint with `--fix` if it flags this" rather than treating it as a bug to fix in `.prettierrc.json`.

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "Add make lint-css using Drupal core's Stylelint config, wire spell/lint-js/lint-css into check"
```

---

## Task 5: GitHub Actions parity (cspell, ESLint, Stylelint)

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the `guard` job's `outputs.run` (existing), `{{MODULE_PATH}}` token (existing).
- Produces: no new job outputs; adds steps to the existing `php` and `prettier` jobs only.

- [ ] **Step 1: Add a guarded CSpell step to the `prettier` job**

Current `prettier` job:

```yaml
  prettier:
    name: Prettier
    needs: guard
    if: needs.guard.outputs.run == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm install --no-audit --no-fund
      - run: npx prettier --check "{{MODULE_PATH}}/**/*.{css,js,json,yml,yaml,md}"
```

Add a step after the Prettier check:

```yaml
  prettier:
    name: Prettier
    needs: guard
    if: needs.guard.outputs.run == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm install --no-audit --no-fund
      - run: npx prettier --check "{{MODULE_PATH}}/**/*.{css,js,json,yml,yaml,md}"

      - name: CSpell
        run: |
          if find {{MODULE_PATH}} -type f -print -quit | grep -q .; then
            npx cspell --no-progress "{{MODULE_PATH}}/**"
          else
            echo "No files found under {{MODULE_PATH}}; skipping cspell."
          fi
```

- [ ] **Step 2: Add guarded ESLint/Stylelint steps to the `php` job**

Current `php` job ends with the PHPUnit step (see `.github/workflows/ci.yml:93-107`). Add these steps immediately after it, still inside the `php` job (it already runs `composer install`, which scaffolds `web/core`):

```yaml
      - name: Set up Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install Drupal core's frontend dependencies
        run: npm ci --prefix web/core

      - name: ESLint (Drupal core config)
        run: |
          if find {{MODULE_PATH}} -name '*.js' -print -quit | grep -q .; then
            node web/core/node_modules/.bin/eslint {{MODULE_PATH}} \
              --no-error-on-unmatched-pattern \
              --ignore-pattern='*.es6.js' \
              --resolve-plugins-relative-to=web/core \
              --ext=.js,.yml \
              -c web/core/.eslintrc.passing.json
          else
            echo "No .js files found under {{MODULE_PATH}}; skipping eslint."
          fi

      - name: Stylelint (Drupal core config)
        run: |
          if find {{MODULE_PATH}} -name '*.css' -print -quit | grep -q .; then
            web/core/node_modules/.bin/stylelint --config web/core/.stylelintrc.json "{{MODULE_PATH}}/**/*.css"
          else
            echo "No .css files found under {{MODULE_PATH}}; skipping stylelint."
          fi
```

- [ ] **Step 3: Verify YAML validity**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
```

Expected: no output (valid YAML). Note in the summary that this only validates YAML syntax; actually running the workflow (confirming `npm ci --prefix web/core` succeeds, the eslint/stylelint invocations pass on a real scaffolded site) needs a live push to GitHub Actions, consistent with this template's existing "a11y job needs live verification" caveat in `PROJECT.md`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "Add cspell, eslint, and stylelint steps to GitHub Actions CI"
```

---

## Task 6: Regression suite coverage

**Files:**
- Modify: `scripts/test-template.sh`

**Interfaces:**
- Consumes: `run_combo()`'s existing `tmp_dir` variable and pass/fail helpers (`pass`, `fail`), `$REPO_ROOT` (already defined at the top of the script).
- Produces: two new assertions per combo, no new functions needed.

- [ ] **Step 1: Add the verbatim-survival and dry-run assertions**

In `scripts/test-template.sh`, inside `run_combo()`, after the existing block `# f. make/JSON/YAML parse.` (the block ending with the `.ddev/config.yaml` YAML check, just before `rm -rf "$tmp_dir"`), add:

```bash
  # g. assets/module.gitlab-ci.yml is not a template file (no {{TOKENS}} inside
  # it), so it must survive init.sh completely unchanged.
  if diff -q "$REPO_ROOT/assets/module.gitlab-ci.yml" "$tmp_dir/assets/module.gitlab-ci.yml" >/dev/null 2>&1; then
    pass "$label: assets/module.gitlab-ci.yml survives init.sh verbatim"
  else
    fail "$label: assets/module.gitlab-ci.yml changed or missing after init.sh"
  fi

  # h. make -n module-ci parses.
  if (cd "$tmp_dir" && make -n module-ci) >/dev/null 2>&1; then
    pass "$label: make -n module-ci parses"
  else
    fail "$label: make -n module-ci failed"
  fi
```

(The existing recursive `grep -rlE '\{\{[A-Z_]+\}\}' "$tmp_dir" ...` check in block "b" already scans `assets/module.gitlab-ci.yml` along with every other file, so no separate leftover-token check is needed for it; the verbatim `diff -q` above is strictly stronger, since a byte-identical file cannot contain a leftover token that was not there originally.)

- [ ] **Step 2: Add the same two assertions to `run_site_only()`**

In `run_site_only()`, after the existing `make -n help` check and before `rm -rf "$tmp_dir"`, add:

```bash
  if diff -q "$REPO_ROOT/assets/module.gitlab-ci.yml" "$tmp_dir/assets/module.gitlab-ci.yml" >/dev/null 2>&1; then
    pass "$label: assets/module.gitlab-ci.yml survives init.sh verbatim"
  else
    fail "$label: assets/module.gitlab-ci.yml changed or missing after init.sh"
  fi

  if (cd "$tmp_dir" && make -n module-ci) >/dev/null 2>&1; then
    pass "$label: make -n module-ci parses (guard-module-name should reject cleanly)"
  else
    fail "$label: make -n module-ci failed"
  fi
```

Note: `make -n module-ci` in site-only mode still parses and prints successfully, because `make -n` never executes recipe shell bodies (including `guard-module-name`'s `exit 1`); it only prints what would run. This mirrors how `make -n help` is already used elsewhere in this script as a pure parse check, not a behavioural one.

- [ ] **Step 3: Run the full regression suite**

Run: `./scripts/test-template.sh`
Expected: exit 0, with the new "assets/module.gitlab-ci.yml survives init.sh verbatim" and "make -n module-ci parses" lines passing for all four combos plus the site-only combo.

- [ ] **Step 4: Prove the failure path (break it on purpose once)**

```bash
cp assets/module.gitlab-ci.yml /tmp/module.gitlab-ci.yml.bak
echo "# tampered" >> assets/module.gitlab-ci.yml
./scripts/test-template.sh; echo "exit: $?"
```

Expected: nonzero exit, with "assets/module.gitlab-ci.yml changed or missing after init.sh" failing for every combo (since the tampered root file no longer matches whatever the tmp_dir rsync copied before the tamper... note: run this from a clean state, tamper, then run the suite, so the failure is genuine). Then restore:

```bash
cp /tmp/module.gitlab-ci.yml.bak assets/module.gitlab-ci.yml
rm /tmp/module.gitlab-ci.yml.bak
./scripts/test-template.sh; echo "exit: $?"
```

Expected: exit 0 again, confirming the restore worked and the check is genuinely load-bearing, not vacuously passing.

- [ ] **Step 5: Commit**

```bash
git add scripts/test-template.sh
git commit -m "test-template.sh: assert module.gitlab-ci.yml survives init.sh verbatim"
```

---

## Task 7: Documentation and status updates

**Files:**
- Modify: `README.md`
- Modify: `PROJECT.md`
- Modify: `AGENTS.md`
- Modify: `PROMPTS.md`

**Interfaces:** None (docs only).

- [ ] **Step 1: `README.md` — "What you get" bullet**

After the existing GitHub Actions CI bullet (`- A GitHub Actions CI workflow ...`), add:

```markdown
- drupal.org (git.drupalcode.org) pipeline parity: `assets/module.gitlab-ci.yml` is a ready `.gitlab-ci.yml` for the module, copied in with `make module-ci`. Local tooling mirrors the same pipeline's default validation jobs, cspell (`make spell`), ESLint and Stylelint (`make lint-js`, `make lint-css`) using Drupal core's own configs, alongside the existing PHPCS/PHPStan/Twig CS Fixer, so `make check` predicts what runs there. Twig CS Fixer is skipped by default upstream; the shipped pipeline turns it back on to match this template's local tooling. Nightwatch (browser JS tests) has no local equivalent and stays CI-only.
```

- [ ] **Step 2: `README.md` — Common commands table**

Current table (`## Common commands`):

```markdown
make check         # lint + stan + test + twig-lint
```

Change to:

```markdown
make check         # lint + stan + test + twig-lint + spell + lint-js + lint-css
```

And add a new row after `make twig-lint`:

```markdown
make module-ci      # Copy the drupal.org GitLab CI pipeline into the module
```

- [ ] **Step 3: `PROJECT.md` — "What the template contains"**

Add a new bullet after the CI bullet:

```markdown
- drupal.org pipeline parity: assets/module.gitlab-ci.yml ships the canonical
  gitlab_templates include block (three files: main, variables, workflows)
  plus a documented variables block. `make module-ci` copies it to
  $(MODULE)/.gitlab-ci.yml, refusing if one exists. Twig CS Fixer defaults to
  SKIPPED upstream (SKIP_TWIG_CS_FIXER: '1'); the shipped file overrides it
  to '0' since this template already lints Twig locally and in GitHub
  Actions. Local parity: cspell.json + .cspell-project-words.txt at the
  template root wired to `make spell`; `make lint-js` and `make lint-css`
  reuse Drupal core's own installed ESLint/Stylelint config and binaries
  from web/core/node_modules, the same approach the drupalcode CI jobs use,
  guarded to skip with a message when the module has no .js/.css files.
  Prettier's CSS output does not shorten hex colors, which core's Stylelint
  config requires (color-hex-length: short); this is a known, verified gap
  with no config fix, write short hex or run stylelint --fix. GitHub
  Actions ci.yml mirrors the same three checks (CSpell in the prettier job,
  ESLint/Stylelint in the php job after composer install). Nightwatch has
  no local equivalent and stays CI-only, same category as the a11y job.
```

- [ ] **Step 4: `PROJECT.md` — Status section**

Append to the end of the `### Status (2026-07)` section:

```markdown
Stage 8, drupal.org (GitLab CI) pipeline parity: DONE. assets/module.gitlab-ci.yml
ships the canonical include block plus a variables block that turns Twig CS
Fixer back on (it defaults to skipped upstream, a fact confirmed directly
against the live gitlab_templates source, not assumed from the Stage 8
prompt text). make module-ci copies it into the module. Local parity added:
make spell (cspell.json + .cspell-project-words.txt), make lint-js and make
lint-css (Drupal core's own ESLint/Stylelint config and binaries from
web/core/node_modules), all wired into make check. GitHub Actions ci.yml
mirrors the same three checks. Actually running make lint-js/lint-css, and
the GitHub Actions eslint/stylelint steps end to end, needs a live DDEV
project with web/core's own npm dependencies installed (`npm ci --prefix
web/core` or the DDEV equivalent), which is outside this stage's scope and
still needs live verification, same caveat as the rest of this template's
DDEV-dependent tooling. Nightwatch (browser JS tests) has no local
equivalent and stays CI-only.
```

- [ ] **Step 5: `AGENTS.md` — Working Rules**

Current line:

```markdown
- Any PHP change ships with PHPUnit tests confirming correct behaviour; run the module test suite plus `phpcbf` then `phpcs` before considering a change done.
```

Change to:

```markdown
- Any PHP change ships with PHPUnit tests confirming correct behaviour; run the module test suite plus `phpcbf` then `phpcs` before considering a change done. PHP and front-end changes must pass `make check`, which mirrors the git.drupalcode.org default validation pipeline (phpcs, phpstan, twig-cs-fixer, cspell, eslint, stylelint).
```

- [ ] **Step 6: `PROMPTS.md` — Stage 8 status**

Current line in the Status section:

```markdown
- Stage 8, drupal.org pipeline parity: OPEN (prompt below).
```

Change to:

```markdown
- Stage 8, drupal.org pipeline parity: DONE. assets/module.gitlab-ci.yml,
  make module-ci, and local parity targets (spell, lint-js, lint-css) landed;
  see PROJECT.md Status for the SKIP_TWIG_CS_FIXER and hex-color caveats
  found during implementation. The DDEV/npm spin-up for lint-js/lint-css
  still needs a live run.
```

- [ ] **Step 7: Verify docs render and no em dashes crept in**

```bash
grep -n "—" README.md PROJECT.md AGENTS.md PROMPTS.md Makefile assets/module.gitlab-ci.yml .github/workflows/ci.yml cspell.json .cspell-project-words.txt package.json || echo "no em dashes found"
```

Expected: "no em dashes found".

- [ ] **Step 8: Commit**

```bash
git add README.md PROJECT.md AGENTS.md PROMPTS.md
git commit -m "Document drupal.org pipeline parity (Stage 8)"
```

---

## Final Verification Checklist

- [ ] `./scripts/test-template.sh` exits 0 (all combos, including the new assertions from Task 6).
- [ ] `make -n module-ci`, `make -n spell`, `make -n lint-js`, `make -n lint-css`, `make -n check` all parse without error, run from this repo's own root (tokens still literal, which is fine for a dry run).
- [ ] `python3 -c "import json; json.load(open('cspell.json'))"` and the same for `package.json` both succeed.
- [ ] `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` succeeds.
- [ ] `bash -n scripts/test-template.sh` succeeds and the file is still mode 100755 (`ls -l scripts/test-template.sh`).
- [ ] No em dashes in any touched file (Task 7, Step 7).
- [ ] Flag explicitly in the final summary to the user: `make lint-js`, `make lint-css`, and the GitHub Actions ESLint/Stylelint steps have only been dry-run/YAML-validated, not executed against a real scaffolded Drupal site with `web/core/node_modules` installed. That is a live-verification gap, not a claimed pass.
