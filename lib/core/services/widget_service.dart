import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

class WidgetService {
  static Future<void> updateStreakWidget(int streak, int totalDays) async {
    if (kIsWeb) return;
    await HomeWidget.saveWidgetData<String>('home_widget_streak', streak.toString());
    await HomeWidget.saveWidgetData<String>('home_widget_total', totalDays.toString());
    await HomeWidget.updateWidget(
      iOSName: 'PreporaWidgetProvider',
      androidName: 'PreporaWidgetProvider',
    );
  }
}