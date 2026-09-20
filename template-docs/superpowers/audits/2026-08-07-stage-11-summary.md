# Stage 11 summary: local dev recipes

Date: 2026-08-07
Branch: `feat/staage-11-local-dev-recipes` (kept as-is, not merged or pushed)
Plan: `template-docs/superpowers/plans/2026-08-06-local-dev-recipes.md`
Final commit: `62482ee`

## Summary

Stage 11 (local dev recipes) is complete: 13 commits across 11 planned tasks
plus one reopened fix round and one final-review fix wave, all task-reviewed
and a final whole-branch review clean. Regression suite is 462/462.

## What shipped

- Two Recipes: `recipes/dev_tools` (devel, environment_indicator,
  environment_indicator_toolbar), `recipes/site_tools` (admin_toolbar,
  admin_toolbar_tools, twig_tweak, eca, eca_ui, bpmn_io)
- `assets/settings.local.php` + `assets/development.services.yml` (local dev
  settings templates)
- `scripts/setup.sh` wiring: composer requires including version-aware
  ECA/bpmn_io (3.x on Drupal 11, 2.x on Drupal 10), template copying, recipe
  application, config export
- `make recipe` target
- Verified live against a real throwaway `localgov 11` DDEV project

## Two real bugs caught and fixed

Both found beyond what static/diff review could catch:

1. **`drush recipe` path bug** (found by live verification): `ddev drush`
   runs from the docroot, not the project root, so both `scripts/setup.sh`'s
   recipe-apply calls, and, caught only in final review, the `make recipe`
   target itself, silently failed on every project built from this template.
   Fixed in both places (commits `8f8a140`, `62482ee`).

2. **Twig debug unverified on 2 of 3 flavours**: traced independently (no
   DDEV needed, just `composer create-project`) and found the
   live-verification "pass" was accidental. LocalGov's own project template
   already ships Twig debug on, so the template's own
   `development.services.yml` copy step never actually ran. Vanilla Drupal
   core's default does not enable debug at all, so vanilla/cms are likely not
   getting Twig debug today. `setup.sh` now verifies and warns honestly
   instead of claiming silent success; flagged in PROJECT.md as needing a
   live check on those two flavours.

## Also corrected

- An inaccurate "exports into config/sync" claim (the real target is a
  gitignored, web-served path since `config_sync_directory` is not
  configured)
- Stale status docs that briefly claimed a bug was unfixed after it had
  actually been fixed

## Known follow-ups (documented, not implemented)

- Twig debug needs a live check on vanilla and cms flavours
- `config_sync_directory` is not set to a git-tracked path by this template;
  projects wanting tracked config exports must configure it themselves
- `config_exclude_modules` only covers module enablement, not config
  entities a dev module creates; `drupal/config_split` may be wanted later
  for stricter config discipline
