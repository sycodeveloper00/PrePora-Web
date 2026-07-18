import 'package:flutter/material.dart';

final Map<String, int> _debounceTimestamps = {};

bool debounce(String key, {int ms = 600}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final last = _debounceTimestamps[key];
  if (last != null && now - last < ms) return false;
  _debounceTimestamps[key] = now;
  return true;
}

class DebouncedElevatedButton extends StatelessWidget {
  final String debounceKey;
  final String label;
  final Color? bgColor;
  final Color? fgColor;
  final VoidCallback? onPressed;
  final double? fontSize;

  const DebouncedElevatedButton({
    super.key,
    required this.debounceKey,
    required this.label,
    this.bgColor,
    this.fgColor,
    this.onPressed,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed == null ? null : () {
        if (debounce(debounceKey)) onPressed!();
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
      ),
      child: Text(label, style: fontSize != null ? TextStyle(fontSize: fontSize) : null),
    );
  }
}
