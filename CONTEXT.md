# TobyShot

TobyShot captures screenshots and provides an annotation editor for marking them up. Its language distinguishes suggested capture areas, annotation tools, and editable annotations.

## Language

### Capture

**Suggested area**:
A visually distinct, bounded container of screen content proposed for capture, such as a card, panel, dialog, or framed image. Content grouped only by meaning, such as an unbounded paragraph inside a card, is not a separate suggested area.

**Nested suggested area**:
A suggested area contained within a larger suggested area, such as a separately framed chart inside a bordered card.

**Nesting path**:
The sequence from an initially hovered suggested area through its enclosing suggested areas, such as chart → card → panel.

**Individual control**:
A single interactive element, such as a button, checkbox, or input field, distinct from the content container that holds it.

### Annotation editor

**Annotation**:
An individual editable object in the composition, such as an arrow, shape, text label, numbered step, redaction, pixelated region, or pasted image.

**Pasted image**:
A clipboard image placed above the original screenshot and below annotation marks. Select moves it; corner handles resize it while preserving its aspect ratio. Its bounds can expand the canvas in any direction. Drawing tools treat its interior as a surface for new annotations, including pixelation. Pasted images remain independent objects until export.

**Active tool**:
The tool currently chosen in the annotation toolbar. An active drawing tool and a selected annotation are separate concepts.

**Selected annotation**:
An annotation currently targeted for editing. Selection can contain one or more annotations.

**Select tool**:
The toolbar tool for selecting and manipulating existing annotations.
_Avoid_: Pointer tool, move tool.

**Arrow endpoint**:
Either end of an arrow, with an editing handle for changing that end's position.
_Avoid_: Edge, when referring to an arrow's endpoint.

**Arrow shaft**:
The line or curve connecting an arrow's endpoints, distinct from its arrowhead and editing handles.

**Bend handle**:
The middle editing handle that defines an arrow's curvature.

**Annotation outline**:
The visible border of an outlined shape, such as an unfilled rectangle or ellipse.

**Empty interior**:
The unfilled area enclosed by an annotation outline, excluding any other annotations within it. It is distinct from the outline and editing handles.

**Editing target**:
Where a gesture starts on an existing annotation: an editing handle, or a visible stroke, outline, or filled area within a small tolerance. With any drawing tool active, a gesture that starts on an editing target edits that annotation; one that starts on empty canvas, an empty interior, or a pasted image creates a new annotation. Handles take priority, and the choice holds for the whole gesture.

## Example dialogue

Developer: "Is the paragraph inside that bordered card a separate suggested area?"

User: "No. The card is the suggested area; the paragraph has no distinct visual boundary of its own."

Developer: "And the separately framed chart inside the card?"

User: "That is a nested suggested area. Its nesting path is chart, card, then the surrounding panel. A sibling chart has its own path through the same card and panel."

Developer: "When you say the arrow is selected, do you mean the Arrow tool or an annotation?"

User: "The Arrow tool is active, and the arrow I just drew is the selected annotation. Its endpoint handles, bend handle, and shaft are different editing targets."

Developer: "And the blank area inside that outlined rectangle?"

User: "That is its empty interior; the visible border is its outline."
