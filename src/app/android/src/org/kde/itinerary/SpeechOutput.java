/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

package org.kde.itinerary;

import android.content.Context;
import android.speech.tts.TextToSpeech;

import java.util.ArrayList;
import java.util.Locale;

/** Spoken output, e.g. for navigation instructions. Must be used from the Android main thread. */
public class SpeechOutput implements TextToSpeech.OnInitListener
{
    private TextToSpeech m_tts;
    private boolean m_ready = false;
    private final ArrayList<String> m_pendingTexts = new ArrayList<>();

    public SpeechOutput(Context context)
    {
        m_tts = new TextToSpeech(context, this);
    }

    @Override
    public void onInit(int status)
    {
        m_ready = status == TextToSpeech.SUCCESS;
        if (!m_ready) {
            return;
        }
        m_tts.setLanguage(Locale.getDefault());
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
