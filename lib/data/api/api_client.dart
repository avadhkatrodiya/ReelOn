import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/domain_models.dart';

class ApiClient {
  ApiClient({String? baseUrl})
    : _baseUrl = baseUrl ?? _defaultBaseUrl,
      _candidateBaseUrls = [
        if (baseUrl != null) baseUrl,
        _defaultBaseUrl,
        'http://127.0.0.1:8080',
        'http://10.0.2.2:8080',
      ];

  String _baseUrl;
  final List<String> _candidateBaseUrls;

  static const _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  Future<List<AppUser>> getUsers() async {
    final response = await _get('/api/users');
    final payload = _decodeBody(response);
    return (payload['users'] as List<dynamic>)
        .map((json) => AppUser.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<LoginSession> login(String email) async {
    final response = await _post(
      '/api/login',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    final payload = _decodeBody(response);
    return LoginSession(
      user: AppUser.fromJson(payload['user'] as Map<String, dynamic>),
      assignedProfessionalIds:
          (payload['assignedProfessionalIds'] as List<dynamic>)
              .map((e) => e as int)
              .toList(),
    );
  }

  Future<List<ScheduleEntry>> getScheduleEntries({
    required int userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final response = await _get(
      '/api/schedule-entries?userId=$userId&from=${Uri.encodeQueryComponent(from.toUtc().toIso8601String())}&to=${Uri.encodeQueryComponent(to.toUtc().toIso8601String())}',
    );
    final payload = _decodeBody(response);
    return (payload['entries'] as List<dynamic>)
        .map((e) => ScheduleEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createScheduleEntry({
    required int actorId,
    required int userId,
    required EntryDraft draft,
  }) async {
    final response = await _post(
      '/api/schedule-entries',
      headers: {'Content-Type': 'application/json', 'X-Actor-Id': '$actorId'},
      body: jsonEncode({
        'userId': userId,
        'type': draft.type,
        'status': draft.status,
        'startAt': draft.start.toUtc().toIso8601String(),
        'endAt': draft.end.toUtc().toIso8601String(),
        'notes': draft.notes,
        'requiresRsvp': draft.requiresRsvp,
      }),
    );

    if (response.statusCode == 409) {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final conflicts = (payload['conflicts'] as List<dynamic>)
          .map(
            (e) => ScheduleEntry.fromConflictJson(
              e as Map<String, dynamic>,
              userId,
            ),
          )
          .toList();
      throw ApiConflictException(conflicts: conflicts);
    }

    _decodeBody(response);
  }

  Future<void> updateScheduleEntry({
    required int actorId,
    required int userId,
    required int entryId,
    required EntryDraft draft,
  }) async {
    final response = await _patch(
      '/api/schedule-entries/$entryId',
      headers: {'Content-Type': 'application/json', 'X-Actor-Id': '$actorId'},
      body: jsonEncode({
        'type': draft.type,
        'status': draft.status,
        'startAt': draft.start.toUtc().toIso8601String(),
        'endAt': draft.end.toUtc().toIso8601String(),
        'notes': draft.notes,
        'requiresRsvp': draft.requiresRsvp,
      }),
    );

    if (response.statusCode == 409) {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final conflicts = (payload['conflicts'] as List<dynamic>)
          .map(
            (e) => ScheduleEntry.fromConflictJson(
              e as Map<String, dynamic>,
              userId,
            ),
          )
          .toList();
      throw ApiConflictException(conflicts: conflicts);
    }

    _decodeBody(response);
  }

  Future<List<TaskItem>> getTasks({required int userId}) async {
    final response = await _get('/api/tasks?userId=$userId');
    final payload = _decodeBody(response);
    return (payload['tasks'] as List<dynamic>)
        .map((e) => TaskItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createTask({
    required int actorId,
    required int userId,
    required TaskDraft draft,
  }) async {
    final response = await _post(
      '/api/tasks',
      headers: {'Content-Type': 'application/json', 'X-Actor-Id': '$actorId'},
      body: jsonEncode({
        'userId': userId,
        'title': draft.title,
        'dueAt': draft.dueAt.toUtc().toIso8601String(),
        'priority': draft.priority,
        'notes': draft.notes,
      }),
    );
    _decodeBody(response);
  }

  Future<void> updateTask({
    required int actorId,
    required int taskId,
    required Map<String, dynamic> update,
  }) async {
    final response = await _patch(
      '/api/tasks/$taskId',
      headers: {'Content-Type': 'application/json', 'X-Actor-Id': '$actorId'},
      body: jsonEncode(update),
    );
    _decodeBody(response);
  }

  Future<void> updateRsvp({
    required int actorId,
    required int scheduleEntryId,
    required int userId,
    required String response,
  }) async {
    final res = await _post(
      '/api/rsvps',
      headers: {'Content-Type': 'application/json', 'X-Actor-Id': '$actorId'},
      body: jsonEncode({
        'scheduleEntryId': scheduleEntryId,
        'userId': userId,
        'response': response,
      }),
    );
    _decodeBody(res);
  }

  Future<List<NotificationItem>> getNotifications({required int userId}) async {
    final response = await _get('/api/notifications?userId=$userId');
    final payload = _decodeBody(response);
    return (payload['notifications'] as List<dynamic>)
        .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AuditEvent>> getAuditEvents({required int userId}) async {
    final response = await _get('/api/audit-logs?userId=$userId&limit=30');
    final payload = _decodeBody(response);
    return (payload['auditLogs'] as List<dynamic>)
        .map((e) => AuditEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }
    throw Exception(
      payload['error'] ?? 'Request failed (${response.statusCode})',
    );
  }

  Future<http.Response> _get(String path) {
    return _withBaseUrlFallback((base) => http.get(Uri.parse('$base$path')));
  }

  Future<http.Response> _post(
    String path, {
    required Map<String, String> headers,
    required String body,
  }) {
    return _withBaseUrlFallback(
      (base) =>
          http.post(Uri.parse('$base$path'), headers: headers, body: body),
    );
  }

  Future<http.Response> _patch(
    String path, {
    required Map<String, String> headers,
    required String body,
  }) {
    return _withBaseUrlFallback(
      (base) =>
          http.patch(Uri.parse('$base$path'), headers: headers, body: body),
    );
  }

  Future<http.Response> _withBaseUrlFallback(
    Future<http.Response> Function(String baseUrl) call,
  ) async {
    final tried = <String>{};
    Object? lastError;
    for (final candidate in [_baseUrl, ..._candidateBaseUrls]) {
      if (!tried.add(candidate)) {
        continue;
      }
      try {
        final response = await call(candidate);
        _baseUrl = candidate;
        return response;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('Could not connect to API server.');
  }
}
