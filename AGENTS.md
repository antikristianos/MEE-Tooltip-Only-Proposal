# MEE repair proposal

Read `D:/Zomboid/Workshop/AGENTS.md` first. This is an adapted third-party repair proposal for Afyrmo's Moodle Effects Explained, not an original mod. Do not register it in the B42 WIP collection. Its code, data, tests and reports belong to this repository.

Keep `upstream/` byte-identical to the documented local author baseline. Preserve attribution and never apply a new license to Afyrmo's code, descriptions or artwork. Keep source provenance and local changes clearly separated.

`Contents/mods/MoodleEffectsExplainedUnified/` is the single runnable proposal package. It has no `require`, `incompatible`, `loadAfter` or `loadBefore` metadata. Preserve original translation text, placeholders and internal MEE option keys. Detect only confirmed companion IDs, without requiring foreign modules.

Run `tools/Validate.ps1` for affected-project validation. Never claim in-game or multiplayer results from fixture tests. The prior tooltip-only three-variant candidate was accepted by the user. Unified candidate `009c836` has user-confirmed passes for manual tests 1-3; test 4 remains not performed.

GitHub publication is authorized for this named repair proposal. Steam upload and contacting the original author are separate actions and are not authorized. Preserve user changes before editing as required by the workspace rules.
