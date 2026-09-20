# Local Dev Recipes (Stage 11) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every project created from this template the standard Drupal local dev setup (Twig debug on, caches off) plus a baseline of site utility modules, delivered through two first-class Recipes (`recipes/dev_tools`, `recipes/site_tools`) and a settings.local.php/development.services.yml pair that `scripts/setup.sh` wires up automatically.

**Architecture:** Two static template files in `assets/` (`settings.local.php`, `development.services.yml`, both token-free) are copied by `scripts/setup.sh` into `web/sites/default/` and `web/sites/` the first time they are absent, and `setup.sh` patches `web/sites/default/settings.php` to activate the include (uncommenting Drupal's own commented block if present, appending the standard guarded include if not). Two Recipes (`recipes/dev_tools/recipe.yml`, `recipes/site_tools/recipe.yml`, also token-free) declare the module install lists; `setup.sh` applies `site_tools` then `dev_tools` via `ddev drush recipe` after the site install, then runs one more `drush cex` so `site_tools`'s modules land in exported config while `dev_tools`'s modules (excluded via `config_exclude_modules` in `settings.local.php`) never do. `drupal/core-recipe-unpack` and ECA/`bpmn_io`'s version pairing (3.x for Drupal 11, 2.x for Drupal 10) are wired into the composer requires the same step already does for the existing dev tooling. A new `make recipe R=path` target and `--no-site-tools`/`--no-dev-tools` `setup.sh` flags round out the plumbing.

**Tech Stack:** Bash (`set -euo pipefail`), Composer, Drush (recipe application), YAML (Drupal recipe.yml), GNU Make. No new runtime dependencies for the template itself.

## Global Constraints

- No em dashes anywhere in code, comments, docs, or script output.
- Scripts stay executable (100755).
- `recipes/`, `assets/settings.local.php`, and `assets/development.services.yml` hold no `{{TOKENS}}` and must survive `scripts/init.sh` verbatim, same as `assets/module.gitlab-ci.yml`.
- Run `scripts/test-template.sh` before calling any change done; it stays network-free (no composer, no DDEV).
- GitHub Actions `${{ }}` expressions must never be touched.
- Keep all three flavours (localgov, vanilla, cms) and both Drupal versions (10, 11, where supported) working; this feature must not regress any of them.
- Verified package facts (2026-08, from drupal.org release pages), do not re-derive or second-guess these:
  - `drupal/core-recipe-unpack`: official recipe-unpacking Composer plugin; needs `allow-plugins.drupal/core-recipe-unpack: true`.
  - `drupal/devel:^5.5` supports `^10.3 || ^11 || ^12`.
  - `drupal/environment_indicator` (no version pin needed; current stable 4.0.25) supports Drupal 10 and 11; toolbar integration ships in the `environment_indicator_toolbar` submodule.
  - `drupal/ctools:^4.1` supports `^9.5 || ^10 || ^11`.
  - `drupal/admin_toolbar:^3.6` supports `^9.5 || ^10 || ^11`; ships `admin_toolbar` and `admin_toolbar_tools`.
  - `drupal/twig_tweak:^3.4` supports `^10.3 || ^11`.
  - `drupal/eca:^3.1` requires Drupal `^11.3 || ^12.0` (Drupal 11 only). `drupal/eca:^2.1` (latest stable 2.1.20) requires `^10.3 || ^11`, so Drupal 10 projects use the 2.x line.
  - `drupal/bpmn_io:^3.0` (latest stable 3.0.6) requires `^11.2 || ^12`, pairs with ECA 3.x. `drupal/bpmn_io:^2.0` (latest stable 2.0.12) requires `^10.3 || ^11`, pairs with ECA 2.x.
  - `$settings['config_exclude_modules']` is a real Drupal core setting (documented in `example.settings.local.php`) that excludes named modules from `core.extension` during `drush cex`/`cim`.
  - `$config['environment_indicator.indicator']['name'|'bg_color'|'fg_color']` are the correct config keys for the indicator module.
  - The Twig debug include line is `$settings['container_yamls'][] = DRUPAL_ROOT . '/sites/development.services.yml';` (not `$site_path`, since the file lives directly under `sites/`, not `sites/default/`).
  - `drush recipe <path>` (Drush 13+) applies a recipe; the template already requires `drush/drush` in dev tooling.

---

### Task 1: Extend the regression suite with failing assertions for the new files

**Files:**
- Modify: `scripts/test-template.sh:177-197` (inside `assert_common`, right after the existing `assets/module.gitlab-ci.yml` verbatim check)

**Interfaces:**
- Produces: no new functions; adds inline assertions inside the existing `assert_common` function that Task 8's full-suite run will exercise.
- Consumes: the existing `pass`/`fail`/`REPO_ROOT`/`yaml_parse` helpers already defined at the top of the file.

This task's assertions will fail until Tasks 2-7 land. That is expected and is the point: it proves the suite actually exercises the new files instead of vacuously passing later.

- [ ] **Step 1: Add verbatim-survival and validity assertions**

In `scripts/test-template.sh`, immediately after this existing block (currently lines 177-182):

```bash
  # assets/module.gitlab-ci.yml holds no {{TOKENS}}, so it must survive verbatim.
  if diff -q "$REPO_ROOT/assets/module.gitlab-ci.yml" "$dir/assets/module.gitlab-ci.yml" >/dev/null 2>&1; then
    pass "$label: assets/module.gitlab-ci.yml survives init.sh verbatim"
  else
    fail "$label: assets/module.gitlab-ci.yml changed or missing after init.sh"
  fi
```

insert:

```bash
  # recipes/ and the local dev settings templates hold no {{TOKENS}} either,
  # so they must survive init.sh verbatim too.
  for f in recipes/dev_tools/recipe.yml recipes/site_tools/recipe.yml \
    assets/settings.local.php assets/development.services.yml; do
    if diff -q "$REPO_ROOT/$f" "$dir/$f" >/dev/null 2>&1; then
      pass "$label: $f survives init.sh verbatim"
    else
      fail "$label: $f changed or missing after init.sh"
    fi
  done

  if yaml_parse "$dir/recipes/dev_tools/recipe.yml"; then
    pass "$label: recipes/dev_tools/recipe.yml is valid YAML"
  else
    fail "$label: recipes/dev_tools/recipe.yml is not valid YAML"
  fi
  if yaml_parse "$dir/recipes/site_tools/recipe.yml"; then
    pass "$label: recipes/site_tools/recipe.yml is valid YAML"
  else
    fail "$label: recipes/site_tools/recipe.yml is not valid YAML"
  fi

  if (cd "$dir" && make -n recipe R=recipes/site_tools) >/dev/null 2>&1; then
    pass "$label: make -n recipe parses"
  else
    fail "$label: make -n recipe failed"
  fi
```

- [ ] **Step 2: Run the suite and confirm the new assertions fail**

Run: `./scripts/test-template.sh 2>&1 | grep -E "recipe|settings.local.php|development.services.yml"`

Expected: several `FAIL` lines (files/target do not exist yet). This confirms the assertions are wired up and reachable, not silently skipped.

- [ ] **Step 3: Commit**

```bash
git add scripts/test-template.sh
git commit -m "test: add failing assertions for local dev recipes plumbing"
```

---

### Task 2: Ship the local settings templates

**Files:**
- Create: `assets/settings.local.php`
- Create: `assets/development.services.yml`

**Interfaces:**
- Produces: two static files with no `{{TOKENS}}`, consumed by Task 6's `setup.sh` copy logic (source paths `assets/settings.local.php`, `assets/development.services.yml`) and by Task 1's verbatim-survival assertions (already added).

- [ ] **Step 1: Write `assets/settings.local.php`**

```php
<?php

/**
 * Local development settings, copied into place by scripts/setup.sh.
 *
 * Edit the copy at web/sites/default/settings.local.php, not this template:
 * setup.sh only copies this file when the destination is absent, so local
 * edits survive a re-run of setup.sh.
 */

// Enable local development services (Twig debug on, Twig cache off). See
// assets/development.services.yml, copied to web/sites/development.services.yml.
$settings['container_yamls'][] = DRUPAL_ROOT . '/sites/development.services.yml';

// Disable CSS and JS aggregation.
$config['system.performance']['css']['preprocess'] = FALSE;
$config['system.performance']['js']['preprocess'] = FALSE;

// Disable the render, page, and dynamic page caches for local development.
$settings['cache']['bins']['render'] = 'cache.backend.null';
$settings['cache']['bins']['page'] = 'cache.backend.null';
$settings['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';

// Skip file system permissions hardening.
$settings['skip_permissions_hardening'] = TRUE;

// Exclude local-only modules from configuration synchronization, so a
// production config import never tries to enable them. See
// recipes/dev_tools/recipe.yml for what installs them locally.
$settings['config_exclude_modules'] = ['devel', 'environment_indicator_toolbar'];

// Environment indicator: local name and colours. Staging and production set
// their own name and colours the same way, in their own settings.local.php
// equivalent; environment_indicator itself is not in config_exclude_modules
// above, so the module stays enabled through the normal config export/import.
$config['environment_indicator.indicator']['name'] = 'Local';
$config['environment_indicator.indicator']['bg_color'] = '#0b6623';
$config['environment_indicator.indicator']['fg_color'] = '#ffffff';
```

- [ ] **Step 2: Write `assets/development.services.yml`**

```yaml
# Local development services, copied into place by scripts/setup.sh to
# web/sites/development.services.yml. Edit the copy there, not this
# template: setup.sh only copies this file when the destination is absent.
parameters:
  twig.config:
    debug: true
    auto_reload: true
    cache: false
```

- [ ] **Step 3: Verify syntax**

Run: `php -l assets/settings.local.php`
Expected: `No syntax errors detected`

Run (Ruby, matching `yaml_parse` in test-template.sh): `ruby -ryaml -e "YAML.load_file('assets/development.services.yml')" && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add assets/settings.local.php assets/development.services.yml
git commit -m "feat: ship local dev settings.local.php and development.services.yml templates"
```

---

### Task 3: Create the two recipes

**Files:**
- Create: `recipes/dev_tools/recipe.yml`
- Create: `recipes/site_tools/recipe.yml`

**Interfaces:**
- Produces: two recipe directories at `recipes/dev_tools` and `recipes/site_tools`, applied by Task 7's `setup.sh` logic via `ddev drush recipe recipes/dev_tools` / `ddev drush recipe recipes/site_tools`, and by Task 4's `make recipe` target.
- `type:` is free-text metadata only; deliberately not `'Site'` (that value makes core's own installer list the recipe as an install-profile choice, which neither of these two should be).

- [ ] **Step 1: Write `recipes/dev_tools/recipe.yml`**

```yaml
name: 'Dev tools'
description: 'Local-only development tooling: Devel and Environment Indicator (with its toolbar integration). Colours, Twig debug, and cache settings are per-environment settings.local.php concerns, not this recipe. Its modules are covered by config_exclude_modules in assets/settings.local.php, except environment_indicator itself, which is allowed to flow through config sync (see that file for why).'
type: 'Development tooling'
install:
  - devel
  - environment_indicator
  - environment_indicator_toolbar
```

- [ ] **Step 2: Write `recipes/site_tools/recipe.yml`**

```yaml
name: 'Site tools'
description: 'Production site utility modules: Admin Toolbar, Twig Tweak, and ECA (Event - Condition - Action) with its BPMN visual modeller. These are production features: they are NOT in config_exclude_modules, and they export into config/sync on the next drush cex. ctools is required by Composer but deliberately not in this install list: it is an API module other contrib modules enable as a dependency when they need it.'
type: 'Site configuration'
install:
  - admin_toolbar
  - admin_toolbar_tools
  - twig_tweak
  - eca
  - eca_ui
  - bpmn_io
```

- [ ] **Step 3: Verify YAML validity**

Run: `ruby -ryaml -e "YAML.load_file('recipes/dev_tools/recipe.yml'); YAML.load_file('recipes/site_tools/recipe.yml')" && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add recipes/dev_tools/recipe.yml recipes/site_tools/recipe.yml
git commit -m "feat: add dev_tools and site_tools recipes"
```

---

### Task 4: Add the `make recipe` target

**Files:**
- Modify: `Makefile:6-10` (`.PHONY` list)
- Modify: `Makefile:63-69` (insert a new `## == Recipes ==` section after the Drupal section's `cr` target, before `## == Theme ==`)

**Interfaces:**
- Consumes: `ddev drush recipe`, exercised live in Task 11.
- Produces: `make recipe R=<path>` target, already referenced by Task 1's `make -n recipe R=recipes/site_tools` assertion and by Task 7's `setup.sh` (which calls `ddev drush recipe recipes/site_tools` and `ddev drush recipe recipes/dev_tools` directly, not through this Make target, since setup.sh needs the `-y` global flag and per-recipe success/warn handling; `make recipe` is the manual/ad-hoc entry point for any other recipe path).

- [ ] **Step 1: Add `recipe` to `.PHONY`**

In `Makefile`, change:

```makefile
.PHONY: help start stop restart open logs si install enable cr \
        test lint lint-fix stan check format format-check twig-lint twig-fix \
        spell lint-js lint-css module-ci subtheme component \
        mod-log mod-status mod-fetch mod-branch tag switch mr \
        guard-module-name guard-module-git guard-theme-name
```

to:

```makefile
.PHONY: help start stop restart open logs si install enable cr recipe \
        test lint lint-fix stan check format format-check twig-lint twig-fix \
        spell lint-js lint-css module-ci subtheme component \
        mod-log mod-status mod-fetch mod-branch tag switch mr \
        guard-module-name guard-module-git guard-theme-name
```

- [ ] **Step 2: Add the target**

In `Makefile`, immediately after the `cr` target (currently):

```makefile
cr: ## Clear Drupal caches
	ddev drush cr

## == Theme ====================================================================
```

insert a new section between them:

```makefile
cr: ## Clear Drupal caches
	ddev drush cr

## == Recipes ==================================================================

recipe: ## Apply a recipe (usage: make recipe R=recipes/site_tools)
	@test -n "$(R)" || (echo "Usage: make recipe R=recipes/site_tools" && exit 1)
	ddev drush recipe $(R)

## == Theme ====================================================================
```

- [ ] **Step 3: Verify it parses**

Run: `make -n recipe R=recipes/site_tools`
Expected: prints `ddev drush recipe recipes/site_tools` (dry run, no execution)

Run: `make -n recipe`
Expected: exits nonzero with `Usage: make recipe R=recipes/site_tools`

Run: `make -n help`
Expected: still parses, `recipe` appears in the target list output when actually run (not `-n`, but confirm no syntax break)

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "feat: add make recipe target"
```

---

### Task 5: Composer wiring in scripts/setup.sh (recipes plumbing + site utility modules)

**Files:**
- Modify: `scripts/setup.sh:15-20` (token variable declarations)
- Modify: `scripts/setup.sh:115-131` (insert new sections after the existing "Dev tooling" block, before "Prettier")

**Interfaces:**
- Produces: `DRUPAL_TYPE` shell variable (substituted by `init.sh`, which already lists `scripts/setup.sh` in its `FILES` array and already has a `sub DRUPAL_TYPE "$DRUPAL_TYPE"` call, so no `init.sh` change is needed for this token to reach the new usage).
- Consumes: `ddev composer require`, `ddev composer config`, matching the existing pattern at `scripts/setup.sh:122-131`.

- [ ] **Step 1: Add the `DRUPAL_TYPE` variable**

In `scripts/setup.sh`, change:

```bash
COMPOSER_PROJECT="{{COMPOSER_PROJECT}}"
INSTALL_PROFILE="{{INSTALL_PROFILE}}"
```

to:

```bash
COMPOSER_PROJECT="{{COMPOSER_PROJECT}}"
INSTALL_PROFILE="{{INSTALL_PROFILE}}"
DRUPAL_TYPE="{{DRUPAL_TYPE}}"
```

- [ ] **Step 2: Add the site utility modules and dev-only modules sections**

In `scripts/setup.sh`, immediately after the existing "Dev tooling" block (currently ending at line 131):

```bash
if ddev composer require --dev --no-interaction -W \
  drupal/core-dev drupal/coder mglaman/phpstan-drupal \
  phpstan/phpstan phpstan/phpstan-deprecation-rules \
  vincentlanglet/twig-cs-fixer drush/drush; then
  success "PHP dev tooling installed."
else
  warn "Some dev dependencies failed to install; add them manually."
fi
```

insert, before the `# --- Prettier ---` comment:

```bash
# --- Site utility modules (recipes plumbing) ---
# drupal/core-recipe-unpack lets `drush recipe` and any composer-distributed
# recipe unpack its dependencies into this project's own composer.json.
# Required up front alongside the modules recipes/site_tools and
# recipes/dev_tools install (applied later, after the site install).
info "Adding site utility modules..."
ddev composer config --no-plugins allow-plugins.drupal/core-recipe-unpack true 2>/dev/null || true
# ECA and its BPMN modeller are version-paired with Drupal core: the 3.x line
# needs Drupal 11.3+, so Drupal 10 projects use the 2.x line instead.
if [ "$DRUPAL_TYPE" = "drupal10" ]; then
  ECA_PACKAGES=(drupal/eca:^2.1 drupal/bpmn_io:^2.0)
else
  ECA_PACKAGES=(drupal/eca:^3.1 drupal/bpmn_io:^3.0)
fi
if ddev composer require --no-interaction -W \
  drupal/core-recipe-unpack drupal/environment_indicator \
  drupal/ctools:^4.1 drupal/admin_toolbar:^3.6 drupal/twig_tweak:^3.4 \
  "${ECA_PACKAGES[@]}"; then
  success "Site utility modules installed."
else
  warn "Some site utility modules failed to install; add them manually."
fi

# --- Dev-only modules (require-dev, absent from a --no-dev production build) ---
info "Adding dev-only modules..."
if ddev composer require --dev --no-interaction -W drupal/devel:^5.5; then
  success "Dev-only modules installed."
else
  warn "drupal/devel failed to install; add it manually."
fi
```

- [ ] **Step 3: Verify the script still parses**

Run: `bash -n scripts/setup.sh`
Expected: no output, exit 0

- [ ] **Step 4: Commit**

```bash
git add scripts/setup.sh
git commit -m "feat: wire recipe-unpack, site utility modules, and version-aware ECA into setup.sh"
```

---

### Task 6: Copy the local settings templates into place in scripts/setup.sh

**Files:**
- Modify: `scripts/setup.sh:139-148` (insert a new section after "Optional: clone the target module", before "Install the site")

**Interfaces:**
- Consumes: `assets/settings.local.php`, `assets/development.services.yml` (Task 2).
- Produces: `web/sites/default/settings.local.php`, `web/sites/development.services.yml`, and an activated include in `web/sites/default/settings.php`, verified live in Task 11.

- [ ] **Step 1: Add the local settings section**

In `scripts/setup.sh`, immediately after the existing "Optional: clone the target module" block (currently):

```bash
if [ -n "${MODULE_NAME}" ]; then
  if [ -n "${MODULE_REPO}" ] && [ ! -d "${MODULE_PATH}" ]; then
    info "Cloning module into ${MODULE_PATH}..."
    mkdir -p "$(dirname "${MODULE_PATH}")"
    git clone "${MODULE_REPO}" "${MODULE_PATH}" && success "Module cloned." || warn "Module clone failed; clone manually."
  fi
else
  info "Site-only project: skipping module clone and enable."
fi
```

insert, before the `# --- Install the site ---` comment:

```bash
# --- Local development settings ---
# Copied only when absent, so a re-run of setup.sh never clobbers local edits.
info "Adding local development settings..."
if [ ! -f "web/sites/default/settings.local.php" ]; then
  cp assets/settings.local.php web/sites/default/settings.local.php
  success "web/sites/default/settings.local.php created."
else
  success "web/sites/default/settings.local.php already present, not overwriting."
fi
if [ ! -f "web/sites/development.services.yml" ]; then
  cp assets/development.services.yml web/sites/development.services.yml
  success "web/sites/development.services.yml created."
else
  success "web/sites/development.services.yml already present, not overwriting."
fi

SETTINGS_PHP="web/sites/default/settings.php"
if [ -f "$SETTINGS_PHP" ]; then
  ACTIVE_INCLUDE="if (file_exists(\$app_root . '/' . \$site_path . '/settings.local.php')) {"
  COMMENTED_INCLUDE="# if (file_exists(\$app_root . '/' . \$site_path . '/settings.local.php')) {"
  if grep -qF "$ACTIVE_INCLUDE" "$SETTINGS_PHP" 2>/dev/null; then
    success "settings.php already includes settings.local.php."
  elif grep -qF "$COMMENTED_INCLUDE" "$SETTINGS_PHP" 2>/dev/null; then
    info "Enabling the settings.local.php include in settings.php..."
    line_no="$(grep -nF "$COMMENTED_INCLUDE" "$SETTINGS_PHP" | head -1 | cut -d: -f1)"
    l2=$((line_no + 1)); l3=$((line_no + 2))
    tmp="$(mktemp)"
    awk -v a="$line_no" -v b="$l2" -v c="$l3" \
      'NR==a || NR==b || NR==c { sub(/^# ?/, "") } { print }' \
      "$SETTINGS_PHP" > "$tmp" && cat "$tmp" > "$SETTINGS_PHP" && rm -f "$tmp"
    success "settings.local.php include enabled."
  else
    info "Appending the settings.local.php include to settings.php..."
    {
      echo ""
      echo "$ACTIVE_INCLUDE"
      echo "  include \$app_root . '/' . \$site_path . '/settings.local.php';"
      echo "}"
    } >> "$SETTINGS_PHP"
    success "settings.local.php include appended."
  fi
else
  warn "web/sites/default/settings.php not found; DDEV should have created it. Add the settings.local.php include manually after install."
fi
```

Note: this does not touch DDEV's own `settings.ddev.php` include (a different filename, added by DDEV itself); the three detection/uncomment branches above key off the full `settings.local.php` opening-brace line via `grep -F` (fixed-string) matching, not a generic pattern like a bare `# }`, so no other commented block in `settings.php` (there are several, e.g. reverse proxy, trusted host patterns) is touched.

- [ ] **Step 2: Verify the script still parses**

Run: `bash -n scripts/setup.sh`
Expected: no output, exit 0

- [ ] **Step 3: Verify the uncomment logic against a synthetic settings.php**

This proves the line-number-targeted awk only touches the intended three lines, even when the file has other unrelated commented blocks ending in `# }`.

```bash
cat > /tmp/settings-php-test.php <<'EOF'
<?php
# $settings['reverse_proxy'] = TRUE;
# $settings['reverse_proxy_addresses'] = ['a.b.c.d'];
#
# if (isset($_SERVER['HTTP_HOST'])) {
#   $settings['something'] = TRUE;
# }
#
# if (file_exists($app_root . '/' . $site_path . '/settings.local.php')) {
#   include $app_root . '/' . $site_path . '/settings.local.php';
# }
EOF
SETTINGS_PHP="/tmp/settings-php-test.php"
ACTIVE_INCLUDE="if (file_exists(\$app_root . '/' . \$site_path . '/settings.local.php')) {"
COMMENTED_INCLUDE="# if (file_exists(\$app_root . '/' . \$site_path . '/settings.local.php')) {"
line_no="$(grep -nF "$COMMENTED_INCLUDE" "$SETTINGS_PHP" | head -1 | cut -d: -f1)"
l2=$((line_no + 1)); l3=$((line_no + 2))
awk -v a="$line_no" -v b="$l2" -v c="$l3" \
  'NR==a || NR==b || NR==c { sub(/^# ?/, "") } { print }' \
  "$SETTINGS_PHP"
```

Expected output: the reverse-proxy and `HTTP_HOST` blocks stay commented (including their own `# }` lines), and only the final three lines are uncommented:

```
if (file_exists($app_root . '/' . $site_path . '/settings.local.php')) {
  include $app_root . '/' . $site_path . '/settings.local.php';
}
```

If any other line changes, the pattern is not selective enough; stop and fix before proceeding.

- [ ] **Step 4: Commit**

```bash
git add scripts/setup.sh
git commit -m "feat: copy local dev settings templates and activate settings.local.php include"
```

---

### Task 7: Apply the recipes after install in scripts/setup.sh

**Files:**
- Modify: `scripts/setup.sh:4-6` (flags header comment)
- Modify: `scripts/setup.sh:24-30` (flag parsing)
- Modify: `scripts/setup.sh:150-160` ("Install the site" block)

**Interfaces:**
- Consumes: `recipes/dev_tools`, `recipes/site_tools` (Task 3).
- Produces: `--no-site-tools`, `--no-dev-tools` flags, verified live in Task 11.

- [ ] **Step 1: Document the new flags**

In `scripts/setup.sh`, change:

```bash
# Flags:
#   --force-reviewer   re-fetch drupal-reviewer even if present
#   --skip-install     scaffold + tooling only, do not install the Drupal site
```

to:

```bash
# Flags:
#   --force-reviewer   re-fetch drupal-reviewer even if present
#   --skip-install     scaffold + tooling only, do not install the Drupal site
#   --no-site-tools    skip applying recipes/site_tools after install
#   --no-dev-tools     skip applying recipes/dev_tools after install
```

- [ ] **Step 2: Parse the new flags**

Change:

```bash
FORCE_REVIEWER=0; SKIP_INSTALL=0
for a in "$@"; do
  case "$a" in
    --force-reviewer) FORCE_REVIEWER=1 ;;
    --skip-install)   SKIP_INSTALL=1 ;;
  esac
done
```

to:

```bash
FORCE_REVIEWER=0; SKIP_INSTALL=0; NO_SITE_TOOLS=0; NO_DEV_TOOLS=0
for a in "$@"; do
  case "$a" in
    --force-reviewer) FORCE_REVIEWER=1 ;;
    --skip-install)   SKIP_INSTALL=1 ;;
    --no-site-tools)  NO_SITE_TOOLS=1 ;;
    --no-dev-tools)   NO_DEV_TOOLS=1 ;;
  esac
done
```

- [ ] **Step 3: Apply the recipes after install**

Change:

```bash
if [ "$SKIP_INSTALL" -eq 0 ]; then
  info "Installing Drupal (profile: ${INSTALL_PROFILE})..."
  ./scripts/install-drupal "${INSTALL_PROFILE}"
  if [ -n "${MODULE_NAME}" ] && [ -d "${MODULE_PATH}" ]; then
    info "Enabling ${MODULE_NAME}..."
    ddev drush en "${MODULE_NAME}" -y && ddev drush cr && success "${MODULE_NAME} enabled."
  fi
else
  warn "--skip-install set: site not installed. Run ./scripts/install-drupal when ready."
fi
```

to:

```bash
if [ "$SKIP_INSTALL" -eq 0 ]; then
  info "Installing Drupal (profile: ${INSTALL_PROFILE})..."
  ./scripts/install-drupal "${INSTALL_PROFILE}"
  if [ -n "${MODULE_NAME}" ] && [ -d "${MODULE_PATH}" ]; then
    info "Enabling ${MODULE_NAME}..."
    ddev drush en "${MODULE_NAME}" -y && ddev drush cr && success "${MODULE_NAME} enabled."
  fi

  if [ "$NO_SITE_TOOLS" -eq 0 ]; then
    info "Applying recipes/site_tools..."
    ddev drush recipe recipes/site_tools -y && success "recipes/site_tools applied." || warn "recipes/site_tools failed to apply."
  else
    info "--no-site-tools set: skipping recipes/site_tools."
  fi

  if [ "$NO_DEV_TOOLS" -eq 0 ]; then
    info "Applying recipes/dev_tools..."
    ddev drush recipe recipes/dev_tools -y && success "recipes/dev_tools applied." || warn "recipes/dev_tools failed to apply."
  else
    info "--no-dev-tools set: skipping recipes/dev_tools."
  fi

  if [ "$NO_SITE_TOOLS" -eq 0 ] || [ "$NO_DEV_TOOLS" -eq 0 ]; then
    info "Re-exporting config after recipes..."
    ddev drush cex -y && success "Config exported." || warn "Config export failed; run 'ddev drush cex -y' manually."
  fi
else
  warn "--skip-install set: site not installed. Run ./scripts/install-drupal when ready."
fi
```

Ordering matters: `site_tools` applies before `dev_tools`, then one shared `drush cex` runs, so `site_tools`'s modules land in `config/sync` while `dev_tools`'s modules (`devel`, `environment_indicator_toolbar`) stay out via `config_exclude_modules` (Task 2).

- [ ] **Step 4: Verify the script still parses**

Run: `bash -n scripts/setup.sh`
Expected: no output, exit 0

- [ ] **Step 5: Commit**

```bash
git add scripts/setup.sh
git commit -m "feat: apply recipes/site_tools and recipes/dev_tools after install"
```

---

### Task 8: Run the full regression suite and confirm green

**Files:**
- None (verification only; fixes go back into whichever task's files if something fails).

**Interfaces:**
- Consumes: everything from Tasks 1-7.

- [ ] **Step 1: Run the suite**

Run: `./scripts/test-template.sh`

Expected: all assertions pass, including the ones added in Task 1 (`recipes/dev_tools/recipe.yml survives init.sh verbatim`, `recipes/site_tools/recipe.yml survives init.sh verbatim`, `assets/settings.local.php survives init.sh verbatim`, `assets/development.services.yml survives init.sh verbatim`, both YAML validity checks, `make -n recipe parses`), across every flavour/version/module/theme combination already in the suite.

If anything fails, fix the relevant task's files (do not weaken the assertion) and re-run before proceeding.

- [ ] **Step 2: No commit for this task** (verification only; any fixes are committed as part of the task they belong to).

---

### Task 9: Docs

**Files:**
- Modify: `README.md` (What you get, Common commands, Notes)
- Modify: `TEMPLATE.md:27` (token list for `scripts/setup.sh`)
- Modify: `PROJECT.md` ("What the template contains", Status)
- Modify: `PROMPTS.md` (Status)

**Interfaces:**
- None (documentation only).

- [ ] **Step 1: README.md, "What you get"**

Add a new bullet after the existing custom-code-workspace bullet (the one ending "...still get one `make check`."):

```markdown
- Local development settings applied automatically: `web/sites/default/settings.local.php` (Twig debug on, Twig cache off, the render/page/dynamic_page_cache bins null-backed) and `web/sites/development.services.yml`, copied from `assets/` by `scripts/setup.sh`. Two Recipes carry the rest: `recipes/dev_tools` (Devel, Environment Indicator, its toolbar integration) is local-only and excluded from configuration sync; `recipes/site_tools` (Admin Toolbar, Twig Tweak, ECA with its BPMN visual modeller) is meant for production and exports into `config/sync` on the next `drush cex`. `setup.sh` applies both after the site install (`--no-site-tools` / `--no-dev-tools` to skip either); `make recipe R=path` applies any recipe by hand.
```

- [ ] **Step 2: README.md, "Common commands"**

Add a line to the fenced command list, after `make module-ci`:

```
make recipe R=recipes/site_tools   # Apply a recipe
```

- [ ] **Step 3: README.md, "Notes"**

Add a new bullet at the end of the Notes section:

```markdown
- `config_exclude_modules` (set in `assets/settings.local.php`) only keeps a module's own enablement out of exported config; it does not exclude any config entities a dev-only module might create along the way. Projects with strict config discipline may want `drupal/config_split` for a more complete local/production split later; this template does not implement that, only documents the gap.
```

- [ ] **Step 4: TEMPLATE.md**

In the "Where tokens appear" list, change:

```markdown
- `scripts/setup.sh`, `MODULE_REPO`, `MODULE_PATH`, `MODULE_NAME`, `DDEV_NAME`, `DDEV_URL`, `SKILL_FORK`, `COMPOSER_PROJECT`, `INSTALL_PROFILE`
```

to:

```markdown
- `scripts/setup.sh`, `MODULE_REPO`, `MODULE_PATH`, `MODULE_NAME`, `DDEV_NAME`, `DDEV_URL`, `SKILL_FORK`, `COMPOSER_PROJECT`, `INSTALL_PROFILE`, `DRUPAL_TYPE`
```

- [ ] **Step 5: PROJECT.md, "What the template contains"**

Add a new bullet after the existing "Theme targets" bullet and before "CI":

```markdown
- Local dev recipes: assets/settings.local.php and assets/development.services.yml
  (Twig debug on, Twig cache off, render/page/dynamic_page_cache bins
  null-backed) are copied by setup.sh into web/sites/default/ and web/sites/
  only when absent, and setup.sh activates the include in
  web/sites/default/settings.php (uncomments Drupal's own commented block if
  present, appends the standard guarded include if not; never touches DDEV's
  own settings.ddev.php include). recipes/dev_tools (devel,
  environment_indicator, environment_indicator_toolbar) and recipes/site_tools
  (admin_toolbar, admin_toolbar_tools, twig_tweak, eca, eca_ui, bpmn_io) apply
  via ddev drush recipe after the site install, site_tools then dev_tools,
  followed by one more drush cex; config_exclude_modules in
  settings.local.php keeps devel and environment_indicator_toolbar out of
  that export (environment_indicator itself is not excluded, so it flows to
  every environment through normal config sync). ECA and bpmn_io are
  version-paired with Drupal core in setup.sh's composer require: ^3.1/^3.0
  on Drupal 11 (ECA 3.x needs core 11.3+), ^2.1/^2.0 on Drupal 10.
  drupal/core-recipe-unpack is required and pre-authorised
  (allow-plugins.drupal/core-recipe-unpack) alongside them. make recipe
  R=path applies any recipe; --no-site-tools and --no-dev-tools skip either
  recipe independently in setup.sh.
```

- [ ] **Step 6: PROJECT.md, Status**

Leave a placeholder line for now; Task 11 replaces it with the real verification results:

```markdown
Stage 11, local dev recipes: IN PROGRESS, see Task 11 of
template-docs/superpowers/plans/2026-08-06-local-dev-recipes.md for live verification.
```

- [ ] **Step 7: PROMPTS.md, Status**

Add a corresponding placeholder line at the end of the `## Status` list, same wording as Step 6, to be replaced by Task 11.

- [ ] **Step 8: Commit**

```bash
git add README.md TEMPLATE.md PROJECT.md PROMPTS.md
git commit -m "docs: document local dev recipes plumbing"
```

---

### Task 10: Static verification

**Files:** None (verification only).

- [ ] **Step 1: Full regression suite (re-confirm after docs commit touched nothing script-related)**

Run: `./scripts/test-template.sh`
Expected: all pass (same as Task 8; this re-run just guards against any accidental edit during Task 9).

- [ ] **Step 2: Shell syntax**

Run: `bash -n scripts/setup.sh && bash -n scripts/init.sh && bash -n scripts/install-drupal && echo OK`
Expected: `OK`

- [ ] **Step 3: Makefile**

Run: `make -n recipe R=recipes/site_tools && make -n help && echo OK`
Expected: `OK`

- [ ] **Step 4: PHP lint**

Run: `php -l assets/settings.local.php`
Expected: `No syntax errors detected`

- [ ] **Step 5: Executable bits**

Run: `test -x scripts/setup.sh && test -x scripts/init.sh && test -x scripts/install-drupal && echo OK`
Expected: `OK`

No commit (verification only).

---

### Task 11: Live verification

**Files:** None in the template repo itself; this task operates against a throwaway project created from the template.

Docker and DDEV are confirmed available in this environment, so this must be run live, not deferred.

- [ ] **Step 1: Stage a throwaway copy and initialise it**

```bash
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/recipe-live-verify.XXXXXX")"
rsync -a --exclude='.git' --exclude='_to_delete' --exclude='.superpowers' \
  --exclude='docs' --exclude='.claude/settings.local.json' \
  --exclude='node_modules' --exclude='package-lock.json' \
  "$(git rev-parse --show-toplevel)"/ "$STAGE"/
cd "$STAGE"
printf 'recipe_smoke\n\n\n\n\n\n\n\n\nlocalgov\n11\n' | ./scripts/init.sh
```

Confirm: `DRUPAL_TYPE=drupal11`, `COMPOSER_PROJECT=drupal/localgov_project`, `INSTALL_PROFILE=localgov` landed in `scripts/setup.sh` (`grep -E "DRUPAL_TYPE=|COMPOSER_PROJECT=|INSTALL_PROFILE=" scripts/setup.sh`).

- [ ] **Step 2: Run setup.sh end to end**

```bash
./scripts/setup.sh
```

Watch for: the "Site utility modules installed" and "Dev-only modules installed" success lines (composer resolves cleanly on `localgov 11` including both ECA packages at `^3.1`/`^3.0`), "settings.local.php include enabled" (or "appended", whichever branch fires), "recipes/site_tools applied.", "recipes/dev_tools applied.", "Config exported.".

If composer fails to resolve, capture the exact conflict, fix the offending constraint in `scripts/setup.sh` (Task 5), and re-run from Step 1 in a fresh `STAGE` dir; do not paper over a real resolution failure.

- [ ] **Step 3: Confirm Twig debug is active**

```bash
ddev drush ev '$twig = \Drupal::service("twig"); var_dump($twig->isDebug());'
```

Expected: `bool(true)`.

- [ ] **Step 4: Confirm caches are null-backed**

```bash
ddev drush ev '
foreach (["render", "page", "dynamic_page_cache"] as $bin) {
  $backend = \Drupal::service("cache_factory")->get($bin);
  echo $bin . ": " . get_class($backend) . PHP_EOL;
}
'
```

Expected: all three print `Drupal\Core\Cache\NullBackend`.

- [ ] **Step 5: Confirm config_exclude_modules kept devel and environment_indicator_toolbar out**

```bash
ddev drush cex -y
ddev drush config:get core.extension module | grep -E "devel|environment_indicator" || true
```

Expected: `environment_indicator` (and `admin_toolbar`, `twig_tweak`, `eca`, `eca_ui`, `bpmn_io`, `admin_toolbar_tools`) present; `devel` and `environment_indicator_toolbar` absent from the list.

- [ ] **Step 6: Confirm the indicator renders**

```bash
ddev drush ev 'echo \Drupal::config("environment_indicator.indicator")->get("name") . " / " . \Drupal::config("environment_indicator.indicator")->get("bg_color") . PHP_EOL;'
DDEV_SITE_URL="https://$(awk '/^name:/ {print $2; exit}' .ddev/config.yaml).ddev.site"
curl -sk "$DDEV_SITE_URL" | grep -qi "environment-indicator" && echo "indicator markup found" || echo "indicator markup NOT found"
```

Expected: `Local / #0b6623`, and `indicator markup found` (adjust the grep target if the rendered markup uses a different class/id; inspect the page source directly if the first grep misses, do not just report a pass without checking).

- [ ] **Step 7: Confirm both ECA packages actually resolved to the expected line**

```bash
ddev composer show drupal/eca | grep -E "^versions"
ddev composer show drupal/bpmn_io | grep -E "^versions"
```

Expected: `eca` on a `3.1.x` release, `bpmn_io` on a `3.0.x` release (this project was initialised as Drupal 11).

- [ ] **Step 8: Clean up**

State before running: this deletes the throwaway DDEV project's containers, database, and mutagen/docker volumes, and removes the staged directory from disk. Nothing in the real template repo or any other project is affected; `$STAGE` is a `mktemp -d` throwaway never committed anywhere.

```bash
ddev delete -Oy
cd "$(git -C "$(git rev-parse --show-toplevel)" rev-parse --show-toplevel)"
rm -rf "$STAGE"
```

- [ ] **Step 9: Update PROJECT.md and PROMPTS.md with the real result**

Replace the Task 9 placeholder lines in both files with a paragraph in the existing "Stage N: DONE" style (see Stage 10's paragraph in `PROJECT.md` for the level of detail expected: what was built, what was verified live, any caveats found). Include, at minimum: the flavour/version combination tested (`localgov 11`), that composer resolved cleanly, that Twig debug and null caches were confirmed, that `drush cex` showed the correct module split, that the indicator rendered, and any bug found and fixed during the run (if none, say so explicitly rather than omitting the point).

- [ ] **Step 10: Commit**

```bash
git add PROJECT.md PROMPTS.md
git commit -m "docs: record Stage 11 live verification"
```

---

## Self-Review Notes

- Spec coverage: composer wiring (Task 5), settings.local.php/development.services.yml (Task 2), setup.sh copy + settings.php activation (Task 6), two recipes (Task 3), Makefile recipe target (Task 4), setup.sh recipe application + flags + cex (Task 7), docs (Task 9), verification including live DDEV run (Tasks 8, 10, 11) all map directly to the seven numbered steps in the original request.
- The `config_exclude_modules` caveat requested for README.md is in Task 9 Step 3, worded to match the spec's own phrasing.
- `ctools`'s "required by composer, not in either recipe's install list, documented in a recipe comment" requirement is satisfied in Task 3 Step 2's `recipes/site_tools/recipe.yml` description.
- No task references a function, flag, or config key not verified against drupal.org or Drupal core's own documented behaviour in the Global Constraints section above.
