// lib/widgets/shimmer_loader.dart
// ─────────────────────────────────────────────────────────────────────────────
// Lightweight shimmer/skeleton loading widgets — no external package needed.
// Use these anywhere a screen shows data fetched over the network, in place
// of a bare CircularProgressIndicator, so the first paint already hints at
// the shape of the content that's coming in.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A single shimmering box. Building block for skeleton layouts.
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value; // 0 → 1, looping
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * t, 0),
              end: Alignment(1.0 + 2.0 * t, 0),
              colors: [c.surfaceAlt, c.borderLight, c.surfaceAlt],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton stand-in for a `_screenedCard`-style patient row: avatar +
/// two text lines + a trailing status chip. Matches the real card's
/// dimensions so there's no layout jump when data arrives.
class SkeletonPatientCard extends StatelessWidget {
  const SkeletonPatientCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Row(children: [
        const ShimmerBox(
          width: 42,
          height: 42,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              ShimmerBox(width: 140, height: 13),
              SizedBox(height: 8),
              ShimmerBox(width: 90, height: 10),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const ShimmerBox(
          width: 56,
          height: 22,
          borderRadius: BorderRadius.all(Radius.circular(11)),
        ),
      ]),
    );
  }
}

/// A column of `count` skeleton cards — drop this in wherever a list is
/// still on its first load, instead of an empty state or a spinner.
class SkeletonPatientList extends StatelessWidget {
  final int count;
  const SkeletonPatientList({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (_) => const SkeletonPatientCard()),
    );
  }
}
