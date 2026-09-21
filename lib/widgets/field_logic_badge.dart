import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum FieldLogicType { auto, conditional, carried, validated }

Color fieldLogicColor(FieldLogicType type) {
  switch (type) {
    case FieldLogicType.auto:
      return const Color(0xFF2563EB);
    case FieldLogicType.conditional:
      return const Color(0xFFD97706);
    case FieldLogicType.carried:
      return const Color(0xFF16A34A);
    case FieldLogicType.validated:
      return const Color(0xFF7C3AED);
  }
}

/// Coloured “i” that opens a small popup describing auto / conditional /
/// carried / validated field logic. Matches the web FieldLogicBadge.
class FieldLogicBadge extends StatefulWidget {
  final FieldLogicType type;
  final String title;

  const FieldLogicBadge({
    super.key,
    required this.type,
    this.title = '',
  });

  @override
  State<FieldLogicBadge> createState() => _FieldLogicBadgeState();
}

class _FieldLogicBadgeState extends State<FieldLogicBadge> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
    _open = false;
  }

  void _toggle() {
    if (widget.title.isEmpty) return;
    if (_open) {
      _removeOverlay();
      if (mounted) setState(() {});
      return;
    }
    final overlay = Overlay.of(context);
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    _entry = OverlayEntry(
      builder: (ctx) {
        final screenW = MediaQuery.sizeOf(ctx).width;
        final maxW = (screenW - 32).clamp(200.0, 280.0);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _removeOverlay();
                  if (mounted) setState(() {});
                },
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomCenter,
              followerAnchor: Alignment.topCenter,
              offset: const Offset(0, 6),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_entry!);
    _open = true;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final color = fieldLogicColor(widget.type);
    return CompositedTransformTarget(
      link: _link,
      child: Semantics(
        button: widget.title.isNotEmpty,
        label: widget.title.isEmpty ? widget.type.name : widget.title,
        child: InkWell(
          onTap: widget.title.isEmpty ? null : _toggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              Icons.info_outline,
              size: 15,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class FieldLogicLegend extends StatelessWidget {
  const FieldLogicLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: const [
          _LegendItem(FieldLogicType.auto, "Auto-calculated"),
          _LegendItem(FieldLogicType.conditional, "Depends on another answer"),
          _LegendItem(FieldLogicType.carried, "Carried from another form"),
          _LegendItem(FieldLogicType.validated, "Checked against another field"),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final FieldLogicType type;
  final String label;
  const _LegendItem(this.type, this.label);

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLogicBadge(type: type),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: c.textTertiary,
          ),
        ),
      ],
    );
  }
}
