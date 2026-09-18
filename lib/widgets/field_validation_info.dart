import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small “i” control that shows a validation-rule popover (tap to open/close).
class FieldValidationInfo extends StatefulWidget {
  final String hint;

  const FieldValidationInfo({super.key, required this.hint});

  @override
  State<FieldValidationInfo> createState() => _FieldValidationInfoState();
}

class _FieldValidationInfoState extends State<FieldValidationInfo> {
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
        final c = AppTheme.of(ctx);
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
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 6),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        widget.hint,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
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
    final c = AppTheme.of(context);
    return CompositedTransformTarget(
      link: _link,
      child: Semantics(
        button: true,
        label: 'Field validation info',
        child: InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              Icons.info_outline,
              size: 15,
              color: c.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
