# TobyShot annotation editor

The annotation editor is the workspace for marking up a screenshot. Its language distinguishes the tool used to create annotations from the annotations being edited.

## Language

**Annotation**:
An individual editable mark on a screenshot, such as an arrow, shape, text label, numbered step, redaction, or pixelated region.

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
Where a gesture starts on an existing annotation: an editing handle, or a visible stroke, outline, or filled area within a small tolerance. With any drawing tool active, a gesture that starts on an editing target edits that annotation; one that starts on empty canvas or an empty interior creates a new annotation. Handles take priority, and the choice holds for the whole gesture.

## Example dialogue

Developer: "When you say the arrow is selected, do you mean the Arrow tool or an annotation?"

User: "The Arrow tool is active, and the arrow I just drew is the selected annotation. Its endpoint handles, bend handle, and shaft are different editing targets."

Developer: "And the blank area inside that outlined rectangle?"

User: "That is its empty interior; the visible border is its outline."
