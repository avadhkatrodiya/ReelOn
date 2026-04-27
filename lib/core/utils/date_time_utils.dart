DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dateLabel(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

String shortDateLabel(DateTime d) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${weekdays[d.weekday - 1]} ${two(d.day)}/${two(d.month)}';
}

String timeRangeLabel(DateTime start, DateTime end) =>
    '${timeLabel(start)} - ${timeLabel(end)}';

String dateTimeLabel(DateTime d) => '${dateLabel(d)} ${timeLabel(d)}';

String timeLabel(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String two(int value) => value.toString().padLeft(2, '0');
