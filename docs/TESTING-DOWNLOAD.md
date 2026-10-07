# Testing the unified MEE repair proposal

This ZIP is an unofficial testing build for Afyrmo's review. Original code, descriptions, translations and artwork are credited to Afyrmo. It is not an official MEE/Steam release.

## Install locally

1. Exit Project Zomboid completely.
2. Extract the ZIP. Copy its **MoodleEffectsExplainedUnified** folder into your local Zomboid mod directory:
   - Windows: `%USERPROFILE%\Zomboid\mods\`
   - Linux/macOS: `~/Zomboid/mods/`
3. Keep the folder structure intact. For example, the metadata must be at `Zomboid/mods/MoodleEffectsExplainedUnified/42.20/mod.info`, alongside the package's `common` folder.
4. Start the game and enable **Moodle Effects Explained - Unified Repair Proposal** (`MoodleEffectsExplainedUnified`). Disable the three original MEE editions while testing this alternative.
5. Start a suitable test game. Tested game version: **Build 42.21**. The package's minimum metadata version is **42.20.2**; earlier builds were not executed in this work.

No Java agent, JAR, Workshop upload or additional MEE dependency is needed. Optional companion mods keep their own requirements. The package contains no dependency, incompatibility or load-order declarations.

## Expected automatic selection

| Enabled companion IDs | Description content |
| --- | --- |
| Neither | Standard MEE |
| `ExpandedMoodles` | EM |
| `DynamicTraits` | DTEM |
| Both, in either order | DTEM, with shared EM notes only once |

This is MEE description selection. It does not certify safe execution of overlapping gameplay mechanics from both companions. Enable only one Hi-Res edition at a time, and restart the whole process between mod configurations.

## What to review

- Native or foreign Moodle column remains the only column; MEE never moves/hides it or adds its own icons.
- Complete multiline tooltip background, correct icon/description association, fonts, description modes and background option.
- Automatic profile selection with no manual MEE-variant choice, including both companion activation orders.
- Existing supported foreign Moodle tooltip integration and unobstructed sidebar/inventory controls.
- Language changes and save/game reload retain the correct profile/text and fully sized tooltip.

## Recorded validation

52,848 existing native Translator/Kahlua assertions passed after the cleanup included in this ZIP. The user reported unified manual tests 1-3 passed for the preceding unified candidate; the subsequent cleanup preserves its visible behavior. **Manual test 4 (language change and save/game reload) was not performed.** No result is invented for it.

`PACKAGE-MANIFEST.json` identifies the exact source commit and SHA-256 of every packaged mod file. The separate `.sha256` download verifies the ZIP as a whole.

## Remove the local test copy

Exit the game, disable the proposal and remove only `Zomboid/mods/MoodleEffectsExplainedUnified`. Original Workshop files are not overwritten by this installation method.

Project and review documentation: https://github.com/antikristianos/MEE-Tooltip-Only-Proposal
