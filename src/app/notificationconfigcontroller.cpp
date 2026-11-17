/*
    SPDX-FileCopyrightText: 2020 Volker Krause <vkrause@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#include "notificationconfigcontroller.h"

#ifdef Q_OS_ANDROID
#include "kandroidextras/activity.h"
#include "kandroidextras/context.h"
#include "kandroidextras/intent.h"
#include "kandroidextras/settings.h"
#endif

// not available on iOS, and only needed on desktop platforms
#if !defined(Q_OS_ANDROID) && !defined(Q_OS_IOS)
#include <KSandbox>
#endif

#include <QCoreApplication>
#include <QDebug>
#include <QDesktopServices>
#if QT_CONFIG(process)
#include <QProcess>
#endif
#include <QStandardPaths>
#include <QUrl>

using namespace Qt::Literals;

#if !defined(Q_OS_ANDROID) && !defined(Q_OS_IOS)
struct {
    bool initialized : 1 = false;
    bool hasSystemSettingsUri : 1 = false;
    bool hasKcm : 1 = false;
} static s_capabilities;

static void detectCapabilities()
{
    if (s_capabilities.initialized) {
        return;
    }
    s_capabilities.initialized = true;

    if (KSandbox::isInside()) {
        // technically only for Plasma >= 6.7, but we have no way to detect that
        s_capabilities.hasSystemSettingsUri = qgetenv("XDG_CURRENT_DESKTOP") == "KDE";
        return;
    }

    s_capabilities.hasSystemSettingsUri = !QStandardPaths::findExecutable(u"systemsettings"_s).isEmpty();

#if QT_CONFIG(process)
    if (!s_capabilities.hasSystemSettingsUri) {
        QProcess proc;
        proc.start(u"kcmshell6"_s, {u"--list"_s});
        proc.waitForFinished();
        s_capabilities.hasKcm = proc.readAllStandardOutput().contains("\nkcm_notifications "_L1);
    }
#endif
}
#endif

bool NotificationConfigController::canConfigureNotification()
{
#if defined(Q_OS_ANDROID) || defined(Q_OS_IOS)
    return true;
#else
    detectCapabilities();
    return s_capabilities.hasSystemSettingsUri || s_capabilities.hasKcm;
#endif
}

bool NotificationConfigController::canShowOnLockScreen()
{
#if defined(Q_OS_ANDROID)
    return true;
#else
    return false;
#endif
}

void NotificationConfigController::configureNotifications()
{
#ifdef Q_OS_ANDROID
    using namespace KAndroidExtras;

    Intent intent;
    intent.setAction(Settings::ACTION_APP_NOTIFICATION_SETTINGS);
    intent.putExtra<java::lang::String>(Settings::EXTRA_APP_PACKAGE, Context::getPackageName());
    Activity::startActivity(intent, 0);
#elif defined(Q_OS_IOS)
    // UIApplicationOpenSettingsURLString, opens the app's page in the system settings including its notification settings
    QDesktopServices::openUrl(QUrl(u"app-settings:"_s));
#else
    detectCapabilities();
    if (s_capabilities.hasSystemSettingsUri) {
        QUrl url;
        url.setScheme(u"systemsettings"_s);
        url.setHost(u"kcm_notifications"_s);
        url.setPath("/--notifyrc "_L1 + QCoreApplication::applicationName());
        QDesktopServices::openUrl(url);
        return;
    }

#if QT_CONFIG(process)
    if (s_capabilities.hasKcm) {
        QProcess proc;
        proc.setProgram(u"kcmshell6"_s);
        proc.setArguments({u"--args"_s, "--notifyrc %1"_L1.arg(QCoreApplication::applicationName()), u"notifications"_s});
        proc.startDetached();
    }
#endif
#endif
}

#include "moc_notificationconfigcontroller.cpp"
