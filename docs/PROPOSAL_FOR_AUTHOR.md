# Proposal for Afyrmo

## Problem and proposed behavior

The native Moodle UI draws a fixed two-line tooltip background. MEE's longer translated descriptions overflow it. Replacing the entire Moodle column fixes tooltip sizing but introduces unnecessary ownership of icon placement, visibility, animation and foreign UI interactions. The existing external tooltip path also attempted a private Java-field read that is unavailable to normal Lua.

This proposal makes MEE a tooltip extension: native/foreign owners keep their column, MEE measures and draws its text/background, and public collection APIs reproduce the actual native order. The preceding tooltip-only change has user-reported ingame acceptance. Unified-package manual tests 1-3 are also user-confirmed passes; language change/reload test 4 was not performed and remains unconfirmed.

## One package instead of three mutually exclusive editions

The proposal stores all original Standard/EM/DTEM content under unique translation namespaces, chooses by activated mod ID and applies the selected raw values after startup. The public native translation map serves all consumers, rather than making profile-specific prose exist only in MEE's own tooltip. Optional companions require no dependency or incompatibility declaration in MEE.

`DynamicTraits` selects DTEM, including when `ExpandedMoodles` is also active; otherwise EM selects its profile, and absence of both selects Standard. Detection is independent of companion script initialization. DTEM already includes the shared EM notes, so concatenating both profiles would duplicate them. This is description selection, not a gameplay interoperability patch between the two companions.

## Benefits and retained behavior

- One selectable MEE mod with automatic companion detection.
- Original descriptions and localization retained verbatim across all 28 languages.
- No competing Moodle column, native-root hiding, permanent coordinate corrections or new Java dependency.
- Existing font, description-mode and shadow controls, with text preserved when the native shadow is disabled.
- Existing supported foreign tooltip paths retained, including delayed discovery of late-created real Lua-renderer classes.
- Exact native-order matching and text/geometry caching.
- Tests and author snapshots provide a reviewable boundary between original material and changes.

## Review limits

Validated runtime: installed Build 42.21. Future native map/order changes, unsupported foreign tooltip systems and older B42 APIs require separate checks. Both companion IDs are handled by MEE in either order; this does not assert that redundant gameplay effects from both companions are safe. Manual results are documented separately for the previous and unified candidates, without extending test 1-3 passes to the unperformed fourth point.

The runnable package uses a proposal-specific mod ID so the author can inspect it alongside the local baseline. It should be enabled alone as the MEE provider. The original Workshop ID is unchanged, and no Steam upload is part of this proposal.
