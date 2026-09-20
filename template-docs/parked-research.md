# Parked research: editorial preview for decoupled Drupal

Provenance: copied 2026-09-10 from claude_future-explorations.md in the
Claude Project (recorded there 2026-08-06). Not carried over: the section
pairing this template with the Astro template, made obsolete by the
2026-09-09 decision in memory.md that the Astro sibling is independent, and
a clause referring to the dropped shared-contract docs. The research dates
from 2026-08; recheck upstream issue status and tooling before relying on it.

## Editorial preview for decoupled sites

James considers this THE blocker for decoupled sites of any flavour, and
wants it solved properly, not worked around. Capture of the current state
of the art so a future session starts warm:

- Drupal side, the draft data is already reachable: core JSON:API supports
  revision access via the resourceVersion query parameter, including
  rel:working-copy for the latest draft (permission-gated). Known core
  rough edges: multilingual multiple-draft scenarios and wrong revisions
  in includes have open issues; check their status when starting.
- The reference implementation to study is next-drupal (the Next.js for
  Drupal project plus its Drupal-side "next" module): its preview flow is
  editor clicks preview in Drupal -> Drupal builds a signed preview URL to
  the front end -> front end enters draft mode, fetches working-copy
  content server-side with an authenticated request, renders uncached.
  The pattern is framework-agnostic even though the implementation is
  Next-specific.
- Astro translation of that pattern: the site stays static except a
  server-rendered /preview route (prerender = false, needs an adapter
  even on otherwise-static sites). The route validates a signed token
  from Drupal (simple_oauth or a shared-secret HMAC), fetches the
  working-copy revision via JSON:API server-side, and renders with the
  same components the static build uses, bypassing cache. Reusing the
  static build's components is the key move: preview fidelity comes free
  because there is only one rendering path.
- Open questions to resolve when building: token issuance UX on the
  Drupal side (a "next"-module equivalent for Astro, probably a tiny
  custom module the Drupal template ships as a recipe); iframe preview
  inside the Drupal admin versus a new-tab preview; how close live-editing
  expectations (Experience Builder era) make plain draft preview feel
  dated, and whether that matters for the actual editorial workflows in
  scope.
- Same problem generalises to the WordPress sibling if it ever goes
  headless; solve it once as a pattern (signed token + server preview
  route + shared components).

## WordPress sibling (mapped, unscheduled)

Only a summary survives. The full mapping was recorded in
claude/roadmap-2026-08.md, which is not in this repo or the Claude Project.
Summary as recorded: Bedrock, wp-cli, WPCS, phpstan-wordpress,
@wordpress/scripts configs, Plugin Check as the CI parity target,
Playground blueprints as the recipes analog, Query Monitor plus WP_DEBUG as
dev_tools, WP_ENVIRONMENT_TYPE as the core environment indicator.
