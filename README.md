# ReelOnTask Assessment Submission

A full-stack implementation of the assignment: **Multi-User Scheduling & Task Coordination Module**.

## What is implemented

- Responsive Flutter UI for mobile + tablet/desktop layouts.
- Multi-user role flow:
  - Professional can manage their own schedule/tasks.
  - Manager can switch between assigned professionals and manage their calendars/tasks.
- Schedule management with types/statuses and metadata.
- Conflict detection on schedule creation/update (backend-enforced).
- Auto-linked schedule concept support (`sourceType`, `sourceId`, `isAutoLinked`).
- Task management with due dates and status.
- RSVP state updates for eligible entries.
- Notifications feed.
- Audit trail feed.
- REST backend with SQLite persistence.

## Stack

- Frontend: Flutter
- Backend: Python (`http.server`) + SQLite
- Protocol: JSON REST APIs

The assignment preferred Rails/PostgreSQL; this implementation uses a lightweight alternative stack with equivalent schema/API concepts for fast local evaluation.

## Project structure

- `/Users/avadh/StudioProjects/reelOnTask/lib/main.dart` App bootstrap only
- `/Users/avadh/StudioProjects/reelOnTask/lib/app.dart` Root app widget + theme wiring
- `/Users/avadh/StudioProjects/reelOnTask/lib/core` Shared theme and utility helpers
- `/Users/avadh/StudioProjects/reelOnTask/lib/data` API client + typed models
- `/Users/avadh/StudioProjects/reelOnTask/lib/features/auth` Login feature module
- `/Users/avadh/StudioProjects/reelOnTask/lib/features/dashboard` Dashboard feature module (schedule/tasks/notifications/audit UI)
- `/Users/avadh/StudioProjects/reelOnTask/lib/shared/widgets` Reusable UI components
- `/Users/avadh/StudioProjects/reelOnTask/backend/server.py` Backend server, schema migration, seeding, APIs
- `/Users/avadh/StudioProjects/reelOnTask/docs/ARCHITECTURE.md` Architecture note
- `/Users/avadh/StudioProjects/reelOnTask/docs/AI_WORKFLOW.md` AI-assisted development note

## Run locally

### 1) Start backend

```bash
cd /Users/avadh/StudioProjects/reelOnTask/backend
python3 server.py
```

Backend runs on `http://localhost:8080`.

### 2) Run Flutter app

```bash
cd /Users/avadh/StudioProjects/reelOnTask
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

For Android emulator, pass `--dart-define=API_BASE_URL=http://10.0.2.2:8080`.

### One-command demo run

```bash
cd /Users/avadh/StudioProjects/reelOnTask
./scripts/run_demo.sh -d chrome
```

## Demo users

Login with any seeded user from the login screen:

- Managers:
  - `neha@reelon.app`
  - `arjun@reelon.app`
- Professionals:
  - `aanya@reelon.app`
  - `rohan@reelon.app`
  - `sara@reelon.app`

## API summary

- `GET /health`
- `POST /api/login`
- `GET /api/users`
- `GET /api/schedule-entries`
- `POST /api/schedule-entries`
- `PATCH /api/schedule-entries/:id`
- `GET /api/tasks`
- `POST /api/tasks`
- `PATCH /api/tasks/:id`
- `POST /api/rsvps`
- `GET /api/notifications`
- `GET /api/audit-logs`

## Assignment design input

Figma referenced in assignment PDF:
- https://www.figma.com/design/vVqbJnXBJRmg0Je2dmulRT/Assignment?node-id=1-14755&t=pLxrTU7ll9xHGQSy-0

## Notes

- This project is intentionally scoped for interview evaluation and product-thinking demonstration.
- Complex recurrence, external calendar sync, and payment workflows are intentionally excluded as per assignment guidance.
# ReelOn
