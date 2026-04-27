enum UserRole {
  professional('professional', 'Professional'),
  manager('manager', 'Manager');

  const UserRole(this.value, this.label);

  final String value;
  final String label;

  static UserRole fromValue(String value) {
    return UserRole.values.firstWhere((e) => e.value == value);
  }
}

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      role: UserRole.fromValue(json['role'] as String),
    );
  }

  final int id;
  final String name;
  final String email;
  final UserRole role;
}

class LoginSession {
  LoginSession({required this.user, required this.assignedProfessionalIds});

  final AppUser user;
  final List<int> assignedProfessionalIds;
}

class ScheduleEntry {
  ScheduleEntry({
    required this.id,
    required this.userId,
    required this.type,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.notes,
    required this.isAutoLinked,
    required this.requiresRsvp,
    required this.createdByName,
    required this.updatedByName,
    required this.rsvpResponse,
  });

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleEntry(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      type: json['type'] as String,
      status: json['status'] as String,
      startAt: DateTime.parse(json['start_at'] as String).toLocal(),
      endAt: DateTime.parse(json['end_at'] as String).toLocal(),
      notes: (json['notes'] as String?) ?? '',
      isAutoLinked: (json['is_auto_linked'] as int?) == 1,
      requiresRsvp: (json['requires_rsvp'] as int?) == 1,
      createdByName: (json['created_by_name'] as String?) ?? 'Unknown',
      updatedByName: (json['updated_by_name'] as String?) ?? 'Unknown',
      rsvpResponse: (json['rsvp_response'] as String?) ?? 'pending',
    );
  }

  factory ScheduleEntry.fromConflictJson(
    Map<String, dynamic> json,
    int userId,
  ) {
    return ScheduleEntry(
      id: json['id'] as int,
      userId: userId,
      type: (json['type'] as String?) ?? 'Conflict Entry',
      status: (json['status'] as String?) ?? 'busy',
      startAt: DateTime.parse(json['start_at'] as String).toLocal(),
      endAt: DateTime.parse(json['end_at'] as String).toLocal(),
      notes: '',
      isAutoLinked: false,
      requiresRsvp: false,
      createdByName: 'System',
      updatedByName: 'System',
      rsvpResponse: 'pending',
    );
  }

  final int id;
  final int userId;
  final String type;
  final String status;
  final DateTime startAt;
  final DateTime endAt;
  final String notes;
  final bool isAutoLinked;
  final bool requiresRsvp;
  final String createdByName;
  final String updatedByName;
  final String rsvpResponse;

  String get statusLabel => status.replaceAll('_', ' ').toUpperCase();
}

class TaskItem {
  TaskItem({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.notes,
    required this.dueAt,
  });

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      id: json['id'] as int,
      title: json['title'] as String,
      status: json['status'] as String,
      priority: json['priority'] as String,
      notes: (json['notes'] as String?) ?? '',
      dueAt: DateTime.parse(json['due_at'] as String).toLocal(),
    );
  }

  final int id;
  final String title;
  final String status;
  final String priority;
  final String notes;
  final DateTime dueAt;
}

class NotificationItem {
  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as int,
      title: json['title'] as String,
      message: json['message'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  final int id;
  final String title;
  final String message;
  final DateTime createdAt;
}

class AuditEvent {
  AuditEvent({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.actorName,
    required this.createdAt,
  });

  factory AuditEvent.fromJson(Map<String, dynamic> json) {
    return AuditEvent(
      id: json['id'] as int,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as int,
      action: json['action'] as String,
      actorName: json['actor_name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  final int id;
  final String entityType;
  final int entityId;
  final String action;
  final String actorName;
  final DateTime createdAt;
}

class EntryDraft {
  EntryDraft({
    required this.type,
    required this.status,
    required this.start,
    required this.end,
    required this.notes,
    required this.requiresRsvp,
  });

  final String type;
  final String status;
  final DateTime start;
  final DateTime end;
  final String notes;
  final bool requiresRsvp;
}

class TaskDraft {
  TaskDraft({
    required this.title,
    required this.notes,
    required this.dueAt,
    required this.priority,
  });

  final String title;
  final String notes;
  final DateTime dueAt;
  final String priority;
}

class ApiConflictException implements Exception {
  ApiConflictException({required this.conflicts});

  final List<ScheduleEntry> conflicts;
}
