# SwiftInferProperties — moved

The SwiftInferProperties PRD and source no longer live in this repo. As of 2026-04-30, SwiftInferProperties is an independent Swift package with a one-way dependency on SwiftPropertyLaws.

- **Repo:** [Joseph-Cursio/SwiftInferProperties](https://github.com/Joseph-Cursio/SwiftInferProperties)
- **Local checkout:** `~/xcode_projects/SwiftInferProperties/`
- **Canonical PRD:** `docs/SwiftInferProperties PRD v0.3.md` in that repo
- **Older drafts (v0.1, v0.2):** in this repo's git history, prior to commit `e272ba8` (2026-04-30)

The split was made so SwiftInferProperties can release on its own cadence and pull SwiftPropertyLaws via SPM, preventing accidental upward coupling.
