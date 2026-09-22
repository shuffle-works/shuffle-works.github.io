# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.

## Publishing

This repo (`shuffle-works.github.io`) is vendored output, not hand-edited source. It's normally kept
in sync by `shuffle-works/shuffle-works-site-build`'s `Sync site` GitHub Actions workflow, which runs
`scripts/sync-static-sites.sh` on every push to that repo's main branch: it clones
`shuffle-works/sparkforensics` at its `build` ref, stamps the shared product-bar/footer/tokens chrome
(the `shuffle-works-*.css` files and `partials/shuffle-works-footer.html` in this repo's root),
relocates the Spark tuning reference to its own top-level mount, and regenerates `sitemap.xml` into
`sparkforensics/` and `spark-tuning-reference/` here.

If that workflow can't run (e.g. the build repo's Actions minutes are exhausted), reproduce it by hand:
clone `shuffle-works/shuffle-works-site-build` to a scratch dir, then run its
`scripts/sync-static-sites.sh` with `PUBLISH_ROOT` set to this repo's checkout root. Requires `gh auth
status` to succeed (the script shells out to `gh repo clone` itself). Read the script before running
it if anything is unclear, it's well-commented.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
