/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

package org.kde.itinerary;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

/** Foreground service keeping navigation running while the screen is off or another app is in front,
 *  with an ongoing notification showing the next instruction.
 */
public class NavigationService extends Service
{
    private static final String CHANNEL_ID = "org.kde.itinerary.navigation";
    private static final int NOTIFICATION_ID = 0x4e4156; // "NAV"
    private static final String EXTRA_CHANNEL_NAME = "channelName";
    private static final String EXTRA_TITLE = "title";
    private static final String EXTRA_TEXT = "text";

    public static void start(Context context, String channelName, String title, String text)
    {
        Intent intent = new Intent(context, NavigationService.class);
        intent.putExtra(EXTRA_CHANNEL_NAME, channelName);
        intent.putExtra(EXTRA_TITLE, title);
        intent.putExtra(EXTRA_TEXT, text);
        context.startForegroundService(intent);
    }

    public static void update(Context context, String channelName, String title, String text)
    {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        manager.notify(NOTIFICATION_ID, buildNotification(context, channelName, title, text));
    }

    public static void stop(Context context)
    {
        context.stopService(new Intent(context, NavigationService.class));
    }

    private static Notification buildNotification(Context context, String channelName, String title, String text)
    {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(new NotificationChannel(CHANNEL_ID, channelName, NotificationManager.IMPORTANCE_LOW));
        }

        Intent openIntent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        PendingIntent contentIntent = PendingIntent.getActivity(context, 0, openIntent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

        return new Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.getApplicationInfo().icon)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_NAVIGATION)
            .build();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId)
    {
        String channelName = intent != null ? intent.getStringExtra(EXTRA_CHANNEL_NAME) : "Navigation";
        String title = intent != null ? intent.getStringExtra(EXTRA_TITLE) : "";
        String text = intent != null ? intent.getStringExtra(EXTRA_TEXT) : "";
        Notification notification = buildNotification(this, channelName, title, text);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent)
    {
        return null;
    }
}
