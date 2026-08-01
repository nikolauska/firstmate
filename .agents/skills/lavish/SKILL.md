---
name: lavish
description: Turn complex or visual agent responses into rich, reviewable HTML artifacts users can annotate and send feedback on, using an already available lavish-axi command. It applies to plans, comparisons, diagrams, tables, code diffs, reports, or other content easier to grasp visually than as prose, and excludes plain prose or simple answers.
metadata: { internal: true }
---

# Lavish Editor

Lavish Editor turns rich HTML artifacts into collaborative human review surfaces.
Before running any command, verify that `command -v lavish-axi` succeeds.
If `lavish-axi` is unavailable, stop and direct the operator to this repository's `bin/fm-bootstrap.sh` detection and approved installation path.
Continue only after the already available `lavish-axi` command is present.
Never substitute another launcher, runtime path, or installation workaround.

## Request

$ARGUMENTS

If the request above is non-empty, the user invoked `/lavish` explicitly, so build an HTML artifact for that request now.
If it is empty, infer what to visualize from the conversation.

## When to use

Use lavish-axi when the user asks for a visual artifact, HTML explainer, interactive prototype, review surface, product or technical plan, comparison, report, or browser-based feedback loop.
Do not use lavish-axi for plain prose or simple answers.

## Workflow

1. Create the HTML artifact at `.lavish/<name>.html` in the working directory unless the user specifies another location.
2. Run `lavish-axi <html-file>` to open or resume a review session in the browser.
If the user explicitly ended the session from the browser, the command refuses to reopen it without `--reopen`.
Pass `--reopen` only when the user asks for further review or something important needs their visual attention.
3. Run `lavish-axi poll <html-file>` to long-poll for the user's annotations and queued prompts.
On the first poll, prefer `--agent-reply "<one-line summary of what you built and what to review first>"` so the conversation panel opens with context.
Browser-detected layout issues are filed passively in the user's Layout issues inbox and arrive as an ordinary `layout-warnings` prompt only when the user selects and queues them.
Never edit an issue the user has not queued.
The only response that arrives without user action is `artifact_failures`, when the review surface itself is unusable.
The poll stays silent until the user acts or a fatal artifact failure makes the review surface unusable.
Leave it running and never kill it.
Cosmetic, intentional, transient, tiny, and uncertain observations remain silent.
Keep the poll in the foreground by default and let it return feedback directly to the agent.
A background poll is allowed only through a harness-native tracked background-job facility whose completion result is guaranteed to resume or notify the same agent.
Never use `nohup`, shell `&`, `disown`, redirected fire-and-forget processes, or a detached terminal without an explicit verified callback merely to keep polling alive.
If the harness has no completion-aware background facility, use the foreground poll or first wire a verified wake callback into the surrounding supervisor.
Do not tell the user the artifact is being monitored until that wake path is live.
If the poll gets killed or times out, rerun it because queued feedback is never lost.
4. If poll returns feedback, apply the user's prompts.
A `layout-warnings` prompt is an explicit repair request.
Apply every listed fix in one pass before saving, and let Lavish re-check it after a newer artifact load.
5. Apply human feedback, then poll again with `--agent-reply "<message>"` to reply in the browser and keep the loop going under the same foreground-or-verified-wake-path rule.
6. Run `lavish-axi end <html-file>` when the review is finished.
7. `Send & End` ends the session.
Its final feedback is still delivered once.
After that response, polling stops, and the agent must not reopen the session uninvited.
Deliver any remaining updates directly in the conversation.

## Visual guidance

- Use visual hierarchy to make the most important decisions, risks, tradeoffs, and next actions obvious at a glance.
- Use visual structure such as sections, cards, tables, diagrams, annotated snippets, and side-by-side comparisons instead of long prose.
- Choose typography, spacing, color, and layout deliberately so the artifact has a clear point of view.
- Prevent horizontal overflow at every nesting level.
Nested grid and flex children also need `minmax(0, 1fr)` tracks and `min-width: 0`, especially when badges, labels, or status text use wide pixel or monospace fonts.
Wrap, truncate, or contain long unbreakable text deliberately.
- When the artifact would describe existing or current UI or state, show it instead.
Capture screenshots of the real pages by running the app read-only if needed and embed them rather than explaining the current look in prose.
Reserve prose for rationale, tradeoffs, and open questions.

## Playbooks

Run `lavish-axi playbook <id>` for focused, detailed guidance on any matching playbook.
One artifact often combines several playbooks, such as a plan with a comparison and a diagram.
Open each matching playbook before writing HTML.
For flows, architecture, state, or sequence diagrams, do not hand-build boxes-and-arrows from div or flexbox.
Open the diagram playbook and use the theme-aware Mermaid snippet from `lavish-axi design` unless SVG is needed for richly annotated nodes.

- `diagram` - Map relationships, flows, state, and architecture.
- `table` - Turn dense records into scan-friendly review surfaces.
- `comparison` - Show options, tradeoffs, and current versus target behavior.
- `plan` - Explain a product or technical plan before implementation.
- `code` - Render source code, code files, patches, PR diffs, and before-and-after code inside Lavish artifacts.
- `input` - Must be used when the agent needs to collect user input on decisions, choices, preferences, triage, scope, or other structured feedback from within the artifact.
- `slides` - Create a deliberate presentation when slides are requested.

## Commands & rules

- Unless the user specifies another location, create HTML artifacts in the current working directory under `.lavish/`.
- Lavish serves the HTML file through a local server.
If the HTML needs filesystem assets such as images, CSS, fonts, or local scripts, copy them into the same directory as the HTML file and reference them with relative paths.
Never prepend `/` to those asset paths because root paths do not work.
- Rendered Mermaid diagrams in `.mermaid` containers become embedded, editable Excalidraw whiteboards in the browser.
Flowchart, sequence, class, ER, and state diagrams convert to editable shapes.
Other types embed as an image to draw on.
Scenes autosave locally.
When a reload detects changed Mermaid source, the reviewer explicitly chooses whether to re-convert and discard saved edits or keep editing the saved scene.
Standalone and exported copies still render plain Mermaid.
Queue feedback adds a prompt to the Conversation panel.
When poll returns a `whiteboard` prompt, read its bounded edit summary first, open the listed scene and preview files only when needed, and update the Mermaid source in the artifact rather than writing the scene back.
- Run `lavish-axi export <html-file> [--out <path>]` to write a portable copy of the artifact with local assets inlined.
Remote references remain links and may need network access to render.
Users can also export from the browser chrome's overflow menu.
- CLI publication is disabled.
Use the browser's publish workflow only after explicit user authorization for that specific artifact and a safe channel approved for its contents.
Never publish private, secret, customer, or otherwise sensitive content by default.
The browser publish dialog does not accept CLI token controls, and any preconfigured ambient token is handled internally.
Until deletion-key ownership exists, do not promise later updates or deletion, and prefer local review or `lavish-axi export` for content requiring lifecycle management.
- Run `lavish-axi stop` to shut down the background server.
The server also self-stops when idle or after the last session ends with nothing connected.
- Lavish does not auto-inject any design system, so artifacts stay portable when opened directly without the command running.
Before writing HTML, decide the design direction in this strict priority order.
First use a specific look or named design system requested by the user.
Otherwise inspect the project the artifact is about and match its design system, including Tailwind or theme config, shared CSS variables or design tokens, component libraries, brand assets, or existing styled pages.
If the artifact previews, proposes, or mocks a specific app's UI, render it in that app's own design system even when running in a different repository.
Only when both steps come up empty, use the Lavish-recommended Tailwind CSS browser runtime v4 with DaisyUI v5 available through a CDN.
Run `lavish-axi design` for a content-to-playbook router, a copy-pasteable CDN snippet, a Mermaid CDN snippet and initializer, and the DaisyUI component reference.
When delivering the artifact, state which design source you used and why.
