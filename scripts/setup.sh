#!/usr/bin/env bash
# {{DDEV_NAME}} - one-command dev environment spin-up.
# Run from the repo root: ./scripts/setup.sh
# Flags:
#   --force-reviewer   re-fetch drupal-reviewer even if present
#   --skip-install     scaffold + tooling only, do not install the Drupal site
#   --no-site-tools    skip applying recipes/site_tools after install
#   --no-dev-tools     skip applying recipes/dev_tools after install
set -euo pipefail

BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
info()    { echo -e "${BOLD}> $*${RESET}"; }
success() { echo -e "${GREEN}OK $*${RESET}"; }
warn()    { echo -e "${YELLOW}!! $*${RESET}"; }
error()   { echo -e "${RED}xx $*${RESET}"; exit 1; }

MODULE_REPO="{{MODULE_REPO}}"
MODULE_PATH="{{MODULE_PATH}}"
MODULE_NAME="{{MODULE_NAME}}"
SKILL_FORK="{{SKILL_FORK}}"
COMPOSER_PROJECT="{{COMPOSER_PROJECT}}"
INSTALL_PROFILE="{{INSTALL_PROFILE}}"
DRUPAL_TYPE="{{DRUPAL_TYPE}}"
REVIEWER_REF="main"
REVIEWER_URL="https://raw.githubusercontent.com/${SKILL_FORK}/drupal-agent-resources/${REVIEWER_REF}/.claude/agents/drupal-reviewer.md"

FORCE_REVIEWER=0; SKIP_INSTALL=0; NO_SITE_TOOLS=0; NO_DEV_TOOLS=0
for a in "$@"; do
  case "$a" in
    --force-reviewer) FORCE_REVIEWER=1 ;;
    --skip-install)   SKIP_INSTALL=1 ;;
    --no-site-tools)  NO_SITE_TOOLS=1 ;;
    --no-dev-tools)   NO_DEV_TOOLS=1 ;;
  esac
done

echo ""; echo -e "${BOLD}=== {{DDEV_NAME}} setup ===${RESET}"; echo ""

# --- Prerequisites ---
info "Checking prerequisites..."
command -v ddev &>/dev/null || error "DDEV not found. Install from https://ddev.com then re-run."
command -v git  &>/dev/null || error "git not found."
success "DDEV: $(ddev version | head -1)"

# --- Agent resources (skills) ---
info "Installing Claude Code / Cursor skills via agr..."
# Skills are a convenience, not a prerequisite for a working site, so any agr
# failure (most commonly: not run inside a git repository) warns and carries
# on instead of aborting the whole spin-up under set -euo pipefail.
agr_failed() {
  warn "agr could not install the skills; continuing without them."
  warn "agr must run inside a git repository. If this project is not one yet:"
  warn "  git init && git add -A && git commit -m 'Initialise from template'"
  warn "Then re-run: agr sync"
}
if command -v agr &>/dev/null; then
  if [ -f "agr.lock" ]; then
    if agr sync; then
      success "Skills installed from agr.lock (agr sync)."
    else
      agr_failed
    fi
  else
    if agr add madsnorgaard/drupal-agent-resources/drupal-expert --overwrite \
      && agr add madsnorgaard/drupal-agent-resources/ddev-expert --overwrite \
      && agr add "${SKILL_FORK}/drupal-agent-resources/drupal-localgov" --overwrite; then
      success "Skills installed (drupal-expert, ddev-expert, drupal-localgov)."
    else
      agr_failed
    fi
  fi
else
  warn "agr not found, skipping skills."
  warn "Install uv (https://docs.astral.sh/uv/), then: uv tool install agr && agr sync"
fi

# --- drupal-reviewer agent (tracked copy is canonical) ---
info "Ensuring drupal-reviewer agent..."
mkdir -p .claude/agents
if [ -f ".claude/agents/drupal-reviewer.md" ] && [ "$FORCE_REVIEWER" -eq 0 ]; then
  success "drupal-reviewer already present (tracked copy kept)."
elif command -v curl &>/dev/null; then
  curl -fsSL -o .claude/agents/drupal-reviewer.md "${REVIEWER_URL}" \
    && success "drupal-reviewer fetched (${REVIEWER_REF})." \
    || warn "Could not fetch drupal-reviewer. Save manually from ${REVIEWER_URL}"
else
  warn "curl not found. Save drupal-reviewer manually from ${REVIEWER_URL}"
fi

# --- Claude settings.local.json ---
if [ ! -f ".claude/settings.local.json" ] && [ -f ".claude/settings.local.json.dist" ]; then
  info "Creating .claude/settings.local.json from dist..."
  sed "s|<absolute-path-to-repo>|$(pwd)|g" .claude/settings.local.json.dist > .claude/settings.local.json
  success ".claude/settings.local.json created."
fi

# --- DDEV ---
info "Starting DDEV..."
ddev start
success "DDEV running."

# --- Drupal codebase (scaffold without clobbering template files) ---
if [ ! -f "composer.json" ]; then
  info "Scaffolding Drupal project: ${COMPOSER_PROJECT}"
  ddev exec "rm -rf /tmp/scaffold && composer create-project ${COMPOSER_PROJECT} /tmp/scaffold --no-install --no-interaction"
  # cp -rn preserves the template's own files (CLAUDE.md, Makefile, scripts,
  # etc.) by skipping anything that collides by name; upstream files under a
  # name this template does not use still land untouched, which is what the
  # prune list right below cleans up.
  ddev exec "cp -rn /tmp/scaffold/. /var/www/html/ && rm -rf /tmp/scaffold"
  success "Project scaffolded."

  # --- Prune upstream scaffold artefacts ---
  # drupal/localgov_project (and the vanilla/cms equivalents) is
  # scaffolded in wholesale via composer create-project above, including its
  # own CI and local-dev-environment files. None of this applies to a project
  # built from this template: CI here is GitHub Actions
  # (.github/workflows/ci.yml, kept), local dev is DDEV only, and
  # phpstan.neon scopes to LINT_PATHS rather than the whole web/ tree a
  # baseline would have been generated against. Keeping the list here, next
  # to the copy step it cleans up after, is what makes it easy to audit when
  # the upstream scaffold changes.
  #   .github/workflows/test.yml - upstream's own GitHub Actions CI. It can
  #     never pass here: it derives its composer ref from the branch name
  #     (dev-main on a main branch), which is not a published version.
  #   .gitlab-ci.yml             - upstream's GitLab CI config; this
  #     template's own CI is GitHub Actions only.
  #   .gitpod.yml, .gitpod/      - upstream's cloud dev environment.
  #   .lando.dist.yml, .lando/   - upstream's alternative local dev
  #     environment; this template standardises on DDEV.
  #   .vscode/                  - upstream's editor/xdebug config, half
  #     wired for Lando, which this template does not use.
  #   README_FRONTEND_TOOLING.md - documents `lando`/`ddev` custom commands
  #     (eslint-js, stylelint, install-frontend) this template does not
  #     define; actively misleading if left in place.
  #   phpstan-baseline.php      - a baseline for upstream's own unscoped
  #     phpstan run against the whole web/ tree; not referenced by this
  #     template's own phpstan.neon, which scopes to LINT_PATHS.
  info "Pruning upstream scaffold artefacts..."
  SCAFFOLD_PRUNE=(
    ".github/workflows/test.yml"
    ".gitlab-ci.yml"
    ".gitpod.yml"
    ".gitpod"
    ".lando.dist.yml"
    ".lando"
    ".vscode"
    "README_FRONTEND_TOOLING.md"
    "phpstan-baseline.php"
  )
  for path in "${SCAFFOLD_PRUNE[@]}"; do
    if [ -e "$path" ]; then
      rm -rf -- "$path"
      echo "  removed $path"
    fi
  done
  success "Upstream scaffold artefacts pruned."
fi
info "Installing Composer dependencies..."
ddev composer install
success "Dependencies installed."

# --- Custom code workspace ---
# The quality tooling (LINT_PATHS in the Makefile, phpcs.xml.dist, phpstan.neon,
# and CI) scopes to these paths. Create them up front so a bare phpcs or phpstan
# run works on a project that has only modules, or only a theme, so far.
mkdir -p web/modules/custom web/themes/custom

# --- Dev tooling (lint / static analysis / tests) ---
info "Adding PHP dev tooling..."
# Pre-authorise the Composer plugins the dev tooling pulls in, so the require
# below is not aborted by a project's allow-plugins allowlist. Drupal CMS ships
# a stricter allowlist than the localgov and vanilla project templates, so
# phpstan/extension-installer (via mglaman/phpstan-drupal) and the phpcodesniffer
# installer (via drupal/coder) must be allowed first.
ddev composer config --no-plugins allow-plugins.dealerdirect/phpcodesniffer-composer-installer true 2>/dev/null || true
ddev composer config --no-plugins allow-plugins.phpstan/extension-installer true 2>/dev/null || true
if ddev composer require --dev --no-interaction -W \
  drupal/core-dev drupal/coder mglaman/phpstan-drupal \
  phpstan/phpstan phpstan/phpstan-deprecation-rules \
  vincentlanglet/twig-cs-fixer drush/drush; then
  success "PHP dev tooling installed."
else
  warn "Some dev dependencies failed to install; add them manually."
fi

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

# --- Prettier ---
if [ -f "package.json" ]; then
  info "Installing Prettier (npm)..."
  ddev exec "npm install" && success "Prettier installed." || warn "npm install failed; run 'ddev exec npm install' later."
fi

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
if grep -q "debug: true" "web/sites/development.services.yml" 2>/dev/null; then
  success "Twig debug confirmed active in web/sites/development.services.yml."
else
  warn "Twig debug not confirmed active in web/sites/development.services.yml (a different development.services.yml, likely from the installed Drupal distribution, may already be in place). Check web/sites/development.services.yml manually, or delete it and re-run setup.sh to install this template's version."
fi

SETTINGS_PHP="web/sites/default/settings.php"
if [ -f "$SETTINGS_PHP" ]; then
  ACTIVE_INCLUDE="if (file_exists(\$app_root . '/' . \$site_path . '/settings.local.php')) {"
  COMMENTED_INCLUDE="# if (file_exists(\$app_root . '/' . \$site_path . '/settings.local.php')) {"
  if grep -qFx "$ACTIVE_INCLUDE" "$SETTINGS_PHP" 2>/dev/null; then
    success "settings.php already includes settings.local.php."
  elif grep -qFx "$COMMENTED_INCLUDE" "$SETTINGS_PHP" 2>/dev/null; then
    info "Enabling the settings.local.php include in settings.php..."
    line_no="$(grep -nFx "$COMMENTED_INCLUDE" "$SETTINGS_PHP" | head -1 | cut -d: -f1)"
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

# --- Install the site ---
if [ "$SKIP_INSTALL" -eq 0 ]; then
  info "Installing Drupal (profile: ${INSTALL_PROFILE})..."
  ./scripts/install-drupal "${INSTALL_PROFILE}"
  if [ -n "${MODULE_NAME}" ] && [ -d "${MODULE_PATH}" ]; then
    info "Enabling ${MODULE_NAME}..."
    ddev drush en "${MODULE_NAME}" -y && ddev drush cr && success "${MODULE_NAME} enabled."
  fi

  if [ "$NO_SITE_TOOLS" -eq 0 ]; then
    info "Applying recipes/site_tools..."
    ddev drush recipe ../recipes/site_tools -y && success "recipes/site_tools applied." || warn "recipes/site_tools failed to apply."
  else
    info "--no-site-tools set: skipping recipes/site_tools."
  fi

  if [ "$NO_DEV_TOOLS" -eq 0 ]; then
    info "Applying recipes/dev_tools..."
    ddev drush recipe ../recipes/dev_tools -y && success "recipes/dev_tools applied." || warn "recipes/dev_tools failed to apply."
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

echo ""; success "Setup complete."
echo "  Site:  ${BOLD}{{DDEV_URL}}${RESET}"
echo "  Open:  ddev launch        Login: ddev drush uli"
echo "  Tasks: make help"
