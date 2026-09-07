import 'package:flutter/material.dart';

/// Red asterisk for mandatory CRF fields (Forms A / B / C).
const Color kRequiredAsteriskColor = Color(0xFFE53935);

String stripTrailingAsterisk(String label) =>
    label.replaceFirst(RegExp(r'\s*\*+\s*$'), '').trimRight();

bool labelHasAsterisk(String label) =>
    RegExp(r'\*\s*$').hasMatch(label.trim());

/// Label with a red ` *` when [required] is true or [label] already ends with `*`.
Widget requiredLabel(
  String label, {
  TextStyle? style,
  Color asteriskColor = kRequiredAsteriskColor,
  bool required = false,
}) {
  final showStar = required || labelHasAsterisk(label);
  final base = stripTrailingAsterisk(label);
  if (!showStar) {
    return Text(base, style: style);
  }
  return Text.rich(
    TextSpan(
      style: style,
      children: [
        TextSpan(text: base),
        TextSpan(
          text: ' *',
          style: TextStyle(
            color: asteriskColor,
            fontWeight: FontWeight.w800,
            fontSize: style?.fontSize,
            height: style?.height,
            fontFamily: style?.fontFamily,
          ),
        ),
      ],
    ),
  );
}
