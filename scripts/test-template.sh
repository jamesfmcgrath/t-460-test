#!/usr/bin/env bash
# Regression suite for the bare template. Exercises scripts/init.sh across
# every supported flavour/version combo, and across all four module/theme
# combinations, in a throwaway copy, then asserts tokeniser + file invariants.
# Combos drive init.sh through its flags with stdin closed, except one that
# keeps the interactive prompt path covered via init_input.
# No network, no composer, no DDEV: the live spin-up remains a manual
# verification step (see template-docs/PROJECT.md).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BOLD="\033[1m"; GREEN="\033[32m"; RED="\033[31m"; RESET="\033[0m"

TOTAL_PASS=0
TOTAL_FAIL=0

pass() { TOTAL_PASS=$((TOTAL_PASS + 1)); echo -e "  ${GREEN}OK${RESET}   $*"; }
fail() { TOTAL_FAIL=$((TOTAL_FAIL + 1)); echo -e "  ${RED}FAIL${RESET} $*"; }

# One entry per supported flavour/version pair:
#   flavour|version|expected DRUPAL_TYPE|expected COMPOSER_PROJECT|expected INSTALL_PROFILE
# Add a line here when a new flavour lands; this is the only place a new combo
# needs to register its expected derived values. cms is Drupal 11 only, and its
# INSTALL_PROFILE is a recipe path rather than a profile machine name.
COMBOS=(
  "localgov|11|drupal11|drupal/localgov_project|localgov"
  "localgov|10|drupal10|drupal/localgov_project:^3.0|localgov"
  "vanilla|11|drupal11|drupal/recommended-project:^11|standard"
  "vanilla|10|drupal10|drupal/recommended-project:^10|standard"
  "cms|11|drupal11|drupal/cms|recipes/drupal_cms_starter"
)

MODULE_NAME="regress_mod"
MODULE_LABEL="Regress Mod"
MODULE_PATH="web/modules/custom/regress_mod"
MODULE_REPO="https://example.invalid/regress_mod.git"
THEME_NAME="regress_theme"
THEME_LABEL="Regress Theme"
DDEV_NAME="regress-dev"
DDEV_URL="https://regress-dev.ddev.site"
# The ampersand is deliberate: real council names contain one, and & is special
# in a sed replacement, so this also proves init.sh escapes its values.
CLIENT="Regress & District Council"
SKILL_FORK="regressowner"

# The scratch file one combo injects before running init.sh, to prove the
# substitution list is discovered rather than hand-maintained.
INJECTED_FILE="scratch-token-check.md"

# Files that document the {{UPPER_SNAKE}} token convention as literal text
# (companion maintainer docs), not files init.sh substitutes into.
TOKEN_DOC_EXCEPTIONS=("template-docs/PROJECT.md" "template-docs/PROMPTS.md" "template-docs/memory.md")

yaml_parse() {
  local f="$1"
  if command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -e "YAML.load_file(ARGV[0])" "$f" >/dev/null 2>&1
  elif python3 -c "import yaml" >/dev/null 2>&1; then
    python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$f" >/dev/null 2>&1
  else
    echo "  no YAML parser (ruby or python3+PyYAML) available" >&2
    return 1
  fi
}

# Feed init.sh's prompts in order. A blank line accepts the offered default.
# Prompt order: module name, [module label, module path, module git URL],
# theme name, [theme label], DDEV name, DDEV URL, client, skill fork,
# flavour, version. Used by the one combo that covers the interactive path;
# every other combo goes through init_flags below.
init_input() { # init_input <module_name> <theme_name> <flavour> <version>
  local module="$1" theme="$2" flavour="$3" version="$4"
  printf '%s\n' "$module"
  [ -n "$module" ] && printf '\n\n\n'
  printf '%s\n' "$theme"
  [ -n "$theme" ] && printf '\n'
  printf '\n\n\n\n'
  printf '%s\n%s\n' "$flavour" "$version"
}

# The non-interactive form: one flag per prompt, one line per argument so the
# caller can read it back into an array. An empty module or theme is passed as
# --module=/--theme= (the explicit-empty form), which must select site-only or
# no-theme mode rather than falling back to the prompt.
init_flags() { # init_flags <module_name> <theme_name> <flavour> <version>
  local module="$1" theme="$2" flavour="$3" version="$4"
  local args=()
  if [ -n "$module" ]; then
    args+=(--module "$module" --module-label "$MODULE_LABEL"
           --module-path "$MODULE_PATH" --module-repo "$MODULE_REPO")
  else
    args+=(--module=)
  fi
  if [ -n "$theme" ]; then
    args+=(--theme "$theme" --theme-label "$THEME_LABEL")
  else
    args+=(--theme=)
  fi
  args+=(--ddev-name "$DDEV_NAME" --ddev-url "$DDEV_URL" --client "$CLIENT"
         --skill-fork "$SKILL_FORK" --flavour "$flavour" --version "$version")
  printf '%s\n' "${args[@]}"
}

stage_copy() { # stage_copy <dest>
  rsync -a --exclude='.git' --exclude='_to_delete' --exclude='.superpowers' \
    --exclude='template-docs' --exclude='.claude/settings.local.json' \
    --exclude='node_modules' --exclude='package-lock.json' \
    "$REPO_ROOT"/ "$1"/ >/dev/null
}

assert_no_leftover_tokens() { # assert_no_leftover_tokens <dir> <label>
  local dir="$1" label="$2" ex leftover
  local exclude_args=()
  for ex in "${TOKEN_DOC_EXCEPTIONS[@]}"; do exclude_args+=(--exclude="$ex"); done
  leftover="$(grep -rlE '\{\{[A-Z_]+\}\}' "$dir" --exclude-dir=.git "${exclude_args[@]}" 2>/dev/null || true)"
  if [ -z "$leftover" ]; then
    pass "$label: no {{UPPER_SNAKE}} tokens remain outside ${TOKEN_DOC_EXCEPTIONS[*]}"
  else
    fail "$label: leftover tokens in: $(echo "$leftover" | tr '\n' ' ')"
  fi
}

# Theme-mode assertions. Run for every combo: with a theme name the THEME_*
# tokens must carry the answers through; without one they must still resolve
# to something sane and the Makefile must still parse.
assert_theme() { # assert_theme <dir> <label> <theme_name>
  local dir="$1" label="$2" theme="$3"

  if [ -n "$theme" ]; then
    if grep -q "^THEME_NAME = $theme$" "$dir/Makefile" 2>/dev/null; then
      pass "$label: Makefile THEME_NAME is $theme"
    else
      fail "$label: Makefile THEME_NAME is not $theme"
    fi
    if grep -q "^THEME_PATH = web/themes/custom/$theme$" "$dir/Makefile" 2>/dev/null; then
      pass "$label: Makefile THEME_PATH is web/themes/custom/$theme"
    else
      fail "$label: Makefile THEME_PATH is not web/themes/custom/$theme"
    fi
    if grep -q "^THEME_LABEL = $THEME_LABEL$" "$dir/Makefile" 2>/dev/null; then
      pass "$label: Makefile THEME_LABEL is $THEME_LABEL"
    else
      fail "$label: Makefile THEME_LABEL is not $THEME_LABEL"
    fi
    for f in AGENTS.md .claude/commands/a11y-check.md; do
      if grep -q "$theme" "$dir/$f" 2>/dev/null; then
        pass "$label: $f contains $theme"
      else
        fail "$label: $f missing $theme"
      fi
    done
  else
    if grep -q "^THEME_NAME = $" "$dir/Makefile" 2>/dev/null; then
      pass "$label: Makefile THEME_NAME is empty (no custom theme)"
    else
      fail "$label: Makefile THEME_NAME is not empty"
    fi
    if grep -q "no custom theme" "$dir/AGENTS.md" 2>/dev/null; then
      pass "$label: AGENTS.md records that there is no custom theme"
    else
      fail "$label: AGENTS.md does not record the no-theme state"
    fi
  fi

  if (cd "$dir" && make -n subtheme) >/dev/null 2>&1; then
    pass "$label: make -n subtheme parses"
  else
    fail "$label: make -n subtheme failed"
  fi
  if (cd "$dir" && make -n component NAME=demo_card) >/dev/null 2>&1; then
    pass "$label: make -n component parses"
  else
    fail "$label: make -n component failed"
  fi
}

# Shared per-run assertions: the invariants that must hold after init.sh no
# matter which module/theme/flavour combination was answered.
assert_common() { # assert_common <dir> <label>
  local dir="$1" label="$2"

  if [ ! -e "$dir/scripts/init.sh" ]; then pass "$label: scripts/init.sh removed itself"; else fail "$label: scripts/init.sh still present"; fi
  if [ ! -e "$dir/TEMPLATE.md" ]; then pass "$label: TEMPLATE.md removed"; else fail "$label: TEMPLATE.md still present"; fi
  if [ ! -e "$dir/scripts/test-template.sh" ]; then pass "$label: scripts/test-template.sh removed"; else fail "$label: scripts/test-template.sh still present"; fi
  if [ ! -e "$dir/template-docs" ]; then pass "$label: template-docs/ removed"; else fail "$label: template-docs/ still present"; fi

  assert_no_leftover_tokens "$dir" "$label"

  if bash -n "$dir/scripts/setup.sh" 2>/dev/null; then pass "$label: scripts/setup.sh bash -n"; else fail "$label: scripts/setup.sh bash -n failed"; fi
  if bash -n "$dir/scripts/install-drupal" 2>/dev/null; then pass "$label: scripts/install-drupal bash -n"; else fail "$label: scripts/install-drupal bash -n failed"; fi
  if [ -x "$dir/scripts/setup.sh" ]; then pass "$label: scripts/setup.sh executable"; else fail "$label: scripts/setup.sh not executable"; fi
  if [ -x "$dir/scripts/install-drupal" ]; then pass "$label: scripts/install-drupal executable"; else fail "$label: scripts/install-drupal not executable"; fi

  if (cd "$dir" && make -n help) >/dev/null 2>&1; then pass "$label: make -n help parses"; else fail "$label: make -n help failed"; fi
  if (cd "$dir" && make -n module-ci) >/dev/null 2>&1; then pass "$label: make -n module-ci parses"; else fail "$label: make -n module-ci failed"; fi

  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$dir/.claude/settings.local.json.dist" 2>/dev/null; then
    pass "$label: settings.local.json.dist is valid JSON"
  else
    fail "$label: settings.local.json.dist is not valid JSON"
  fi
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$dir/package.json" 2>/dev/null; then
    pass "$label: package.json is valid JSON"
  else
    fail "$label: package.json is not valid JSON"
  fi
  if yaml_parse "$dir/.github/workflows/ci.yml"; then pass "$label: ci.yml is valid YAML"; else fail "$label: ci.yml is not valid YAML"; fi
  if yaml_parse "$dir/.ddev/config.yaml"; then pass "$label: .ddev/config.yaml is valid YAML"; else fail "$label: .ddev/config.yaml is not valid YAML"; fi
  if python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1])" "$dir/phpcs.xml.dist" 2>/dev/null; then
    pass "$label: phpcs.xml.dist is valid XML"
  else
    fail "$label: phpcs.xml.dist is not valid XML"
  fi

  # assets/module.gitlab-ci.yml holds no {{TOKENS}}, so it must survive verbatim.
  if diff -q "$REPO_ROOT/assets/module.gitlab-ci.yml" "$dir/assets/module.gitlab-ci.yml" >/dev/null 2>&1; then
    pass "$label: assets/module.gitlab-ci.yml survives init.sh verbatim"
  else
    fail "$label: assets/module.gitlab-ci.yml changed or missing after init.sh"
  fi

  # setup.sh's scaffold-prune list holds no {{TOKENS}} either, so it must
  # survive init.sh verbatim (a stray substitution could silently narrow or
  # widen what a fresh project prunes from the upstream scaffold).
  prune_block() { sed -n '/^  SCAFFOLD_PRUNE=($/,/^  )$/p' "$1"; }
  if diff -q <(prune_block "$REPO_ROOT/scripts/setup.sh") <(prune_block "$dir/scripts/setup.sh") >/dev/null 2>&1; then
    pass "$label: setup.sh SCAFFOLD_PRUNE list survives init.sh verbatim"
  else
    fail "$label: setup.sh SCAFFOLD_PRUNE list changed after init.sh"
  fi

  # recipes/, the local dev settings templates, and the VRT/scan-urls files
  # hold no {{TOKENS}} either, so they must survive init.sh verbatim too.
  for f in recipes/dev_tools/recipe.yml recipes/site_tools/recipe.yml \
    assets/settings.local.php assets/development.services.yml \
    scan-urls.json playwright.config.mjs tests/vrt/vrt.spec.mjs; do
    if diff -q "$REPO_ROOT/$f" "$dir/$f" >/dev/null 2>&1; then
      pass "$label: $f survives init.sh verbatim"
    else
      fail "$label: $f changed or missing after init.sh"
    fi
  done

  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$dir/scan-urls.json" 2>/dev/null; then
    pass "$label: scan-urls.json is valid JSON"
  else
    fail "$label: scan-urls.json is not valid JSON"
  fi

  if (cd "$dir" && make -n vrt) >/dev/null 2>&1; then
    pass "$label: make -n vrt parses"
  else
    fail "$label: make -n vrt failed"
  fi
  if (cd "$dir" && make -n vrt-update) >/dev/null 2>&1; then
    pass "$label: make -n vrt-update parses"
  else
    fail "$label: make -n vrt-update failed"
  fi

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

  # The custom code workspace is the scoping unit for the quality tooling.
  for f in phpcs.xml.dist phpstan.neon package.json .github/workflows/ci.yml; do
    if grep -q 'web/modules/custom' "$dir/$f" 2>/dev/null && grep -q 'web/themes/custom' "$dir/$f" 2>/dev/null; then
      pass "$label: $f covers both custom code paths"
    else
      fail "$label: $f does not cover both custom code paths"
    fi
  done
  if grep -q '^LINT_PATHS = web/modules/custom web/themes/custom$' "$dir/Makefile" 2>/dev/null; then
    pass "$label: Makefile LINT_PATHS covers both custom code paths"
  else
    fail "$label: Makefile LINT_PATHS does not cover both custom code paths"
  fi
}

assert_file_contains() { # assert_file_contains <file> <literal> <message>
  if grep -qF "$2" "$1" 2>/dev/null; then pass "$3"; else fail "$3"; fi
}

# The answers file records what init.sh resolved, in every mode, prompted and
# derived values alike.
assert_answers() { # assert_answers <dir> <label> <module> <theme> <drupal_type> <composer_project> <install_profile>
  local dir="$1" label="$2" module="$3" theme="$4" drupal_type="$5"
  local composer_project="$6" install_profile="$7" expected
  if [ -f "$dir/template.answers" ]; then
    pass "$label: template.answers written and kept"
  else
    fail "$label: template.answers missing"
    return
  fi
  for expected in "MODULE_NAME=$module" "THEME_NAME=$theme" \
    "DRUPAL_TYPE=$drupal_type" "COMPOSER_PROJECT=$composer_project" \
    "INSTALL_PROFILE=$install_profile"; do
    if grep -qxF "$expected" "$dir/template.answers"; then
      pass "$label: template.answers records $expected"
    else
      fail "$label: template.answers missing $expected"
    fi
  done
}

# Values only a flag-driven run supplies, so each flag mapping is exercised.
# The interactive combo accepts every default and skips these.
assert_flag_values() { # assert_flag_values <dir> <label> <module>
  local dir="$1" label="$2" module="$3" expected
  assert_file_contains "$dir/.ddev/config.yaml" "name: $DDEV_NAME" "$label: .ddev/config.yaml carries --ddev-name"
  assert_file_contains "$dir/AGENTS.md" "$DDEV_URL" "$label: AGENTS.md carries --ddev-url"
  assert_file_contains "$dir/AGENTS.md" "$CLIENT" "$label: AGENTS.md carries --client"
  assert_file_contains "$dir/README.md" "$CLIENT" "$label: README.md carries --client"
  assert_file_contains "$dir/agr.toml" "$SKILL_FORK/drupal-agent-resources" "$label: agr.toml carries --skill-fork"
  if [ -n "$module" ]; then
    assert_file_contains "$dir/Makefile" "MODULE = $MODULE_PATH" "$label: Makefile carries --module-path"
    assert_file_contains "$dir/scripts/setup.sh" "MODULE_REPO=\"$MODULE_REPO\"" "$label: setup.sh carries --module-repo"
  fi
  for expected in "DDEV_NAME=$DDEV_NAME" "DDEV_URL=$DDEV_URL" "CLIENT=$CLIENT" \
    "SKILL_FORK=$SKILL_FORK"; do
    if grep -qxF "$expected" "$dir/template.answers" 2>/dev/null; then
      pass "$label: template.answers records $expected"
    else
      fail "$label: template.answers missing $expected"
    fi
  done
}

run_combo() { # run_combo <flavour> <version> <drupal_type> <composer_project> <install_profile> <module_name> <theme_name> <label_suffix> [mode] [inject]
  local flavour="$1" version="$2" drupal_type="$3" composer_project="$4" install_profile="$5"
  local module="$6" theme="$7" suffix="${8:-}" mode="${9:-flags}" inject="${10:-}"
  local label="$flavour $version${suffix:+ ($suffix)}"

  echo ""
  echo -e "${BOLD}== $label ==${RESET}"

  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/test-template.XXXXXX")"
  stage_copy "$tmp_dir"

  local ci_before ci_after
  ci_before="$(grep -oF '${{' "$tmp_dir/.github/workflows/ci.yml" | wc -l | tr -d ' ')"

  # A file that did not exist when the template was written must still be
  # substituted: the file list is discovered, not hand-maintained.
  if [ "$inject" = "1" ]; then
    printf 'Injected before init.sh, for %s\n' '{{CLIENT}}' > "$tmp_dir/$INJECTED_FILE"
  fi

  local init_log="$tmp_dir/.init-output.log"
  if [ "$mode" = "interactive" ]; then
    if (cd "$tmp_dir" && init_input "$module" "$theme" "$flavour" "$version" | ./scripts/init.sh) >"$init_log" 2>&1; then
      pass "$label: init.sh exits 0"
    else
      fail "$label: init.sh exited nonzero (see $init_log)"
    fi
  else
    local flags=() arg
    while IFS= read -r arg; do flags+=("$arg"); done < <(init_flags "$module" "$theme" "$flavour" "$version")
    # stdin closed: a flag run that still reaches a prompt fails here.
    if (cd "$tmp_dir" && ./scripts/init.sh "${flags[@]}" </dev/null) >"$init_log" 2>&1; then
      pass "$label: init.sh exits 0 with no tty interaction"
    else
      fail "$label: init.sh exited nonzero (see $init_log)"
    fi
  fi

  assert_common "$tmp_dir" "$label"
  assert_answers "$tmp_dir" "$label" "$module" "$theme" "$drupal_type" "$composer_project" "$install_profile"
  if [ "$mode" != "interactive" ]; then
    assert_flag_values "$tmp_dir" "$label" "$module"
  fi

  if [ "$inject" = "1" ]; then
    if grep -qF "$CLIENT" "$tmp_dir/$INJECTED_FILE" 2>/dev/null; then
      pass "$label: newly added $INJECTED_FILE was discovered and substituted"
    else
      fail "$label: newly added $INJECTED_FILE was not substituted"
    fi
  fi

  # GitHub Actions ${{ ... }} expressions must survive untouched.
  ci_after="$(grep -oF '${{' "$tmp_dir/.github/workflows/ci.yml" | wc -l | tr -d ' ')"
  if [ "$ci_before" = "$ci_after" ]; then
    pass "$label: \${{ count in ci.yml unchanged ($ci_before)"
  else
    fail "$label: \${{ count in ci.yml changed ($ci_before -> $ci_after)"
  fi

  # Module answers land where they apply.
  if [ -n "$module" ]; then
    for f in AGENTS.md Makefile .claude/settings.local.json.dist .claude/commands/a11y-check.md; do
      if grep -q "$module" "$tmp_dir/$f" 2>/dev/null; then
        pass "$label: $f contains $module"
      else
        fail "$label: $f missing $module"
      fi
    done
  else
    if grep -q '^MODULE_NAME = $' "$tmp_dir/Makefile" 2>/dev/null; then
      pass "$label: Makefile MODULE_NAME is empty (no module)"
    else
      fail "$label: Makefile MODULE_NAME is not empty"
    fi
  fi

  assert_theme "$tmp_dir" "$label" "$theme"

  # Flavour/version answers land in the derived values.
  if grep -qF "$drupal_type" "$tmp_dir/.ddev/config.yaml" 2>/dev/null; then
    pass "$label: .ddev/config.yaml contains $drupal_type"
  else
    fail "$label: .ddev/config.yaml missing $drupal_type"
  fi
  if grep -qF "$composer_project" "$tmp_dir/scripts/setup.sh" 2>/dev/null; then
    pass "$label: scripts/setup.sh contains $composer_project"
  else
    fail "$label: scripts/setup.sh missing $composer_project"
  fi
  if grep -qF "$install_profile" "$tmp_dir/scripts/setup.sh" 2>/dev/null; then
    pass "$label: scripts/setup.sh contains $install_profile"
  else
    fail "$label: scripts/setup.sh missing $install_profile"
  fi
  if grep -qF "$install_profile" "$tmp_dir/.github/workflows/ci.yml" 2>/dev/null; then
    pass "$label: ci.yml contains $install_profile"
  else
    fail "$label: ci.yml missing $install_profile"
  fi

  rm -rf "$tmp_dir"
}

for combo in "${COMBOS[@]}"; do
  IFS='|' read -r flavour version drupal_type composer_project install_profile <<< "$combo"
  run_combo "$flavour" "$version" "$drupal_type" "$composer_project" "$install_profile" "$MODULE_NAME" ""
done

# All four module/theme combinations. Module only is covered above; these add
# module plus theme, theme only, and neither.
# One combo, and only one, drives init.sh through its prompts instead of its
# flags, so the interactive path stays covered. It answers the most questions:
# module name, label, path and repo, theme name and label, then the rest.
run_combo "localgov" "11" "drupal11" "drupal/localgov_project" "localgov" "$MODULE_NAME" "$THEME_NAME" "module + theme, interactive" "interactive"
run_combo "localgov" "11" "drupal11" "drupal/localgov_project" "localgov" "" "$THEME_NAME" "theme only" "flags" "1"
run_combo "vanilla"  "11" "drupal11" "drupal/recommended-project:^11" "standard" "" "$THEME_NAME" "theme only"
run_combo "cms"      "11" "drupal11" "drupal/cms" "recipes/drupal_cms_starter" "$MODULE_NAME" "$THEME_NAME" "module + theme"
run_combo "localgov" "11" "drupal11" "drupal/localgov_project" "localgov" "" "" "site-only"
run_combo "cms"      "11" "drupal11" "drupal/cms" "recipes/drupal_cms_starter" "" "" "site-only"

echo ""
echo -e "${BOLD}== Summary ==${RESET}"
if [ "$TOTAL_FAIL" -gt 0 ]; then
  echo -e "  ${GREEN}$TOTAL_PASS passed${RESET}, ${RED}$TOTAL_FAIL failed${RESET}"
  exit 1
fi
echo -e "  ${GREEN}$TOTAL_PASS passed${RESET}, 0 failed"
exit 0
