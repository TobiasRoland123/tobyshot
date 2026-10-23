# Suggested areas during Capture Area

Status: product definition agreed; ready for a feasibility prototype. Implementation and usability testing have not started.

GitHub issue: [#51 — Suggest screenshot areas on hover in Capture Area](https://github.com/TobiasRoland123/tobyshot/issues/51).

## Feature intent

Capture a clearly bounded piece of screen content without manually tracing its edges. In the existing Capture Area flow, hover to preview a suggested area, scroll to choose an enclosing or nested area, and click to capture. Dragging remains available for drawing a custom capture area.

Terms are defined in [CONTEXT.md](../../CONTEXT.md).

## Eligible areas in the first version

Suggestions target visually distinct, bounded containers, such as cards, panels, dialogs, and framed images. Content grouped only by meaning is not independently suggested: an unbounded paragraph inside a bordered card belongs to the card's suggested area.

Individual controls, including buttons, checkboxes, and input fields, do not qualify. Hovering over a control can suggest the smallest eligible container that holds it.

Start conservatively: omit containers whose edges can only be roughly guessed. A surrounding container with clear boundaries can still qualify. Otherwise, the user can draw a manual rectangle.

Omit containers that are partially off-screen, clipped, or obscured by another window. Fully visible containers within them can still qualify. Manual selection remains available for capturing a visible portion.

## Hover and scrolling

1. Ordinary hover highlights the smallest eligible container under the pointer. A separately framed chart inside a bordered card is suggested over the chart; the whole card is suggested over its surrounding background.
2. Scrolling follows the nesting path from the initially hovered area. One direction expands through chart → card → panel; reversing moves inward along the same path. This makes enclosing areas accessible even without exposed background.
3. Each scroll step that changes the selected area moves the pointer to that area's center. Scrolling updates the preview without capturing. A short on-screen hint explains the interaction.
4. The area chosen by scrolling stays highlighted while the pointer remains inside it, until another scroll step changes the selection or a manual drag starts. Small pointer movements do not reset the selection to a smaller container.
5. Preserve the original nesting path even if recentering lands over different nested content. Scrolling back inward returns to the original child area.
6. Leaving the selected area ends that nesting path and resumes ordinary smallest-area hover selection.

## Click and drag

Pressing and releasing without dragging captures the highlighted suggestion on release. A small movement tolerance distinguishes a slightly shaky click from a deliberate drag. Clicking with no highlighted suggestion does nothing.

Dragging anywhere, including inside a suggestion, draws a fresh manual rectangle from the original press point. Once dragging starts, suggestions disappear for that gesture and the rectangle does not snap to their edges. Releasing captures the manual rectangle.

A mouse press fixes the suggested target, or the absence of one, for that gesture. Suggestions arriving afterward cannot change what a click captures or interrupt a manual drag.

## Capture boundary

The suggested crop is a tight rectangle around the container's outer boundary, including its visible border, with no added padding or surrounding drop shadow. Rounded containers retain the background pixels visible within the rectangle at their corners. The highlighted rectangle corresponds exactly to the pixels included in the capture.

## Responsiveness

Detecting suggestions must not add a wait before Capture Area becomes usable. Manual dragging is available immediately; suggestions appear when ready. Actual readiness time needs measurement during prototyping. No fixed latency target has been agreed.

## Existing capture behavior to preserve

These are integration constraints from the current code, not new detection capabilities:

- Capture Area displays frozen screen snapshots and crops the chosen rectangle from the corresponding snapshot.
- Escape cancels selection, and selection is available across the connected displays.
- Existing actions after capture, such as copying, saving, annotating, or pinning, continue to apply. The chosen rectangle remains usable by Capture Previous Area.
- Dedicated window capture and recording selection retain their existing behavior; this feature concerns screenshot area selection.

Relevant code: [RegionSelector.swift](../../Sources/TobyShot/RegionSelector.swift), [ScreenCaptureService.swift](../../Sources/TobyShot/ScreenCaptureService.swift), and [AppCoordinator.swift](../../Sources/TobyShot/AppCoordinator.swift).

## Initial acceptance example

Use a browser dashboard with clearly bordered cards and nested charts as the primary test example. This is an agreed example category; no particular app or page has been selected.

The test screen should include a card with a heading, an unbounded paragraph, individual controls, and two separately framed charts. Place the charts so that expanding from one to the card recenters the pointer over the other. Include a surrounding panel, rounded borders and shadows, and variants with uncertain or partially hidden boundaries.

| Scenario | Expected result |
| --- | --- |
| Hover over an unbounded paragraph or button inside a card | Suggest the card, not the paragraph or control. |
| Hover over a separately framed chart | Suggest the chart as the smallest eligible area. |
| Scroll outward through chart → card → panel | Highlight each enclosing area and center the pointer in it; do not capture. |
| Recenter over a sibling chart, then scroll inward | Return along the original nesting path, not to the sibling. |
| Move slightly inside an area chosen by scrolling | Keep the chosen area highlighted. |
| Move outside that area | Resume ordinary smallest-area hover selection. |
| Click a highlighted area with slight pointer movement | Capture that area on release, within the click movement tolerance. |
| Start dragging inside a suggestion | Draw a fresh manual rectangle from the press point without snapping. |
| Click where no suggestion is highlighted | Do not capture. |
| Hover over an ambiguous, clipped, or obscured container | Omit that container; independently eligible visible containers can still qualify. |
| Capture a rounded, bordered card with a shadow | Include the border and visible corner pixels; add no padding or surrounding shadow. |
| Start a click or drag before suggestions finish arriving | Preserve the gesture's original target or manual selection. |

## Prototype checks and tuning

The interaction is specified, but reliable detection has not been demonstrated. The prototype should establish:

- Whether on-device detection can find useful containers, recover nesting, and distinguish containers from individual controls across representative layouts.
- Whether the initial conservative policy produces useful coverage. Review both inaccurate suggestions and missed containers, and adjust after testing.
- How quickly suggestions become available, while verifying that detection does not delay or interrupt manual capture.
- Appropriate click movement tolerance and scroll sensitivity for both a mouse wheel and a trackpad, including momentum and the ends of a nesting path.
- Whether pointer recentering feels predictable and works correctly across display positions and scaling settings.
- Whether crop boundaries, borders, shadows, clipping, and occlusion match the acceptance examples.

These checks guide implementation and tuning; they are not completed test results.

## Deferred scope

Suggestions for individual controls may be added later if needed. Suggestions for partially visible containers are outside the first version's scope. The conservative detection policy can be revised based on testing.
