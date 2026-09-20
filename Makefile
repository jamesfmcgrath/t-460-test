##
## {{DDEV_NAME}} - dev environment
## Usage: make <target>
##

.PHONY: help start stop restart open logs xdebug-on xdebug-off si install enable cr recipe \
        snapshot restore import \
        test lint lint-fix stan check format format-check twig-lint twig-fix \
        spell lint-js lint-css vrt vrt-update module-ci subtheme component \
        mod-log mod-status mod-fetch mod-branch tag switch mr \
        guard-module-name guard-module-git guard-theme-name

MODULE = {{MODULE_PATH}}
MODULE_NAME = {{MODULE_NAME}}

THEME_PATH = {{THEME_PATH}}
THEME_NAME = {{THEME_NAME}}
THEME_LABEL = {{THEME_LABEL}}
DRUPAL_FLAVOUR = {{DRUPAL_FLAVOUR}}

# The custom code workspace. Every quality target below iterates over these
# paths, so a project can hold any number of custom modules and themes. Add a
# path here to widen the workspace. The module targets (enable, module-ci, the
# mod-* git helpers) stay scoped to $(MODULE); the theme targets stay scoped to
# $(THEME_PATH).
LINT_PATHS = web/modules/custom web/themes/custom

## == Environment ==============================================================

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make \033[36m<target>\033[0m\n\nTargets:\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

start: ## Start DDEV
	ddev start

stop: ## Stop DDEV
	ddev stop

restart: ## Restart DDEV
	ddev restart

open: ## Open site in browser
	ddev launch

logs: ## Tail web server logs
	ddev logs -f

xdebug-on: ## Enable Xdebug
	ddev xdebug on

xdebug-off: ## Disable Xdebug
	ddev xdebug off

## == Drupal ===================================================================

si: ## Fresh Drupal install (LocalGov profile)
	ddev drush si localgov -y
	ddev drush cr

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

cr: ## Clear Drupal caches
	ddev drush cr

## == Recipes ==================================================================

recipe: ## Apply a recipe (usage: make recipe R=recipes/site_tools)
	@test -n "$(R)" || (echo "Usage: make recipe R=recipes/site_tools" && exit 1)
	ddev drush recipe ../$(R)

## == Data =====================================================================

snapshot: ## Create a DDEV database/files snapshot
	ddev snapshot

restore: ## Restore the most recent DDEV snapshot
	ddev snapshot restore --latest

import: ## Import a database dump (usage: make import DB=path/to/dump.sql.gz)
	@test -n "$(DB)" || (echo "Usage: make import DB=path/to/dump.sql.gz" && exit 1)
	ddev import-db --file=$(DB)

## == Theme ====================================================================

guard-theme-name:
	@if [ -z "$(THEME_NAME)" ]; then \
	  echo "No theme configured. Add one under web/themes/custom/ and set THEME_NAME, THEME_LABEL, and THEME_PATH in the Makefile."; \
	  exit 1; \
	fi

subtheme: guard-theme-name ## Scaffold the custom theme at $(THEME_PATH)
	@if [ -d "$(THEME_PATH)" ]; then \
	  echo "$(THEME_PATH) already exists; not scaffolding over it."; \
	  exit 1; \
	fi
	@if [ "$(DRUPAL_FLAVOUR)" = "localgov" ] && [ -f web/themes/contrib/localgov_base/scripts/create_subtheme.sh ]; then \
	  echo "Creating a localgov_base subtheme: $(THEME_LABEL) ($(THEME_NAME))"; \
	  ddev exec sh -c 'cd web/themes/contrib/localgov_base && printf "%s\n%s\n" "$(THEME_LABEL)" "$(THEME_NAME)" | bash scripts/create_subtheme.sh'; \
	elif [ "$(DRUPAL_FLAVOUR)" = "localgov" ]; then \
	  echo "localgov_base not found at web/themes/contrib/localgov_base."; \
	  echo "Install it first (ddev composer require drupal/localgov_base), then re-run make subtheme."; \
	  exit 1; \
	else \
	  echo "Generating a starterkit theme: $(THEME_LABEL) ($(THEME_NAME))"; \
	  if ddev exec test -x vendor/bin/dr; then \
	    ddev exec vendor/bin/dr generate-theme $(THEME_NAME) --name "$(THEME_LABEL)" --path themes/custom; \
	  else \
	    ddev exec php web/core/scripts/drupal generate-theme $(THEME_NAME) --name "$(THEME_LABEL)" --path themes/custom; \
	  fi; \
	fi
	@marker="# Generic subtheme vocabulary (added by make subtheme)"; \
	if ! grep -qF "$$marker" .cspell-project-words.txt 2>/dev/null; then \
	  { \
	    echo ""; \
	    echo "$$marker"; \
	    for w in favicons msapplication mstile xlink evenodd linecap miterlimit focusable ckeditor subtheme colour colours; do \
	      grep -qxF "$$w" .cspell-project-words.txt 2>/dev/null || echo "$$w"; \
	    done; \
	  } >> .cspell-project-words.txt; \
	  echo "Added generic subtheme vocabulary to .cspell-project-words.txt so make spell passes on scaffolded theme output."; \
	fi
	@echo ""
	@echo "Next: ddev drush theme:enable $(THEME_NAME) -y"
	@echo "      ddev drush config:set system.theme default $(THEME_NAME) -y"
	@echo ""
	@echo "Note: shipped assets (logo.svg, favicon SVGs, package.json contributors) can"
	@echo "      carry proper-noun metadata (author/tool names). That is yours to keep"
	@echo "      or strip; make spell does not add proper nouns to the dictionary for you."

component: guard-theme-name ## Scaffold a single directory component (usage: make component NAME=card)
	@test -n "$(NAME)" || (echo "Usage: make component NAME=card" && exit 1)
	@echo "Generating component $(NAME) in $(THEME_NAME)."
	@echo "The remaining prompts (description, libraries, CSS/JS, props, slots) are yours to answer."
	@echo "Give every prop a type and a title; see the SDC section in AGENTS.md."
	@label="$$(echo '$(NAME)' | tr '_' ' ' | awk '{for(i=1;i<=NF;i++)$$i=toupper(substr($$i,1,1))substr($$i,2)}1')"; \
	ddev drush generate single-directory-component \
	  --answer "$(THEME_NAME)" --answer "$$label" --answer "$(NAME)"

## == Quality ==================================================================

test: ## Run PHPUnit across the custom code paths
	@for p in $(LINT_PATHS); do \
	  if find "$$p" -type f -print -quit 2>/dev/null | grep -q .; then \
	    ddev exec vendor/bin/phpunit -c web/core "$$p" || exit $$?; \
	  else \
	    echo "No files under $$p; skipping phpunit."; \
	  fi; \
	done

lint: ## Run PHPCS across the custom code paths
	@for p in $(LINT_PATHS); do \
	  if find "$$p" -type f -print -quit 2>/dev/null | grep -q .; then \
	    ddev exec vendor/bin/phpcs "$$p" || exit $$?; \
	  else \
	    echo "No files under $$p; skipping phpcs."; \
	  fi; \
	done

lint-fix: ## Auto-fix PHPCS violations with PHPCBF
	@for p in $(LINT_PATHS); do \
	  if find "$$p" -type f -print -quit 2>/dev/null | grep -q .; then \
	    ddev exec vendor/bin/phpcbf "$$p" || exit $$?; \
	  else \
	    echo "No files under $$p; skipping phpcbf."; \
	  fi; \
	done

stan: ## Run PHPStan static analysis across the custom code paths
	@for p in $(LINT_PATHS); do \
	  if find "$$p" -type f -print -quit 2>/dev/null | grep -q .; then \
	    ddev exec vendor/bin/phpstan analyse "$$p" || exit $$?; \
	  else \
	    echo "No files under $$p; skipping phpstan."; \
	  fi; \
	done

twig-lint: ## Lint Twig templates
	@for p in $(LINT_PATHS); do \
	  if find "$$p" -name '*.twig' -print -quit 2>/dev/null | grep -q .; then \
	    ddev exec vendor/bin/twig-cs-fixer lint "$$p" || exit $$?; \
	  else \
	    echo "No .twig files under $$p; skipping twig-cs-fixer."; \
	  fi; \
	done

twig-fix: ## Auto-fix Twig template violations
	@for p in $(LINT_PATHS); do \
	  if find "$$p" -name '*.twig' -print -quit 2>/dev/null | grep -q .; then \
	    ddev exec vendor/bin/twig-cs-fixer lint "$$p" --fix || exit $$?; \
	  else \
	    echo "No .twig files under $$p; skipping twig-cs-fixer."; \
	  fi; \
	done

spell: ## Spell-check the custom code with cspell
	@for p in $(LINT_PATHS); do \
	  if find "$$p" -type f -print -quit 2>/dev/null | grep -q .; then \
	    ddev exec npx cspell --no-progress --no-must-find-files "$$p/**" || exit $$?; \
	  else \
	    echo "No files found under $$p; skipping cspell."; \
	  fi; \
	done

lint-js: ## Lint custom JS/YAML with Drupal core's ESLint config
	@if [ ! -d web/core/node_modules ]; then \
	  echo "web/core/node_modules not found; run: ddev exec sh -c \"cd web/core && corepack enable && yarn install\""; \
	  exit 0; \
	fi; \
	for p in $(LINT_PATHS); do \
	  if find "$$p" \( -name '*.js' -o -name '*.yml' \) -print -quit 2>/dev/null | grep -q .; then \
	    ddev exec node web/core/node_modules/.bin/eslint "$$p" \
	      --no-error-on-unmatched-pattern \
	      --ignore-pattern='*.es6.js' \
	      --resolve-plugins-relative-to=web/core \
	      --ext=.js,.yml \
	      -c web/core/.eslintrc.passing.json || exit $$?; \
	  else \
	    echo "No .js or .yml files found under $$p; skipping eslint."; \
	  fi; \
	done

lint-css: ## Lint custom CSS with Drupal core's Stylelint config
	@if [ ! -d web/core/node_modules ]; then \
	  echo "web/core/node_modules not found; run: ddev exec sh -c \"cd web/core && corepack enable && yarn install\""; \
	  exit 0; \
	fi; \
	for p in $(LINT_PATHS); do \
	  if find "$$p" -name '*.css' -print -quit 2>/dev/null | grep -q .; then \
	    ddev exec web/core/node_modules/.bin/stylelint --config web/core/.stylelintrc.json "$$p/**/*.css" || exit $$?; \
	  else \
	    echo "No .css files found under $$p; skipping stylelint."; \
	  fi; \
	done

check: lint stan test twig-lint spell lint-js lint-css ## Run all quality checks (lint + stan + test + twig-lint + spell + lint-js + lint-css)

vrt: ## Visual regression test (Playwright); comparisons are authoritative on Linux/CI only, macOS runs are advisory
	npx playwright test tests/vrt

vrt-update: ## Regenerate VRT baselines; only commit baselines generated on Linux/CI, never from a macOS run
	npx playwright test tests/vrt --update-snapshots

format: ## Format front-end assets with Prettier (CSS/JS/JSON/YAML/MD)
	@for p in $(LINT_PATHS); do \
	  if find "$$p" -type f -print -quit 2>/dev/null | grep -q .; then \
	    ddev exec npx prettier --write --no-error-on-unmatched-pattern "$$p/**/*.{css,js,json,yml,yaml,md}" || exit $$?; \
	  else \
	    echo "No files found under $$p; skipping prettier."; \
	  fi; \
	done

format-check: ## Check Prettier formatting without writing
	@for p in $(LINT_PATHS); do \
	  if find "$$p" -type f -print -quit 2>/dev/null | grep -q .; then \
	    ddev exec npx prettier --check --no-error-on-unmatched-pattern "$$p/**/*.{css,js,json,yml,yaml,md}" || exit $$?; \
	  else \
	    echo "No files found under $$p; skipping prettier."; \
	  fi; \
	done

## == drupal.org pipeline parity ===============================================

module-ci: guard-module-name ## Copy the drupal.org GitLab CI pipeline into the module
	@if [ -f "$(MODULE)/.gitlab-ci.yml" ]; then \
	  echo "$(MODULE)/.gitlab-ci.yml already exists, not overwriting."; \
	  exit 1; \
	fi
	cp assets/module.gitlab-ci.yml "$(MODULE)/.gitlab-ci.yml"
	@echo "Copied assets/module.gitlab-ci.yml to $(MODULE)/.gitlab-ci.yml"

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
