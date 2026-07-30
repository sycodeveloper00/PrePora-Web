import 'package:flutter/material.dart';

class GenderBadge extends StatelessWidget {
  final String gender;
  final double size;
  final Color? color;

  const GenderBadge({
    super.key,
    required this.gender,
    this.size = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final g = gender.toLowerCase().trim();
    if (g.isEmpty) return const SizedBox.shrink();

    IconData icon;
    Color iconColor;

    switch (g) {
      case 'male':
        icon = Icons.male_rounded;
        iconColor = color ?? const Color(0xFF2196F3);
        break;
      case 'female':
        icon = Icons.female_rounded;
        iconColor = color ?? const Color(0xFFE91E63);
        break;
      case 'other':
        icon = Icons.transgender_rounded;
        iconColor = color ?? const Color(0xFF9C27B0);
        break;
      default:
        return const SizedBox.shrink();
    }

    return Icon(icon, size: size, color: iconColor);
  }
}
