package com.daniel.breathewell;

import android.Manifest;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Notification;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;

/** Feuert einmal taeglich (siehe ReminderScheduler), zeigt die Benachrichtigung
 *  und plant direkt den naechsten Tag neu ein. */
public class ReminderReceiver extends BroadcastReceiver {

    @SuppressWarnings("deprecation") // Notification.Builder(context) ohne Channel: noetig fuer API < 26
    @Override
    public void onReceive(Context context, Intent intent) {
        SharedPreferences prefs = context.getSharedPreferences(ReminderScheduler.PREFS, Context.MODE_PRIVATE);
        if (!prefs.getBoolean(ReminderScheduler.KEY_ENABLED, false)) return;

        int hour = prefs.getInt(ReminderScheduler.KEY_HOUR, 8);
        int minute = prefs.getInt(ReminderScheduler.KEY_MINUTE, 0);

        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(new NotificationChannel(
                    ReminderScheduler.CHANNEL_ID, "Atem-Erinnerung", NotificationManager.IMPORTANCE_DEFAULT));
        }

        Intent openApp = new Intent(context, MainActivity.class);
        openApp.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent contentIntent = PendingIntent.getActivity(context, 0, openApp,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(context, ReminderScheduler.CHANNEL_ID)
                : new Notification.Builder(context);
        Notification notification = builder
                .setContentTitle("Zeit zum Atmen")
                .setContentText("Kurze Atemübung gefällig?")
                .setSmallIcon(context.getApplicationInfo().icon)
                .setContentIntent(contentIntent)
                .setAutoCancel(true)
                .build();

        boolean canNotify = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU
                || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
        if (canNotify) {
            nm.notify(1, notification);
        }

        ReminderScheduler.scheduleNext(context, hour, minute);
    }
}
