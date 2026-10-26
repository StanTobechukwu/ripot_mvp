class BackupSchedule {
  const BackupSchedule({
    this.enabled = false,
    this.hour = 20,
    this.minute = 0,
    this.weekday = 0,
    this.keep = 5,
    this.nextDue,
  });
  final bool enabled;
  final int hour, minute, weekday, keep; // weekday 0=daily, 1..7=weekly
  final DateTime? nextDue;
  DateTime nextAfter(DateTime now) {
    final local = now.toLocal();
    var next = DateTime(local.year, local.month, local.day, hour, minute);
    while (!next.isAfter(local) || (weekday != 0 && next.weekday != weekday)) {
      // Calendar arithmetic preserves the selected wall-clock time over DST.
      next = DateTime(next.year, next.month, next.day + 1, hour, minute);
    }
    return next;
  }

  bool due(DateTime now) =>
      enabled && nextDue != null && !nextDue!.isAfter(now);
  BackupSchedule advance(DateTime now) => BackupSchedule(
    enabled: enabled,
    hour: hour,
    minute: minute,
    weekday: weekday,
    keep: keep,
    nextDue: nextAfter(now),
  );
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'weekday': weekday,
    'keep': keep,
    'nextDue': nextDue?.toUtc().toIso8601String(),
  };
  factory BackupSchedule.fromJson(Map<String, dynamic> j) {
    final hour = j['hour'] as int,
        minute = j['minute'] as int,
        weekday = j['weekday'] as int,
        keep = j['keep'] as int;
    if (hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        weekday < 0 ||
        weekday > 7 ||
        keep < 3 ||
        keep > 10) {
      throw const FormatException('Invalid backup schedule.');
    }
    return BackupSchedule(
      enabled: j['enabled'] == true,
      hour: hour,
      minute: minute,
      weekday: weekday,
      keep: keep,
      nextDue: j['nextDue'] == null
          ? null
          : DateTime.parse(j['nextDue'] as String),
    );
  }
}
