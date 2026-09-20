# Getting started

## Create and initialise

1. Create a repo from this template (GitHub "Use this template"), then clone it.
2. From the repo root, run the initialiser:

   ```bash
   ./scripts/init.sh
   ```

   It prompts for the module name and path (blank to skip the module), the
   theme name (blank for no custom theme), DDEV site, client, skill fork,
   and the Drupal flavour (`localgov`, `vanilla`, or `cms`) and version
   (`11` or `10`; Drupal CMS is Drupal 11 only). Every prompt also has a
   flag, so the same run works unattended; see the main `README.md` for the
   full flag list and `--defaults`. `init.sh` tokenises every file, writes
   `template.answers`, then removes itself.

## Set up the environment

```bash
./scripts/setup.sh
```

This installs the agent resources, starts DDEV, scaffolds and installs the
Drupal site for your chosen flavour, adds dev tooling (PHPCS, PHPStan,
PHPUnit, Prettier), clones your module if you gave a repo URL, and enables
it. Use `--skip-install` to stop before installing the site.

## First login

```bash
ddev launch      # open the site
ddev drush uli    # one-time login link
```

Run `make help` for the full task list. To reinstall or switch profile
later: `./scripts/install-drupal` (interactive) or
`./scripts/install-drupal localgov` (direct).

## Next steps

- Adding a theme: see `add-a-theme.md`.
- Growing a site-only project into a module later: see `add-a-module-later.md`.
- Optional dev/site tooling recipes: see `recipes.md`.
- Something not working: see `troubleshooting.md`.
