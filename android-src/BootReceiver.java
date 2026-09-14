package com.daniel.breathewell;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

/** AlarmManager-Alarme ueberleben einen Geraete-Neustart nicht - hier neu
 *  einplanen, falls die Erinnerung aktiv war. */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) return;
        SharedPreferences prefs = context.getSharedPreferences(ReminderScheduler.PREFS, Context.MODE_PRIVATE);
        if (!prefs.getBoolean(ReminderScheduler.KEY_ENABLED, false)) return;
        int hour = prefs.getInt(ReminderScheduler.KEY_HOUR, 8);
        int minute = prefs.getInt(ReminderScheduler.KEY_MINUTE, 0);
        ReminderScheduler.scheduleNext(context, hour, minute);
    }
}
