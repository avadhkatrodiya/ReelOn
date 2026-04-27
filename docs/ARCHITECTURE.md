# Architecture README

## 1) System architecture

- Flutter client consumes backend REST APIs.
- Backend exposes role-aware scheduling/task endpoints with conflict detection and audit logging.
- SQLite stores normalized entities for users, schedules, tasks, RSVPs, notifications, and audit logs.

Flow:
1. User logs in by email.
2. Client loads role context (professional or manager + assigned professionals).
3. Client reads day-level schedule + tasks + notifications + audit trail.
4. Create/update actions go through backend permission checks, conflict checks, audit trail, and notification fanout.

## 2) Data model

Core tables:
- `users`
  - `role`: `professional | manager`
- `manager_assignments`
  - maps manager to one or many professionals
- `schedule_entries`
  - manual + auto-linked schedule states
  - time range (`start_at`, `end_at`), status, source linkage, RSVP flag
- `tasks`
  - due-date action items, status, priority
- `rsvps`
  - participation response per `(schedule_entry_id, user_id)`
- `notifications`
  - activity feed items by user
- `audit_logs`
  - immutable audit stream of key actions

## 3) Permission model

- Professional:
  - Can read/write own schedule/tasks/RSVP.
- Manager:
  - Can read/write schedules/tasks of assigned professionals.
  - Can also manage own entities.

Permission enforcement is backend-first (`can_edit_user`).

## 4) Conflict handling

Conflict detection on create/update:
- conflict if new range overlaps existing non-cancelled entries for same user.
- overlap check:
  - `existing.start_at < new.end_at`
  - `existing.end_at > new.start_at`

Returns `409` with conflicting entries list.

## 5) Key decisions

- Used simple REST + SQLite for fast setup and clear interview demo.
- Kept business rules in backend (permissions, conflicts, audit) to ensure consistency across UI changes.
- Responsive UI split into desktop and mobile dashboards for clear usability.
- Used explicit metadata (`created_by`, `updated_by`, source fields) for trust and traceability.

## 6) Assumptions

- Single-tenant environment.
- Email-based demo login (no password/OAuth for assignment scope).
- Timezone handling uses ISO UTC storage and local rendering.

## 7) Tradeoffs

- No real-time sockets; refresh-driven updates.
- No recurring event engine.
- No external calendar integrations.
- Minimal design system, optimized for assignment coverage and clarity.
