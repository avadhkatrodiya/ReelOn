# AI Workflow Note

## Tools used

- Codex (this workspace) for implementation, refactoring, and documentation.

## How AI was used

- Requirement extraction and synthesis from assignment PDF.
- Scaffolded backend schema + endpoint implementation.
- Generated and refined Flutter UI architecture and responsive layouts.
- Drafted architecture and delivery docs.

## Prompting approach

- Started with end-to-end product goal and assignment constraints.
- Iteratively prompted for concrete deliverables:
  - backend data model and APIs,
  - role-based flows,
  - conflict detection,
  - UI modules,
  - docs.

## Generated vs manually refined

AI-generated drafts were manually refined for:
- API contract consistency.
- Permission checks and conflict semantics.
- UI interaction polish and screen composition.
- Naming clarity and readability.

## Validation steps

- Static review of all key flows in code.
- Local formatting + analysis + widget test execution.
- API shape and payload checks against Flutter client usage.

## Engineering judgment decisions

- Chose lightweight Python backend over Rails for speed in time-boxed assignment while preserving architecture depth.
- Prioritized core assignment features and execution quality over non-essential scope.
