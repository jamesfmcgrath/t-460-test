# drupal.org pipeline parity

`assets/module.gitlab-ci.yml` is a ready `.gitlab-ci.yml` for the module,
copied in with `make module-ci`. Local tooling mirrors the same pipeline's
default validation jobs: cspell (`make spell`), ESLint and Stylelint
(`make lint-js`, `make lint-css`) using Drupal core's own configs, alongside
the existing PHPCS/PHPStan/Twig CS Fixer, so `make check` predicts what runs
on git.drupalcode.org.

Twig CS Fixer is skipped by default upstream; the shipped pipeline turns it
back on to match this template's local tooling.

Nightwatch (browser JS tests) and Composer Lint have no local or GitHub
Actions equivalent and stay CI-only.

The cspell config and dictionary (`cspell.json`, `.cspell-project-words.txt`)
live at this template's root, not in `make module-ci`'s copy. A module split
into its own drupalcode.org repo needs its own copy of those two files for
full parity on that job.
