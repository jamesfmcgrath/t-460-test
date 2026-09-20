# Recipes

Apply any recipe by hand with:

```bash
make recipe R=recipes/site_tools
```

`scripts/setup.sh` applies both shipped recipes automatically after site
install (`--no-dev-tools` / `--no-site-tools` to skip either).

## `recipes/dev_tools`

Devel, Environment Indicator, and its toolbar integration. Local-only:
`assets/settings.local.php` excludes it from configuration sync via
`config_exclude_modules`, and `assets/development.services.yml` turns on
Twig debug and disables Twig/render/page caching. Both are copied from
`assets/` into `web/sites/default/` by `scripts/setup.sh`.

## `recipes/site_tools`

Admin Toolbar, Twig Tweak, ECA with its BPMN visual modeller. Meant for
production, so it exports on the next `drush cex`, unlike `dev_tools`.

## The config-export caveat

This template does **not** set `$settings['config_sync_directory']`, so
Drupal falls back to its own default: a `files/sync` path inside the public
files directory. That path is gitignored and web-served, so `site_tools`'s
exported config is not actually tracked in git out of the box.

To track it, set `$settings['config_sync_directory']` to a project-root
path yourself, for example:

```php
$settings['config_sync_directory'] = '../config/sync';
```

Also note `config_exclude_modules` only keeps a dev module's own enablement
out of exported config, not config entities that module creates along the
way. Projects wanting stricter local/production config discipline may want
[`drupal/config_split`](https://www.drupal.org/project/config_split) later;
this template documents the gap but does not implement it.
