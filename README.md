# LocalGov Drupal dev-environment template

A starting point for working locally on a Drupal 10/11 module, theme, or site, with Claude Code and Cursor agent resources, coding standards, and DDEV wiring already set up. Built for LocalGov Drupal (council) projects, but works for any Drupal project.

## What you get

- Claude Code + Cursor agent resources installed reproducibly via [`agr`](https://github.com/kasperjunge/agent-resources): `drupal-expert`, `ddev-expert`, and `drupal-localgov` skills, plus the `drupal-reviewer` agent.
- Shared coding, review, and accessibility standards in a single `AGENTS.md` (read natively by Cursor and most agents; Claude Code loads it via the `@AGENTS.md` import in the `CLAUDE.md` stub).
- An accessibility audit workflow (`.claude/commands/a11y-check.md`): axe-core scan plus keyboard, reflow, and motion passes, aimed at WCAG 2.2 AA (the public sector legal floor is WCAG 2.1 AA / EN 301 549).
- A DDEV config and a one-command `scripts/setup.sh` that starts DDEV, scaffolds a Drupal project (LocalGov, vanilla, or Drupal CMS, chosen at init), prunes the upstream flavour's own CI and local-environment files (its GitHub Actions workflow, Lando/Gitpod/VS Code config, and unscoped PHPStan baseline; see `SCAFFOLD_PRUNE` in `scripts/setup.sh`), installs the site, adds dev tooling, and enables your module if you configured one (site-only projects skip that step).
- A custom code workspace rather than a single hard-coded module: the quality tooling scopes to `web/modules/custom` and `web/themes/custom` (the `LINT_PATHS` list), so a project can hold any number of custom modules and themes and still get one `make check`.
- Local development settings applied automatically: `web/sites/default/settings.local.php` (Twig debug on, Twig cache off, the render/page/dynamic_page_cache bins null-backed) and `web/sites/development.services.yml`, copied from `assets/` by `scripts/setup.sh`. Two Recipes carry the rest: `recipes/dev_tools` (Devel, Environment Indicator, its toolbar integration) is local-only and excluded from configuration sync; `recipes/site_tools` (Admin Toolbar, Twig Tweak, ECA with its BPMN visual modeller) is meant for production and exports on the next `drush cex` (to wherever this project's `config_sync_directory` points, which this template does not configure to a git-tracked path by default). `setup.sh` applies both after the site install (`--no-site-tools` / `--no-dev-tools` to skip either); `make recipe R=path` applies any recipe by hand.
- An optional custom theme alongside the optional module, so module only, theme only, both, or neither all work. `make subtheme` scaffolds the theme: a LocalGov Base subtheme via the generator LocalGov Base ships, or Drupal core's starterkit generator on vanilla and Drupal CMS. `make component NAME=x` adds a single directory component.
- PHP tooling wired to the Makefile: PHPCS (Drupal, DrupalPractice), PHPStan (phpstan-drupal), PHPUnit, Twig CS Fixer for Twig templates (Prettier does not lint Twig), plus Prettier for front-end assets.
- A GitHub Actions CI workflow (`.github/workflows/ci.yml`) running PHPCS, PHPStan, Twig CS Fixer, PHPUnit (unit + kernel), the Prettier check, and a "browser checks" job (axe-core accessibility scan, WCAG 2.2 AA, plus the visual regression test below) against an installed sqlite site, on push and pull request.
- Visual regression testing (`tests/vrt/vrt.spec.mjs`, `playwright.config.mjs`): reuses the same `@playwright/test` install the accessibility job already brings in, screenshotting the pages in `scan-urls.json` and comparing against committed baselines. Baselines are generated and compared on Linux/CI only (font rendering makes cross-OS baselines flaky); see "Visual regression" below.
- drupal.org (git.drupalcode.org) pipeline parity: `assets/module.gitlab-ci.yml` is a ready `.gitlab-ci.yml` for the module, copied in with `make module-ci`, and local tooling (`make check`) mirrors the same pipeline's default validation jobs. See [`docs/pipeline-parity.md`](docs/pipeline-parity.md) for what matches and what stays CI-only.
- A `scripts/test-template.sh` regression suite that exercises `init.sh` across every supported flavour/version combo and all four module/theme combinations, wired into CI so the bare template gets a real, green run instead of skipping everything.
- A `scripts/init.sh` that turns the template into your project by filling in a handful of tokens.

## Requirements

- [DDEV](https://ddev.com) and Docker (required; `setup.sh` aborts without DDEV)
- git (required)
- [uv](https://docs.astral.sh/uv/) and [agr](https://github.com/kasperjunge/agent-resources) for the Claude Code / Cursor skills (recommended). Install once:

  ```bash
  # uv (macOS / Linux)
  curl -LsSf https://astral.sh/uv/install.sh | sh
  # agr
  uv tool install agr
  ```

`setup.sh` installs the skills with `agr` when it is present and skips with a hint if not. It does not install `uv` or `agr` for you, so install those first if you want the agent resources.

## Use it

1. Create a repo from this template (GitHub: "Use this template"), then clone it.
2. From the repo root, run the initialiser and answer the prompts:

   ```bash
   ./scripts/init.sh
   ```

   It asks for the module name (leave blank to skip the module, which also skips the module label/path/repo prompts) and path, the theme name (leave blank for no custom theme, which also skips the theme label prompt), DDEV site, client, skill fork, and the Drupal flavour (`localgov`, `vanilla`, or `cms`) and version (`11` or `10`; Drupal CMS is Drupal 11 only). Module and theme are independent, so module only, theme only, both, and neither are all valid. It tokenises every file, then removes itself.

   Every prompt also has a flag, so the same run works unattended (in a script, a container, or CI):

   ```bash
   ./scripts/init.sh \
     --module localgov_bus_data --module-label "LocalGov Bus Data" \
     --module-path web/modules/custom/localgov_bus_data \
     --module-repo git@git.drupal.org:project/localgov_bus_data.git \
     --theme cumberland_theme --theme-label "Cumberland Theme" \
     --ddev-name lgd-bus-data-dev --ddev-url https://lgd-bus-data-dev.ddev.site \
     --client "Cumberland Council bus timetables" --skill-fork jamesfmcgrath \
     --flavour localgov --version 11
   ```

   Anything you leave out is still prompted for, so flags and prompts mix freely. `--defaults` accepts every default and leaves the module and theme blank, which is the fastest route to a site-only project:

   ```bash
   ./scripts/init.sh --defaults                     # site-only, localgov, Drupal 11
   ./scripts/init.sh --defaults --theme my_theme    # defaults, plus a custom theme
   ```

   With `--defaults`, or with a full flag set, `init.sh` never touches a tty. Use the `--flag=value` form for a deliberately empty value: `--module=""` selects site-only mode instead of falling back to the prompt. `./scripts/init.sh --help` lists every flag.

   The resolved answers are written to `template.answers` in the project root before substitution. Commit it: it records what the run decided (prompted values and the derived `DRUPAL_TYPE`, `COMPOSER_PROJECT`, and `INSTALL_PROFILE`), so the initialisation is auditable afterwards and repeatable as a flag invocation.
3. Spin the whole environment up with one command:

   ```bash
   ./scripts/setup.sh
   ```

   This installs the agent resources, starts DDEV, scaffolds and installs the Drupal site for your chosen flavour, adds the dev tooling (PHPCS, PHPStan, PHPUnit, Prettier), clones your module if you gave a repo URL, and enables it. Use `--skip-install` to stop before installing the site.
4. Start coding: `ddev launch` to open the site, `ddev drush uli` for a login link, and open the project in Claude Code or Cursor. Run `make help` for the task list.

To reinstall or switch profile later, run `./scripts/install-drupal` (interactive menu) or `./scripts/install-drupal localgov` (direct).

## Tokens

`init.sh` replaces these placeholders. See `TEMPLATE.md` for the full list and where each appears.

| Token | Example |
|---|---|
| `{{MODULE_NAME}}` | `localgov_bus_data` (blank for no custom module) |
| `{{MODULE_LABEL}}` | `LocalGov Bus Data` |
| `{{MODULE_PATH}}` | `web/modules/custom/localgov_bus_data` |
| `{{MODULE_REPO}}` | `git@git.drupal.org:project/localgov_bus_data.git` |
| `{{THEME_NAME}}` | `cumberland_theme` (blank for no custom theme) |
| `{{THEME_LABEL}}` | `Cumberland Theme` |
| `{{THEME_PATH}}` | `web/themes/custom/cumberland_theme` |
| `{{DDEV_NAME}}` | `lgd-bus-data-dev` |
| `{{DDEV_URL}}` | `https://lgd-bus-data-dev.ddev.site` |
| `{{CLIENT}}` | `Cumberland Council bus timetables` |
| `{{SKILL_FORK}}` | `jamesfmcgrath` |

From your flavour/version answers, `init.sh` also derives `{{DRUPAL_TYPE}}` (DDEV type, e.g. `drupal11`), `{{DRUPAL_FLAVOUR}}` (`localgov`, `vanilla`, or `cms`), `{{COMPOSER_PROJECT}}` (e.g. `drupal/localgov_project`), and `{{INSTALL_PROFILE}}` (e.g. `localgov`).

## Common commands

A `Makefile` wraps the everyday tasks (run `make help` for the full list):

```bash
make help          # List all targets
make start         # Start DDEV (also stop / restart / open / logs)
make xdebug-on     # Enable Xdebug (also xdebug-off)
make install       # Clean install, choose a profile
make si            # Fresh LocalGov install
make enable        # Enable the module
make cr            # Clear caches
make snapshot      # Create a DDEV database/files snapshot (also restore)
make import DB=path/to/dump.sql.gz   # Import a database dump
make subtheme      # Scaffold the custom theme (LocalGov Base subtheme or core starterkit)
make component NAME=promo_card   # Scaffold a single directory component
make test          # PHPUnit (also lint / lint-fix / stan)
make check         # lint + stan + test + twig-lint + spell + lint-js + lint-css
make twig-lint     # Lint Twig templates (also twig-fix)
make module-ci      # Copy the drupal.org GitLab CI pipeline into the module
make recipe R=recipes/site_tools   # Apply a recipe
make format        # Prettier format front-end assets (also format-check)
make vrt           # Visual regression test (Playwright); comparisons are authoritative on Linux/CI only
make vrt-update    # Regenerate VRT baselines; commit only when generated on Linux/CI
make mod-status    # Module git status (also mod-log / mod-fetch / mod-branch)
make switch BRANCH=1.0.x     # also: make mr MR=123, make tag VERSION=1.0.0-alpha1
```

## Visual regression

`tests/vrt/vrt.spec.mjs` screenshots every path in `scan-urls.json` against a running site and compares each with `expect(page).toHaveScreenshot()` (full page, animations disabled, 1% max diff pixel ratio). It reuses the `@playwright/test` install the accessibility job already brings in rather than adding a second browser-test stack.

Baselines are generated and compared on **Linux only**, because font rendering differs enough between macOS and Linux to make cross-OS baselines flaky. Playwright suffixes each baseline with the OS it was generated on (`tests/vrt/__screenshots__/linux/…`, `tests/vrt/__screenshots__/darwin/…`); the `linux/` directory is the one that is committed, `darwin/` is gitignored. On a Mac, that means:

- `make vrt` / `make vrt-update` locally are **advisory only**: useful to confirm the plumbing works, not to generate baselines to commit.
- Generate and refresh real baselines inside CI (the "browser checks" GitHub Actions job) or a Linux container/VM, then commit the resulting `tests/vrt/__screenshots__/linux/` directory.
- In CI, a missing `linux/` baseline is not a failure: the job generates it and uploads it as a build artifact for review and commit. Once baselines exist, genuine diffs fail the job and the HTML diff report uploads as an artifact.

**Alternative:** [BackstopJS](https://github.com/garris/BackstopJS), including the official [`ddev/ddev-backstopjs`](https://github.com/ddev/ddev-backstopjs) add-on, is a well-supported alternative if you specifically want its standalone HTML report UI. This template does not run both stacks side by side: `@playwright/test` already ships here for accessibility testing, has `toHaveScreenshot()` built in, and already has a working install-serve-scan CI pattern, so adding BackstopJS as well would mean maintaining two browser-automation stacks for one job.

Live-verified locally (2026-08-10) against a throwaway LocalGov 11 install: screenshots generate and the comparison correctly fails on a real diff. On a fresh install with no front page configured, `/` redirects anonymous visitors to `/user/login`, whose LocalGov Design System template shows a randomly chosen hero photo per request (a genuine ~25% pixel diff between two loads, not a bug in this plumbing). Point `scan-urls.json` at real, deterministic pages once a project has content; a login page with rotating decorative imagery is a poor VRT target on any project.

## Updating an existing project

`init.sh` deletes itself and `template-docs/` on first run, so a project
created from this template has no update path back to it: there is no
command that pulls in later template changes. Check `CHANGELOG.md` in this
template's repo for what has landed since your project was created, and
apply anything relevant by hand.

## Notes

- Custom code lives in the workspace the quality tooling scopes to: `web/modules/custom` and `web/themes/custom`. That list is `LINT_PATHS` in the `Makefile`, and it is mirrored in `phpcs.xml.dist`, `phpstan.neon`, `package.json`, and the `LINT_PATHS` job env var in `.github/workflows/ci.yml`. To widen it, add the path in those five places. The module-specific targets (`enable`, `module-ci`, `mod-*`) stay scoped to the configured module; `subtheme` and `component` stay scoped to the configured theme.
- Agent resource folders (`.claude/skills/`, `.cursor/skills/`) are gitignored and reproduced by `agr` from `agr.toml` + `agr.lock`. Do not vendor copies. Tracked canonical files: `AGENTS.md`, `CLAUDE.md` (import stub), `agr.toml`, `.claude/agents/`, `.claude/commands/`, `.claude/settings.local.json.dist`.
- The `drupal-localgov` skill is hosted in a fork of `drupal-agent-resources` (`{{SKILL_FORK}}/drupal-agent-resources`). Point `{{SKILL_FORK}}` at whichever fork you maintain.
- `agr.lock` is not committed in this bare template, since `{{SKILL_FORK}}` is still a token and agr cannot resolve it into a lock. `scripts/setup.sh` runs `agr sync`/`agr add` on first run, after `init.sh` has substituted a real GitHub owner, which generates `agr.lock`. Commit that generated `agr.lock` in the project created from this template so skill versions are pinned for the rest of the team.
- `config_exclude_modules` (set in `assets/settings.local.php`) only keeps a module's own enablement out of exported config; it does not exclude any config entities a dev-only module might create along the way. Projects with strict config discipline may want `drupal/config_split` for a more complete local/production split later; this template does not implement that, only documents the gap.
- This template does not set `$settings['config_sync_directory']`, so Drupal falls back to its own default (a `files/sync` path inside the public files directory, which `.gitignore` already excludes and which is web-served). Projects that want `site_tools`'s exported config actually tracked in git need to set `$settings['config_sync_directory']` to a project-root path (for example `'../config/sync'`) themselves; this template does not do that for you.
