# Stage 13 summary: non-interactive init and dynamic token discovery

Date: 2026-08-10
Branch: `feat/stage-13-init-token` (merged into `main` in PR #3)
Base commit: `fd6273a`
Files changed: `scripts/init.sh`, `scripts/test-template.sh`, `README.md`,
`TEMPLATE.md`, `PROJECT.md`, `PROMPTS.md`, `.gitignore`

## Summary

Two robustness problems in one stage, both living in `scripts/init.sh` and both
changing `scripts/test-template.sh`: `init.sh` could only be driven by prompts,
and the list of files it substituted into was hand-maintained. Regression suite
grew from 528 to 697 checks, all passing, and its failure path was proven by
breaking a flag mapping on purpose rather than assumed.

## What shipped

### 1. A flag for every prompt

`--module`, `--module-label`, `--module-path`, `--module-repo`, `--theme`,
`--theme-label`, `--ddev-name`, `--ddev-url`, `--client`, `--skill-fork`,
`--flavour`, `--version`, plus `--defaults` (accept every default, blank module
and theme) and `--help`.

- Both `--flag value` and `--flag=value` forms are accepted.
- A missing value, or a value that looks like another flag, fails with a
  message instead of silently swallowing the next argument.
- `--module=""` and `--theme=""` are the explicit-empty form: they select
  site-only and no-theme mode rather than falling back to the prompt.
- Anything not supplied by flag is still prompted exactly as before, so flags
  and prompts mix; `--defaults` composes with explicit flags, and explicit
  flags win.
- Flag values are validated before the first prompt (machine names, non-empty
  values, flavour, version), so a typo fails immediately rather than after a
  run of questions. The prompts keep their historic permissive fallback
  (anything else means localgov, anything but 10 means 11).

### 2. `template.answers`

Written to the project root before substitution and left in place to be
committed: `KEY=value` lines for the twelve answers plus the four derived
values (`DRUPAL_TYPE`, `DRUPAL_FLAVOUR`, `COMPOSER_PROJECT`,
`INSTALL_PROFILE`). Keys match the flag names, so an init run is auditable
after the fact and reproducible as a flag invocation. It is a record, not a
shell script: values are unquoted and nothing reads the file back.

### 3. Dynamic file discovery

The hand-maintained `FILES` array is gone. The substitution list is discovered
per run with `grep -rlE` for `{{UPPER_SNAKE}}`, so a file added to the template
later is picked up with no change to the script. Excluded: `.git`,
`node_modules`, `vendor`, `web`, `docs`, `template-docs`, the token-convention
docs (`PROJECT.md`, `PROMPTS.md`, `memory.md`), `template.answers`, and the two
self-deleting scripts. Substitution still writes back into the original file
rather than moving a temp file over it, so executable bits survive (verified:
`scripts/setup.sh` and `scripts/install-drupal` stage as 100755 after init).

### 4. Regression suite

Every combo now runs `init.sh` with flags and stdin closed, so a run that still
reaches a prompt fails the assertion. Exactly one combo (localgov 11, module
plus theme) keeps the interactive `init_input` path covered. New assertions:
each flag's value landing in the file that carries it, `template.answers`
contents (prompted and derived), and a scratch file containing a `{{CLIENT}}`
token injected into the copy before `init.sh` that must come back substituted.

## Two things found while implementing

1. **Unescaped sed replacements.** `&` in a sed replacement means "the whole
   match", so a client name like "Bath & North East Somerset" was silently
   mangled by the previous implementation as well. Values are now escaped for
   `\`, `&`, and the `|` delimiter. The suite's test client name contains an
   ampersand on purpose to hold this in place.

2. **Self-substitution hazard.** `init.sh` matches its own token pattern (its
   already-initialised guard greps for a literal token). Dynamic discovery
   would therefore have rewritten the running script while bash was still
   reading it, which corrupts execution part-way through. Both self-deleting
   scripts are excluded from the discovered list for that reason, not for
   tidiness.

## Verification

- `scripts/test-template.sh`: **697 passed, 0 failed** (was 528).
- Failure path proven, not assumed: the `--client` mapping was broken on
  purpose (flag parsed, value dropped), the suite was re-run, the `--client`
  assertions and the discovery check failed and the suite exited 1, then the
  mapping was restored from a backup copy and the suite re-ran green.
- Checked by hand on throwaway copies: `--help`, unknown flag, invalid
  flavour, invalid version, invalid machine name, `--module` with no value,
  `--module --theme x` (flag-as-value guard), `--defaults` alone,
  `--defaults` combined with explicit flags, an ampersand in `--client`
  reaching `AGENTS.md`/`README.md`/`package.json` intact, executable bits
  after init, and `template.answers` not being gitignored.

## Not verified

- No DDEV, composer, or network run: the live spin-up remains a manual
  verification step, unchanged by this stage.
- The `docs/` and `template-docs/` discovery exclusions are not covered by the
  suite, because `stage_copy` already excludes `docs/` from the throwaway copy.
  They are documented in `TEMPLATE.md` and `PROJECT.md` instead.

## Known follow-ups

- Stage 14, if it lands `template-docs/`, needs no `init.sh` change: the
  exclusion is already in place.
- Nothing reads `template.answers` back yet. Feeding it to `init.sh` as a
  `--from-answers` input would close the reproducibility loop properly, but it
  was not in scope here.
