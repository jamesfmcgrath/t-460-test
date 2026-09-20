#!/usr/bin/env bash
# One-time template initialiser. Run from the repo root immediately after
# creating a repo from this template:  ./scripts/init.sh
# Takes its answers from flags, from prompts, or from both; records them in
# template.answers; substitutes {{TOKENS}} across every file that holds one;
# then removes itself and TEMPLATE.md. Portable across macOS (BSD) and Linux
# (GNU).
set -euo pipefail

BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
info()  { echo -e "${BOLD}> $*${RESET}"; }
ok()    { echo -e "${GREEN}OK $*${RESET}"; }
warn()  { echo -e "${YELLOW}!! $*${RESET}"; }
die()   { echo -e "${RED}!! $*${RESET}" >&2; exit 1; }

ANSWERS_FILE="template.answers"

usage() {
  cat <<'EOF'
Usage: ./scripts/init.sh [options]

Any value not given as a flag is prompted for. With --defaults, or with a full
flag set, the script runs without touching a tty.

  --module NAME          Module machine name ("" for a site-only project)
  --module-label LABEL   Module label (default: title-cased machine name)
  --module-path PATH     Module path (default: web/modules/custom/NAME)
  --module-repo URL      Module git URL ("" to skip cloning)
  --theme NAME           Theme machine name ("" for no custom theme)
  --theme-label LABEL    Theme label (default: title-cased machine name)
  --ddev-name NAME       DDEV project name
  --ddev-url URL         DDEV site URL (default: https://DDEV_NAME.ddev.site)
  --client TEXT          Client / context line
  --skill-fork OWNER     GitHub owner of the drupal-agent-resources fork
  --flavour FLAVOUR      localgov | vanilla | cms
  --version VERSION      11 | 10 (cms is Drupal 11 only)
  --defaults             Accept every default and leave module and theme blank
  -h, --help             Show this help

Flags take --flag VALUE or --flag=VALUE. Use --flag=VALUE for an empty value,
for example --module="" to select site-only mode without a prompt.
EOF
}

# Answers, with a companion flag recording whether the value came from a flag.
# An explicitly empty flag value counts as supplied, so --module="" selects
# site-only mode rather than falling back to the prompt.
MODULE_NAME="";  SET_MODULE_NAME=0
MODULE_LABEL=""; SET_MODULE_LABEL=0
MODULE_PATH="";  SET_MODULE_PATH=0
MODULE_REPO="";  SET_MODULE_REPO=0
THEME_NAME="";   SET_THEME_NAME=0
THEME_LABEL="";  SET_THEME_LABEL=0
DDEV_NAME="";    SET_DDEV_NAME=0
DDEV_URL="";     SET_DDEV_URL=0
CLIENT="";       SET_CLIENT=0
SKILL_FORK="";   SET_SKILL_FORK=0
FLAVOUR="";      SET_FLAVOUR=0
VERSION="";      SET_VERSION=0
DEFAULTS=0

require_value() { # require_value <flag> <remaining argc> <next arg>
  local flag="$1" argc="$2" value="${3-}"
  [ "$argc" -ge 2 ] || die "$flag requires a value (use $flag=VALUE for an empty one)."
  case "$value" in
    --*) die "$flag requires a value, got $value. Use $flag=VALUE for a value starting with --." ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --module=*)       MODULE_NAME="${1#*=}";  SET_MODULE_NAME=1 ;;
    --module)         require_value "$1" "$#" "${2-}"; MODULE_NAME="$2";  SET_MODULE_NAME=1;  shift ;;
    --module-label=*) MODULE_LABEL="${1#*=}"; SET_MODULE_LABEL=1 ;;
    --module-label)   require_value "$1" "$#" "${2-}"; MODULE_LABEL="$2"; SET_MODULE_LABEL=1; shift ;;
    --module-path=*)  MODULE_PATH="${1#*=}";  SET_MODULE_PATH=1 ;;
    --module-path)    require_value "$1" "$#" "${2-}"; MODULE_PATH="$2";  SET_MODULE_PATH=1;  shift ;;
    --module-repo=*)  MODULE_REPO="${1#*=}";  SET_MODULE_REPO=1 ;;
    --module-repo)    require_value "$1" "$#" "${2-}"; MODULE_REPO="$2";  SET_MODULE_REPO=1;  shift ;;
    --theme=*)        THEME_NAME="${1#*=}";   SET_THEME_NAME=1 ;;
    --theme)          require_value "$1" "$#" "${2-}"; THEME_NAME="$2";   SET_THEME_NAME=1;   shift ;;
    --theme-label=*)  THEME_LABEL="${1#*=}";  SET_THEME_LABEL=1 ;;
    --theme-label)    require_value "$1" "$#" "${2-}"; THEME_LABEL="$2";  SET_THEME_LABEL=1;  shift ;;
    --ddev-name=*)    DDEV_NAME="${1#*=}";    SET_DDEV_NAME=1 ;;
    --ddev-name)      require_value "$1" "$#" "${2-}"; DDEV_NAME="$2";    SET_DDEV_NAME=1;    shift ;;
    --ddev-url=*)     DDEV_URL="${1#*=}";     SET_DDEV_URL=1 ;;
    --ddev-url)       require_value "$1" "$#" "${2-}"; DDEV_URL="$2";     SET_DDEV_URL=1;     shift ;;
    --client=*)       CLIENT="${1#*=}";       SET_CLIENT=1 ;;
    --client)         require_value "$1" "$#" "${2-}"; CLIENT="$2";       SET_CLIENT=1;       shift ;;
    --skill-fork=*)   SKILL_FORK="${1#*=}";   SET_SKILL_FORK=1 ;;
    --skill-fork)     require_value "$1" "$#" "${2-}"; SKILL_FORK="$2";   SET_SKILL_FORK=1;   shift ;;
    --flavour=*)      FLAVOUR="${1#*=}";      SET_FLAVOUR=1 ;;
    --flavour)        require_value "$1" "$#" "${2-}"; FLAVOUR="$2";      SET_FLAVOUR=1;      shift ;;
    --version=*)      VERSION="${1#*=}";      SET_VERSION=1 ;;
    --version)        require_value "$1" "$#" "${2-}"; VERSION="$2";      SET_VERSION=1;      shift ;;
    --defaults)       DEFAULTS=1 ;;
    -h|--help)        usage; exit 0 ;;
    *)                usage >&2; die "Unknown option: $1" ;;
  esac
  shift
done

if ! grep -q "{{MODULE_INTRO}}" AGENTS.md 2>/dev/null; then
  warn "Already initialised (no {{MODULE_INTRO}} token in AGENTS.md). Aborting."
  exit 1
fi

ask() { # ask <prompt> <default> -> echoes answer
  local prompt="$1" def="${2:-}" ans
  if [ "$DEFAULTS" = "1" ]; then echo "$def"; return 0; fi
  if [ -n "$def" ]; then read -r -p "$prompt [$def]: " ans; echo "${ans:-$def}"
  else read -r -p "$prompt: " ans; echo "$ans"; fi
}

titlecase() { echo "$1" | tr '_' ' ' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1))substr($i,2)}1'; }

MACHINE_NAME_RULE="Machine names must start with a lowercase letter and may contain only lowercase letters, digits and underscores (for example my_module). Hyphens are not valid."

valid_machine_name() { # valid_machine_name <value> -> 0 when usable
  local ans="$1"
  case "$ans" in [a-z]*) ;; *) return 1 ;; esac
  [ -z "$(printf '%s' "$ans" | tr -d 'a-z0-9_')" ]
}

check_machine_name() { # check_machine_name <value> <flag> (empty is allowed)
  local ans="$1" flag="$2"
  [ -z "$ans" ] && return 0
  valid_machine_name "$ans" && return 0
  die "$flag: $MACHINE_NAME_RULE"
}

require_flag_value() { # require_flag_value <value> <flag>
  [ -n "$1" ] || die "$2 must not be empty."
}

ask_machine_name() { # ask_machine_name <prompt> -> echoes a valid name or empty
  local prompt="$1" ans
  while true; do
    ans="$(ask "$prompt" '')"
    [ -z "$ans" ] && { echo ""; return 0; }
    if valid_machine_name "$ans"; then echo "$ans"; return 0; fi
    warn "$MACHINE_NAME_RULE" >&2
  done
}

# Validate flag values before the first prompt, so a typo fails immediately
# rather than after a run of questions. Flags whose emptiness only matters in
# module or theme mode (--module-label, --module-path, --theme-label) are
# checked further down, once the mode is known.
[ "$SET_MODULE_NAME" = "1" ] && check_machine_name "$MODULE_NAME" "--module"
[ "$SET_THEME_NAME" = "1" ]  && check_machine_name "$THEME_NAME" "--theme"
[ "$SET_DDEV_NAME" = "1" ]   && require_flag_value "$DDEV_NAME" "--ddev-name"
[ "$SET_DDEV_URL" = "1" ]    && require_flag_value "$DDEV_URL" "--ddev-url"
[ "$SET_CLIENT" = "1" ]      && require_flag_value "$CLIENT" "--client"
[ "$SET_SKILL_FORK" = "1" ]  && require_flag_value "$SKILL_FORK" "--skill-fork"
# Flag values are validated rather than silently normalised; the prompts keep
# their historic permissive fallback (anything else means localgov, anything
# but 10 means 11).
if [ "$SET_FLAVOUR" = "1" ]; then
  case "$FLAVOUR" in
    localgov|vanilla|drupal|cms) ;;
    *) die "--flavour must be localgov, vanilla or cms (got '$FLAVOUR')." ;;
  esac
fi
if [ "$SET_VERSION" = "1" ]; then
  case "$VERSION" in
    10|11) ;;
    *) die "--version must be 11 or 10 (got '$VERSION')." ;;
  esac
fi

echo ""; info "Initialise this template"; echo ""
if [ "$SET_MODULE_NAME" != "1" ]; then
  MODULE_NAME="$(ask_machine_name 'Module machine name (blank for a site-only project)')"
fi

if [ -n "$MODULE_NAME" ]; then
  if [ "$SET_MODULE_LABEL" = "1" ]; then
    require_flag_value "$MODULE_LABEL" "--module-label"
  else
    MODULE_LABEL="$(ask 'Module label' "$(titlecase "$MODULE_NAME")")"
  fi
  if [ "$SET_MODULE_PATH" = "1" ]; then
    require_flag_value "$MODULE_PATH" "--module-path"
  else
    MODULE_PATH="$(ask 'Module path' "web/modules/custom/$MODULE_NAME")"
  fi
  if [ "$SET_MODULE_REPO" != "1" ]; then
    MODULE_REPO="$(ask 'Module git URL (blank to skip cloning)' '')"
  fi
else
  # Site-only mode ignores the module label, path and repo answers.
  MODULE_LABEL=""
  MODULE_PATH="web/modules/custom"
  MODULE_REPO=""
fi

# Optional custom theme. Module and theme are independent: all four
# combinations (module only, theme only, both, neither) are supported.
if [ "$SET_THEME_NAME" != "1" ]; then
  THEME_NAME="$(ask_machine_name 'Theme machine name (blank for no custom theme)')"
fi
if [ -n "$THEME_NAME" ]; then
  if [ "$SET_THEME_LABEL" = "1" ]; then
    require_flag_value "$THEME_LABEL" "--theme-label"
  else
    THEME_LABEL="$(ask 'Theme label' "$(titlecase "$THEME_NAME")")"
  fi
  THEME_PATH="web/themes/custom/$THEME_NAME"
else
  THEME_LABEL=""
  THEME_PATH="web/themes/custom"
fi

if [ -n "$MODULE_NAME" ]; then
  DEF_DDEV="$(echo "$MODULE_NAME" | tr '_' '-')-dev"
elif [ -n "$THEME_NAME" ]; then
  DEF_DDEV="$(echo "$THEME_NAME" | tr '_' '-')-dev"
else
  DEF_DDEV="site-dev"
fi
if [ "$SET_DDEV_NAME" != "1" ]; then
  DDEV_NAME="$(ask 'DDEV project name' "$DEF_DDEV")"
fi
if [ "$SET_DDEV_URL" != "1" ]; then
  DDEV_URL="$(ask 'DDEV site URL' "https://$DDEV_NAME.ddev.site")"
fi
if [ "$SET_CLIENT" != "1" ]; then
  CLIENT="$(ask 'Client / context' 'a local council')"
fi
if [ "$SET_SKILL_FORK" != "1" ]; then
  SKILL_FORK="$(ask 'drupal-agent-resources fork owner (hosts drupal-localgov)' 'jamesfmcgrath')"
fi

echo ""
if [ "$SET_FLAVOUR" != "1" ]; then
  FLAVOUR="$(ask 'Drupal flavour: localgov, vanilla or cms' 'localgov')"
fi
if [ "$SET_VERSION" != "1" ]; then
  VERSION="$(ask 'Drupal major version: 11 or 10' '11')"
fi

case "$VERSION" in 10) DRUPAL_TYPE="drupal10";; *) DRUPAL_TYPE="drupal11"; VERSION="11";; esac
case "$FLAVOUR" in
  vanilla|drupal)
    DRUPAL_FLAVOUR="vanilla"
    INSTALL_PROFILE="standard"
    COMPOSER_PROJECT="drupal/recommended-project:^${VERSION}"
    ;;
  cms)
    DRUPAL_FLAVOUR="cms"
    # Drupal CMS is Drupal 11 only; force version regardless of the answer.
    if [ "$VERSION" = "10" ]; then
      warn "Drupal CMS is Drupal 11 only; using Drupal 11."
    fi
    VERSION="11"; DRUPAL_TYPE="drupal11"
    INSTALL_PROFILE="recipes/drupal_cms_starter"
    COMPOSER_PROJECT="drupal/cms"
    ;;
  *)
    DRUPAL_FLAVOUR="localgov"
    INSTALL_PROFILE="localgov"
    # LocalGov distribution: 4.x = Drupal 11, 3.x = Drupal 10. Verify the
    # localgov_project template tag if a clean create fails.
    if [ "$VERSION" = "10" ]; then
      COMPOSER_PROJECT="drupal/localgov_project:^3.0"
    else
      COMPOSER_PROJECT="drupal/localgov_project"
    fi
    ;;
esac

# Prose fragments that read naturally in all four module/theme combinations.
if [ -n "$MODULE_NAME" ]; then
  MODULE_INTRO=", the \`$MODULE_NAME\` module for $CLIENT"
  MODULE_LINE="\`$MODULE_PATH/\`"
  PACKAGE_NAME="${MODULE_NAME}-dev"
  PACKAGE_DESCRIPTION="Front-end tooling for $MODULE_NAME ($CLIENT)."
elif [ -n "$THEME_NAME" ]; then
  MODULE_INTRO=" for $CLIENT"
  MODULE_LINE="none yet, theme-only project"
  PACKAGE_NAME="${THEME_NAME}-dev"
  PACKAGE_DESCRIPTION="Front-end tooling for $THEME_NAME ($CLIENT)."
else
  MODULE_INTRO=" for $CLIENT"
  MODULE_LINE="none yet, site-only project"
  PACKAGE_NAME="$DDEV_NAME"
  PACKAGE_DESCRIPTION="Front-end tooling for $CLIENT."
fi

if [ -n "$THEME_NAME" ]; then
  THEME_INTRO=", themed by \`$THEME_NAME\`"
  THEME_LINE="\`$THEME_PATH/\` (\`$THEME_NAME\`)"
  THEME_LAYER=" Theme-layer fixes belong in \`$THEME_PATH/\`."
else
  THEME_INTRO=""
  THEME_LINE="none yet, no custom theme"
  THEME_LAYER=""
fi

if [ -n "$MODULE_NAME" ] && [ -n "$THEME_NAME" ]; then
  MODULE_AFFECTS="the \`$MODULE_NAME\` module and \`$THEME_NAME\` theme affect"
elif [ -n "$MODULE_NAME" ]; then
  MODULE_AFFECTS="the \`$MODULE_NAME\` module affects"
elif [ -n "$THEME_NAME" ]; then
  MODULE_AFFECTS="the \`$THEME_NAME\` theme affects"
else
  MODULE_AFFECTS="the site includes"
fi

# Record the resolved answers before substituting, so the run is auditable and
# can be reproduced with the matching flags. Each key maps to the flag of the
# same name (MODULE_NAME to --module, THEME_NAME to --theme, and so on); the
# last four are derived from the flavour and version answers.
{
  echo "# Answers used by scripts/init.sh on $(date -u '+%Y-%m-%d'). Not a shell script:"
  echo "# a record of the run, one KEY=value per line, values unquoted."
  echo "MODULE_NAME=$MODULE_NAME"
  echo "MODULE_LABEL=$MODULE_LABEL"
  echo "MODULE_PATH=$MODULE_PATH"
  echo "MODULE_REPO=$MODULE_REPO"
  echo "THEME_NAME=$THEME_NAME"
  echo "THEME_LABEL=$THEME_LABEL"
  echo "THEME_PATH=$THEME_PATH"
  echo "DDEV_NAME=$DDEV_NAME"
  echo "DDEV_URL=$DDEV_URL"
  echo "CLIENT=$CLIENT"
  echo "SKILL_FORK=$SKILL_FORK"
  echo "FLAVOUR=$FLAVOUR"
  echo "VERSION=$VERSION"
  echo "DRUPAL_TYPE=$DRUPAL_TYPE"
  echo "DRUPAL_FLAVOUR=$DRUPAL_FLAVOUR"
  echo "COMPOSER_PROJECT=$COMPOSER_PROJECT"
  echo "INSTALL_PROFILE=$INSTALL_PROFILE"
} > "$ANSWERS_FILE"

# Paths never substituted into: this script (rewriting it while bash is still
# reading it corrupts the run), the suite that documents tokens as test
# fixtures, and the answers file just written.
SKIP_PATHS=(./scripts/init.sh ./scripts/test-template.sh "./$ANSWERS_FILE")

discover_token_files() { # -> one path per line, relative to the repo root
  # template-docs/ holds maintainer history that quotes tokens verbatim;
  # vendor/ and web/ only exist if setup.sh has already run, and contrib
  # code is never ours to rewrite.
  grep -rlE '\{\{[A-Z_]+\}\}' . \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor \
    --exclude-dir=web --exclude-dir=template-docs \
    2>/dev/null || true
}

FILES=()
while IFS= read -r found; do
  [ -n "$found" ] || continue
  skip=0
  for skip_path in "${SKIP_PATHS[@]}"; do
    if [ "$found" = "$skip_path" ]; then skip=1; break; fi
  done
  if [ "$skip" = "1" ]; then continue; fi
  FILES+=("$found")
done <<EOF
$(discover_token_files)
EOF

[ "${#FILES[@]}" -gt 0 ] || die "No files with {{TOKENS}} found. Run this from the repo root."

echo ""; info "Applying to ${#FILES[@]} files..."

# & and | are special in a sed replacement (or are the delimiter), so a client
# name like "Bath & North East Somerset" has to be escaped.
sed_escape() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

SED_ARGS=()
sub() { # sub <token> <value>
  SED_ARGS+=(-e "s|{{$1}}|$(sed_escape "$2")|g")
}
sub MODULE_NAME         "$MODULE_NAME"
sub MODULE_LABEL        "$MODULE_LABEL"
sub MODULE_PATH         "$MODULE_PATH"
sub MODULE_REPO         "$MODULE_REPO"
sub MODULE_INTRO        "$MODULE_INTRO"
sub MODULE_LINE         "$MODULE_LINE"
sub MODULE_AFFECTS      "$MODULE_AFFECTS"
sub THEME_NAME          "$THEME_NAME"
sub THEME_LABEL         "$THEME_LABEL"
sub THEME_PATH          "$THEME_PATH"
sub THEME_INTRO         "$THEME_INTRO"
sub THEME_LINE          "$THEME_LINE"
sub THEME_LAYER         "$THEME_LAYER"
sub PACKAGE_NAME        "$PACKAGE_NAME"
sub PACKAGE_DESCRIPTION "$PACKAGE_DESCRIPTION"
sub DDEV_NAME           "$DDEV_NAME"
sub DDEV_URL            "$DDEV_URL"
sub CLIENT              "$CLIENT"
sub SKILL_FORK          "$SKILL_FORK"
sub DRUPAL_TYPE         "$DRUPAL_TYPE"
sub DRUPAL_FLAVOUR      "$DRUPAL_FLAVOUR"
sub INSTALL_PROFILE     "$INSTALL_PROFILE"
sub COMPOSER_PROJECT    "$COMPOSER_PROJECT"

for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  tmp="$(mktemp)"
  # Write back into the original file so its permissions (e.g. +x) are kept.
  sed "${SED_ARGS[@]}" "$f" > "$tmp" && cat "$tmp" > "$f" && rm -f "$tmp"
done

rm -f TEMPLATE.md scripts/test-template.sh
rm -rf template-docs
chmod +x scripts/setup.sh scripts/install-drupal 2>/dev/null || true
if [ -n "$MODULE_NAME" ] && [ -n "$THEME_NAME" ]; then
  SCOPE="module $MODULE_NAME, theme $THEME_NAME"
elif [ -n "$MODULE_NAME" ]; then
  SCOPE="module $MODULE_NAME"
elif [ -n "$THEME_NAME" ]; then
  SCOPE="theme $THEME_NAME"
else
  SCOPE="site-only"
fi
ok "Tokens applied ($FLAVOUR, Drupal $VERSION, $SCOPE)."
ok "Answers recorded in $ANSWERS_FILE; commit it alongside the substituted files."
info "Removing initialiser (scripts/init.sh)..."
rm -f scripts/init.sh
ok "Done. Next: ./scripts/setup.sh"
echo ""
if [ -z "$MODULE_NAME" ]; then
  warn "No module configured: to add one later, create it under web/modules/custom/ and set MODULE and MODULE_NAME in the Makefile."
fi
if [ -n "$THEME_NAME" ]; then
  warn "Theme $THEME_NAME is configured but not scaffolded yet. After ./scripts/setup.sh, run: make subtheme"
else
  warn "No theme configured: to add one later, create it under web/themes/custom/ and set THEME_NAME, THEME_LABEL, and THEME_PATH in the Makefile."
fi
warn "Review the git diff, then commit: git add -A && git commit -m 'Initialise from template'"
