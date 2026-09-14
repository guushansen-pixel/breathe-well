package com.daniel.breathewell;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import java.util.Calendar;

/**
 * Persistiert die Erinnerungs-Einstellung (eigenes SharedPreferences, nicht
 * localStorage - ReminderReceiver/BootReceiver laufen ausserhalb der WebView
 * und koennten localStorage nicht lesen) und plant/verwirft den naechsten
 * AlarmManager-Alarm. Bewusst ein Einmal-Alarm pro Tag (setAndAllowWhileIdle)
 * statt exaktem Repeating - braucht keine SCHEDULE_EXACT_ALARM-Berechtigung,
 * ein paar Minuten Drift sind fuer eine Atem-Erinnerung voellig ausreichend.
 */
class ReminderScheduler {
    static final String PREFS = "reminder_prefs";
    static final String KEY_ENABLED = "enabled";
    static final String KEY_HOUR = "hour";
    static final String KEY_MINUTE = "minute";
    static final String CHANNEL_ID = "daily_reminder";

    static void enable(Context context, int hour, int minute) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_ENABLED, true)
                .putInt(KEY_HOUR, hour)
                .putInt(KEY_MINUTE, minute)
                .apply();
        scheduleNext(context, hour, minute);
    }

    static void disable(Context context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_ENABLED, false).apply();
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        am.cancel(pendingIntent(context));
    }

    static void scheduleNext(Context context, int hour, int minute) {
        Calendar cal = Calendar.getInstance();
        cal.set(Calendar.HOUR_OF_DAY, hour);
        cal.set(Calendar.MINUTE, minute);
        cal.set(Calendar.SECOND, 0);
        if (cal.getTimeInMillis() <= System.currentTimeMillis()) {
            cal.add(Calendar.DAY_OF_YEAR, 1);
        }
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(), pendingIntent(context));
    }

    private static PendingIntent pendingIntent(Context context) {
        Intent intent = new Intent(context, ReminderReceiver.class);
        return PendingIntent.getBroadcast(context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
}
