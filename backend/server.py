#!/usr/bin/env python3
import json
import os
import sqlite3
from datetime import UTC, datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

DB_PATH = os.path.join(os.path.dirname(__file__), "data.db")
HOST = "0.0.0.0"
PORT = 8080


def now_iso():
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_iso(value: str) -> datetime:
    v = value.replace("Z", "+00:00")
    return datetime.fromisoformat(v)


def dict_row(cursor, row):
    return {cursor.description[i][0]: row[i] for i in range(len(row))}


def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = dict_row
    return conn


def migrate(conn: sqlite3.Connection):
    conn.executescript(
        """
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            role TEXT NOT NULL CHECK(role IN ('professional', 'manager')),
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS manager_assignments (
            manager_id INTEGER NOT NULL,
            professional_id INTEGER NOT NULL,
            PRIMARY KEY (manager_id, professional_id),
            FOREIGN KEY(manager_id) REFERENCES users(id),
            FOREIGN KEY(professional_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS schedule_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            status TEXT NOT NULL,
            start_at TEXT NOT NULL,
            end_at TEXT NOT NULL,
            notes TEXT,
            source_type TEXT,
            source_id TEXT,
            is_auto_linked INTEGER NOT NULL DEFAULT 0,
            requires_rsvp INTEGER NOT NULL DEFAULT 0,
            cancelled INTEGER NOT NULL DEFAULT 0,
            created_by INTEGER NOT NULL,
            updated_by INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id),
            FOREIGN KEY(created_by) REFERENCES users(id),
            FOREIGN KEY(updated_by) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            due_at TEXT NOT NULL,
            status TEXT NOT NULL,
            priority TEXT NOT NULL,
            notes TEXT,
            created_by INTEGER NOT NULL,
            updated_by INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS rsvps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            schedule_entry_id INTEGER NOT NULL,
            user_id INTEGER NOT NULL,
            response TEXT NOT NULL CHECK(response IN ('yes', 'no', 'maybe', 'pending')),
            comment TEXT,
            updated_by INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(schedule_entry_id, user_id),
            FOREIGN KEY(schedule_entry_id) REFERENCES schedule_entries(id),
            FOREIGN KEY(user_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            kind TEXT NOT NULL,
            title TEXT NOT NULL,
            message TEXT NOT NULL,
            seen INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS audit_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_type TEXT NOT NULL,
            entity_id INTEGER NOT NULL,
            action TEXT NOT NULL,
            actor_id INTEGER NOT NULL,
            target_user_id INTEGER,
            details TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY(actor_id) REFERENCES users(id)
        );
        """
    )
    conn.commit()


def seed(conn: sqlite3.Connection):
    existing = conn.execute("SELECT COUNT(*) AS c FROM users").fetchone()["c"]
    if existing > 0:
        return

    now = now_iso()
    users = [
        ("Aanya Kapoor", "aanya@reelon.app", "professional", now),
        ("Rohan Mehta", "rohan@reelon.app", "professional", now),
        ("Sara Khan", "sara@reelon.app", "professional", now),
        ("Neha Sharma", "neha@reelon.app", "manager", now),
        ("Arjun Verma", "arjun@reelon.app", "manager", now),
    ]
    conn.executemany(
        "INSERT INTO users(name, email, role, created_at) VALUES (?, ?, ?, ?)", users
    )

    conn.executemany(
        "INSERT INTO manager_assignments(manager_id, professional_id) VALUES (?, ?)",
        [(4, 1), (4, 2), (5, 3)],
    )

    base = datetime.now(UTC).replace(hour=9, minute=0, second=0, microsecond=0)
    entries = [
        (
            1,
            "Available",
            "available",
            (base + timedelta(hours=0)).isoformat() + "Z",
            (base + timedelta(hours=2)).isoformat() + "Z",
            "Open for calls",
            None,
            None,
            0,
            0,
            0,
            1,
            1,
            now,
            now,
        ),
        (
            1,
            "Shoot/Work Day",
            "confirmed_booking",
            (base + timedelta(hours=3)).isoformat() + "Z",
            (base + timedelta(hours=8)).isoformat() + "Z",
            "Brand campaign day",
            "project",
            "PRJ-302",
            1,
            1,
            0,
            4,
            4,
            now,
            now,
        ),
        (
            2,
            "Travel",
            "busy",
            (base + timedelta(days=1, hours=1)).isoformat() + "Z",
            (base + timedelta(days=1, hours=5)).isoformat() + "Z",
            "Travel to Pune",
            "event",
            "EVT-55",
            1,
            0,
            0,
            4,
            4,
            now,
            now,
        ),
        (
            3,
            "Tentative Booking",
            "tentative_booking",
            (base + timedelta(days=1, hours=2)).isoformat() + "Z",
            (base + timedelta(days=1, hours=4)).isoformat() + "Z",
            "Awaiting client confirmation",
            "assignment",
            "ASN-21",
            1,
            1,
            0,
            5,
            5,
            now,
            now,
        ),
    ]
    conn.executemany(
        """
        INSERT INTO schedule_entries(
            user_id, type, status, start_at, end_at, notes, source_type, source_id,
            is_auto_linked, requires_rsvp, cancelled, created_by, updated_by, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        entries,
    )

    tasks = [
        (
            1,
            "Submission deadline: campaign draft",
            (base + timedelta(hours=6)).isoformat() + "Z",
            "open",
            "high",
            "Share draft links before EOD",
            4,
            4,
            now,
            now,
        ),
        (
            2,
            "Follow-up with coordinator",
            (base + timedelta(days=1, hours=6)).isoformat() + "Z",
            "open",
            "medium",
            "Confirm venue details",
            4,
            4,
            now,
            now,
        ),
    ]
    conn.executemany(
        """
        INSERT INTO tasks(user_id, title, due_at, status, priority, notes, created_by, updated_by, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        tasks,
    )

    conn.execute(
        """
        INSERT INTO rsvps(schedule_entry_id, user_id, response, comment, updated_by, created_at, updated_at)
        VALUES (2, 1, 'pending', 'Waiting for final brief', 1, ?, ?)
        """,
        (now, now),
    )

    notifications = [
        (1, "schedule", "Shoot confirmed", "PRJ-302 was marked as confirmed booking.", 0, now),
        (1, "task", "Task due today", "Submission deadline is due today.", 0, now),
        (2, "schedule", "Travel entry added", "Travel entry was auto-linked from event EVT-55.", 0, now),
    ]
    conn.executemany(
        "INSERT INTO notifications(user_id, kind, title, message, seen, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        notifications,
    )

    conn.commit()


def is_manager_of(conn: sqlite3.Connection, manager_id: int, professional_id: int) -> bool:
    row = conn.execute(
        "SELECT 1 FROM manager_assignments WHERE manager_id = ? AND professional_id = ?",
        (manager_id, professional_id),
    ).fetchone()
    return row is not None


def can_edit_user(conn: sqlite3.Connection, actor_id: int, target_user_id: int) -> bool:
    actor = conn.execute("SELECT role FROM users WHERE id = ?", (actor_id,)).fetchone()
    if not actor:
        return False
    if actor["role"] == "manager":
        return actor_id == target_user_id or is_manager_of(conn, actor_id, target_user_id)
    return actor_id == target_user_id


def add_audit(conn, entity_type, entity_id, action, actor_id, target_user_id, details):
    conn.execute(
        """
        INSERT INTO audit_logs(entity_type, entity_id, action, actor_id, target_user_id, details, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (entity_type, entity_id, action, actor_id, target_user_id, json.dumps(details), now_iso()),
    )


def add_notification(conn, user_id, kind, title, message):
    conn.execute(
        """
        INSERT INTO notifications(user_id, kind, title, message, seen, created_at)
        VALUES (?, ?, ?, ?, 0, ?)
        """,
        (user_id, kind, title, message, now_iso()),
    )


def find_conflicts(conn, user_id, start_at, end_at, ignore_id=None):
    query = """
        SELECT id, type, status, start_at, end_at
        FROM schedule_entries
        WHERE user_id = ?
          AND cancelled = 0
          AND start_at < ?
          AND end_at > ?
    """
    params = [user_id, end_at, start_at]
    if ignore_id:
        query += " AND id != ?"
        params.append(ignore_id)
    return conn.execute(query, params).fetchall()


class Handler(BaseHTTPRequestHandler):
    server_version = "ReelOnBackend/1.0"

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Actor-Id")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PATCH, OPTIONS")

    def _send(self, status=200, payload=None):
        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        if payload is None:
            payload = {}
        self.wfile.write(json.dumps(payload).encode("utf-8"))

    def _read_json(self):
        length = int(self.headers.get("Content-Length", 0))
        if length <= 0:
            return {}
        body = self.rfile.read(length)
        return json.loads(body.decode("utf-8"))

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        conn = get_conn()
        try:
            parsed = urlparse(self.path)
            path = parsed.path
            query = parse_qs(parsed.query)

            if path == "/health":
                self._send(200, {"ok": True, "time": now_iso()})
                return

            if path == "/api/users":
                role = query.get("role", [None])[0]
                if role:
                    rows = conn.execute(
                        "SELECT id, name, email, role FROM users WHERE role = ? ORDER BY name", (role,)
                    ).fetchall()
                else:
                    rows = conn.execute("SELECT id, name, email, role FROM users ORDER BY name").fetchall()
                self._send(200, {"users": rows})
                return

            if path == "/api/schedule-entries":
                user_id = int(query.get("userId", [0])[0])
                from_at = query.get("from", [None])[0]
                to_at = query.get("to", [None])[0]
                if not user_id or not from_at or not to_at:
                    self._send(400, {"error": "userId, from, to are required"})
                    return

                rows = conn.execute(
                    """
                    SELECT se.*, u.name AS user_name, cb.name AS created_by_name, ub.name AS updated_by_name,
                           r.response AS rsvp_response, r.comment AS rsvp_comment
                    FROM schedule_entries se
                    JOIN users u ON u.id = se.user_id
                    JOIN users cb ON cb.id = se.created_by
                    JOIN users ub ON ub.id = se.updated_by
                    LEFT JOIN rsvps r ON r.schedule_entry_id = se.id AND r.user_id = se.user_id
                    WHERE se.user_id = ?
                      AND se.cancelled = 0
                      AND se.start_at < ?
                      AND se.end_at > ?
                    ORDER BY se.start_at
                    """,
                    (user_id, to_at, from_at),
                ).fetchall()
                self._send(200, {"entries": rows})
                return

            if path == "/api/tasks":
                user_id = int(query.get("userId", [0])[0])
                if not user_id:
                    self._send(400, {"error": "userId is required"})
                    return
                rows = conn.execute(
                    """
                    SELECT t.*, cb.name AS created_by_name, ub.name AS updated_by_name
                    FROM tasks t
                    JOIN users cb ON cb.id = t.created_by
                    JOIN users ub ON ub.id = t.updated_by
                    WHERE user_id = ?
                    ORDER BY due_at
                    """,
                    (user_id,),
                ).fetchall()
                self._send(200, {"tasks": rows})
                return

            if path == "/api/notifications":
                user_id = int(query.get("userId", [0])[0])
                if not user_id:
                    self._send(400, {"error": "userId is required"})
                    return
                rows = conn.execute(
                    """
                    SELECT id, kind, title, message, seen, created_at
                    FROM notifications
                    WHERE user_id = ?
                    ORDER BY created_at DESC
                    LIMIT 25
                    """,
                    (user_id,),
                ).fetchall()
                self._send(200, {"notifications": rows})
                return

            if path == "/api/audit-logs":
                user_id = int(query.get("userId", [0])[0])
                limit = int(query.get("limit", [40])[0])
                if not user_id:
                    self._send(400, {"error": "userId is required"})
                    return
                rows = conn.execute(
                    """
                    SELECT a.id, a.entity_type, a.entity_id, a.action, a.details, a.created_at,
                           actor.name AS actor_name
                    FROM audit_logs a
                    JOIN users actor ON actor.id = a.actor_id
                    WHERE a.target_user_id = ? OR a.actor_id = ?
                    ORDER BY a.created_at DESC
                    LIMIT ?
                    """,
                    (user_id, user_id, limit),
                ).fetchall()
                for row in rows:
                    row["details"] = json.loads(row["details"]) if row["details"] else {}
                self._send(200, {"auditLogs": rows})
                return

            self._send(404, {"error": "Not found"})
        except Exception as exc:
            self._send(500, {"error": str(exc)})
        finally:
            conn.close()

    def do_POST(self):
        conn = get_conn()
        try:
            parsed = urlparse(self.path)
            path = parsed.path
            payload = self._read_json()

            if path == "/api/login":
                email = payload.get("email", "").strip().lower()
                if not email:
                    self._send(400, {"error": "email is required"})
                    return
                user = conn.execute(
                    "SELECT id, name, email, role FROM users WHERE lower(email) = ?", (email,)
                ).fetchone()
                if not user:
                    self._send(404, {"error": "User not found"})
                    return

                assigned = []
                if user["role"] == "manager":
                    rows = conn.execute(
                        "SELECT professional_id FROM manager_assignments WHERE manager_id = ?",
                        (user["id"],),
                    ).fetchall()
                    assigned = [r["professional_id"] for r in rows]
                self._send(200, {"user": user, "assignedProfessionalIds": assigned})
                return

            if path == "/api/schedule-entries":
                actor_id = int(self.headers.get("X-Actor-Id", "0"))
                user_id = int(payload.get("userId", 0))
                if not actor_id or not user_id:
                    self._send(400, {"error": "actor and user are required"})
                    return
                if not can_edit_user(conn, actor_id, user_id):
                    self._send(403, {"error": "permission denied"})
                    return

                start_at = payload.get("startAt")
                end_at = payload.get("endAt")
                if not start_at or not end_at:
                    self._send(400, {"error": "startAt and endAt are required"})
                    return
                if parse_iso(end_at) <= parse_iso(start_at):
                    self._send(400, {"error": "endAt must be after startAt"})
                    return

                conflicts = find_conflicts(conn, user_id, start_at, end_at)
                if conflicts:
                    self._send(409, {"error": "Schedule conflict detected", "conflicts": conflicts})
                    return

                now = now_iso()
                cur = conn.execute(
                    """
                    INSERT INTO schedule_entries(
                      user_id, type, status, start_at, end_at, notes, source_type, source_id,
                      is_auto_linked, requires_rsvp, cancelled, created_by, updated_by, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)
                    """,
                    (
                        user_id,
                        payload.get("type", "Available"),
                        payload.get("status", "available"),
                        start_at,
                        end_at,
                        payload.get("notes", ""),
                        payload.get("sourceType"),
                        payload.get("sourceId"),
                        1 if payload.get("isAutoLinked", False) else 0,
                        1 if payload.get("requiresRsvp", False) else 0,
                        actor_id,
                        actor_id,
                        now,
                        now,
                    ),
                )
                entry_id = cur.lastrowid

                add_audit(
                    conn,
                    "schedule_entry",
                    entry_id,
                    "created",
                    actor_id,
                    user_id,
                    {"startAt": start_at, "endAt": end_at, "type": payload.get("type")},
                )
                add_notification(
                    conn,
                    user_id,
                    "schedule",
                    "Schedule entry created",
                    f"{payload.get('type', 'Entry')} was added from {start_at} to {end_at}.",
                )
                conn.commit()

                row = conn.execute("SELECT * FROM schedule_entries WHERE id = ?", (entry_id,)).fetchone()
                self._send(201, {"entry": row})
                return

            if path == "/api/tasks":
                actor_id = int(self.headers.get("X-Actor-Id", "0"))
                user_id = int(payload.get("userId", 0))
                if not actor_id or not user_id:
                    self._send(400, {"error": "actor and user are required"})
                    return
                if not can_edit_user(conn, actor_id, user_id):
                    self._send(403, {"error": "permission denied"})
                    return

                title = payload.get("title", "").strip()
                due_at = payload.get("dueAt")
                if not title or not due_at:
                    self._send(400, {"error": "title and dueAt are required"})
                    return

                now = now_iso()
                cur = conn.execute(
                    """
                    INSERT INTO tasks(user_id, title, due_at, status, priority, notes, created_by, updated_by, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        user_id,
                        title,
                        due_at,
                        payload.get("status", "open"),
                        payload.get("priority", "medium"),
                        payload.get("notes", ""),
                        actor_id,
                        actor_id,
                        now,
                        now,
                    ),
                )
                task_id = cur.lastrowid

                add_audit(conn, "task", task_id, "created", actor_id, user_id, {"title": title})
                add_notification(conn, user_id, "task", "New task", f"{title} was added.")
                conn.commit()

                row = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
                self._send(201, {"task": row})
                return

            if path == "/api/rsvps":
                actor_id = int(self.headers.get("X-Actor-Id", "0"))
                schedule_entry_id = int(payload.get("scheduleEntryId", 0))
                user_id = int(payload.get("userId", 0))
                response = payload.get("response", "pending")
                if not actor_id or not schedule_entry_id or not user_id:
                    self._send(400, {"error": "actor, scheduleEntryId and userId are required"})
                    return
                if not can_edit_user(conn, actor_id, user_id):
                    self._send(403, {"error": "permission denied"})
                    return

                now = now_iso()
                conn.execute(
                    """
                    INSERT INTO rsvps(schedule_entry_id, user_id, response, comment, updated_by, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(schedule_entry_id, user_id)
                    DO UPDATE SET response=excluded.response, comment=excluded.comment, updated_by=excluded.updated_by, updated_at=excluded.updated_at
                    """,
                    (
                        schedule_entry_id,
                        user_id,
                        response,
                        payload.get("comment", ""),
                        actor_id,
                        now,
                        now,
                    ),
                )
                add_audit(
                    conn,
                    "rsvp",
                    schedule_entry_id,
                    "updated",
                    actor_id,
                    user_id,
                    {"response": response},
                )
                add_notification(
                    conn,
                    user_id,
                    "rsvp",
                    "RSVP updated",
                    f"Participation status changed to {response.upper()}.",
                )
                conn.commit()
                self._send(200, {"ok": True})
                return

            self._send(404, {"error": "Not found"})
        except Exception as exc:
            self._send(500, {"error": str(exc)})
        finally:
            conn.close()

    def do_PATCH(self):
        conn = get_conn()
        try:
            parsed = urlparse(self.path)
            path = parsed.path
            payload = self._read_json()
            actor_id = int(self.headers.get("X-Actor-Id", "0"))

            if path.startswith("/api/schedule-entries/"):
                entry_id = int(path.rsplit("/", 1)[-1])
                row = conn.execute("SELECT * FROM schedule_entries WHERE id = ?", (entry_id,)).fetchone()
                if not row:
                    self._send(404, {"error": "entry not found"})
                    return
                if not can_edit_user(conn, actor_id, row["user_id"]):
                    self._send(403, {"error": "permission denied"})
                    return

                start_at = payload.get("startAt", row["start_at"])
                end_at = payload.get("endAt", row["end_at"])
                if parse_iso(end_at) <= parse_iso(start_at):
                    self._send(400, {"error": "endAt must be after startAt"})
                    return

                conflicts = find_conflicts(conn, row["user_id"], start_at, end_at, ignore_id=entry_id)
                if conflicts:
                    self._send(409, {"error": "Schedule conflict detected", "conflicts": conflicts})
                    return

                conn.execute(
                    """
                    UPDATE schedule_entries
                    SET type = ?, status = ?, start_at = ?, end_at = ?, notes = ?, requires_rsvp = ?, updated_by = ?, updated_at = ?
                    WHERE id = ?
                    """,
                    (
                        payload.get("type", row["type"]),
                        payload.get("status", row["status"]),
                        start_at,
                        end_at,
                        payload.get("notes", row["notes"]),
                        1 if payload.get("requiresRsvp", bool(row["requires_rsvp"])) else 0,
                        actor_id,
                        now_iso(),
                        entry_id,
                    ),
                )
                add_audit(conn, "schedule_entry", entry_id, "updated", actor_id, row["user_id"], payload)
                add_notification(
                    conn,
                    row["user_id"],
                    "schedule",
                    "Schedule updated",
                    f"Entry #{entry_id} was updated.",
                )
                conn.commit()
                updated = conn.execute("SELECT * FROM schedule_entries WHERE id = ?", (entry_id,)).fetchone()
                self._send(200, {"entry": updated})
                return

            if path.startswith("/api/tasks/"):
                task_id = int(path.rsplit("/", 1)[-1])
                row = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
                if not row:
                    self._send(404, {"error": "task not found"})
                    return
                if not can_edit_user(conn, actor_id, row["user_id"]):
                    self._send(403, {"error": "permission denied"})
                    return

                conn.execute(
                    """
                    UPDATE tasks
                    SET title = ?, due_at = ?, status = ?, priority = ?, notes = ?, updated_by = ?, updated_at = ?
                    WHERE id = ?
                    """,
                    (
                        payload.get("title", row["title"]),
                        payload.get("dueAt", row["due_at"]),
                        payload.get("status", row["status"]),
                        payload.get("priority", row["priority"]),
                        payload.get("notes", row["notes"]),
                        actor_id,
                        now_iso(),
                        task_id,
                    ),
                )
                add_audit(conn, "task", task_id, "updated", actor_id, row["user_id"], payload)
                conn.commit()
                updated = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
                self._send(200, {"task": updated})
                return

            self._send(404, {"error": "Not found"})
        except Exception as exc:
            self._send(500, {"error": str(exc)})
        finally:
            conn.close()


def boot():
    conn = get_conn()
    migrate(conn)
    seed(conn)
    conn.close()


def main():
    boot()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Backend running at http://{HOST}:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
