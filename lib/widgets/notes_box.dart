// lib/widgets/notes_box.dart
// Mirrors frontend-app/src/components/NotesBox.jsx — local optional notes
// keyed as notes_{formKey}, with migration from a provisional …_new key.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class NotesBox extends StatefulWidget {
  /// e.g. form_a_01-0007 or form_a_new
  final String formKey;

  const NotesBox({super.key, required this.formKey});

  @override
  State<NotesBox> createState() => _NotesBoxState();
}

class _NotesBoxState extends State<NotesBox> {
  static const int _max = 500;
  final _ctrl = TextEditingController();
  bool _focused = false;
  String? _activeKey;
  bool _skipPersist = false;

  String get _storageKey => "notes_${widget.formKey}";

  @override
  void initState() {
    super.initState();
    _hydrate();
    _ctrl.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant NotesBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.formKey != widget.formKey) {
      _hydrate();
    }
  }

  Future<void> _hydrate() async {
    final key = _storageKey;
    _skipPersist = true;
    _activeKey = key;
    final text = await _readNotes(key, widget.formKey);
    if (!mounted) return;
    _ctrl.text = text;
    setState(() {});
    // Allow subsequent edits to persist.
    _skipPersist = false;
  }

  Future<String> _readNotes(String storageKey, String formKey) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(storageKey);
    if (existing != null && existing.isNotEmpty) return existing;

    if (!formKey.endsWith("_new")) {
      final provisionalKey =
          "notes_${formKey.replaceAll(RegExp(r'_[^_]+$'), '_new')}";
      final migrated = prefs.getString(provisionalKey);
      if (migrated != null && migrated.isNotEmpty) {
        await prefs.setString(storageKey, migrated);
        await prefs.remove(provisionalKey);
        return migrated;
      }
    }
    return "";
  }

  Future<void> _persist() async {
    if (_skipPersist) return;
    if (_activeKey != _storageKey) return;
    final prefs = await SharedPreferences.getInstance();
    final text = _ctrl.text;
    if (text.isNotEmpty) {
      await prefs.setString(_storageKey, text);
    } else {
      await prefs.remove(_storageKey);
    }
  }

  void _onChanged() {
    setState(() {});
    _persist();
  }

  Future<void> _clear() async {
    _ctrl.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final len = _ctrl.text.length;
    final pct = (len / _max).clamp(0.0, 1.0);
    final near = len >= (_max * 0.8);
    final atLimit = len >= _max;
    final barColor = atLimit
        ? c.danger
        : near
            ? c.warning
            : c.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused
              ? c.primary.withOpacity(0.45)
              : (_ctrl.text.isNotEmpty
                  ? c.primary.withOpacity(0.2)
                  : c.border),
        ),
        boxShadow: [
          BoxShadow(
            color: c.textPrimary.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.primarySoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.edit_note_rounded, color: c.primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text("Notes",
                    style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.border),
                  ),
                  child: Text("Optional",
                      style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(
                "Add remarks, observations, or follow-up reminders. Not required for submission.",
                style: TextStyle(color: c.textTertiary, fontSize: 11, height: 1.35),
              ),
            ]),
          ),
          if (_ctrl.text.isNotEmpty)
            TextButton(
              onPressed: _clear,
              style: TextButton.styleFrom(
                foregroundColor: c.textTertiary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text("Clear",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          maxLength: _max,
          maxLines: 3,
          minLines: 3,
          inputFormatters: [LengthLimitingTextInputFormatter(_max)],
          onTap: () => setState(() => _focused = true),
          onTapOutside: (_) {
            FocusScope.of(context).unfocus();
            setState(() => _focused = false);
          },
          style: TextStyle(color: c.textPrimary, fontSize: 13, height: 1.4),
          decoration: InputDecoration(
            counterText: "",
            hintText:
                "e.g. Mother anxious during screening, follow-up required, special observations…",
            hintStyle: TextStyle(color: c.textTertiary, fontSize: 12.5),
            filled: true,
            fillColor: c.surfaceAlt,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.primary, width: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                backgroundColor: c.border.withOpacity(0.5),
                color: barColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            "$len / $_max",
            style: TextStyle(
              color: barColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
      ]),
    );
  }
}
