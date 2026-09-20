# Claude Code agents (tracked)

`drupal-reviewer.md` is fetched here by `scripts/setup.sh` (from the
drupal-agent-resources repo) if it is not already present. Once committed, the
tracked copy is canonical: setup.sh will not overwrite it unless you pass
`--force-reviewer`. Pin `REVIEWER_REF` in setup.sh to a tag or commit to control
exactly which version you get.
