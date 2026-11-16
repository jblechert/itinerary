/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#ifndef SPEECHOUTPUT_H
#define SPEECHOUTPUT_H

#include <QString>

#include <memory>

#ifdef Q_OS_ANDROID
#include <QJniObject>
#endif

/** Spoken output using the platform's text to speech engine, e.g. for navigation instructions.
 *  On platforms without support this does nothing.
 */
class SpeechOutput
{
public:
    SpeechOutput();
    ~SpeechOutput();
    SpeechOutput(const SpeechOutput &) = delete;
    SpeechOutput &operator=(const SpeechOutput &) = delete;

    /** Speak @p text, interrupting what is currently being spoken. */
    void speak(const QString &text);

private:
#ifdef Q_OS_ANDROID
    // shared with the calls queued to the Android main thread, which can outlive this
    std::shared_ptr<QJniObject> m_speech;
#endif
};

#endif // SPEECHOUTPUT_H
