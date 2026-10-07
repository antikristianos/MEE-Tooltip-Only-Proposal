# Moodle Effects Explained: unified tooltip-only repair proposal

This repository is a repair proposal for **Afyrmo's [Moodle Effects Explained](https://steamcommunity.com/sharedfiles/filedetails/?id=3747745835)**. Original code, quantified descriptions, translations and artwork are credited to Afyrmo. It is a reviewable contribution proposal, with one runnable package and an attributed upstream snapshot; it is not an official MEE release. Proposal version: **0.1**, based on the locally installed MEE **1.1.3**.

## Why these changes help

MEE previously drew an additional Moodle column to work around Vanilla's fixed two-line tooltip background. That creates a second owner of icon placement, visibility and animation and can interfere with UI mods. This proposal leaves the column to Vanilla or its existing owner and draws only MEE's correctly sized tooltip. It removes MEE's native-root hiding/movement and icon renderer.

The three original MEE variants are consolidated into **one mod ID: `MoodleEffectsExplainedUnified`**. Its `mod.info` contains no dependencies, incompatibilities or load-order references. Companion mods are optional; their own requirements are unchanged.

| Activated companion IDs | Automatically selected content |
| --- | --- |
| Neither | Original Standard descriptions |
| `ExpandedMoodles` | Original Expanded Moodles descriptions |
| `DynamicTraits` | Original DTEM descriptions |
| Both, in either order | Original DTEM descriptions; no duplicated EM text |

DTEM's descriptions already contain EM-effect notes plus the trait-related notes. [Expanded Moodles is the separated Moodle portion of DTEM](https://steamcommunity.com/sharedfiles/filedetails/?id=3675868751). MEE accepts both IDs without metadata exclusions, but this does not certify that both gameplay mods can safely execute their overlapping mechanics together. The unified package selects description content; it does not alter either companion's gameplay.

## Load-order independence

Selection reads the complete `getActivatedMods()` list, not companion Lua globals, and never requires a foreign module. Each profile is stored in distinct namespaced translation keys, so translation-file load order cannot select a different profile accidentally.

After startup the chosen profile is copied to the existing native Moodle translation map through public `Translator.BY_NAME` and `HashMap` APIs. Values are copied raw: percent escapes and native line-break handling remain intact. This makes the selected descriptions available to native and foreign tooltip consumers alike. All 285 original keys per profile and all 28 languages retain their original text.

Startup/player events refresh selection; one deferred tick finishes after startup callbacks and then removes itself. There is no permanent profile poll or per-frame counter-correction. Missing profile data causes no partial translation writes.

The existing Moodles-in-Lua tooltip integration remains. Its startup discovery now also handles a class created by a later event handler: known renderer IDs permit at most ten once-per-second discovery attempts, with immediate teardown on success. Plain Moodles keeps its own column and tooltip. Unknown foreign renderers do not receive a guessed replacement column or tooltip bridge.

## Native tooltip repair

Vanilla's private `moodleUiState` is not accessed from Lua. The native constructor's default Java HashMap is reproduced with the exact same registry keys and insertion order, and its key set is read through public `ArrayList(Collection)` APIs. This preserves the actual native ordering, including invisible registered keys. Hover selection follows current native UI coordinates and logical row pitch. Geometry and text layouts are cached.

The zero-sized, non-interactive tooltip carrier retains the historical `MEEMoodlesLuaFallback` name for older Hi-Res compatibility code, but draws no Moodle icons. It works without Hi-Res and with release/WIP editions. Fonts and the MEE / MEE + Vanilla / Vanilla description options remain available. The native shadow option controls the background only; text remains available when it is disabled.

## Validation status

The preceding three-variant tooltip-only candidate was reported ingame successful by the user on **2026-10-07**; its exact acceptance is recorded in [the acceptance note](docs/accepted-tooltip-tests.md). That acceptance is not relabelled as a pass for the later unified package.

The new candidate passes **52,848 assertions** against installed PZ **Build 42.21**:

- 4,266 tooltip/owner-order/cache/foreign-bridge assertions with actual Kahlua, Java keys and native Moodle UI objects.
- 48,582 profile assertions using the native `Translator.tryFillMapFromFile` reader and public Lua map APIs, across all 28 languages and six activation combinations, including both companion orders and rejection of the unrelated `DynamicTraitsSE` lookalike.
- Complete preservation of each original profile string, native percent/line formatting, all-or-nothing writes on missing data, delayed startup teardown and bounded foreign-class discovery.
- Lua syntax, single-package metadata and Git whitespace checks.

Production Lua needs no debug mode, Java agent or added JAR. Reflection exists only in test fixture setup/oracles. Rendering primitives and character inputs in the tests are fixtures: the new profile/package behavior still requires the manual test in `docs/reports/`.

```powershell
./tools/Build-Package.ps1
./tools/Validate.ps1 -PZRoot 'path/to/ProjectZomboid' -JdkRoot 'path/to/JDK'
```

The executed validation uses JDK 25. See [the test log](docs/validation/automated-tests.txt). The runnable version slice starts at B42.20.2; only installed B42.21 was executed here. Older original MEE slices were not newly validated or silently advertised as supported.

## Trying the proposal

Use `Contents/mods/MoodleEffectsExplainedUnified` as a local mod package. Enable **Moodle Effects Explained - Unified Repair Proposal** and disable the three old MEE editions, which share internal MEE state and are alternate implementations of the same mod. There are no formal incompatibility declarations. Restart the whole game process between mod configurations.

Only one MEE provider is required. Choose companions normally; do not manually select an MEE variant or reorder it around those companions. The new behavior still needs its own ingame acceptance before being described as accepted or release-ready.

No Steam Workshop ID has been created or changed. No Workshop upload is performed by this repository or its tools.

## Review and attribution

- `upstream/`: exact attributed local author baseline for the active slice and common files. It remains unchanged.
- `Contents/`: the single proposed runnable package.
- `tools/Build-Package.ps1`: deterministic namespaced profile generation; no authored prose changes.
- `tests/`: native runtime regression checks.
- [Contribution summary](docs/PROPOSAL_FOR_AUTHOR.md): behavior, benefits and integration boundaries.
- [Attribution](ATTRIBUTION.md): ownership and snapshot provenance.

A public upstream MEE repository was not discoverable in the recorded search. This standalone repository allows the original author to review the changes and integration approach without presenting the proposal as their official project.
