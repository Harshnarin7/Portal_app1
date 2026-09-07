import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Modern date picker with **month** and **year** dropdowns so nurses can
/// jump to any month/year without repeatedly tapping the back chevron.
Future<DateTime?> showModernDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  assert(!lastDate.isBefore(firstDate), 'lastDate must be on or after firstDate');

  var initial = initialDate;
  if (initial.isBefore(firstDate)) initial = firstDate;
  if (initial.isAfter(lastDate)) initial = lastDate;

  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => _ModernDatePickerDialog(
      initialDate: initial,
      firstDate: DateTime(firstDate.year, firstDate.month, firstDate.day),
      lastDate: DateTime(lastDate.year, lastDate.month, lastDate.day),
      helpText: helpText ?? 'Select date',
    ),
  );
}

class _ModernDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String helpText;

  const _ModernDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.helpText,
  });

  @override
  State<_ModernDatePickerDialog> createState() => _ModernDatePickerDialogState();
}

class _ModernDatePickerDialogState extends State<_ModernDatePickerDialog> {
  late int _year;
  late int _month;
  late int _day;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  @override
  void initState() {
    super.initState();
    _year = widget.initialDate.year;
    _month = widget.initialDate.month;
    _day = widget.initialDate.day;
    _ensureValidMonth();
  }

  DateTime get _selected => DateTime(_year, _month, _day);

  int get _daysInMonth => DateTime(_year, _month + 1, 0).day;

  List<int> get _years {
    final out = <int>[];
    for (var y = widget.firstDate.year; y <= widget.lastDate.year; y++) {
      out.add(y);
    }
    return out;
  }

  List<int> get _availableMonths {
    final months = <int>[];
    for (var m = 1; m <= 12; m++) {
      final start = DateTime(_year, m, 1);
      final end = DateTime(_year, m, DateTime(_year, m + 1, 0).day);
      if (!end.isBefore(widget.firstDate) && !start.isAfter(widget.lastDate)) {
        months.add(m);
      }
    }
    return months;
  }

  void _clampDay() {
    final maxDay = _daysInMonth;
    if (_day > maxDay) _day = maxDay;
    var selected = DateTime(_year, _month, _day);
    if (selected.isBefore(widget.firstDate)) {
      _year = widget.firstDate.year;
      _month = widget.firstDate.month;
      _day = widget.firstDate.day;
    } else if (selected.isAfter(widget.lastDate)) {
      _year = widget.lastDate.year;
      _month = widget.lastDate.month;
      _day = widget.lastDate.day;
    }
  }

  void _ensureValidMonth() {
    final months = _availableMonths;
    if (months.isNotEmpty && !months.contains(_month)) {
      _month = months.first;
    }
    _clampDay();
  }

  bool _isSelectable(int day) {
    final d = DateTime(_year, _month, day);
    return !d.isBefore(widget.firstDate) && !d.isAfter(widget.lastDate);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    AppColors? app;
    try {
      app = AppTheme.of(context);
    } catch (_) {
      app = null;
    }

    final primary = app?.primary ?? theme.colorScheme.primary;
    final surface = app?.surface ?? theme.colorScheme.surface;
    final text1 = app?.textPrimary ?? theme.colorScheme.onSurface;
    final text3 = app?.textTertiary ?? theme.colorScheme.onSurfaceVariant;
    final border = app?.border ?? theme.dividerColor;
    final soft = app?.primarySoft ?? primary.withOpacity(0.12);

    final months = _availableMonths;
    final monthValue = months.contains(_month)
        ? _month
        : (months.isNotEmpty ? months.first : _month);

    // Monday-based grid offset
    final firstWeekday = DateTime(_year, _month, 1).weekday; // 1=Mon … 7=Sun
    final leading = firstWeekday - 1;
    final totalCells = leading + _daysInMonth;
    final rows = ((totalCells + 6) ~/ 7);

    return Dialog(
      backgroundColor: surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.helpText,
                style: TextStyle(
                  color: text3,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_weekdays[(_selected.weekday - 1) % 7]}, '
                '${_months[_month - 1].substring(0, 3)} $_day, $_year',
                style: TextStyle(
                  color: text1,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),

              // Month + Year dropdowns
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _dropdownShell(
                      border: border,
                      soft: soft,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: monthValue,
                          isExpanded: true,
                          icon: Icon(Icons.expand_more_rounded, color: primary),
                          style: TextStyle(
                            color: text1,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          items: months
                              .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(_months[m - 1]),
                                  ))
                              .toList(),
                          onChanged: (m) {
                            if (m == null) return;
                            setState(() {
                              _month = m;
                              _ensureValidMonth();
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _dropdownShell(
                      border: border,
                      soft: soft,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _year,
                          isExpanded: true,
                          icon: Icon(Icons.expand_more_rounded, color: primary),
                          menuMaxHeight: 320,
                          style: TextStyle(
                            color: text1,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          items: _years
                              .map((y) => DropdownMenuItem(
                                    value: y,
                                    child: Text('$y'),
                                  ))
                              .toList(),
                          onChanged: (y) {
                            if (y == null) return;
                            setState(() {
                              _year = y;
                              _ensureValidMonth();
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Weekday headers
              Row(
                children: _weekdays
                    .map((d) => Expanded(
                          child: Center(
                            child: Text(
                              d,
                              style: TextStyle(
                                color: text3,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 6),

              // Day grid
              ...List.generate(rows, (row) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: List.generate(7, (col) {
                      final index = row * 7 + col;
                      final dayNum = index - leading + 1;
                      if (dayNum < 1 || dayNum > _daysInMonth) {
                        return const Expanded(child: SizedBox(height: 40));
                      }
                      final selected = dayNum == _day;
                      final enabled = _isSelectable(dayNum);
                      final isToday = _year == DateTime.now().year &&
                          _month == DateTime.now().month &&
                          dayNum == DateTime.now().day;

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Material(
                            color: selected
                                ? primary
                                : (isToday ? soft : Colors.transparent),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: !enabled
                                  ? null
                                  : () => setState(() => _day = dayNum),
                              child: SizedBox(
                                height: 40,
                                child: Center(
                                  child: Text(
                                    '$dayNum',
                                    style: TextStyle(
                                      color: !enabled
                                          ? text3.withOpacity(0.35)
                                          : selected
                                              ? Colors.white
                                              : text1,
                                      fontWeight: selected || isToday
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),

              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      final n = DateTime.now();
                      final today = DateTime(n.year, n.month, n.day);
                      if (today.isBefore(widget.firstDate) ||
                          today.isAfter(widget.lastDate)) {
                        return;
                      }
                      setState(() {
                        _year = today.year;
                        _month = today.month;
                        _day = today.day;
                      });
                    },
                    child: Text('Today',
                        style: TextStyle(
                            color: primary, fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel',
                        style: TextStyle(
                            color: text3, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                    ),
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('OK',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdownShell({
    required Color border,
    required Color soft,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withOpacity(0.55)),
      ),
      child: child,
    );
  }
}
