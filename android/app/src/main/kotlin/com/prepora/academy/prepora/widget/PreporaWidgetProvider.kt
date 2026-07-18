package com.prepora.academy.prepora.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import android.content.SharedPreferences
import android.os.Bundle
import com.prepora.academy.prepora.R

class PreporaWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val prefs: SharedPreferences = context.getSharedPreferences("home_widget_preferences", Context.MODE_PRIVATE)
        for (appWidgetId in appWidgetIds) {
            val streak = prefs.getString("home_widget_streak", "0") ?: "0"
            val totalDays = prefs.getString("home_widget_total", "0") ?: "0"
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 110)
            val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)

            val views = getLayoutForSize(context, minWidth, minHeight, streak, totalDays)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        val prefs: SharedPreferences = context.getSharedPreferences("home_widget_preferences", Context.MODE_PRIVATE)
        val streak = prefs.getString("home_widget_streak", "0") ?: "0"
        val totalDays = prefs.getString("home_widget_total", "0") ?: "0"
        val minWidth = newOptions.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 110)
        val minHeight = newOptions.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)

        val views = getLayoutForSize(context, minWidth, minHeight, streak, totalDays)
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun getLayoutForSize(context: Context, widthDp: Int, heightDp: Int, streak: String, totalDays: String): RemoteViews {
        // Small: 2x2 (~110-140dp)
        if (widthDp < 150 && heightDp < 150) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout_small)
            views.setTextViewText(R.id.streak_text, streak)
            return views
        }
        // Medium: 2x3 / 3x2 (~150-200dp either way)
        if (widthDp < 200 || heightDp < 200) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout_medium)
            views.setTextViewText(R.id.streak_text_medium, streak)
            views.setTextViewText(R.id.message_text, getMessage(streak.toIntOrNull() ?: 0))
            return views
        }
        // Large: 4x2 / 4x4 (250dp+)
        val views = RemoteViews(context.packageName, R.layout.widget_layout_large)
        views.setTextViewText(R.id.streak_text_large, streak)
        views.setTextViewText(R.id.total_days_text, "Total: $totalDays days")
        views.setTextViewText(R.id.motivation_text, getMotivation(streak.toIntOrNull() ?: 0))
        return views
    }

    private fun getMessage(streak: Int): String = when {
        streak == 0 -> "Start your streak!"
        streak <= 2 -> "Great start!"
        streak <= 5 -> "Keep going!"
        streak <= 10 -> "You're on fire!"
        streak <= 20 -> "Amazing dedication!"
        else -> "Legendary!"
    }

    private fun getMotivation(streak: Int): String = when {
        streak == 0 -> "Start learning today!"
        streak == 1 -> "Day 1! The journey begins."
        streak <= 3 -> "Keep showing up!"
        streak <= 7 -> "One week strong!"
        streak <= 14 -> "Two weeks of dedication!"
        streak <= 30 -> "One month of consistency!"
        streak <= 60 -> "Two months! Unstoppable!"
        else -> "You're a learning machine!"
    }
}
