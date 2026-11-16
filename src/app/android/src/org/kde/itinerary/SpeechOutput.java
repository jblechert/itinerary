/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

package org.kde.itinerary;

import android.content.Context;
import android.speech.tts.TextToSpeech;

import java.util.Locale;

/** Spoken output, e.g. for navigation instructions. Must be used from the Android main thread. */
public class SpeechOutput implements TextToSpeech.OnInitListener
{
    private TextToSpeech m_tts;
    private boolean m_ready = false;
    private String m_pendingText = null;

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
        if (m_pendingText != null) {
            speak(m_pendingText);
            m_pendingText = null;
        }
    }

    /** Speak @p text, replacing anything still being spoken. */
    public void speak(String text)
    {
        if (!m_ready) {
            m_pendingText = text;
            return;
        }
        m_tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "org.kde.itinerary.speech");
    }

    public void shutdown()
    {
        m_tts.stop();
        m_tts.shutdown();
        m_ready = false;
    }
}
