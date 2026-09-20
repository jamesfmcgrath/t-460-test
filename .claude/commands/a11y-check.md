---
name: a11y-check
description: Accessibility audit of site pages against WCAG 2.2 AA (legal minimum WCAG 2.1 AA / EN 301 549)
arguments: "[url-or-path ...]"
---

# Accessibility Check

Audit one or more pages of `{{DDEV_URL}}` for accessibility. If paths are given as arguments, test those. Otherwise test a representative set of page types {{MODULE_AFFECTS}} (at minimum: the front page, one listing page, one detail page, and one page with a form).

Public sector context: legal minimum is WCAG 2.1 AA (EN 301 549); test to WCAG 2.2 AA. Before fixing anything found here, consult the drupal-expert or drupal-localgov skill so fixes are made the Drupal way (Twig templates and render arrays, not JS patches), and finish by running the drupal-reviewer agent on the changed files.

## Step 1: Automated scan (axe-core)

If browser tools (Claude in Chrome) are available: navigate to each page, inject axe from the CDN, and run:

```js
const s = document.createElement('script');
s.src = 'https://cdnjs.cloudflare.com/ajax/libs/axe-core/4.10.2/axe.min.js';
document.head.appendChild(s);
// wait for load, then:
const results = await axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'] } });
console.log(JSON.stringify(results.violations.map(v => ({ id: v.id, impact: v.impact, wcag: v.tags, count: v.nodes.length, sample: v.nodes[0]?.target }))));
```

Fallback without browser tools: `npx @axe-core/cli {{DDEV_URL}}/<path>` (ask before installing).

## Step 2: Keyboard pass

For each page, verify by driving the browser or by inspecting the relevant Twig and CSS:

1. Skip link present and functional.
2. Tab reaches every interactive element in a logical order; no positive `tabindex`.
3. Focus always visible; `:focus-visible` styles exist; no `outline: none` without a replacement.
4. Menus, accordions, modals: Escape closes, no focus trap, focus returns to the trigger.

## Step 3: Zoom, reflow, and motion

1. Content reflows at 320 px viewport width with no horizontal scroll and no loss of content (WCAG 1.4.10).
2. Page remains usable at 200% zoom.
3. Animations and transitions are gated behind `prefers-reduced-motion`.

## Step 4: Quick content checks

1. One `h1` per page; heading levels do not skip.
2. Images have appropriate `alt` (empty for decorative).
3. Form fields have programmatically associated labels; errors are announced.
4. Touch targets at least 24x24 CSS px (WCAG 2.2, 2.5.8).
5. Text contrast at least 4.5:1 (3:1 for large text and UI components); nothing conveyed by color alone.

## Step 5: Report

Group findings by WCAG success criterion with severity (critical / serious / moderate / minor), the axe rule id, affected selector, and the likely source (module template, theme, or content). Distinguish issues fixable in this project's custom code from theme issues and from upstream (core / contrib / LocalGov) issues that should be reported upstream.

## Fix rules

- Fix in the correct layer: markup in Twig, styling in CSS following the Front-end Standards in `AGENTS.md`.{{THEME_LAYER}}
- Where the affected markup is a single directory component, fix it inside that component (its Twig, its CSS), not in a theme-wide override.
- Prefer native HTML semantics over ARIA. ARIA is a last resort.
- After fixes: `ddev drush cr`, re-run the scan on affected pages, and run the drupal-reviewer agent.
