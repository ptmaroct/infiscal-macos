# Kubera Agent Notes

## Design System

- Keep primary app windows aligned with the Settings and Onboarding visual language: dark HUD/material background, compact glass cards, amber accents, and restrained macOS controls.
- Prefer `VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)` for major modal/window surfaces instead of the older `WindowBackground()` orb treatment.
- Use compact rows with SF Symbols, subtle dividers, and 6-10px corner radii. Avoid oversized cards, decorative gradients, or marketing-style layouts.
- For selectors, use Settings-style dropdown pills, segmented chips, or wrapped tabs. Project/environment controls should default to a valid selection when possible and expose clear all/project/env filter states.
- Keep action buttons icon-first where the icon is familiar, with `.help(...)` tooltips for icon-only buttons.
- Avoid scrollbars in Add Secret. The sheet should fit its complete form at its fixed window size. For chip groups, wrap with `FlowLayout` instead of horizontal scrolling.
- All Secrets should provide first-class filtering by project, environment, and search, and it must handle duplicate secret keys across projects/environments without crashing.

## Workflow

- Run `swift build` after Swift changes.
- When installing locally, build with `swift build`, run `bash scripts/bundle.sh`, then replace `/Applications/Kubera.app` and relaunch.
- Keep PR branches scoped. Do not stage generated app bundles or `.build` output.
