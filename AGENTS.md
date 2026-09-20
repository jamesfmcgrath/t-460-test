# Drupal Development Guidelines

This is a Drupal 10/11 project{{MODULE_INTRO}}{{THEME_INTRO}}. Follow these guidelines when working on Drupal code.

This file is the single source of truth for AI coding tools. Cursor reads it natively; Claude Code loads it via the `@AGENTS.md` import in `CLAUDE.md`. Edit this file, not the stub.

## Project Context

- **Module:** {{MODULE_LINE}}
- **Theme:** {{THEME_LINE}}
- **Custom code workspace:** `web/modules/custom/` and `web/themes/custom/`. Both are covered by `make check` and CI; keep new custom code inside them.
- **DDEV:** `{{DDEV_NAME}}` at `{{DDEV_URL}}` (PHP 8.3, nginx-fpm)
- **Stack:** Drupal 10.2+, LocalGov Drupal (LGD)
- **Do not use git worktrees**, work directly in the repo on the feature branch

## DDEV

Run all commands via DDEV from the repo root:

```bash
ddev drush <command>
ddev composer <command>
```

Never run `drush`, `php`, or `composer` directly outside DDEV, PHP versions will not match.

## Research-First

**Before writing custom code:** check drupal.org for existing contrib modules, and check whether a LocalGov module already covers it. Prefer contrib over custom.

## Code Standards

- **PHP 8.3**: constructor property promotion, typed properties, `declare(strict_types=1)` in every file
- **PHP Attributes**: `#[Block(...)]` style for plugins, not `@Block` annotations
- **Dependency injection**: never `\Drupal::service()` in classes; inject via constructor
- **Config schema**: required for all custom configuration (`config/schema/`)
- **`final` classes**: prefer `final` on service and form classes unless extension is required
- Add cache metadata to render arrays (`#cache`: tags, contexts, max-age)
- Use `#plain_text` or `Xss::filterAdmin()` for user content; never raw `#markup` with unsanitised input
- Parameterised queries only; never concatenate user input into SQL
- API keys: store in Key module entities, never in plain config

## Front-end Standards

- **Modern CSS**: flexbox/grid with `gap`, logical properties (`margin-inline`, `padding-block`), custom properties for design tokens, `clamp()` for fluid sizing, `aspect-ratio`. No floats for layout, no `!important` escalation.
- **DRY**: reuse existing tokens, components, and services before adding new ones. Repeated values become custom properties; repeated rule blocks mean the component should be extended, not copied.
- **Simple, clean code**: smallest change that solves the problem, lowest specificity that works, no speculative abstractions, delete dead code as you go.
- Use `rem`/`em` for type and spacing so user font scaling works; `px` only for borders and fine detail.
- Format front-end assets with Prettier (`make format`).

### Single Directory Components (SDC)

- Build new theme components as single directory components: one folder under the theme's `components/` directory holding the Twig template, the component definition, and that component's CSS and JS.
- Every component ships a `component.yml` with typed props (`props` schema, with `type`, `title`, and sensible defaults) and declared `slots` for anything the caller passes in as markup. An untyped prop is a bug.
- Component CSS and JS attach through the component itself (`libraryOverrides`, or the CSS/JS files the component picks up automatically), never through a loose theme-wide library. A component's assets load only when the component renders.
- Render components with `{% include %}`/`{% embed %}` against the `theme_name:component_name` id; do not reach into another component's internals.
- Scaffold with `drush generate single-directory-component` (`make component NAME=...`) rather than hand-rolling the folder, so the definition file and structure match core's expectations.
- Accessibility and the Front-end Standards above apply per component: semantic markup, keyboard operability, and contrast are part of the component, not a later pass.

## Accessibility

Council and public sector sites fall under the EU Web Accessibility Directive: legal minimum WCAG 2.1 AA (EN 301 549), and the 2026 EN update adopts WCAG 2.2 AA, so build and review to 2.2 AA. Treat accessibility findings like security findings: they block merge.

- Semantic markup first: landmarks, one `h1`, heading order, buttons for actions, links for navigation; ARIA only when native HTML cannot do it.
- Keyboard: everything reachable and operable, visible `:focus-visible` styles, never `outline: none` without a replacement, no positive `tabindex`.
- Contrast at least 4.5:1 for text and 3:1 for large text and UI components; meaning never conveyed by color alone.
- Motion behind `prefers-reduced-motion`; touch targets at least 24x24 CSS px; reflow at 320 px width and 200% zoom.
- Run the `/a11y-check` workflow (`.claude/commands/a11y-check.md`) after any template or CSS change.

## Drupal AJAX Form Pattern

When a form class injects a service used in an AJAX callback:

- The injected service property **must be `protected`** (not `private`/`readonly`) so `DependencySerializationTrait::__sleep()` can detect it. `private` properties are invisible to `get_object_vars()` from the parent scope.
- **Never override `__sleep()`**, the trait handles serialization once visibility is correct.
- AJAX callbacks must **build their result element directly** on `$form` before returning it; do not rely on `$form_state->setRebuild(TRUE)` inside the callback.

## Agent Resources

Use these proactively, do not wait to be asked.

- **drupal-localgov** (skill), Drupal 10/11 and LocalGov workflows: modules, theming, site building, ops. Use whenever a task touches Drupal.
- **drupal-expert** (skill), Drupal API, hook usage, architecture decisions before writing non-trivial code.
- **ddev-expert** (skill), DDEV container, config, or service troubleshooting.
- **drupal-reviewer** (agent), **run after writing or modifying any Drupal PHP file.** Catches security, DI, and render-escaping issues PHPCS will not.
- **a11y-check** (command), accessibility audit: axe-core scan plus keyboard, reflow, and motion passes. Run after template or CSS changes.

Install once via `./scripts/setup.sh` (see README).

## Working Rules

- Work incrementally: small, self-contained changes, tested as you go.
- Any PHP change ships with PHPUnit tests confirming correct behaviour; run the custom code test suite plus `phpcbf` then `phpcs` before considering a change done. PHP and front-end changes must pass `make check`, which mirrors the git.drupalcode.org default validation pipeline (phpcs, phpstan, twig-cs-fixer, cspell, eslint, stylelint).
- No em dashes in output. No code comments unless essential.
