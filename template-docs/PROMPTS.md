# Maintenance prompts and status

Staged Claude Code prompts for improving this template, with current status.
Run open stages from the repo root unless noted. Companion to PROJECT.md,
which holds the Claude Project instructions.

Shared conventions (repeated so they survive pasting into a fresh session):
no em dashes anywhere; scripts stay executable (100755); run
scripts/test-template.sh before calling a script change done; keep all
flavours and supported Drupal versions working; only {{UPPER_SNAKE}} names
are template tokens and GitHub Actions ${{ }} expressions must never be
touched.

## Status (2026-09-10, closing two loose ends and re-verifying two carried-forward items against the tree; entries before Stage 12 are as recorded on their own dates and were not re-audited by this pass)

- Stage 1, reviewer gates upstreamed to the skill fork: DONE
  (jamesfmcgrath/drupal-agent-resources commit 1dc398c; setup.sh fetches from
  the configured fork since 1dfdf84; the tracked .claude/agents/ copy here is
  canonical either way).
- Stage 2, agr.lock policy: DONE (generated per created project, not tracked
  in the bare template; 4e9b725 and 45197f7).
- Stage 3, pa11y-ci accessibility CI job: COMMITTED (cf8b138), needs live
  verification in the first created project that pushes with composer.json
  present (the guard job skips it on the bare template).
- Stage 4, twig-cs-fixer plus vanilla flavour live run: DONE (ef05436;
  vanilla + Drupal 11 verified end to end, three setup bugs found and fixed).
- Stage 5, Drupal CMS flavour: DONE at the tokeniser level (2026-08-05). "cms"
  flavour added: drupal/cms, Drupal 11 only, INSTALL_PROFILE
  recipes/drupal_cms_starter; init.sh forces Drupal 11, install-drupal gained a
  recipe case, test-template.sh covers cms 11 and cms site-only (134/134 pass).
  Verified against Drupal CMS 2.1.3 (core 11, PHP 8.3). Live run 2026-08-05:
  composer create-project and the recipe install succeed; setup.sh's dev-tooling
  require needed an allow-plugins fix (phpstan/extension-installer, now
  pre-authorised in setup.sh), and the Makefile quality targets needed a
  site-only guard. The site-only cms install boots and make check runs clean
  (targets skip). The a11y job now derives its scan URLs at runtime to match the
  installed site (front page, the created node by real id, /search only if
  served), fixing the false /search and /node/1 404s on cms; a real link-name
  WCAG violation in Drupal CMS's own front-page theme remains and is left to
  fail rather than suppressed. Still pending: the dev-tooling require completing
  on a cms project, and make check against a real module (module mode). Prompt
  below.
- Stage 6, template regression suite: DONE. scripts/test-template.sh, wired
  into CI as the "template" job (runs when the guard job's composer.json
  check is false).
- Stage 7, optional module (site-only mode): DONE. init.sh, setup.sh, and the
  Makefile all support a blank module name; scripts/test-template.sh gained a
  site-only regression check. The DDEV/composer spin-up still needs a live
  run.
- Stage 8, drupal.org pipeline parity: DONE. assets/module.gitlab-ci.yml,
  make module-ci, and local parity targets (spell, lint-js, lint-css) landed;
  see PROJECT.md for the SKIP_TWIG_CS_FIXER and hex-color caveats
  found during implementation. The DDEV/npm spin-up for lint-js/lint-css
  still needs a live run.
- Vanilla + Drupal 10 live run: DONE (2026-07-29, re-run 2026-08-05 with no
  issues; site installs and boots on
  Drupal 10.6.14, both vanilla setup bugs from Stage 4 hold fixed, make check
  passes: phpcs/phpunit/twig-cs-fixer clean, empty module test suite skips as
  expected. Caveat: `make stan` can report a spurious exit 1 with zero real
  phpstan errors, a ddev-exec/PHPStan process-exit interaction, not specific
  to Drupal 10 or vanilla; confirmed the identical command exits 0 when run
  through a shell wrapper. Not yet root-caused or fixed in the Makefile).
- Stage 9, replace pa11y-ci with axe-core + Playwright: DONE. pa11y-ci's
  dependency chain (globby/glob/minimatch/brace-expansion) had 5 unfixable
  high-severity npm audit findings and only covered WCAG 2.1 AA; the a11y CI
  job now runs scripts/a11y-scan.mjs (@axe-core/playwright), enforcing WCAG
  2.2 AA to match AGENTS.md. .pa11yci replaced by a11y-urls.json (same 3
  paths). Needs live verification: only checked for YAML syntax and a local
  dry run, not run against GitHub Actions infrastructure.
- Stage 10, workspace generalisation and theme mode: DONE at the tokeniser and
  tooling level (2026-08-06). Single-module scoping replaced by LINT_PATHS
  ("web/modules/custom web/themes/custom"), mirrored in the Makefile,
  phpcs.xml.dist, phpstan.neon, package.json, and ci.yml. init.sh gained
  optional theme prompts (THEME_NAME, THEME_LABEL, THEME_PATH, plus derived
  DRUPAL_FLAVOUR and composed THEME_INTRO/THEME_LINE/THEME_LAYER), so all four
  module/theme combinations work. New Makefile targets subtheme and component;
  AGENTS.md gained an SDC section. Regression suite grew from 134 to 385
  checks, all passing.
  Audited against the full stage specification and verified live on
  2026-08-06: all ten specification items pass, 385/385 regression checks
  pass, and a throwaway localgov 11 theme-only project ran setup.sh, make
  subtheme (localgov_base subtheme created through ddev exec, theme enabled
  and set as default), and make component NAME=test_card (SDC scaffolded into
  the theme). Two changes closed during that audit: make component now
  pre-fills the generator's first three answers, the --answer ordering having
  been confirmed live, and make spell gained --no-must-find-files to match CI
  and package.json. Two follow-up items from that audit, make subtheme on
  the vanilla and cms branches and the make stan ddev-exec exit-code
  caveat, were RESOLVED in the 2026-08-10 cleanup batch (commit f035cd0):
  make subtheme now prefers `vendor/bin/dr generate-theme`, live-verified on
  a throwaway vanilla 11 project (cms was not spun up separately since it
  shares the same Makefile branch); phpstan.neon's duplicate phpstan-drupal
  includes and stale `drupalRoot` key were removed, live-verified
  deterministically (exit 0 clean, exit 1 with a real error shown) on both a
  vanilla and a theme-only localgov project. make subtheme also now appends
  generic subtheme vocabulary to .cspell-project-words.txt automatically.
  Both fixes confirmed unchanged in the tree on 2026-09-10 (`git log
  f035cd0..HEAD -- Makefile phpstan.neon` returns nothing). See PROJECT.md
  for the measurements.
- Stage 11, local dev recipes: DONE (2026-08-06). recipes/site_tools and
  recipes/dev_tools, assets/settings.local.php and
  assets/development.services.yml, setup.sh wiring, and make recipe all
  verified live against a throwaway localgov 11 project (module recipe_smoke)
  spun up with real Docker/DDEV: composer resolved drupal/eca to 3.1.4 and
  drupal/bpmn_io to 3.0.6, Twig debug and all three null-backed cache bins
  (render, page, dynamic_page_cache) confirmed, config_exclude_modules
  confirmed against the actual exported core.extension.yml (devel and
  environment_indicator_toolbar correctly absent from the export; both
  correctly still enabled in active config), and the environment indicator
  confirmed rendering for authenticated users. Two bugs found: staging the
  throwaway copy under $TMPDIR breaks DDEV on this machine's Colima Docker
  provider (only $HOME is mounted into its VM) and had to be re-staged under
  $HOME; and setup.sh's `ddev drush recipe recipes/site_tools -y` /
  `recipes/dev_tools -y` calls failed because ddev drush's cwd is the
  docroot, not the project root, so both recipes silently failed to apply on
  every project built from this template. Fixed in commit 8f8a140
  (`../recipes/site_tools` and `../recipes/dev_tools`), and a scoped
  final-review pass re-checked the fix and confirmed it correct with no new
  breakage. The `make recipe` Makefile target had the identical bug and was
  fixed alongside it in the same review pass. See PROJECT.md for full detail,
  including a further finding from that review: Twig debug was confirmed live
  only on the localgov flavour, and only because localgov's own project
  template already ships Twig debug on by itself; this feature's own
  development.services.yml copy step is inert whenever the underlying Drupal
  distribution already scaffolds its own file, which core-based
  distributions, including vanilla and cms, do without enabling debug.
  setup.sh now verifies Twig debug directly after the copy step instead of
  assuming it. Vanilla and cms still need a live check.
- Stage 12, visual regression testing (VRT): VERIFIED (2026-09-09). Code
  landed 2026-08-10, commit 0b62495, merged via fd6273a; the front-page
  determinism fix landed 2026-09-09 on branch fix/vrt-front-page (PR #5,
  merged via e6fdfbd). Reuses the @playwright/test stack the accessibility
  job already installs rather than adding BackstopJS. a11y-urls.json
  renamed to scan-urls.json, the one shared URL list for both scanners; its
  shipped default trimmed to `["/"]`, the only path confirmed to resolve
  (with or without a redirect) on every flavour straight after install.
  tests/vrt/vrt.spec.mjs and a tests/vrt-scoped playwright.config.mjs exist
  in the tree; Makefile targets vrt and vrt-update exist. Baselines are
  OS-suffixed by directory (tests/vrt/__screenshots__/<platform>/…), only
  linux/ authoritative and committed, darwin/ (and win32/) gitignored; the
  CI "browser checks" job runs the VRT spec after the axe scan against the
  served site and shared scan-urls.json, generating and uploading a missing
  linux/ baseline as an artifact rather than failing the run, and failing
  the job with an uploaded HTML diff report on a genuine diff.
  The front-page determinism fix: a fresh LocalGov install's front page
  redirects anonymous visitors to /user/login, and the LocalGov Design
  System login template shows a randomly chosen hero photo per request
  (~25% pixel diff, reproduced twice in an earlier, now-discarded local
  check). Fix: the node-creation step now runs `vendor/bin/drush config:set
  system.site page.front "/node/${node_id}" -y` right after creating the
  node, only when a node was actually created, matching the existing
  vendor/bin/drush invocation style and -y usage already in that job. This
  also incidentally corrects the axe-core scan, which had been silently
  auditing the /user/login redirect target instead of real front-page
  content.
  Live-verified 2026-09-09 against a fresh test project
  (github.com/jamesfmcgrath/lgd-stage12-verify-20260909-215334, localgov,
  Drupal 11, module and theme both configured), not the discarded dev-test
  project. Observed directly from the job logs: PR #5's Actions run on the
  bare template correctly SKIPPED php/prettier/browser-checks (no
  composer.json yet, so this is not evidence of the fix working) with no
  action-resolution failures from the bumped majors (checkout v7, cache v6,
  setup-node v7, upload-artifact v7) in the jobs that did run. After
  `init.sh`/`setup.sh` scaffolded and installed the fresh project and it was
  pushed (composer.json now present), the guard flipped and
  browser-checks ran for real: it created node 1, set
  `system.site page.front` to `/node/1` (confirmed in the log), axe-core
  scanned 2 pages ("/" and "/node/1") with 0 violations (real front-page
  content, not the login redirect), and the VRT spec found no
  tests/vrt/__screenshots__/linux/ baseline, generated front-page.png and
  node-1.png, and uploaded them as build artifact vrt-baselines-linux
  instead of failing the run. Those PNGs were downloaded with
  `gh run download` and committed to the project repo; a no-op commit then
  triggered a second run whose browser-checks log reads "Committed Linux
  baselines found; comparing against them." followed by "2 passed" — a
  genuine green comparison against the committed baseline. Both runs
  passed on the first attempt.
  The PHP lint/static-analysis/tests and Prettier jobs also ran for real in
  both of those pushed runs (job list confirmed via `gh run view --json
  jobs`, not inferred from browser-checks passing): a 2026-09-10 check of
  the actual per-job logs (`gh api .../actions/jobs/<id>/logs`) found
  actions/checkout@v7, actions/cache@v6, and actions/setup-node@v7 each
  resolving with a valid SHA and zero `##[warning]` lines in both jobs;
  actions/upload-artifact@v7 is not invoked in either job and was confirmed
  clean separately in the browser-checks job logs of the same two runs.
  This closes the gap left by the 2026-09-09 observation above, which only
  covered the jobs skipped on the bare-template PR run.

- Stage 13, non-interactive init and dynamic token discovery: DONE (landed
  2026-08-10, commit 56f50ac, merged via 564d2e1, status corrected in
  fcf3775). init.sh gained a flag for every prompt (--module,
  --module-label, --module-path, --module-repo, --theme, --theme-label,
  --ddev-name, --ddev-url, --client, --skill-fork, --flavour, --version) plus
  --defaults and --help; anything not given as a flag is still prompted, and
  --flag=value is the explicit-empty form so --module="" selects site-only mode
  without falling back to the prompt. Flag values are validated before the
  first prompt. Resolved answers, prompted and derived, are written to
  template.answers before substitution and left to be committed. The
  hand-maintained FILES array is gone: the substitution list is discovered per
  run with grep -rlE for {{UPPER_SNAKE}}, excluding .git, node_modules, vendor,
  web, docs, template-docs, the token-convention docs, template.answers, and
  the two self-deleting scripts. Substitution still writes back into the
  original file (executable bits preserved) and now sed-escapes its values, so
  a client name containing & survives. test-template.sh drives every combo
  through flags with stdin closed, except one combo (localgov 11, module +
  theme) that keeps the interactive init_input path covered, and one that
  injects a new {{CLIENT}}-bearing file into the copy before init.sh to prove
  discovery. Suite grew from 528 to 697 checks at the time this landed, all
  passing; the failure path was proven by breaking the --client mapping on
  purpose (the --client assertions and the discovery check fail, suite exits
  1) and restoring it. This stage needs no live DDEV/composer verification:
  it is tokeniser-level only, and scripts/test-template.sh already covers it
  without touching the network. Confirmed still fully present in the tree by
  the 2026-09-09 truth pass.

- Stage 14, docs split, shipped project docs, changelog: DONE (landed
  2026-08-12, commit ce3b536, direct to main). Moved PROJECT.md, PROMPTS.md,
  and memory.md from the repo root into template-docs/; added docs/
  (getting-started.md, add-a-module-later.md, add-a-theme.md, recipes.md,
  pipeline-parity.md, troubleshooting.md) and CHANGELOG.md at the repo root.
  Confirmed present in the tree by the 2026-09-09 truth pass. Gap found by
  that pass: commit ce3b536 never added its own entry to this ledger, which
  is why this entry did not exist until now, and memory.md was never updated
  to mention it either (fixed in the same pass).

- Stage 15: does not exist. Checked 2026-09-09: no commit in this repo's
  history (`git log --all --grep`) mentions Stage 15, this ledger has never
  had a Stage 15 entry, and no prompt template for one exists below. It was
  never a planned batch here, not merely unlanded; a review session's
  reference to a landed Stage 15 was wrong, not stale, and is corrected here
  rather than carried forward.
  A 2026-09-10 session was asked to write a genuine stage for two items that
  had been carried as notes since before Stage 12 and originally scoped
  into this same phantom Stage 15: make subtheme live proof on vanilla and
  cms, and the make stan spurious exit 1. Checked against the tree first:
  both were already resolved in the 2026-08-10 cleanup batch (commit
  f035cd0, see the corrected Stage 10 entry above), and neither the
  Makefile nor phpstan.neon has changed since. No new stage was written;
  doing so would have re-created a stage for work that was already done,
  the same category of error this entry exists to prevent. The numbering
  still stops at Stage 14; 15 remains the next unused number, free for the
  next stage that is actually new.

---

## Stage 5: Add a Drupal CMS flavour

```
Add "cms" as a third Drupal flavour alongside localgov and vanilla, installing
Drupal CMS (composer project drupal/cms). Facts to build on, verified 2026-07:
Drupal CMS 2.1.x is Drupal core 11 only; it installs headlessly with
drush site:install recipes/drupal_cms_starter -y (the profile argument takes a
recipe path); interactive installs use its own drupal_cms_installer profile.

1. scripts/init.sh:
   - Flavour prompt becomes "localgov, vanilla or cms" (default localgov).
   - For cms: skip or ignore the version prompt and force VERSION=11 with a
     printed note (Drupal CMS is 11-only); set DRUPAL_TYPE=drupal11,
     COMPOSER_PROJECT=drupal/cms, INSTALL_PROFILE=recipes/drupal_cms_starter.
   - Do not change behaviour for the other two flavours.
2. scripts/setup.sh and scripts/install-drupal:
   - Confirm the drush site:install call passes {{INSTALL_PROFILE}} through
     unquoted-path-safe so a recipe path works as the argument.
   - In install-drupal's interactive profile picker, add a "Drupal CMS starter
     (recipe)" option that maps to recipes/drupal_cms_starter, shown only when
     the recipes/drupal_cms_starter directory exists in the docroot project.
   - Drupal CMS scaffolds a web/ docroot like recommended-project; verify
     setup.sh's copy step needs no change, and say so explicitly.
3. Docs: README.md (flavour list, tokens table example), TEMPLATE.md (flavour
   notes: cms forces Drupal 11, INSTALL_PROFILE holds a recipe path for this
   flavour), PROJECT.md (template contents and "keep flavours working" line
   now covers three flavours).
4. Smoke-test per PROJECT.md rules: throwaway copy, run init.sh choosing cms,
   check VERSION was forced to 11, INSTALL_PROFILE substituted to
   recipes/drupal_cms_starter, no leftover {{UPPER_SNAKE}} tokens, ${{ }}
   expressions intact, bash -n on scripts, make -n parses, executable bits
   kept. The composer/DDEV spin-up needs a live run; mark it so.
5. Sanity note to include in your summary: LocalGov and Drupal CMS are separate
   assemblies; cms flavour must not pull the localgov profile or modules, and
   the drupal-localgov skill's LocalGov guidance stays dormant on cms projects
   (it detects LocalGov from composer.json).
6. If scripts/test-template.sh exists (Stage 6), add the cms 11 combination to
   its COMBOS list with the expected derived values.
No em dashes. Keep all three flavours and both Drupal versions (for the two
that support 10) working.
```

---

## Stage 6: Template regression suite (protects all future updates)

```
The template repo has no automated tests: the CI guard job skips every job on
the bare template (no composer.json), and template changes are only protected
by the manual smoke-test convention in PROJECT.md. Automate that convention.

1. Create scripts/test-template.sh (tracked, mode 100755). It must:
   - Define a COMBOS list at the top, one entry per supported flavour/version
     pair with the expected derived values, currently:
       localgov 11 -> drupal11, drupal/localgov_project, localgov
       localgov 10 -> drupal10, drupal/localgov_project:^3.0, localgov
       vanilla  11 -> drupal11, drupal/recommended-project:^11, standard
       vanilla  10 -> drupal10, drupal/recommended-project:^10, standard
     (Add cms 11 here when the Stage 5 flavour lands; keep this list the single
     place a new flavour registers its expectations.)
   - For each combo: copy the repo to a fresh temp dir (exclude .git and any
     _to_delete), pipe scripted answers into ./scripts/init.sh with module name
     regress_mod, all other prompts defaulted except flavour and version.
   - Assert, per combo, with clear pass/fail output and a nonzero exit on any
     failure:
     a. init.sh exits 0; scripts/init.sh and TEMPLATE.md removed themselves.
     b. No {{UPPER_SNAKE}} tokens remain anywhere except PROJECT.md (which
        documents the token convention as literal text).
     c. The count of ${{ occurrences in .github/workflows/ci.yml is unchanged
        from before init ran.
     d. AGENTS.md, Makefile, agr.toml, .claude/settings.local.json.dist, and
        .claude/commands/a11y-check.md contain the substituted values
        (regress_mod and the combo's derived DRUPAL_TYPE, COMPOSER_PROJECT,
        INSTALL_PROFILE where each applies).
     e. bash -n passes on scripts/setup.sh and scripts/install-drupal; both
        are still executable.
     f. make -n help parses; the settings dist parses as JSON; ci.yml and
        .ddev/config.yaml parse as YAML (python3 -c with json/yaml, or
        equivalent available on the runner).
   - The suite must not touch the network, run composer, or start DDEV. It
     tests the tokeniser and file invariants only; the live spin-up remains a
     manual verification step.
2. Wire it into CI as a "template" job in .github/workflows/ci.yml that runs
   ONLY on the bare template, the inverse of the existing guard:
   if needs.guard.outputs.run == 'false'. Created projects (composer.json
   present) skip it and run the existing jobs instead; the bare template
   finally gets a green, meaningful CI run.
3. init.sh: add scripts/test-template.sh to the files it removes at the end,
   next to TEMPLATE.md, so created projects do not carry the suite. Update the
   test itself to assert the removal happened (part of check a).
4. Docs: README.md (What you get, one line on the regression suite),
   PROJECT.md (template contents; replace the manual smoke-test wording in
   Working Rules with "run scripts/test-template.sh before calling a template
   change done", keeping the DDEV/composer "needs live verification" caveat;
   update Status).
5. Verify by running scripts/test-template.sh yourself before committing, and
   also break it on purpose once (reintroduce a fake {{TOKEN}} in Makefile,
   confirm the suite fails, revert) so the failure path is proven, not assumed.
No em dashes. Scripts stay 100755. GitHub Actions ${{ }} expressions untouched
except where the new job legitimately uses them.
```

---

## Stage 7: Make the module optional (site-only mode)

```
Make the custom module optional at init time. Two usage modes:
site-only (just spin up a Drupal or LocalGov site) and module mode (current
behaviour, developing a module against the site). Module mode must not change.

1. scripts/init.sh:
   - The module name prompt becomes optional: "Module machine name (blank for
     a site-only project)". Blank selects site-only mode; a name selects
     module mode exactly as today.
   - In site-only mode: skip the module label, path, and repo prompts
     entirely. Substitute the module tokens with values that keep every file
     valid: MODULE_NAME empty, MODULE_PATH web/modules/custom (the directory,
     so quality tooling scopes to all future custom modules), MODULE_REPO
     empty. Derive nothing else differently; flavour and version work as
     today.
   - Print a closing note in site-only mode: to add a module later, create it
     under web/modules/custom/ and set MODULE in the Makefile.
2. scripts/setup.sh: guard every module-specific step (clone, drush en) so a
   blank module name skips them silently with one informational line. The
   site install itself must be identical in both modes.
3. Makefile: with MODULE set to web/modules/custom, test/lint/stan/twig
   targets operate on the whole custom modules directory, which is correct
   for both modes; the module git targets (mod-log, mod-status, mod-fetch,
   mod-branch, tag, switch, mr) and the enable target must detect a
   site-only setup (MODULE has no repo of its own or no module name) and
   exit with a clear "site-only project" message instead of failing
   confusingly.
4. phpcs.xml.dist, phpstan.neon, package.json, .github/workflows/ci.yml,
   .claude/settings.local.json.dist, .claude/commands/a11y-check.md, and
   AGENTS.md: verify each stays valid and sensible when MODULE_PATH is
   web/modules/custom and MODULE_NAME is empty. The ci.yml phpunit step and
   the twig step already guard on directory contents; confirm the phpcs and
   phpstan steps tolerate an empty or module-free web/modules/custom (skip
   with a message rather than erroring on "no files to scan"). Reword the
   a11y-check page-selection line so it reads naturally when no module name
   is present.
5. AGENTS.md project context: in site-only mode the Module line should read
   as "none yet, site-only project" rather than an empty backtick pair.
   Handle this in init.sh (conditional substitution), not by hand.
6. Regression cover: scripts/test-template.sh (Stage 6) gains a site-only
   variant for at least one flavour/version combo, asserting init.sh exits 0
   with a blank module answer, no {{UPPER_SNAKE}} tokens remain, the Makefile
   parses, and setup.sh passes bash -n. If Stage 6 has not run yet, note that
   this requirement moves into its COMBOS design.
7. Docs: README.md (Use it section: mention the blank-for-site-only prompt;
   What you get), TEMPLATE.md token table (MODULE_NAME "blank for
   site-only"), PROJECT.md (template contents, conventions: both modes must
   keep working from now on).
8. Smoke-test both modes per the repo conventions before calling it done:
   one throwaway init in site-only mode and one in module mode, checking the
   usual invariants (tokens, ${{ }}, bash -n, make -n, executable bits).
No em dashes. Scripts stay 100755.
```

---

## Stage 8: drupal.org (git.drupalcode.org) pipeline parity

```
Modules developed with this template are pushed to git.drupalcode.org, where
the official gitlab_templates pipeline runs. Make sure a module that passes
locally also passes there, and ship a ready pipeline file for module repos.

0. Read the official docs first and treat them as authoritative over this
   prompt (the job list changes over time):
   https://project.pages.drupalcode.org/gitlab_templates/ (setup page and
   jobs page). As of 2026-07 the default validation jobs include
   composer-lint, cspell, eslint, stylelint, phpcs, and twig-cs-fixer, with
   phpunit and nightwatch as default test jobs; phpstan and variant testing
   (previous/next minor/major, max PHP) are controlled by OPT_IN_* /
   RUN_JOB_* / SKIP_* variables. Confirm the current defaults and the
   canonical .gitlab-ci.yml include block from the setup page.

1. Ship a ready module pipeline file: assets/module.gitlab-ci.yml containing
   the canonical include block from the docs plus a commented variables
   section (OPT_IN_TEST_NEXT_MAJOR, _TARGET_PHP, the relevant SKIP_ and
   RUN_JOB_ knobs, each with a one-line comment). Add a Makefile target
   module-ci that copies it to $(MODULE)/.gitlab-ci.yml if none exists, and
   refuses with a message if one does.

2. Local parity so make check predicts the drupalcode pipeline:
   - cspell: add a cspell config and a project-words file at the template
     root, wired to a Makefile target (spell) covering $(MODULE); seed the
     words file with obvious project terms (localgov, drush, ddev).
   - eslint and stylelint: run them against $(MODULE) using Drupal core's
     configs from the spun-up site (web/core/), the same approach the
     drupalcode jobs use; Makefile targets lint-js and lint-css, both via
     ddev exec. Guard each to skip with a message when the module has no
     .js or .css files.
   - Add spell, lint-js, and lint-css to the check aggregate target.
   - Note in the summary anything the drupalcode defaults run that local
     tooling still cannot (nightwatch is expected to stay CI-only; say so).

3. GitHub Actions ci.yml: add matching cspell, eslint, and stylelint steps
   to the php or prettier job, each guarded on relevant files existing, so
   the GitHub side of a project repo enforces the same standards.

4. Check for conflicts: Prettier formats CSS and JS in this template; core's
   eslint and stylelint configs are Prettier-aware, but verify on a sample
   file that prettier --write output passes both linters, and reconcile
   (adjust prettier config or scope) if not.

5. Docs: README.md (What you get: drupal.org pipeline parity and the
   module-ci target; Common commands table), PROJECT.md (template contents),
   AGENTS.md Working Rules line: PHP changes must pass make check, which now
   mirrors the git.drupalcode.org default pipeline.

6. Regression suite (if scripts/test-template.sh exists): assert
   assets/module.gitlab-ci.yml survives init.sh with no tokens left inside
   it if you tokenise it, or verbatim if you do not, and that make -n
   module-ci parses. Smoke-test per repo conventions either way.
No em dashes. Scripts stay 100755. GitHub Actions ${{ }} expressions and the
GitLab $ variables in the shipped pipeline file must both survive init.sh
untouched; extend the token regex checks to cover the new file.
```

---

## Vanilla + Drupal 10 live run

Requires Docker and DDEV running locally.

```
Run the vanilla + Drupal 10 live verification for this template. Work from a
throwaway copy so the template itself stays untouched.

1. Copy the repo to a temp dir (exclude .git and any _to_delete). In the copy
   run ./scripts/init.sh with: module name vanilla10_smoke, defaults for
   label, path, repo URL (blank), DDEV name, URL, client, and skill fork;
   flavour vanilla; version 10.
2. Verify the tokeniser result before spinning up: DRUPAL_TYPE=drupal10,
   COMPOSER_PROJECT=drupal/recommended-project:^10, INSTALL_PROFILE=standard;
   no leftover {{UPPER_SNAKE}} tokens outside PROJECT.md; ${{ }} expressions
   intact in ci.yml; setup.sh and install-drupal still executable; init.sh
   and TEMPLATE.md removed themselves.
3. Run ./scripts/setup.sh and let it do the full spin-up. Watch specifically
   for the two vanilla bugs fixed on the Drupal 11 run holding here too:
   drush/drush gets installed (vanilla does not bundle it) and the
   dev-tooling composer require resolves with -W against
   drupal/recommended-project:^10.
4. Confirm the site is actually up: ddev drush status reports Drupal 10.x
   with a successful database bootstrap, and the front page returns 200.
5. Run make check in the spun-up project to prove the quality toolchain on
   Drupal 10 (phpcs, phpstan, phpunit, twig-lint). Empty module test suites
   may skip; report that as skipped, not green.
6. Report pass/fail per phase. If Docker or DDEV is unavailable, stop after
   step 2 and say the spin-up still needs a live run. Do not claim success
   you did not observe.
7. On a full pass, in the REAL repo (not the throwaway): update PROJECT.md's
   Status section to record vanilla + Drupal 10 verified with today's date
   and drop its "not yet live-run" caveat, and update the matching line in
   the Status section of PROMPTS.md. If scripts/test-template.sh exists,
   confirm the vanilla 10 combo is present in COMBOS.
8. Clean up: ddev delete -Oy the test project and remove the temp dir.
No em dashes.
```
