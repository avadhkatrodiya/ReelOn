import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../data/api/api_client.dart';
import '../../data/models/domain_models.dart';
import '../auth/login_screen.dart';

enum ScheduleViewMode { day, week }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final ApiClient _api = ApiClient();

  List<AppUser> _users = const [];
  AppUser? _sessionUser;
  Set<int> _assignedProfessionalIds = <int>{};

  DateTime _selectedDay = startOfDay(DateTime.now());
  int? _selectedProfessionalId;

  List<ScheduleEntry> _entries = const [];
  List<ScheduleEntry> _weekEntries = const [];
  List<TaskItem> _tasks = const [];
  List<NotificationItem> _notifications = const [];
  List<AuditEvent> _auditEvents = const [];

  bool _bootLoading = true;
  bool _dataLoading = false;
  int _activeTab = 0;
  ScheduleViewMode _scheduleViewMode = ScheduleViewMode.day;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _bootLoading = true);
    try {
      final users = await _api.getUsers();
      setState(() {
        _users = users;
      });
    } catch (e) {
      _showError(
        'Could not load users. Start backend first: cd backend && python3 server.py. Details: $e',
      );
    } finally {
      if (mounted) {
        setState(() => _bootLoading = false);
      }
    }
  }

  Future<void> _login(AppUser user) async {
    setState(() => _bootLoading = true);
    try {
      final session = await _api.login(user.email);
      final signedIn = session.user;
      final assigned = session.assignedProfessionalIds.toSet();
      final selectedProfessionalId = signedIn.role == UserRole.professional
          ? signedIn.id
          : (assigned.isNotEmpty ? assigned.first : signedIn.id);

      setState(() {
        _sessionUser = signedIn;
        _assignedProfessionalIds = assigned;
        _selectedProfessionalId = selectedProfessionalId;
      });
      await _reloadData();
    } catch (e) {
      _showError('Login failed: $e');
    } finally {
      if (mounted) {
        setState(() => _bootLoading = false);
      }
    }
  }

  Future<void> _reloadData() async {
    final user = _sessionUser;
    final targetUser = _selectedProfessionalId;
    if (user == null || targetUser == null) {
      return;
    }

    setState(() => _dataLoading = true);
    try {
      final dayStart = startOfDay(_selectedDay);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final weekStart = dayStart.subtract(const Duration(days: 3));
      final weekEnd = weekStart.add(const Duration(days: 7));

      final entries = await _api.getScheduleEntries(
        userId: targetUser,
        from: dayStart,
        to: dayEnd,
      );
      final weekEntries = await _api.getScheduleEntries(
        userId: targetUser,
        from: weekStart,
        to: weekEnd,
      );
      final tasks = await _api.getTasks(userId: targetUser);
      final notifications = await _api.getNotifications(userId: targetUser);
      final auditEvents = await _api.getAuditEvents(userId: targetUser);

      setState(() {
        _entries = entries;
        _weekEntries = weekEntries;
        _tasks = tasks;
        _notifications = notifications;
        _auditEvents = auditEvents;
      });
    } catch (e) {
      _showError('Could not load dashboard data: $e');
    } finally {
      if (mounted) {
        setState(() => _dataLoading = false);
      }
    }
  }

  Future<void> _openCreateEntryDialog() async {
    final sessionUser = _sessionUser;
    final targetUser = _selectedProfessionalId;
    if (sessionUser == null || targetUser == null) {
      return;
    }

    final created = await showDialog<EntryDraft>(
      context: context,
      builder: (_) => EntryDialog(initialDate: _selectedDay),
    );
    if (created == null) {
      return;
    }

    try {
      await _api.createScheduleEntry(
        actorId: sessionUser.id,
        draft: created,
        userId: targetUser,
      );
      await _reloadData();
      _showMessage('Schedule entry created.');
    } on ApiConflictException catch (conflict) {
      _showConflictDialog(conflict.conflicts);
    } catch (e) {
      _showError('Failed to create schedule entry: $e');
    }
  }

  Future<void> _openEditEntryDialog(ScheduleEntry entry) async {
    final sessionUser = _sessionUser;
    final targetUser = _selectedProfessionalId;
    if (sessionUser == null || targetUser == null) {
      return;
    }

    final edited = await showDialog<EntryDraft>(
      context: context,
      builder: (_) => EntryDialog(initialDate: entry.startAt, existing: entry),
    );
    if (edited == null) {
      return;
    }

    try {
      await _api.updateScheduleEntry(
        actorId: sessionUser.id,
        userId: targetUser,
        entryId: entry.id,
        draft: edited,
      );
      await _reloadData();
      _showMessage('Schedule entry updated.');
    } on ApiConflictException catch (conflict) {
      _showConflictDialog(conflict.conflicts);
    } catch (e) {
      _showError('Failed to update schedule entry: $e');
    }
  }

  Future<void> _openCreateTaskDialog() async {
    final sessionUser = _sessionUser;
    final targetUser = _selectedProfessionalId;
    if (sessionUser == null || targetUser == null) {
      return;
    }

    final created = await showDialog<TaskDraft>(
      context: context,
      builder: (_) => TaskDialog(initialDate: _selectedDay),
    );
    if (created == null) {
      return;
    }

    try {
      await _api.createTask(
        actorId: sessionUser.id,
        userId: targetUser,
        draft: created,
      );
      await _reloadData();
      _showMessage('Task created.');
    } catch (e) {
      _showError('Failed to create task: $e');
    }
  }

  Future<void> _updateTaskStatus(TaskItem task, String status) async {
    final sessionUser = _sessionUser;
    if (sessionUser == null) {
      return;
    }

    try {
      await _api.updateTask(
        actorId: sessionUser.id,
        taskId: task.id,
        update: {
          'status': status,
          'title': task.title,
          'dueAt': task.dueAt.toUtc().toIso8601String(),
          'priority': task.priority,
          'notes': task.notes,
        },
      );
      await _reloadData();
    } catch (e) {
      _showError('Failed to update task: $e');
    }
  }

  Future<void> _updateRsvp(ScheduleEntry entry, String response) async {
    final sessionUser = _sessionUser;
    if (sessionUser == null) {
      return;
    }

    try {
      await _api.updateRsvp(
        actorId: sessionUser.id,
        scheduleEntryId: entry.id,
        userId: entry.userId,
        response: response,
      );
      await _reloadData();
    } catch (e) {
      _showError('Failed to update RSVP: $e');
    }
  }

  void _showConflictDialog(List<ScheduleEntry> conflicts) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Conflict Warning'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This entry overlaps with:'),
              const SizedBox(height: 10),
              ...conflicts.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${c.type} · ${timeRangeLabel(c.startAt, c.endAt)}',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _logout() {
    setState(() {
      _sessionUser = null;
      _selectedProfessionalId = null;
      _assignedProfessionalIds = <int>{};
      _entries = const [];
      _weekEntries = const [];
      _tasks = const [];
      _notifications = const [];
      _auditEvents = const [];
      _activeTab = 0;
    });
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(text), backgroundColor: Colors.red.shade700),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_bootLoading && _sessionUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_sessionUser == null) {
      return LoginScreen(users: _users, onLogin: _login);
    }

    final session = _sessionUser!;
    final targetUser = _users.firstWhere(
      (u) => u.id == _selectedProfessionalId,
      orElse: () => session,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('ReelOn Scheduler'),
        actions: [
          IconButton(
            onPressed: _reloadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 2),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF4F8FA), Color(0xFFEAF3F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            _HeaderBar(
              session: session,
              targetUser: targetUser,
              selectedDay: _selectedDay,
              users: _users,
              assignedProfessionalIds: _assignedProfessionalIds,
              onDateChanged: (d) {
                setState(() => _selectedDay = startOfDay(d));
                _reloadData();
              },
              onProfessionalChanged: (id) {
                setState(() => _selectedProfessionalId = id);
                _reloadData();
              },
              onCreateEntry: _openCreateEntryDialog,
              onCreateTask: _openCreateTaskDialog,
            ),
            Expanded(
              child: _dataLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _tabBody(session, targetUser),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _activeTab,
        onDestinationSelected: (index) => setState(() => _activeTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_rounded),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_alt_rounded),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_active_rounded),
            label: 'Activity',
          ),
        ],
      ),
    );
  }

  Widget _tabBody(AppUser session, AppUser targetUser) {
    switch (_activeTab) {
      case 0:
        return _DashboardTab(
          targetUser: targetUser,
          entries: _entries,
          tasks: _tasks,
          notifications: _notifications,
        );
      case 1:
        return _ScheduleTab(
          session: session,
          selectedDay: _selectedDay,
          mode: _scheduleViewMode,
          entries: _entries,
          weekEntries: _weekEntries,
          tasks: _tasks,
          assignedProfessionalIds: _assignedProfessionalIds,
          onModeChanged: (mode) => setState(() => _scheduleViewMode = mode),
          onDaySelected: (day) {
            setState(() {
              _selectedDay = day;
            });
            _reloadData();
          },
          onCreateEntry: _openCreateEntryDialog,
          onRsvpChanged: _updateRsvp,
          onEditEntry: _openEditEntryDialog,
        );
      case 2:
        return _TasksTab(
          tasks: _tasks,
          onTaskStatusChanged: _updateTaskStatus,
          onCreateTask: _openCreateTaskDialog,
        );
      case 3:
        return _ActivityTab(
          notifications: _notifications,
          auditEvents: _auditEvents,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.session,
    required this.targetUser,
    required this.selectedDay,
    required this.users,
    required this.assignedProfessionalIds,
    required this.onDateChanged,
    required this.onProfessionalChanged,
    required this.onCreateEntry,
    required this.onCreateTask,
  });

  final AppUser session;
  final AppUser targetUser;
  final DateTime selectedDay;
  final List<AppUser> users;
  final Set<int> assignedProfessionalIds;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<int> onProfessionalChanged;
  final VoidCallback onCreateEntry;
  final VoidCallback onCreateTask;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final managerDropdown = session.role == UserRole.manager
              ? SizedBox(
                  width: constraints.maxWidth < 760 ? double.infinity : 250,
                  child: DropdownButtonFormField<int>(
                    initialValue: targetUser.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Professional',
                      isDense: true,
                    ),
                    items: users
                        .where((u) => assignedProfessionalIds.contains(u.id))
                        .map(
                          (u) => DropdownMenuItem(
                            value: u.id,
                            child: Text(u.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        onProfessionalChanged(value);
                      }
                    },
                  ),
                )
              : null;

          final summaryChips = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.person_rounded, size: 18),
                label: Text('${session.name} · ${session.role.label}'),
              ),
              Chip(
                avatar: const Icon(Icons.calendar_today_rounded, size: 18),
                label: Text(dateLabel(selectedDay)),
              ),
            ],
          );

          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onCreateEntry,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New Entry'),
              ),
              OutlinedButton.icon(
                onPressed: onCreateTask,
                icon: const Icon(Icons.task_rounded),
                label: const Text('New Task'),
              ),
            ],
          );

          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                summaryChips,
                if (managerDropdown != null) ...[
                  const SizedBox(height: 10),
                  managerDropdown,
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => onDateChanged(
                          selectedDay.subtract(const Duration(days: 1)),
                        ),
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Prev'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => onDateChanged(
                          selectedDay.add(const Duration(days: 1)),
                        ),
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Next'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                actions,
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summaryChips,
                    if (managerDropdown != null) ...[
                      const SizedBox(height: 8),
                      managerDropdown,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () => onDateChanged(
                  selectedDay.subtract(const Duration(days: 1)),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(
                shortDateLabel(selectedDay),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              IconButton(
                onPressed: () =>
                    onDateChanged(selectedDay.add(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              const SizedBox(width: 8),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkGray.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.targetUser,
    required this.entries,
    required this.tasks,
    required this.notifications,
  });

  final AppUser targetUser;
  final List<ScheduleEntry> entries;
  final List<TaskItem> tasks;
  final List<NotificationItem> notifications;

  @override
  Widget build(BuildContext context) {
    final doneCount = tasks.where((t) => t.status == 'done').length;
    final pendingCount = tasks.length - doneCount;
    final metrics = [
      ('Selected User', targetUser.name),
      ('Entries Today', '${entries.length}'),
      ('Pending Tasks', '$pendingCount'),
      ('Notifications', '${notifications.length}'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
      children: [
        _GlassCard(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: metrics
                .map(
                  (m) => ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 150),
                    child: _MetricTile(label: m.$1, value: m.$2),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Today Timeline',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                const Text('No schedule entries for today.')
              else
                ...entries
                    .take(5)
                    .map(
                      (e) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.skyAccent.withValues(alpha: 0.33),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${e.type} · ${timeRangeLabel(e.startAt, e.endAt)}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                e.statusLabel,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab({
    required this.session,
    required this.selectedDay,
    required this.mode,
    required this.entries,
    required this.weekEntries,
    required this.tasks,
    required this.assignedProfessionalIds,
    required this.onModeChanged,
    required this.onDaySelected,
    required this.onCreateEntry,
    required this.onRsvpChanged,
    required this.onEditEntry,
  });

  final AppUser session;
  final DateTime selectedDay;
  final ScheduleViewMode mode;
  final List<ScheduleEntry> entries;
  final List<ScheduleEntry> weekEntries;
  final List<TaskItem> tasks;
  final Set<int> assignedProfessionalIds;
  final ValueChanged<ScheduleViewMode> onModeChanged;
  final ValueChanged<DateTime> onDaySelected;
  final VoidCallback onCreateEntry;
  final Future<void> Function(ScheduleEntry entry, String value) onRsvpChanged;
  final Future<void> Function(ScheduleEntry entry) onEditEntry;

  @override
  Widget build(BuildContext context) {
    final weekDays = List<DateTime>.generate(
      7,
      (index) => startOfDay(
        selectedDay
            .subtract(const Duration(days: 3))
            .add(Duration(days: index)),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
      children: [
        _GlassCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My Calendar',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Last synced: ${dateLabel(DateTime.now())} · ${timeLabel(DateTime.now())}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onCreateEntry,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create'),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Filter placeholder')),
                  );
                },
                icon: const Icon(Icons.filter_list_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 1080;
            final sidebar = _ScheduleSidebar(
              selectedDay: selectedDay,
              entries: entries,
              tasks: tasks,
              session: session,
              assignedProfessionalIds: assignedProfessionalIds,
              onDaySelected: onDaySelected,
            );
            final weekView = _ScheduleWeekGrid(
              selectedDay: selectedDay,
              weekDays: weekDays,
              entries: weekEntries,
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 360, child: sidebar),
                  const SizedBox(width: 14),
                  Expanded(child: weekView),
                ],
              );
            }

            return Column(
              children: [
                weekView,
                const SizedBox(height: 14),
                sidebar,
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ScheduleSidebar extends StatelessWidget {
  const _ScheduleSidebar({
    required this.selectedDay,
    required this.entries,
    required this.tasks,
    required this.session,
    required this.assignedProfessionalIds,
    required this.onDaySelected,
  });

  final DateTime selectedDay;
  final List<ScheduleEntry> entries;
  final List<TaskItem> tasks;
  final AppUser session;
  final Set<int> assignedProfessionalIds;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final upcomingTasks = tasks
        .where((task) => !task.dueAt.isBefore(DateTime.now().subtract(const Duration(days: 1))))
        .take(4)
        .toList();

    return Column(
      children: [
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Calendar',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 10),
              _MonthMiniCalendar(
                selectedDay: selectedDay,
                entries: entries,
                tasks: tasks,
                onDaySelected: onDaySelected,
              ),
              const SizedBox(height: 10),
              const Text('My Calendar',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const _CalendarToggle(label: 'My Work', selected: true),
              const _CalendarToggle(label: 'Google Calendar', selected: true),
              const _CalendarToggle(label: 'Apple Calendar', selected: false),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (session.role == UserRole.manager)
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Managed Talent',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 10),
                ...assignedProfessionalIds.map(
                  (id) => _CalendarToggle(
                    label: 'Professional • $id',
                    selected: true,
                  ),
                ),
              ],
            ),
          ),
        if (session.role == UserRole.manager) const SizedBox(height: 12),
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Upcoming Tasks',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 10),
              if (upcomingTasks.isEmpty)
                const Text('No upcoming tasks.')
              else
                ...upcomingTasks.map(
                  (task) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.skyAccent.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Due ${dateLabel(task.dueAt)} · ${task.priority}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CalendarToggle extends StatelessWidget {
  const _CalendarToggle({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
          size: 18,
          color: selected ? AppColors.deepTeal : AppColors.darkGray,
        ),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

class _MonthMiniCalendar extends StatelessWidget {
  const _MonthMiniCalendar({
    required this.selectedDay,
    required this.entries,
    required this.tasks,
    required this.onDaySelected,
  });

  final DateTime selectedDay;
  final List<ScheduleEntry> entries;
  final List<TaskItem> tasks;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(selectedDay.year, selectedDay.month, 1);
    final weekdayOffset = firstOfMonth.weekday % 7;
    final totalCells = 42;
    final days = List<DateTime>.generate(totalCells, (index) {
      final dayNumber = index - weekdayOffset + 1;
      return DateTime(selectedDay.year, selectedDay.month, dayNumber);
    });

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${selectedDay.month}/${selectedDay.year}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const Icon(Icons.calendar_month_rounded, size: 18),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.2,
          children: [
            ...['S', 'M', 'T', 'W', 'T', 'F', 'S'].map(
              (label) => Center(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            ...days.map(
              (date) {
                final inMonth = date.month == selectedDay.month;
                final isSelected = sameDay(date, selectedDay);
                final hasEntries = entries.any((e) => sameDay(e.startAt, date));
                final hasTasks = tasks.any((t) => sameDay(t.dueAt, date));
                final hasActivity = hasEntries || hasTasks;
                return GestureDetector(
                  onTap: () => onDaySelected(date),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.deepTeal : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            color: inMonth
                                ? (isSelected ? Colors.white : AppColors.ink)
                                : AppColors.darkGray.withValues(alpha: 0.35),
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                        if (hasActivity && !isSelected)
                          Positioned(
                            bottom: 2,
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.aquaAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _ScheduleWeekGrid extends StatelessWidget {
  const _ScheduleWeekGrid({
    required this.selectedDay,
    required this.weekDays,
    required this.entries,
  });

  final DateTime selectedDay;
  final List<DateTime> weekDays;
  final List<ScheduleEntry> entries;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton(
                onPressed: () {},
                child: const Text('Today'),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Week of ${shortDateLabel(selectedDay)}'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 520,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: weekDays
                    .map(
                      (day) => SizedBox(
                        width: 180,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    shortDateLabel(day),
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    dateLabel(day),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            ...entries
                                .where((entry) => sameDay(entry.startAt, day))
                                .map(
                                  (entry) => Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: _statusColor(entry.status).withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.type,
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          timeRangeLabel(entry.startAt, entry.endAt),
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'available':
      return AppColors.success;
    case 'busy':
      return AppColors.warning;
    case 'confirmed_booking':
      return AppColors.deepTeal;
    case 'shoot_work_day':
      return AppColors.aquaAccent;
    case 'travel':
      return AppColors.skyAccent;
    default:
      return AppColors.darkGray;
  }
}

class _TasksTab extends StatelessWidget {
  const _TasksTab({
    required this.tasks,
    required this.onTaskStatusChanged,
    required this.onCreateTask,
  });

  final List<TaskItem> tasks;
  final Future<void> Function(TaskItem task, String status) onTaskStatusChanged;
  final VoidCallback onCreateTask;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
      children: [
        _GlassCard(
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Task List',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
              ),
              FilledButton.icon(
                onPressed: onCreateTask,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New Task'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _GlassCard(
          child: tasks.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('No tasks yet.')),
                )
              : Column(
                  children: tasks
                      .map(
                        (task) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(task.title),
                          subtitle: Text(
                            'Due ${dateTimeLabel(task.dueAt)} · ${task.priority.toUpperCase()}',
                          ),
                          trailing: SizedBox(
                            width: 112,
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: task.status,
                              items: const [
                                DropdownMenuItem(
                                  value: 'open',
                                  child: Text('Open'),
                                ),
                                DropdownMenuItem(
                                  value: 'done',
                                  child: Text('Done'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  onTaskStatusChanged(task, value);
                                }
                              },
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.notifications, required this.auditEvents});

  final List<NotificationItem> notifications;
  final List<AuditEvent> auditEvents;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
      children: [
        _GlassCard(
          child: const Text(
            'Notifications',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ),
        const SizedBox(height: 10),
        _GlassCard(
          child: notifications.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: Text('No notifications')),
                )
              : Column(
                  children: notifications
                      .map(
                        (n) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            radius: 9,
                            backgroundColor: AppColors.aquaAccent,
                          ),
                          title: Text(n.title),
                          subtitle: Text(
                            '${n.message}\n${dateTimeLabel(n.createdAt)}',
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 10),
        _GlassCard(
          child: const Text(
            'Audit Trail',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ),
        const SizedBox(height: 10),
        _GlassCard(
          child: auditEvents.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: Text('No recent changes')),
                )
              : Column(
                  children: auditEvents
                      .map(
                        (a) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.circle,
                            size: 10,
                            color: AppColors.deepTeal,
                          ),
                          title: Text(
                            '${a.action.toUpperCase()} · ${a.entityType} #${a.entityId}',
                          ),
                          subtitle: Text(
                            '${a.actorName} · ${dateTimeLabel(a.createdAt)}',
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class EntryDialog extends StatefulWidget {
  const EntryDialog({super.key, required this.initialDate, this.existing});

  final DateTime initialDate;
  final ScheduleEntry? existing;

  @override
  State<EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<EntryDialog> {
  final _notesController = TextEditingController();

  late String _type;
  late String _status;
  late bool _requiresRsvp;
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? 'Available';
    _status = existing?.status ?? 'available';
    _requiresRsvp = existing?.requiresRsvp ?? false;
    _start =
        existing?.startAt ?? widget.initialDate.add(const Duration(hours: 10));
    _end = existing?.endAt ?? widget.initialDate.add(const Duration(hours: 12));
    _notesController.text = existing?.notes ?? '';
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Create Entry' : 'Edit Entry'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items:
                    const [
                          'Available',
                          'Not Available',
                          'Busy',
                          'Shoot/Work Day',
                          'Travel',
                          'Personal Block',
                          'Hold',
                          'Tentative Booking',
                          'Confirmed Booking',
                        ]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items:
                    const [
                          'available',
                          'not_available',
                          'busy',
                          'shoot_work_day',
                          'travel',
                          'personal_block',
                          'hold',
                          'tentative_booking',
                          'confirmed_booking',
                        ]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 8),
              _DateTimeRow(
                label: 'Start',
                value: _start,
                onPick: () async {
                  final v = await _pickDateTime(
                    context,
                    current: _start,
                    firstDate: startOfDay(widget.initialDate),
                  );
                  if (v != null) {
                    setState(() {
                      final previousDuration = _end.difference(_start);
                      _start = v;
                      if (!_end.isAfter(_start)) {
                        final fallbackDuration = previousDuration.inMinutes > 0
                            ? previousDuration
                            : const Duration(hours: 1);
                        _end = _start.add(fallbackDuration);
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              _DateTimeRow(
                label: 'End',
                value: _end,
                onPick: () async {
                  final v = await _pickDateTime(
                    context,
                    current: _end,
                    firstDate: startOfDay(_start),
                  );
                  if (v != null) {
                    setState(() => _end = v);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              CheckboxListTile(
                value: _requiresRsvp,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _requiresRsvp = v ?? false),
                title: const Text('Requires RSVP'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_end.isBefore(_start) || _end.isAtSameMomentAs(_start)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('End must be after start')),
              );
              return;
            }
            Navigator.pop(
              context,
              EntryDraft(
                type: _type,
                status: _status,
                start: _start,
                end: _end,
                notes: _notesController.text.trim(),
                requiresRsvp: _requiresRsvp,
              ),
            );
          },
          child: Text(widget.existing == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

class TaskDialog extends StatefulWidget {
  const TaskDialog({super.key, required this.initialDate});

  final DateTime initialDate;

  @override
  State<TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<TaskDialog> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  String _priority = 'medium';
  late DateTime _due;

  @override
  void initState() {
    super.initState();
    _due = widget.initialDate.add(const Duration(hours: 18));
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Task'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                ],
                onChanged: (value) =>
                    setState(() => _priority = value ?? _priority),
              ),
              const SizedBox(height: 8),
              _DateTimeRow(
                label: 'Due',
                value: _due,
                onPick: () async {
                  final v = await _pickDateTime(
                    context,
                    current: _due,
                    firstDate: startOfDay(widget.initialDate),
                  );
                  if (v != null) {
                    setState(() => _due = v);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Title is required')),
              );
              return;
            }
            Navigator.pop(
              context,
              TaskDraft(
                title: _title.text.trim(),
                notes: _notes.text.trim(),
                dueAt: _due,
                priority: _priority,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('$label: ${dateTimeLabel(value)}')),
        TextButton(onPressed: onPick, child: const Text('Pick')),
      ],
    );
  }
}

Future<DateTime?> _pickDateTime(
  BuildContext context, {
  required DateTime current,
  required DateTime firstDate,
}) async {
  final date = await showDatePicker(
    context: context,
    firstDate: startOfDay(firstDate),
    lastDate: DateTime(2035),
    initialDate: current.isBefore(firstDate) ? firstDate : current,
  );
  if (date == null || !context.mounted) {
    return null;
  }

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(current),
  );
  if (time == null) {
    return null;
  }
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
