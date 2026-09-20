# Add a module later

Site-only projects (no module answered at `init.sh` time) can grow a custom
module at any point. The quality tooling already scopes to
`web/modules/custom` and `web/themes/custom` as a workspace, not to a single
named module, so a new module under that path is picked up automatically by
`make check` (PHPCS, PHPStan, PHPUnit, Twig CS Fixer).

## Steps

1. Create the module under `web/modules/custom/<module_name>`.
2. Set these in the `Makefile`:
   - `MODULE_NAME`: the module machine name.
   - `MODULE`: the module path, e.g. `web/modules/custom/<module_name>`.
3. Enable it:

   ```bash
   make enable
   ```

## What stays scoped to the module

Only the module-specific targets need `MODULE_NAME` / `MODULE` set:
`enable`, `module-ci` (copies the drupal.org GitLab CI pipeline into the
module), and the `mod-*` maintainer targets (`mod-log`, `mod-status`,
`mod-fetch`, `mod-branch`, `tag`, `switch`, `mr`): these assume the module
is its own git checkout (for example a drupal.org project clone).

## Widening the custom code workspace

If you add more than one module or theme, `LINT_PATHS` in the `Makefile`
already covers the whole `web/modules/custom web/themes/custom` tree, so no
change is needed there. It is mirrored in `phpcs.xml.dist`, `phpstan.neon`,
`package.json`, and the `LINT_PATHS` job env var in
`.github/workflows/ci.yml`. Change all five together only if you move
custom code outside those two directories.
