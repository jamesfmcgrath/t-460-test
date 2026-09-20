# Add a theme

If you skipped the theme prompt in `init.sh`, add one by hand:

1. Create the theme under `web/themes/custom/<theme_name>`.
2. Set `THEME_NAME`, `THEME_LABEL`, and `THEME_PATH` in the `Makefile`.
3. Run `make subtheme` (only scaffolds if `THEME_PATH` does not already exist).

## What `make subtheme` does

- On LocalGov flavour: generates a [LocalGov Base](https://github.com/localgovdrupal/localgov_base)
  subtheme via `localgov_base`'s own `create_subtheme.sh`. Requires
  `drupal/localgov_base` to already be installed
  (`ddev composer require drupal/localgov_base` if it is not).
- On vanilla or Drupal CMS flavour: generates a theme with Drupal core's
  starterkit generator (`vendor/bin/dr generate-theme` or
  `core/scripts/drupal generate-theme`). See the
  [core starterkit theming docs](https://www.drupal.org/docs/develop/theming-drupal/using-starterkit-theme-generator).

After scaffolding, enable it:

```bash
ddev drush theme:enable <theme_name> -y
ddev drush config:set system.theme default <theme_name> -y
```

## Single Directory Components (SDC)

Build new components as SDCs: one folder under the theme's `components/`
directory, scaffolded with:

```bash
make component NAME=promo_card
```

This runs `drush generate single-directory-component` so the definition
file and structure match core's expectations. Conventions (from
`AGENTS.md`, the source of truth):

- Every `component.yml` has typed `props` (type, title, sensible defaults)
  and declared `slots` for caller-supplied markup. An untyped prop is a bug.
- CSS/JS attach through the component itself, never a loose theme-wide
  library, so a component's assets load only when it renders.
- Render with `{% include %}` / `{% embed %}` against `theme_name:component_name`;
  do not reach into another component's internals.
- Semantic markup, keyboard operability, and contrast are part of the
  component, not a later pass. Run `/a11y-check` after template/CSS changes.

See core's [Single Directory Components docs](https://www.drupal.org/docs/develop/theming-drupal/using-single-directory-components)
for the full schema reference.
