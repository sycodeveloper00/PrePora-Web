import 'dart:ui';
import 'package:flutter/material.dart';

class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double borderRadius;
  final double blur;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final List<Color> gradientColors;

  const GlassmorphicContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius = 20.0,
    this.blur = 10.0,
    this.padding = const EdgeInsets.all(16.0),
    this.margin = EdgeInsets.zero,
    this.gradientColors = const [
      Colors.white12,
      Colors.white24,
    ],
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF7C5CBF).withValues(alpha: 0.3);
    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.1 : 0.08);
    final effectiveGradient = gradientColors.length >= 2
        ? gradientColors
        : [
            isDark ? Colors.white12 : Colors.black12,
            isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          ];
    final bgColors = isDark
        ? effectiveGradient
        : [Colors.white.withValues(alpha: 0.95), Colors.white.withValues(alpha: 0.85)];
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 15,
            spreadRadius: -5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor,
                width: 1.5,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: bgColors,
              ),
            ),
            child: DefaultTextStyle(
              style: TextStyle(color: textColor, fontSize: 14),
              child: IconTheme(
                data: IconThemeData(color: textColor),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
