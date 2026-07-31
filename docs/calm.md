# Calm mode

Calm is a presentation toggle for the supported Pi and OMP extensions.
It is off by default, and the last `/calm` choice persists for the effective Firstmate home across Pi and OMP session starts, new sessions, and resumes.

## Pi presentation

While Calm is active and an agent run is under way, Pi hides its built-in `Working...` row and shows a small two-row animated boat in its place, and no separate Calm status row is added.
The water fills the usable width in standard ANSI blue and the complete boat is standard ANSI yellow.
The boat is deliberately calm: it moves one column every 880ms, while the water ripples on its own faster cadence so the surface stays alive between boat steps.
Its mainsail is directional, showing `<|` while travelling right and `|>` while travelling left, and it flips on the exact frame the boat turns at either edge.
Every resize reflows the sprite without wrapping, and it disappears when the run settles, aborts, or fails.
Within one Pi session and Calm extension lifetime, the next working period resumes the boat from its last rendered column and travel direction rather than restarting at the left edge.
Hidden elapsed time does not advance the animation, and a resize while hidden clamps the frozen boat to the new width without changing its valid travel direction.
A fresh Pi session or new Calm extension lifetime starts at the normal initial position.
Very narrow terminals fall back to a smaller deterministic sprite.
While Calm is off, Pi's stock working row is left exactly as Pi renders it.
Pi Calm hides collapsed thinking labels, the shells for Pi's seven built-in tools, the `fm_watch_arm_pi` tool shell, and canonically classified Firstmate operational user rows.
The operational inputs remain ordinary user-role messages, while Pi's transcript layout renders their complete rows at zero height.
The session-start nudge remains on its existing non-displayed custom-message path.

## OMP presentation

While Calm is active, OMP collapses tool output through its public `ctx.ui.getToolsExpanded()` and `ctx.ui.setToolsExpanded()` extension APIs.
Calm saves the user's current OMP tool-expansion choice and restores it when Calm is toggled off or the session ends.
During an active OMP agent run, Calm uses the public `ctx.ui.setWorkingMessage()` API to show the shorter `Working` presentation, retains it through automatic continuation, and restores OMP's stock working message when the run settles.
While Calm is off, OMP's stock tool-expansion and working-message presentation are left unchanged.
OMP Calm does not hide ordinary transcript rows because the verified OMP extension surface exposes no supported transcript-wide, ordinary-user, assistant, or built-in-tool renderer.
It does not add a widget or replace a renderer to simulate that missing boundary.

## Shared behavior and limits

Both implementations change presentation only.
Tool execution, input delivery, ordering, model context, session storage, diagnostics, and `/export` and `/share` operation remain unchanged.
Every hidden Firstmate input remains available to the model and in serialized session data and exported artifacts.
Legacy operational custom messages remain in session data and Pi's sidebar tree, although the main HTML transcript may omit them.
Toggling Calm off restores ordinary rendering, and Pi's `Ctrl+O` expansion state plus OMP's saved tool-expansion state are preserved.

Pi's supported presentation API does not expose a global transcript filter.
Expanded reasoning and its reserved spacing, built-in tool images, user-bash rows, skill and summary rows, generic status notices, and arbitrary custom-tool or extension rows remain visible when Pi does not expose a supported seam.
These are supported-API boundaries rather than hidden-content failures.

## Compatibility and ownership

Calm has no numeric Pi version minimum or maximum and never refuses Pi solely because its version is newer than a previously verified version.
The collapsed-thinking and operational-user-row presentation adapters probe the exact Pi API seam they patch when Calm loads.
If Pi removes one of those seams, Calm logs a diagnostic naming the unavailable adapter and skips only that adapter; `/calm`, the other adapter, and unrelated Pi extensions remain available.
OMP Calm uses the public `ExtensionContext.ui.getToolsExpanded()`, `setToolsExpanded()`, and `setWorkingMessage()` seams verified against the installed OMP 17.2.1.
OMP Calm deliberately has no fallback renderer claim when OMP does not expose a supported transcript-row seam.

[`calm-mode-feasibility.md`](calm-mode-feasibility.md) owns the version-scoped renderer taxonomy, OMP API boundary, and empirical evidence.
[`configuration.md`](configuration.md#calm-preference-configcalm) owns the persisted preference file and resolution rules.
`.pi/extensions/lib/fm-calm-visibility.ts` owns the Pi visibility policy, `.pi/extensions/lib/fm-calm-operational-user-layout.ts` owns the Pi zero-height operational-user row adapter, `.pi/extensions/lib/fm-calm-working-ship.ts` owns the Pi animated working presentation, and `.omp/extensions/fm-calm.ts` owns the OMP-native supported presentation.

Regression entry points:

```sh
tests/fm-calm-pi-extension.test.sh
tests/fm-calm-omp-extension.test.sh
tests/fm-pi-primary-types.test.sh
FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh
```
