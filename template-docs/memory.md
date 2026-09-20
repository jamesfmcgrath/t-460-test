# Project memory: localgov-drupal-dev-template

Last updated: 2026-09-10 (closed two loose ends left open by the 2026-09-09
pass, then re-checked two carried-forward notes against the tree before
deciding whether to write them up as a new stage). The 2026-09-09 pass was a
truth pass against the tree, done the same day as Stage 12 live verification
against a fresh test project; the version before that was dated 2026-08-06
and was silent on Stages 12 through 14, which had already landed on main by
then. Every stage-status claim in this file is checked against git history
and the working tree before being written, never carried forward unverified.
See template-docs/PROJECT.md's "Keeping status honest" section for the rule
this pass follows.

2026-09-16: parked research filed into template-docs/parked-research.md and
pointed to below. No status claim in this file was re-checked by that edit.

## What this is

GitHub template repo (github.com/jamesfmcgrath/localgov-drupal-dev-template).
Create a project from it, run ./scripts/init.sh (tokeniser), then
./scripts/setup.sh (one-command DDEV spin-up), and get a running Drupal or
LocalGov Drupal site ready to code in. Full detail lives in PROJECT.md;
staged improvement prompts and their status live in PROMPTS.md.

## Decisions

- 2026-09-09: the Astro sibling diverged into its own repo and Claude Project; the shared-contract approach between the two templates was dropped, and this repo is now maintained independently.

## Parked research (not scheduled, not verified)

- Editorial preview for decoupled Drupal, plus a summary of the WordPress
  sibling mapping: template-docs/parked-research.md. Copied out of the Claude
  Project on 2026-09-10, researched 2026-08. Nothing in it has been checked
  against current upstream issue status or tooling; recheck before relying
  on it.

## Corrections (previous notes that were wrong, not merely stale)

- setup.sh has always scaffolded with `cp -rn` (recursive, no-clobber), not
  `cp -n`. PROJECT.md previously said `cp -n`; that was wrong from the start,
  since `cp -n` alone cannot copy a directory tree. Corrected here and in
  PROJECT.md.
- Stage 15 does not exist anywhere in this repo: no commit, no PROMPTS.md
  entry, no prompt template. An earlier review session's note that Stage 15
  had landed was wrong, not stale. There is nothing to mark as landed,
  partial, or even planned; the numbering simply stops at Stage 14.
- A 2026-09-10 session was asked to write a new stage for two items carried
  as notes since before Stage 12 (make subtheme live proof on vanilla/cms,
  and the make stan spurious exit 1), both originally scoped into the same
  phantom Stage 15 above. Checked against the tree first, per the rule this
  file follows: both were already resolved in the 2026-08-10 cleanup batch
  (commit f035cd0), and neither the Makefile nor phpstan.neon has changed
  since (`git log f035cd0..HEAD -- Makefile phpstan.neon` returns nothing).
  No new stage was created; writing one for already-resolved work would have
  repeated the exact stale-note error this section exists to correct.
  PROMPTS.md's Stage 10 entry, which still read "still open" for both, is
  corrected to match. The next unused stage number is still 15; nothing has
  claimed it.
- The axe-core accessibility scan was, until the 2026-09-09 fix landed,
  silently auditing `/user/login` rather than the front page on every fresh
  LocalGov install, because of LocalGov's anonymous-visitor redirect off
  `/`. Any earlier accessibility pass recorded against `/` (this includes
  the discarded dev-test project's local checks) is evidence about the
  login page, not the front page, and must not be cited as an accessibility
  result for real site content. Only the 2026-09-09 live run against
  `/node/1` (via the `page.front` fix) counts as a front-page accessibility
  check.

## Flavours and versions

- localgov: Drupal 11 and Drupal 10.
- vanilla: Drupal 11 and Drupal 10.
- cms (Drupal CMS): Drupal 11 only (drupal/cms, recipe
  recipes/drupal_cms_starter). Tokeniser-level support DONE (2026-08-05);
  full spin-up still needs a live run (unchanged since 2026-08-06; no commit
  since has touched this).
- Usage modes: module and theme are independent optional prompts, so four
  combinations. Module only, theme only, both, and neither must all keep
  working.

## Custom code workspace

Quality tooling scopes to LINT_PATHS ("web/modules/custom web/themes/custom"),
not to a single module. Mirrored in five places: Makefile (LINT_PATHS),
phpcs.xml.dist (file entries), phpstan.neon (paths), package.json (globs), and
.github/workflows/ci.yml (job-level env var). Change it in all five or none.
$(MODULE) and $(MODULE_NAME) stay for enable, module-ci, and the mod-* targets;
$(THEME_PATH) stays for subtheme and component.

## Stage status, verified against the tree on 2026-09-09

Stages 1 through 11 are as previously recorded in PROMPTS.md and were not
re-audited line by line in this pass (out of scope; see PROJECT.md's
"Keeping status honest" note on scope). Stages 12 to 15 were the subject of
this pass, checked directly against git history and the working tree:

- Stage 12, visual regression testing: VERIFIED (2026-09-09). Landed
  2026-08-10 (commit 0b62495, merged via fd6273a); the front-page
  determinism fix landed 2026-09-09 on branch fix/vrt-front-page, PR #5,
  merged via e6fdfbd. Both are now live-verified end to end against a fresh
  test project (github.com/jamesfmcgrath/lgd-stage12-verify-20260909-215334,
  localgov flavour, Drupal 11, module and theme both configured), not the
  discarded dev-test project.
  What was actually observed on 2026-09-09, in order: PR #5's Actions run on
  the bare template correctly SKIPPED the php/prettier/browser-checks jobs
  (no composer.json yet) and the guard plus a "Template regression suite"
  job passed; this is recorded as skipped, not passed, and is not evidence
  the fix works. No action-resolution failures or removed-input warnings
  from the bumped majors (checkout v7, cache v6, setup-node v7,
  upload-artifact v7) in the jobs that did run; cache/setup-node/
  upload-artifact live only in the jobs that were skipped here, so this PR
  run alone did not exercise them.
  A fresh project was then created from the template, `init.sh` then
  `setup.sh` run for localgov/Drupal 11/module+theme, and the site installed
  cleanly end to end via DDEV. Once pushed (composer.json now present), the
  guard flipped and php/prettier/browser-checks all ran for real. The
  browser-checks job: created node 1, ran
  `vendor/bin/drush config:set system.site page.front "/node/1" -y`
  (confirmed in the job log), then axe-core scanned 2 pages ("/" and
  "/node/1") with 0 violations, confirming the scan hit real front-page
  content and not the /user/login redirect. The VRT spec found no
  tests/vrt/__screenshots__/linux/ baseline, generated one
  (front-page.png, node-1.png), and uploaded it as build artifact
  vrt-baselines-linux instead of failing the job. Those two PNGs were
  downloaded with `gh run download` and committed to the project repo. A
  no-op commit was then pushed to trigger a second run: its browser-checks
  job log reads "Committed Linux baselines found; comparing against them."
  followed by "2 passed" — a genuine green comparison against the committed
  baseline, not a second bootstrap. This is the proof this stage was
  waiting for; both runs passed on the first attempt, so there was no
  diff to diagnose.
  Also reconfirmed in the same pass: all nine SCAFFOLD_PRUNE artefacts
  (.github/workflows/test.yml, .gitlab-ci.yml, .gitpod.yml, .gitpod/,
  .lando.dist.yml, .lando/, .vscode/, README_FRONTEND_TOOLING.md,
  phpstan-baseline.php) were absent after setup.sh on this fresh project,
  and the template's own .github/workflows/ci.yml survived with its
  {{TOKENS}} substituted (checked directly, no {{UPPER_SNAKE}} tokens
  remain). This supersedes the e8f63eb commit message's earlier
  `--skip-install` scaffold-only check with a full site-install run.
- Stage 13, non-interactive init and dynamic token discovery: DONE. Landed
  2026-08-10 (commit 56f50ac, merged via 564d2e1, status corrected in
  fcf3775). Confirmed present in scripts/init.sh: a flag for every prompt,
  --defaults/--help, validation before the first prompt, template.answers
  written before substitution, and the grep -rlE-based discovered
  substitution list (checked directly in the script, not assumed from
  PROMPTS.md). This stage needs no live DDEV/composer verification: it is
  tokeniser-level only, already covered by scripts/test-template.sh without
  touching the network, and that suite passes today.
- Stage 14, docs split, shipped project docs, changelog: DONE. Landed
  2026-08-12, commit ce3b536, a direct commit to main (not a PR merge).
  Confirmed present in the tree: template-docs/ holds PROJECT.md, PROMPTS.md,
  and memory.md (moved from the repo root); docs/ holds getting-started.md,
  add-a-module-later.md, add-a-theme.md, recipes.md, pipeline-parity.md, and
  troubleshooting.md; CHANGELOG.md exists at the repo root. Gap this pass
  closed: ce3b536 never added its own entry to PROMPTS.md's ledger, and this
  file was never updated to mention Stages 12 through 14 at all until now.
- Stage 15: does not exist. See Corrections above.

## Verification status (stages before 12; unchanged since 2026-08-06, not re-checked by this pass except where noted)

- LocalGov + Drupal 11: verified end to end.
- LocalGov + Drupal 10: verified end to end.
- Vanilla + Drupal 11: verified end to end (2026-07-28); fixed three setup
  bugs (lowercase "standard" profile match, composer require -W, drush/drush
  install for vanilla).
- Vanilla + Drupal 10: verified end to end (first run 2026-07-29, re-run
  2026-08-05 with no issues). Installs and boots on Drupal 10.6.14, front
  page 200, make check clean.
- LocalGov + Drupal 11, theme-only project: verified end to end (2026-08-06).
- LocalGov + Drupal 11, module and theme both configured, full DDEV/composer
  site install (not --skip-install): verified end to end (2026-09-09), as
  part of the Stage 12 live verification above.

## Open items / needs live verification (checked 2026-09-09: no commit since 2026-08-06 resolves any of these; confirmed still open by reading the intervening git history, not assumed)

- cms flavour live run: dev-tooling require completing on a cms project, and
  make check against a real module (module mode), both still pending.
- a11y CI job (axe-core) on real GitHub Actions infrastructure: RESOLVED
  2026-09-09. Ran live in the Stage 12 verification above (0 violations
  across 2 pages, against real front-page content, not the login redirect).
  Only the localgov/Drupal 11/module+theme combination was exercised;
  vanilla and cms flavours have not run this job live yet.
- Stage 12 VRT live verification: RESOLVED 2026-09-09. See Stage status
  above.
- Site-only mode full DDEV/composer spin-up (site install, not just
  scaffold): still open. Note for future verification: a scaffold-and-prune
  smoke test that passes --skip-install to setup.sh does not satisfy this
  item, since it stops before the site install step this item is asking
  about.
- make lint-js / lint-css and the GitHub Actions eslint/stylelint steps
  against a live web/core frontend install: still open.
- PHP version: still 8.3 in .ddev/config.yaml (confirmed by reading the
  file). Bumping to 8.4 needs a live check that LocalGov 4.x's contrib
  dependency tree resolves and runs cleanly on 8.4 first; not attempted.

## Caveats resolved and confirmed still resolved in the tree (checked 2026-09-09)

- `make stan` spurious exit 1: phpstan.neon carries only `parameters.level`
  and `parameters.paths`, no `drupal_root` key and no explicit
  phpstan-drupal `includes:` block (confirmed by reading the file directly).
  Matches the 2026-08-10 fix; still correct.
- `make subtheme` on vanilla: Makefile prefers `vendor/bin/dr generate-theme`
  when present, falling back to the legacy `web/core/scripts/drupal` call
  otherwise (confirmed by reading the Makefile directly). Still correct.
- `make subtheme` cspell vocabulary: the Makefile still appends a
  marker-guarded, deduplicated block of generic subtheme words to
  .cspell-project-words.txt after scaffolding (confirmed by reading the
  Makefile directly). Still correct.

## Release status

v1.0.0 tagged 2026-09-09, once Stage 12 live verification (both the
scaffold prune and the VRT baseline round-trip) passed against
lgd-stage12-verify-20260909-215334. Release notes drawn from CHANGELOG.md's
former Unreleased section, now moved under the `[1.0.0]` heading. The only
other tag in the repository is `v-a11y-1` (confirmed with `git tag -l`).

Test project disposition (decided 2026-09-10): jamesfmcgrath/lgd-stage12-verify-20260909-215334
is KEPT as the standing verification project, not deleted. Created
2026-09-09T20:53:37Z per `gh repo view` (confirmed live, not from memory),
from the template at commit e6fdfbd (the PR #5 merge), functionally
identical to the a4200ed tag commit, which only added documentation
(confirmed with `git show --stat a4200ed`: CHANGELOG.md and template-docs/
only). It is the sole artifact evidence behind the v1.0.0 tag: the committed
Linux VRT baselines, both browser-checks run logs, and the scaffold-prune
check all live only in that project's history. Deleting it would leave those
claims with no reproducible evidence, unlike the earlier dev-test project,
which really was disposable and cost nothing to discard once its findings
were folded into this file.

What it has proven, and on what date:
- 2026-09-09: the Stage 12 VRT round-trip (missing-baseline generation and
  artifact upload on the first real run, committed baseline, genuine green
  comparison on the second run) and the nine-artefact SCAFFOLD_PRUNE check,
  both against a real localgov/Drupal 11/module+theme site install. See the
  Stage 12 entry above.
- 2026-09-10: confirmed directly from the actual GitHub Actions job logs
  (`gh api .../actions/jobs/<id>/logs`, not inferred from the browser-checks
  job passing) that the PHP and Prettier jobs ran for real in the two pushes
  after the guard flipped (runs 34404280850 and 34404569476), and that
  actions/checkout@v7, actions/cache@v6, and actions/setup-node@v7 each
  resolved with a valid SHA and zero `##[warning]` lines in both job logs;
  actions/upload-artifact@v7 is not invoked in either job (confirmed by
  grep) and was separately confirmed clean in the browser-checks job logs of
  the same two runs. This closes the 2026-09-09 note's gap: browser-checks
  passing alone did not establish this for PHP and Prettier, and now the
  actual per-job logs do.

Evidence expiry: this project proves the template as it stood at
e6fdfbd/a4200ed (v1.0.0). Any future claim resting on it (the VRT
round-trip, the scaffold prune, the four action-version bumps) must be
re-verified against a fresh spin-up if setup.sh, .github/workflows/ci.yml,
tests/vrt/vrt.spec.mjs, or scripts/a11y-scan.mjs change after that commit.
Do not cite this project's history as current evidence for a changed
template, the way the earlier discarded dev-test project's stale evidence
was wrongly cited twice in the 2026-09-09 session.

## Conventions (hard rules)

- No em dashes anywhere.
- Scripts stay executable, committed 100755.
- Only UPPER_SNAKE names wrapped in double curly braces are tokens; GitHub
  Actions ${{ }} expressions must never be touched.
- Run scripts/test-template.sh before calling any template change done.
- Keep all flavours, both Drupal versions, and all four module/theme
  combinations working.
- Status claims in this file, PROJECT.md, and PROMPTS.md are checked against
  git history and the working tree before being written, not carried forward
  from a previous note or an external conversation. The tree wins over any
  document.
