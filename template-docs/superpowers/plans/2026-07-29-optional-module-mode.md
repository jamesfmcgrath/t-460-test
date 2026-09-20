# Optional Module Mode (Stage 7) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the custom module optional at `./scripts/init.sh` time, adding a site-only mode (Drupal or LocalGov site with no custom module) alongside the existing module mode, without changing module mode's behaviour.

**Architecture:** A blank answer to the module-name prompt in `scripts/init.sh` switches MODULE_NAME/MODULE_PATH/MODULE_REPO to site-only defaults and skips the label/path/repo prompts. Five new composed tokens (MODULE_INTRO, MODULE_LINE, MODULE_AFFECTS, PACKAGE_NAME, PACKAGE_DESCRIPTION), computed once as plain strings in `init.sh` and substituted like any other token, keep prose in AGENTS.md, `.claude/commands/a11y-check.md`, and `package.json` grammatical in both modes. `scripts/setup.sh` and the `Makefile` gain explicit `MODULE_NAME`-based guards so module-only steps (clone, drush enable, module git targets) skip cleanly instead of running on an empty or wrong value. `.github/workflows/ci.yml` gains a file-presence guard on the phpcs/phpstan steps, mirroring the existing twig/phpunit guards.

**Tech Stack:** Bash (`set -euo pipefail`), GNU Make, GitHub Actions YAML, no new dependencies.

## Global Constraints

- Module mode (non-blank module name) must not change in behaviour, prompts, or output, from this feature's perspective.
- No em dashes anywhere in code, comments, docs, or script output.
- Scripts stay executable (100755).
- Run `scripts/test-template.sh` before calling any script change done; it must stay network-free (no composer, no DDEV).
- Only `{{UPPER_SNAKE}}` names are template tokens; GitHub Actions `${{ }}` expressions must never be touched.
- `PROJECT.md` and `PROMPTS.md` are documented exceptions to the "no leftover tokens" check (they describe the token convention as literal text).
- Where a message must read a specific way, the required substring is quoted below; anything unquoted is guidance, not verbatim text.

---

### Task 1: Extend the regression suite with a failing site-only test

**Files:**
- Modify: `scripts/test-template.sh`

**Interfaces:**
- Produces: a `run_site_only <flavour> <version>` bash function, called once after the existing `COMBOS` loop, using the same `pass`/`fail`/`TOKEN_DOC_EXCEPTIONS` helpers already defined at the top of the file.

This test will fail until Tasks 2-8 are done. That is expected: it proves the suite actually exercises the new behaviour instead of vacuously passing.

- [ ] **Step 1: Add the `run_site_only` function**

Insert this function directly after the closing `}` of the existing `run_combo` function (before the `for combo in "${COMBOS[@]}"` loop):

```bash
run_site_only() {
  local flavour="$1" version="$2"
  local label="site-only $flavour $version"

  echo ""
  echo -e "${BOLD}== $label ==${RESET}"

  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/test-template-site.XXXXXX")"
  rsync -a --exclude='.git' --exclude='_to_delete' "$REPO_ROOT"/ "$tmp_dir"/ >/dev/null

  local init_log="$tmp_dir/.init-output.log"
  if (cd "$tmp_dir" && printf '\n\n\n\n\n%s\n%s\n' "$flavour" "$version" | ./scripts/init.sh) >"$init_log" 2>&1; then
    pass "$label: init.sh exits 0 with a blank module answer"
  else
    fail "$label: init.sh exited nonzero (see $init_log)"
  fi

  if [ ! -e "$tmp_dir/scripts/init.sh" ]; then
    pass "$label: scripts/init.sh removed itself"
  else
    fail "$label: scripts/init.sh still present"
  fi

  local exclude_args=()
  for ex in "${TOKEN_DOC_EXCEPTIONS[@]}"; do exclude_args+=(--exclude="$ex"); done
  local leftover
  leftover="$(grep -rlE '\{\{[A-Z_]+\}\}' "$tmp_dir" --exclude-dir=.git "${exclude_args[@]}" 2>/dev/null || true)"
  if [ -z "$leftover" ]; then
    pass "$label: no {{UPPER_SNAKE}} tokens remain outside ${TOKEN_DOC_EXCEPTIONS[*]}"
  else
    fail "$label: leftover tokens in: $(echo "$leftover" | tr '\n' ' ')"
  fi

  if (cd "$tmp_dir" && make -n help) >/dev/null 2>&1; then
    pass "$label: Makefile parses (make -n help)"
  else
    fail "$label: Makefile failed to parse"
  fi

  if bash -n "$tmp_dir/scripts/setup.sh" 2>/dev/null; then
    pass "$label: scripts/setup.sh bash -n"
  else
    fail "$label: scripts/setup.sh bash -n failed"
  fi

  rm -rf "$tmp_dir"
}
```

- [ ] **Step 2: Call it once after the COMBOS loop**

Change:

```bash
for combo in "${COMBOS[@]}"; do
  IFS='|' read -r flavour version drupal_type composer_project install_profile <<< "$combo"
  run_combo "$flavour" "$version" "$drupal_type" "$composer_project" "$install_profile"
done

echo ""
echo -e "${BOLD}== Summary ==${RESET}"
```

to:

```bash
for combo in "${COMBOS[@]}"; do
  IFS='|' read -r flavour version drupal_type composer_project install_profile <<< "$combo"
  run_combo "$flavour" "$version" "$drupal_type" "$composer_project" "$install_profile"
done

run_site_only "localgov" "11"

echo ""
echo -e "${BOLD}== Summary ==${RESET}"
```

- [ ] **Step 3: Run the suite and confirm the new checks fail (RED)**

Run: `./scripts/test-template.sh`

Expected: the four existing combos still pass (module mode unaffected so far), but the `site-only localgov 11` block fails on "init.sh exits 0 with a blank module answer" (current `init.sh` exits 1 on a blank module name) and likely on the leftover-tokens check too. Overall exit code nonzero. This confirms the test exercises real behaviour before any implementation exists.

- [ ] **Step 4: Commit**

```bash
git add scripts/test-template.sh
git commit -m "Add failing site-only regression test (Stage 7)"
```

---

### Task 2: scripts/init.sh - optional module name and composed tokens

**Files:**
- Modify: `scripts/init.sh`

**Interfaces:**
- Produces: five new tokens available to `sub()`: `MODULE_INTRO`, `MODULE_LINE`, `MODULE_AFFECTS`, `PACKAGE_NAME`, `PACKAGE_DESCRIPTION`. Later tasks (3, 4, 5) consume these exact names in AGENTS.md, `.claude/commands/a11y-check.md`, and `package.json`.
- Consumes: nothing from earlier tasks.

- [ ] **Step 1: Replace the already-initialised check**

Change:

```bash
if ! grep -q "{{MODULE_NAME}}" AGENTS.md 2>/dev/null; then
  warn "Already initialised (no {{MODULE_NAME}} token in AGENTS.md). Aborting."
  exit 1
fi
```

to:

```bash
if ! grep -q "{{MODULE_INTRO}}" AGENTS.md 2>/dev/null; then
  warn "Already initialised (no {{MODULE_INTRO}} token in AGENTS.md). Aborting."
  exit 1
fi
```

(This is safe to make first: `{{MODULE_INTRO}}` does not exist in AGENTS.md yet, so this check would currently always fail. Task 3 introduces the token it looks for. Do not run init.sh standalone until Task 3 is also done; the regression suite in Task 9 is the real verification point.)

- [ ] **Step 2: Make the module name prompt optional**

Change:

```bash
echo ""; info "Initialise this template"; echo ""
MODULE_NAME="$(ask 'Module machine name (e.g. localgov_bus_data)' '')"
[ -n "$MODULE_NAME" ] || { warn "Module name is required."; exit 1; }
DEF_LABEL="$(echo "$MODULE_NAME" | tr '_' ' ' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1))substr($i,2)}1')"
MODULE_LABEL="$(ask 'Module label' "$DEF_LABEL")"
MODULE_PATH="$(ask 'Module path' "web/modules/custom/$MODULE_NAME")"
MODULE_REPO="$(ask 'Module git URL (blank to skip cloning)' '')"
DEF_DDEV="$(echo "$MODULE_NAME" | tr '_' '-')-dev"
DDEV_NAME="$(ask 'DDEV project name' "$DEF_DDEV")"
```

to:

```bash
echo ""; info "Initialise this template"; echo ""
MODULE_NAME="$(ask 'Module machine name (blank for a site-only project)' '')"

if [ -n "$MODULE_NAME" ]; then
  DEF_LABEL="$(echo "$MODULE_NAME" | tr '_' ' ' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1))substr($i,2)}1')"
  MODULE_LABEL="$(ask 'Module label' "$DEF_LABEL")"
  MODULE_PATH="$(ask 'Module path' "web/modules/custom/$MODULE_NAME")"
  MODULE_REPO="$(ask 'Module git URL (blank to skip cloning)' '')"
  DEF_DDEV="$(echo "$MODULE_NAME" | tr '_' '-')-dev"
else
  MODULE_LABEL=""
  MODULE_PATH="web/modules/custom"
  MODULE_REPO=""
  DEF_DDEV="site-dev"
fi
DDEV_NAME="$(ask 'DDEV project name' "$DEF_DDEV")"
```

This preserves the exact prompt count and order for module mode (non-blank answer): label, path, repo, then DDEV name, unchanged from today. Site-only mode (blank answer) skips straight from the module-name prompt to the DDEV name prompt.

- [ ] **Step 3: Compute the five composed tokens**

After the existing flavour/version block (the `case "$FLAVOUR" in ... esac` block) and before the `echo ""; info "Applying..."` line, insert:

```bash
# Prose fragments that read naturally whether or not a module is configured.
if [ -n "$MODULE_NAME" ]; then
  MODULE_INTRO=", the \`$MODULE_NAME\` module for $CLIENT"
  MODULE_LINE="\`$MODULE_PATH/\`"
  MODULE_AFFECTS="the \`$MODULE_NAME\` module affects"
  PACKAGE_NAME="${MODULE_NAME}-dev"
  PACKAGE_DESCRIPTION="Front-end tooling for $MODULE_NAME ($CLIENT)."
else
  MODULE_INTRO=" for $CLIENT"
  MODULE_LINE="none yet, site-only project"
  MODULE_AFFECTS="the site includes"
  PACKAGE_NAME="$DDEV_NAME"
  PACKAGE_DESCRIPTION="Front-end tooling for $CLIENT."
fi
```

In module mode these evaluate to strings identical in meaning to what the template already produces today (verify: `MODULE_INTRO` reconstructs `, the \`$MODULE_NAME\` module for $CLIENT`, matching AGENTS.md's current wording exactly; `MODULE_LINE` reconstructs `` `$MODULE_PATH/` ``, matching AGENTS.md's current wording exactly; `PACKAGE_NAME` reconstructs `$MODULE_NAME-dev`, identical to today's `package.json` name).

- [ ] **Step 4: Add the five `sub()` calls**

Change:

```bash
sub MODULE_NAME      "$MODULE_NAME"
sub MODULE_LABEL     "$MODULE_LABEL"
sub MODULE_PATH      "$MODULE_PATH"
sub MODULE_REPO      "$MODULE_REPO"
sub DDEV_NAME        "$DDEV_NAME"
```

to:

```bash
sub MODULE_NAME         "$MODULE_NAME"
sub MODULE_LABEL        "$MODULE_LABEL"
sub MODULE_PATH         "$MODULE_PATH"
sub MODULE_REPO         "$MODULE_REPO"
sub MODULE_INTRO        "$MODULE_INTRO"
sub MODULE_LINE         "$MODULE_LINE"
sub MODULE_AFFECTS      "$MODULE_AFFECTS"
sub PACKAGE_NAME        "$PACKAGE_NAME"
sub PACKAGE_DESCRIPTION "$PACKAGE_DESCRIPTION"
sub DDEV_NAME           "$DDEV_NAME"
```

(leave the remaining `sub DDEV_URL`, `sub CLIENT`, `sub SKILL_FORK`, `sub DRUPAL_TYPE`, `sub INSTALL_PROFILE`, `sub COMPOSER_PROJECT` lines exactly as they are)

- [ ] **Step 5: Closing messages**

Change:

```bash
rm -f TEMPLATE.md scripts/test-template.sh
chmod +x scripts/setup.sh scripts/install-drupal 2>/dev/null || true
ok "Tokens applied ($FLAVOUR, Drupal $VERSION)."
info "Removing initialiser (scripts/init.sh)..."
rm -f scripts/init.sh
ok "Done. Next: ./scripts/setup.sh"
echo ""
warn "Review the git diff, then commit: git add -A && git commit -m 'Initialise from template'"
```

to:

```bash
rm -f TEMPLATE.md scripts/test-template.sh
chmod +x scripts/setup.sh scripts/install-drupal 2>/dev/null || true
if [ -n "$MODULE_NAME" ]; then
  ok "Tokens applied ($FLAVOUR, Drupal $VERSION, module $MODULE_NAME)."
else
  ok "Tokens applied ($FLAVOUR, Drupal $VERSION, site-only)."
fi
info "Removing initialiser (scripts/init.sh)..."
rm -f scripts/init.sh
ok "Done. Next: ./scripts/setup.sh"
echo ""
if [ -z "$MODULE_NAME" ]; then
  warn "Site-only project: to add a module later, create it under web/modules/custom/ and set MODULE and MODULE_NAME in the Makefile."
fi
warn "Review the git diff, then commit: git add -A && git commit -m 'Initialise from template'"
```

- [ ] **Step 6: Syntax check**

Run: `bash -n scripts/init.sh`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/init.sh
git commit -m "Make the module name prompt optional in init.sh"
```

---

### Task 3: AGENTS.md - consume MODULE_INTRO and MODULE_LINE

**Files:**
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: `{{MODULE_INTRO}}` and `{{MODULE_LINE}}` tokens produced by Task 2.

- [ ] **Step 1: Update the intro sentence**

Change:

```
This is a Drupal 10/11 project, the `{{MODULE_NAME}}` module for {{CLIENT}}. Follow these guidelines when working on Drupal code.
```

to:

```
This is a Drupal 10/11 project{{MODULE_INTRO}}. Follow these guidelines when working on Drupal code.
```

- [ ] **Step 2: Update the Module context line**

Change:

```
- **Module:** `{{MODULE_PATH}}/`
```

to:

```
- **Module:** {{MODULE_LINE}}
```

- [ ] **Step 3: Verify by hand**

Confirm `grep -c '{{MODULE_INTRO}}\|{{MODULE_LINE}}' AGENTS.md` reports 2, and `grep -c '{{MODULE_NAME}}' AGENTS.md` reports 0 (the raw token no longer appears directly in this file; it is only ever seen composed inside `MODULE_INTRO`/`MODULE_LINE` at substitution time).

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md
git commit -m "AGENTS.md: read naturally in site-only mode"
```

---

### Task 4: package.json - consume PACKAGE_NAME and PACKAGE_DESCRIPTION

**Files:**
- Modify: `package.json`

**Interfaces:**
- Consumes: `{{PACKAGE_NAME}}` and `{{PACKAGE_DESCRIPTION}}` tokens produced by Task 2.

**Why this is needed:** with the raw `{{MODULE_NAME}}` token, a blank module name would leave `"name": "-dev"` (a package name most tools treat as valid but nobody would call sensible) and `"description": "Front-end tooling for  (a local council)."` (a double space and a dangling reference to nothing). `PACKAGE_NAME`/`PACKAGE_DESCRIPTION` are pre-composed by init.sh so both modes read correctly, and in module mode they reconstruct byte-for-byte what the template produces today.

- [ ] **Step 1: Edit package.json**

Change:

```json
{
  "name": "{{MODULE_NAME}}-dev",
  "private": true,
  "description": "Front-end tooling for {{MODULE_NAME}} ({{CLIENT}}).",
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

to:

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

- [ ] **Step 2: Commit**

```bash
git add package.json
git commit -m "package.json: valid name/description in both modes"
```

---

### Task 5: a11y-check.md - consume MODULE_AFFECTS

**Files:**
- Modify: `.claude/commands/a11y-check.md`

**Interfaces:**
- Consumes: `{{MODULE_AFFECTS}}` token produced by Task 2.

- [ ] **Step 1: Reword the page-selection line**

Change:

```
Audit one or more pages of `{{DDEV_URL}}` for accessibility. If paths are given as arguments, test those. Otherwise test a representative set of page types the `{{MODULE_NAME}}` module affects (at minimum: the front page, one listing page, one detail page, and one page with a form).
```

to:

```
Audit one or more pages of `{{DDEV_URL}}` for accessibility. If paths are given as arguments, test those. Otherwise test a representative set of page types {{MODULE_AFFECTS}} (at minimum: the front page, one listing page, one detail page, and one page with a form).
```

- [ ] **Step 2: Commit**

```bash
git add .claude/commands/a11y-check.md
git commit -m "a11y-check.md: natural page-selection wording in both modes"
```

---

### Task 6: scripts/setup.sh - guard module-specific steps

**Files:**
- Modify: `scripts/setup.sh`

**Interfaces:**
- Consumes: `MODULE_NAME`, `MODULE_REPO`, `MODULE_PATH` shell variables already assigned near the top of the script from `{{MODULE_NAME}}`/`{{MODULE_REPO}}`/`{{MODULE_PATH}}` tokens (unchanged by this task).

- [ ] **Step 1: Guard the clone step and add the site-only message**

Change:

```bash
# --- Optional: clone the target module ---
if [ -n "${MODULE_REPO}" ] && [ ! -d "${MODULE_PATH}" ]; then
  info "Cloning module into ${MODULE_PATH}..."
  mkdir -p "$(dirname "${MODULE_PATH}")"
  git clone "${MODULE_REPO}" "${MODULE_PATH}" && success "Module cloned." || warn "Module clone failed; clone manually."
fi
```

to:

```bash
# --- Optional: clone the target module ---
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

- [ ] **Step 2: Guard the enable step**

Change:

```bash
# --- Install the site ---
if [ "$SKIP_INSTALL" -eq 0 ]; then
  info "Installing Drupal (profile: ${INSTALL_PROFILE})..."
  ./scripts/install-drupal "${INSTALL_PROFILE}"
  if [ -d "${MODULE_PATH}" ]; then
    info "Enabling ${MODULE_NAME}..."
    ddev drush en "${MODULE_NAME}" -y && ddev drush cr && success "${MODULE_NAME} enabled."
  fi
else
  warn "--skip-install set: site not installed. Run ./scripts/install-drupal when ready."
fi
```

to:

```bash
# --- Install the site ---
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

This is the only behavioural change in the file: previously `[ -d "${MODULE_PATH}" ]` alone gated the enable step, which is wrong in site-only mode because `MODULE_PATH` (`web/modules/custom`) exists as soon as Drupal is scaffolded, so `ddev drush en ""` would have run. Adding the `MODULE_NAME` check fixes that and matches module mode's existing behaviour exactly when a module name is set (that branch is untouched).

- [ ] **Step 3: Syntax check**

Run: `bash -n scripts/setup.sh`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/setup.sh
git commit -m "setup.sh: guard module clone/enable on module name, not just path"
```

---

### Task 7: Makefile - guard module git targets and enable

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Produces: `MODULE_NAME` make variable, `guard-module-name` and `guard-module-git` internal targets, usable as prerequisites.
- Consumes: `MODULE` variable (unchanged), `{{MODULE_NAME}}` token (already used elsewhere in the file today).

- [ ] **Step 1: Add the MODULE_NAME variable and tidy the header/PHONY list**

Change:

```makefile
##
## {{DDEV_NAME}} - dev environment for the {{MODULE_NAME}} module
## Usage: make <target>
##

.PHONY: help start stop restart open logs si install enable cr \
        test lint lint-fix stan check format format-check twig-lint twig-fix \
        mod-log mod-status mod-fetch mod-branch tag switch mr

MODULE = {{MODULE_PATH}}
```

to:

```makefile
##
## {{DDEV_NAME}} - dev environment
## Usage: make <target>
##

.PHONY: help start stop restart open logs si install enable cr \
        test lint lint-fix stan check format format-check twig-lint twig-fix \
        mod-log mod-status mod-fetch mod-branch tag switch mr \
        guard-module-name guard-module-git

MODULE = {{MODULE_PATH}}
MODULE_NAME = {{MODULE_NAME}}
```

(The header comment no longer names the module, so it does not read with a double space in site-only mode. `MODULE_NAME` is a new variable that reuses the existing `{{MODULE_NAME}}` token, which is already substituted correctly in both modes by Task 2: empty in site-only, the module name otherwise.)

- [ ] **Step 2: Add guard-module-name and use it on enable**

Change:

```makefile
install: ## Clean install, choose a profile (Standard/LocalGov/Microsites/...)
	./scripts/install-drupal

enable: ## Enable the {{MODULE_NAME}} module
	ddev drush en {{MODULE_NAME}} -y
	ddev drush cr
```

to:

```makefile
install: ## Clean install, choose a profile (Standard/LocalGov/Microsites/...)
	./scripts/install-drupal

guard-module-name:
	@if [ -z "$(MODULE_NAME)" ]; then \
	  echo "No module configured (site-only project). Add one under web/modules/custom/ and set MODULE_NAME in the Makefile."; \
	  exit 1; \
	fi

enable: guard-module-name ## Enable the module
	ddev drush en $(MODULE_NAME) -y
	ddev drush cr
```

- [ ] **Step 3: Add guard-module-git and use it on all module git targets**

Change:

```makefile
## == Maintainer (module git) ==================================================

mod-log: ## Recent module commits (usage: make mod-log or make mod-log N=40)
	git -C $(MODULE) log --oneline -$${N:-20}

mod-status: ## Git status of the module
	git -C $(MODULE) status

mod-fetch: ## Fetch latest from upstream
	git -C $(MODULE) fetch origin
	@echo ""
	@git -C $(MODULE) log --oneline -5 origin/$$(git -C $(MODULE) rev-parse --abbrev-ref HEAD)

mod-branch: ## List branches and show current
	git -C $(MODULE) branch -av

tag: ## Tag and push a release  (usage: make tag VERSION=1.0.0-alpha1)
	@test -n "$(VERSION)" || (echo "Usage: make tag VERSION=1.0.0-alpha1" && exit 1)
	git -C $(MODULE) tag $(VERSION)
	git -C $(MODULE) push origin $(VERSION)
	@echo "Tagged and pushed $(VERSION)"

switch: ## Switch module branch  (usage: make switch BRANCH=1.0.x)
	@test -n "$(BRANCH)" || (echo "Usage: make switch BRANCH=1.0.x" && exit 1)
	git -C $(MODULE) checkout $(BRANCH)

mr: ## Check out a contributor MR for review  (usage: make mr MR=123)
	@test -n "$(MR)" || (echo "Usage: make mr MR=123" && exit 1)
	git -C $(MODULE) fetch origin merge-requests/$(MR)/head:mr-$(MR)
	git -C $(MODULE) checkout mr-$(MR)
```

to:

```makefile
## == Maintainer (module git) ==================================================

guard-module-git:
	@if [ -z "$(MODULE_NAME)" ] || [ ! -d "$(MODULE)/.git" ]; then \
	  echo "No module git checkout to operate on (site-only project)."; \
	  exit 1; \
	fi

mod-log: guard-module-git ## Recent module commits (usage: make mod-log or make mod-log N=40)
	git -C $(MODULE) log --oneline -$${N:-20}

mod-status: guard-module-git ## Git status of the module
	git -C $(MODULE) status

mod-fetch: guard-module-git ## Fetch latest from upstream
	git -C $(MODULE) fetch origin
	@echo ""
	@git -C $(MODULE) log --oneline -5 origin/$$(git -C $(MODULE) rev-parse --abbrev-ref HEAD)

mod-branch: guard-module-git ## List branches and show current
	git -C $(MODULE) branch -av

tag: guard-module-git ## Tag and push a release  (usage: make tag VERSION=1.0.0-alpha1)
	@test -n "$(VERSION)" || (echo "Usage: make tag VERSION=1.0.0-alpha1" && exit 1)
	git -C $(MODULE) tag $(VERSION)
	git -C $(MODULE) push origin $(VERSION)
	@echo "Tagged and pushed $(VERSION)"

switch: guard-module-git ## Switch module branch  (usage: make switch BRANCH=1.0.x)
	@test -n "$(BRANCH)" || (echo "Usage: make switch BRANCH=1.0.x" && exit 1)
	git -C $(MODULE) checkout $(BRANCH)

mr: guard-module-git ## Check out a contributor MR for review  (usage: make mr MR=123)
	@test -n "$(MR)" || (echo "Usage: make mr MR=123" && exit 1)
	git -C $(MODULE) fetch origin merge-requests/$(MR)/head:mr-$(MR)
	git -C $(MODULE) checkout mr-$(MR)
```

`test`, `lint`, `lint-fix`, `stan`, `check`, `format`, `format-check`, `twig-lint`, `twig-fix` are unchanged: they already operate on `$(MODULE)`, which is `web/modules/custom` in site-only mode, correctly scoping to all future custom modules per the spec.

- [ ] **Step 4: Verify with make -n**

Run: `make -n help` and `make -n enable` (the latter is expected to print the guard's `echo` and exit nonzero only once a module-free Makefile exists; against the current repo's own token-bearing Makefile, `make -n` still just needs to parse without a syntax error).
Expected: `make -n help` prints the target list with no errors.

- [ ] **Step 5: Commit**

```bash
git add Makefile
git commit -m "Makefile: guard module git targets and enable on MODULE_NAME"
```

---

### Task 8: .github/workflows/ci.yml - guard phpcs/phpstan on empty module dir

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `{{MODULE_PATH}}` token (unchanged).

- [ ] **Step 1: Guard the PHPCS and PHPStan steps**

Change:

```yaml
      - name: PHPCS (Drupal, DrupalPractice)
        run: vendor/bin/phpcs

      - name: PHPStan
        run: vendor/bin/phpstan analyse --no-progress
```

to:

```yaml
      - name: PHPCS (Drupal, DrupalPractice)
        run: |
          if find {{MODULE_PATH}} -type f -print -quit | grep -q .; then
            vendor/bin/phpcs
          else
            echo "No files found under {{MODULE_PATH}}; skipping phpcs."
          fi

      - name: PHPStan
        run: |
          if find {{MODULE_PATH}} -type f -print -quit | grep -q .; then
            vendor/bin/phpstan analyse --no-progress
          else
            echo "No files found under {{MODULE_PATH}}; skipping phpstan."
          fi
```

This mirrors the existing guard style used a few lines below for the Twig CS Fixer step and the PHPUnit step in the same job, so the job stays internally consistent.

- [ ] **Step 2: YAML sanity check**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))" ` (or the ruby equivalent `ruby -ryaml -e "YAML.load_file('.github/workflows/ci.yml')"` if PyYAML is not installed)
Expected: no output, exit 0.

- [ ] **Step 3: Confirm the `${{ }}` GitHub Actions expression count is unchanged**

Run: `grep -oF '${{' .github/workflows/ci.yml | wc -l`
Expected: same count as before this edit (this task only edits the `run:` shell blocks, which use `{{MODULE_PATH}}` template tokens, not `${{ }}` GitHub Actions expressions).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci.yml: skip phpcs/phpstan cleanly when web/modules/custom is empty"
```

---

### Task 9: Run the full regression suite (confirm GREEN) and fix stragglers

**Files:**
- None expected, this task is verification. If it turns anything up, the fix belongs in the file it points at.

- [ ] **Step 1: Run the suite**

Run: `./scripts/test-template.sh`

Expected: all four existing combos pass exactly as before (module mode unaffected), and the new `site-only localgov 11` block now passes all five assertions added in Task 1. Overall exit code 0.

- [ ] **Step 2: If anything fails, fix the specific file it names and re-run**

Do not proceed to Task 10 until the suite exits 0.

- [ ] **Step 3: Also check phpcs.xml.dist and phpstan.neon by inspection (no code change expected)**

Run: `grep -n MODULE_PATH phpcs.xml.dist phpstan.neon .claude/settings.local.json.dist`

Confirm each remaining `{{MODULE_PATH}}` usage sits in a context that is valid with the value `web/modules/custom`: `phpcs.xml.dist`'s `<file>{{MODULE_PATH}}</file>` and `phpstan.neon`'s `paths: - {{MODULE_PATH}}` both accept a plain directory, and `.claude/settings.local.json.dist`'s four `Bash(... {{MODULE_PATH}})` allowlist entries are still valid Claude Code permission strings pointing at a real directory. Also confirm `phpcs.xml.dist`'s `<ruleset name="{{MODULE_NAME}}">` becomes `<ruleset name="">` in site-only mode: this is syntactically valid XML and the `name` attribute is cosmetic only (PHPCS does not require it to be non-empty), so no change is needed there. Note in the final report that this was checked by inspection, not a live `phpcs` run (no PHP toolchain available in this environment); flag it for live verification alongside the rest of the site-only spin-up.

- [ ] **Step 4: Commit if Step 2 required fixes**

Only commit here if Step 2 changed something; otherwise there is nothing to commit for this task.

---

### Task 10: Documentation

**Files:**
- Modify: `README.md`
- Modify: `TEMPLATE.md`
- Modify: `PROJECT.md`
- Modify: `PROMPTS.md`

- [ ] **Step 1: README.md - "Use it" section**

Change:

```
   It asks for the module name and path, DDEV site, client, skill fork, and the Drupal flavour (`localgov` or `vanilla`) and version (`11` or `10`). It tokenises every file, then removes itself.
```

to:

```
   It asks for the module name (leave blank for a site-only project, which skips the module label/path/repo prompts) and path, DDEV site, client, skill fork, and the Drupal flavour (`localgov` or `vanilla`) and version (`11` or `10`). It tokenises every file, then removes itself.
```

- [ ] **Step 2: README.md - "What you get"**

Change:

```
- A DDEV config and a one-command `scripts/setup.sh` that starts DDEV, scaffolds a Drupal project (LocalGov or vanilla, chosen at init), installs the site, adds dev tooling, and enables your module.
```

to:

```
- A DDEV config and a one-command `scripts/setup.sh` that starts DDEV, scaffolds a Drupal project (LocalGov or vanilla, chosen at init), installs the site, adds dev tooling, and enables your module if you configured one (site-only projects skip that step).
```

- [ ] **Step 3: README.md - Tokens table**

Change:

```
| `{{MODULE_NAME}}` | `localgov_bus_data` |
```

to:

```
| `{{MODULE_NAME}}` | `localgov_bus_data` (blank for a site-only project) |
```

- [ ] **Step 4: TEMPLATE.md - token table**

Change:

```
| `{{MODULE_NAME}}` | Module machine name | `my_module` |
```

to:

```
| `{{MODULE_NAME}}` | Module machine name | `my_module` (blank for a site-only project) |
```

- [ ] **Step 5: TEMPLATE.md - "Where tokens appear" list**

Change:

```
- `AGENTS.md`, project context, module path, DDEV site, client (CLAUDE.md is only the @AGENTS.md import stub, no tokens)
- `.claude/commands/a11y-check.md`, DDEV site URL, module name
```

to:

```
- `AGENTS.md`, project context (composed via `MODULE_INTRO`/`MODULE_LINE` so it reads naturally with or without a module), DDEV site, client (CLAUDE.md is only the @AGENTS.md import stub, no tokens)
- `.claude/commands/a11y-check.md`, DDEV site URL, page-selection wording (`MODULE_AFFECTS`)
```

Change:

```
- `package.json`, `MODULE_NAME`, `MODULE_PATH`, `CLIENT`
```

to:

```
- `package.json`, `PACKAGE_NAME`, `PACKAGE_DESCRIPTION`, `MODULE_PATH`
```

- [ ] **Step 6: TEMPLATE.md - new "Site-only mode" section**

Insert a new section after "## Non-LocalGov projects" (at the end of the file):

```markdown

## Site-only mode

Leave the module machine name prompt blank in `init.sh` to skip module mode entirely: no module label, path, or repo prompt, `MODULE_PATH` becomes `web/modules/custom` (so quality tooling still scopes to whatever custom modules get added later), and `MODULE_NAME`/`MODULE_REPO` stay empty. Five composed tokens, `MODULE_INTRO`, `MODULE_LINE`, `MODULE_AFFECTS`, `PACKAGE_NAME`, and `PACKAGE_DESCRIPTION`, are not prompted directly; `init.sh` derives them from `MODULE_NAME` and the other answers so AGENTS.md, `.claude/commands/a11y-check.md`, and `package.json` read naturally in both modes. To add a module later, create it under `web/modules/custom/` and set `MODULE` and `MODULE_NAME` in the `Makefile`.
```

- [ ] **Step 7: PROJECT.md - template contents**

Change:

```
- scripts/init.sh: one-time tokeniser. Prompts for module name/path, DDEV site,
  client, skill fork, and Drupal flavour (localgov|vanilla) + version (11|10).
  Substitutes {{TOKENS}} across files, then removes itself, TEMPLATE.md, and
  scripts/test-template.sh. Must preserve file executable bits (it writes back
  into files rather than mv-ing a temp over them, and re-chmods the scripts).
```

to:

```
- scripts/init.sh: one-time tokeniser. Prompts for module name/path, DDEV site,
  client, skill fork, and Drupal flavour (localgov|vanilla) + version (11|10).
  A blank module name selects site-only mode (Stage 7): the label/path/repo
  prompts are skipped, MODULE_PATH becomes web/modules/custom, and five
  composed tokens (MODULE_INTRO, MODULE_LINE, MODULE_AFFECTS, PACKAGE_NAME,
  PACKAGE_DESCRIPTION) keep AGENTS.md, a11y-check.md, and package.json reading
  naturally either way. Substitutes {{TOKENS}} across files, then removes
  itself, TEMPLATE.md, and scripts/test-template.sh. Must preserve file
  executable bits (it writes back into files rather than mv-ing a temp over
  them, and re-chmods the scripts).
```

- [ ] **Step 8: PROJECT.md - conventions**

Change:

```
- Keep both flavour branches (localgov, vanilla) and both versions (10, 11)
  working.
```

to:

```
- Keep both flavour branches (localgov, vanilla) and both versions (10, 11)
  working.
- Keep both usage modes working: site-only (blank module name) and module
  mode (a module name given). Module mode's behaviour must never change as a
  side effect of site-only work, or vice versa.
```

- [ ] **Step 9: PROJECT.md - Status section**

Append a new sentence to the end of the existing Status paragraph (after "...still needs live verification, as before."):

```
Stage 7, optional module (site-only mode): tokeniser and file-invariant work
DONE, covered by scripts/test-template.sh's site-only regression check; the
full site-only DDEV/composer spin-up still needs a live run, same caveat as
the rest of setup.sh.
```

- [ ] **Step 10: PROMPTS.md - Status header**

Change:

```
- Stage 7, optional module (site-only mode): OPEN (prompt below).
```

to:

```
- Stage 7, optional module (site-only mode): DONE. init.sh, setup.sh, and the
  Makefile all support a blank module name; scripts/test-template.sh gained a
  site-only regression check. The DDEV/composer spin-up still needs a live
  run.
```

- [ ] **Step 11: Commit**

```bash
git add README.md TEMPLATE.md PROJECT.md PROMPTS.md
git commit -m "Document site-only mode (Stage 7)"
```

---

### Task 11: Smoke-test both modes end to end

**Files:**
- None (verification only, throwaway copies).

- [ ] **Step 1: Run the full regression suite one more time**

Run: `./scripts/test-template.sh`
Expected: exit 0, all combos and the site-only check pass.

- [ ] **Step 2: Manual throwaway init in site-only mode**

```bash
tmp_site="$(mktemp -d)"
rsync -a --exclude='.git' "$(pwd)"/ "$tmp_site"/
cd "$tmp_site"
printf '\n\n\n\n\n%s\n%s\n' "localgov" "11" | ./scripts/init.sh
```

Check by hand: no `{{UPPER_SNAKE}}` tokens remain outside PROJECT.md/PROMPTS.md (`grep -rlE '\{\{[A-Z_]+\}\}' . --exclude-dir=.git --exclude=PROJECT.md --exclude=PROMPTS.md`), `${{ }}` count in `.github/workflows/ci.yml` unchanged, `bash -n scripts/setup.sh` and `bash -n scripts/install-drupal` both pass, `make -n help` parses, `scripts/setup.sh` and `scripts/install-drupal` are still mode 100755, `scripts/init.sh` and `TEMPLATE.md` are gone, and `AGENTS.md`'s Module line reads "none yet, site-only project".

Then clean up: `cd - && rm -rf "$tmp_site"`

- [ ] **Step 3: Manual throwaway init in module mode**

```bash
tmp_mod="$(mktemp -d)"
rsync -a --exclude='.git' "$(pwd)"/ "$tmp_mod"/
cd "$tmp_mod"
printf 'smoke_test_mod\n\n\n\n\n\n\n\n%s\n%s\n' "localgov" "11" | ./scripts/init.sh
```

Check by hand: the same invariants as Step 2, plus `smoke_test_mod` present in AGENTS.md, Makefile, `.claude/settings.local.json.dist`, `.claude/commands/a11y-check.md`, and `package.json`'s `name` field reads `smoke_test_mod-dev` exactly (proving module mode is byte-for-byte unchanged).

Then clean up: `cd - && rm -rf "$tmp_mod"`

- [ ] **Step 4: Report status honestly**

State plainly in the final summary that the DDEV/composer/npm spin-up (`scripts/setup.sh` actually running `ddev start`, `composer create-project`, `ddev drush en`) was not exercised live in either mode, consistent with this repo's existing "needs live verification" convention, since Docker/DDEV are not available in this working environment. Do not claim the live spin-up was verified.

---

## Self-Review Notes

- Spec coverage: items 1-8 of the original request map to Tasks 2 (item 1), 6 (item 2), 7 (item 3), 8+9 (item 4), 3 (item 5), 1+9 (item 6), 10 (item 7), 11 (item 8).
- Module mode parity: Task 2 Step 3 explicitly reconstructs today's exact strings for `MODULE_INTRO`, `MODULE_LINE`, and `PACKAGE_NAME` when `MODULE_NAME` is non-blank, so AGENTS.md/package.json render identically to the current template in module mode. Task 6 and Task 7's guards are additive (`[ -n "${MODULE_NAME}" ] && ...`) and only change behaviour when `MODULE_NAME` is blank, an input module mode never provides.
- No placeholders: every step above contains the literal before/after text or literal shell block to apply.
