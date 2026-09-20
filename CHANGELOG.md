# Changelog

All notable changes to this template are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

## [1.0.0] - 2026-09-09

### Added

- Front page determinism fix for the "browser checks" CI job: the
  node-creation step now sets `system.site page.front` to the created
  node's path via drush, so both the axe-core scan and the VRT spec see
  real front-page content instead of LocalGov's anonymous `/user/login`
  redirect (whose randomly-chosen hero photo per request had also been
  producing a ~25% VRT pixel diff). This also corrects the axe-core scan,
  which had been silently auditing the login page rather than the front
  page. Live-verified against a fresh test project (see Stage 12 below).
- Documentation split: `PROJECT.md`, `PROMPTS.md`, and `memory.md` moved
  into `template-docs/`; `docs/` gained `getting-started.md`,
  `add-a-module-later.md`, `add-a-theme.md`, `recipes.md`, and
  `pipeline-parity.md`, `troubleshooting.md`; this `CHANGELOG.md` added
  (Stage 14).
- `scripts/setup.sh` now prunes upstream scaffold artefacts immediately after
  the `composer create-project` copy: `.github/workflows/test.yml`,
  `.gitlab-ci.yml`, `.gitpod.yml`/`.gitpod/`, `.lando.dist.yml`/`.lando/`,
  `.vscode/`, `README_FRONTEND_TOOLING.md`, and `phpstan-baseline.php`. These
  land untouched today because `cp -rn` only skips files that collide by
  name with this template's own; none of them are right for a project built
  from this template (`.github/workflows/test.yml` in particular can never
  pass, since it derives its composer ref from the branch name and no
  `dev-main` version exists). See `SCAFFOLD_PRUNE` in `scripts/setup.sh` for
  the full list and per-file reasoning.
  **Existing projects created before this change are not fixed
  retroactively: `init.sh` deletes itself and `template-docs/` on first run,
  so there is no update path back to the template. Delete
  `.github/workflows/test.yml` (and, if present, the other files above) by
  hand.**
  Live-verified with a full site install (not just `--skip-install`)
  against a fresh test project: all nine paths absent after `setup.sh`,
  and this template's own `ci.yml` survived with its tokens substituted.
- Non-interactive `init.sh`: every prompt has a matching flag, plus
  `--defaults` and `--help`; dynamic token discovery replaces a
  hand-maintained substitution list (Stage 13).
- Visual regression testing via Playwright (`make vrt`, `make vrt-update`),
  reusing the accessibility job's browser install (Stage 12). Live-verified
  end to end against a fresh test project: a first CI run with no Linux
  baseline generated and uploaded one as a build artifact, that baseline
  was committed, and a second run against it produced a green comparison
  with no diff; see `template-docs/PROMPTS.md` for the full observation.
- `recipes/dev_tools` and `recipes/site_tools`, `make recipe`, and local dev
  settings templates (`assets/settings.local.php`,
  `assets/development.services.yml`) applied automatically by `setup.sh`
  (Stage 11).
- Custom code workspace generalisation: quality tooling scopes to
  `web/modules/custom` and `web/themes/custom` rather than one hard-coded
  module; optional theme mode alongside the optional module, so module
  only, theme only, both, or neither all work; `make subtheme` and
  `make component` (Stage 10).
- axe-core + Playwright accessibility scan, replacing pa11y-ci, with
  runtime-derived scan URLs (Stage 9).
- drupal.org (git.drupalcode.org) pipeline parity: `assets/module.gitlab-ci.yml`,
  `make module-ci`, and local cspell/ESLint/Stylelint parity with the
  upstream pipeline's default jobs (Stage 8).
- Optional module (site-only mode): a blank module name is a fully
  supported project shape (Stage 7).
- `scripts/test-template.sh` regression suite, exercising `init.sh` across
  every flavour/version/module/theme combination, wired into CI (Stage 6).
- Drupal CMS flavour (`drupal/cms`, Drupal 11 only, the
  `recipes/drupal_cms_starter` recipe) (Stage 5).
- Twig CS Fixer (`make twig-lint`, `make twig-fix`) and a verified vanilla
  flavour live run (Stage 4).
- `agr.lock` policy: generated per created project rather than tracked in
  the bare template (Stage 2).

### Fixed

- pa11y-ci accessibility CI job committed; needs live verification on a
  project with `composer.json` present (Stage 3).

### Changed

- `.github/workflows/ci.yml`: bumped `actions/checkout` v5 to v7,
  `actions/cache` v5 to v6, `actions/setup-node` v5 to v7, and
  `actions/upload-artifact` v4 to v7 (current stable majors confirmed against
  each action's GitHub releases; none of the breaking changes between those
  majors apply to how this workflow uses them).
- Claude Code / Cursor reviewer gates upstreamed to the `drupal-agent-resources`
  skill fork, so the tracked `.claude/agents/` copy and the fork stay in
  sync (Stage 1).
