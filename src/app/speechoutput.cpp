/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#include "speechoutput.h"

#include "logging.h"

#ifdef Q_OS_ANDROID
#include <QCoreApplication>

#include <functional>
#endif

#ifdef Q_OS_ANDROID
// Android's TextToSpeech needs to be created and used on a thread with a looper, i.e. the Android main thread
static void runOnMainThread(std::function<void()> &&func)
{
    QNativeInterface::QAndroidApplication::runOnAndroidMainThread(std::move(func));
}
#endif

SpeechOutput::SpeechOutput()
#ifdef Q_OS_ANDROID
    : m_speech(std::make_shared<QJniObject>())
#endif
{
#ifdef Q_OS_ANDROID
    runOnMainThread([speech = m_speech]() {
        *speech = QJniObject("org/kde/itinerary/SpeechOutput", "(Landroid/content/Context;)V", QNativeInterface::QAndroidApplication::context().object());
    });
#endif
}

SpeechOutput::~SpeechOutput()
{
#ifdef Q_OS_ANDROID
    runOnMainThread([speech = m_speech]() {
        if (speech->isValid()) {
            speech->callMethod<void>("shutdown", "()V");
        }
    });
#endif
}

void SpeechOutput::speak(const QString &text)
{
    qCInfo(Log) << "speaking:" << text;
#ifdef Q_OS_ANDROID
    runOnMainThread([speech = m_speech, text]() {
        if (speech->isValid()) {
            speech->callMethod<void>("speak", "(Ljava/lang/String;)V", QJniObject::fromString(text).object<jstring>());
        }
    });
#endif
}

bool SpeechOutput::isAvailable()
{
#ifdef Q_OS_ANDROID
    return QJniObject::callStaticMethod<jboolean>("org/kde/itinerary/SpeechOutput",
                                                 "isAvailable",
                                                 "(Landroid/content/Context;)Z",
                                                 QNativeInterface::QAndroidApplication::context().object());
#else
    return false;
#endif
}

void SpeechOutput::openSettings()
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>("org/kde/itinerary/SpeechOutput",
                                       "openSettings",
                                       "(Landroid/content/Context;)V",
                                       QNativeInterface::QAndroidApplication::context().object());
#endif
}

void SpeechOutput::installEngine(const QString &packageName)
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>("org/kde/itinerary/SpeechOutput",
                                       "installEngine",
                                       "(Landroid/content/Context;Ljava/lang/String;)V",
                                       QNativeInterface::QAndroidApplication::context().object(),
                                       QJniObject::fromString(packageName).object<jstring>());
#else
    Q_UNUSED(packageName);
#endif
}

bool SpeechOutput::isLanguageMissing() const
{
#ifdef Q_OS_ANDROID
    // only reads a volatile field, so this doesn't need to run on the Android main thread
    return m_speech->isValid() && m_speech->callMethod<jboolean>("isLanguageMissing", "()Z");
#else
    return false;
#endif
}

void SpeechOutput::installVoice()
{
#ifdef Q_OS_ANDROID
    runOnMainThread([speech = m_speech]() {
        if (speech->isValid()) {
            speech->callMethod<void>("installVoice", "()V");
        }
    });
#endif
}
