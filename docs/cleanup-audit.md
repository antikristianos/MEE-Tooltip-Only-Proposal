# Unified package cleanup audit

## Removed runtime ownership

The runnable package contains no original Moodle-column renderer, icon/background/border texture lookup or cache, blink/oscillation state, native Moodle visibility scan, native hiding/movement callback, or external-renderer whitelist for choosing a replacement column. The old three-way package dependencies/incompatibilities and duplicate implementation packages are not present in `Contents/`.

## Follow-up cleanup

The unused `start()` method only set the legacy `active` property. That published-instance status is now initialized directly; rendering still never reads it. The redundant forward declaration for the shadow helper, obsolete baseline-selector test variable and unused icon-animation fixture fields were removed. Outdated code comments were corrected.

This preserves the visible tooltip behavior and the legacy singleton's published status. No profile texts, saved option identifiers or lookup rules were changed.

## Intentionally retained

- The zero-sized, non-interactive UI carrier performs tooltip drawing.
- The historical `MEEMoodlesLuaFallback` namespace/status and the marked Hi-Res-handle exclusion preserve existing integration boundaries; names alone do not imply an icon renderer.
- Font/description/shadow options, their translation and save keys, and the real Lua-renderer tooltip bridge provide current functionality.
- Standard/EM/DTEM namespaced profile content provides automatic choice and restoration. Public Standard keys provide the initial/native fallback until the selected profile is applied.
- Native order, visibility and text-layout caches are used by current tooltip selection/rendering.
- `mee_icon.png` and `mee_poster.png` are referenced metadata artwork, not obsolete runtime sprite assets.
- `upstream/` is an attributed read-only author snapshot outside the runnable package; it is not installed as runtime content.

All 52,848 existing native assertions still pass after cleanup. Unified tests 1-3 were reported passed by the user for candidate `009c836`; test 4 was not executed. No new manual result is invented by this maintenance pass.
