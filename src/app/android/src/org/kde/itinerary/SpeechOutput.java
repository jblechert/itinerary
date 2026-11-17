/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

package org.kde.itinerary;

import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.provider.Settings;
import android.speech.tts.TextToSpeech;

import java.util.ArrayList;
import java.util.Locale;

/** Spoken output, e.g. for navigation instructions. Must be used from the Android main thread. */
public class SpeechOutput implements TextToSpeech.OnInitListener
{
    private final Context m_context;
    private TextToSpeech m_tts;
    private boolean m_ready = false;
    // result of setting the language, read from other threads
    private volatile int m_languageStatus = TextToSpeech.LANG_AVAILABLE;
    private boolean m_failed = false;
    private final ArrayList<String> m_pendingTexts = new ArrayList<>();

    public SpeechOutput(Context context)
    {
        m_context = context;
        m_tts = new TextToSpeech(context, this);
    }

    /** Returns whether a text to speech engine is installed, without one nothing can be spoken. */
    public static boolean isAvailable(Context context)
    {
        final Intent intent = new Intent(TextToSpeech.Engine.INTENT_ACTION_TTS_SERVICE);
        return !context.getPackageManager().queryIntentServices(intent, 0).isEmpty();
    }

    /** Opens the system settings for text to speech, e.g. to choose an engine and a voice. */
    public static void openSettings(Context context)
    {
        try {
            context.startActivity(new Intent("com.android.settings.TTS_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (ActivityNotFoundException e) {
            context.startActivity(new Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        }
    }

    /** Opens the page of the text to speech engine @p packageName in an app store, e.g. F-Droid, to install it. */
    public static void installEngine(Context context, String packageName)
    {
        try {
            context.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=" + packageName)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (ActivityNotFoundException e) {
            context.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse("https://f-droid.org/packages/" + packageName + "/")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        }
    }

    /** Returns whether the engine has no voice for the language of the application, so nothing is spoken. */
    public boolean isLanguageMissing()
    {
        return m_languageStatus == TextToSpeech.LANG_MISSING_DATA || m_languageStatus == TextToSpeech.LANG_NOT_SUPPORTED;
    }

    /** Lets the user install a voice for the engine in use, or choose another engine. */
    public void installVoice()
    {
        try {
            final Intent intent = new Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            intent.setPackage(m_tts.getDefaultEngine());
            m_context.startActivity(intent);
        } catch (ActivityNotFoundException e) {
            openSettings(m_context);
        }
    }

    @Override
    public void onInit(int status)
    {
        m_ready = status == TextToSpeech.SUCCESS;
        if (!m_ready) {
            // e.g. no engine installed, try again when there is something to say, maybe one got installed meanwhile
            m_failed = true;
            return;
        }
        m_languageStatus = m_tts.setLanguage(Locale.getDefault());
        for (String text : m_pendingTexts) {
            speak(text);
        }
        m_pendingTexts.clear();
    }

    /** Speak @p text, after what is still being spoken.
     *  Announcements can follow each other immediately, e.g. the start of navigation and the first turn.
     */
    public void speak(String text)
    {
        if (!m_ready) {
            m_pendingTexts.add(text);
            if (m_failed && isAvailable(m_context)) {
                m_failed = false;
                m_tts.shutdown();
                m_tts = new TextToSpeech(m_context, this);
            }
            return;
        }
        m_tts.speak(text, TextToSpeech.QUEUE_ADD, null, "org.kde.itinerary.speech");
    }

    public void shutdown()
    {
        m_tts.stop();
        m_tts.shutdown();
        m_ready = false;
    }
}
