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

    /** Speak @p text, after what is currently being spoken. */
    void speak(const QString &text);

    /** Returns whether there is a text to speech engine to speak with. */
    [[nodiscard]] static bool isAvailable();
    /** Opens the platform's settings for text to speech, e.g. to choose an engine or a voice. */
    static void openSettings();
    /** Opens an app store to install the text to speech engine @p packageName. */
    static void installEngine(const QString &packageName);
    /** Returns whether the engine has no voice for the language of the application. */
    [[nodiscard]] bool isLanguageMissing() const;
    /** Lets the user install a voice for the engine in use. */
    void installVoice();

private:
#ifdef Q_OS_ANDROID
    // shared with the calls queued to the Android main thread, which can outlive this
    std::shared_ptr<QJniObject> m_speech;
#endif
};

#endif // SPEECHOUTPUT_H
