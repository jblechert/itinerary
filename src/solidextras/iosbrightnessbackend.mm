/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#include "iosbrightnessbackend.h"

#import <UIKit/UIKit.h>

IosBrightnessBackend::IosBrightnessBackend(QObject *parent)
    : BrightnessBackend(parent)
{
}

IosBrightnessBackend::~IosBrightnessBackend() = default;

float IosBrightnessBackend::brightness() const
{
    return UIScreen.mainScreen.brightness;
}

void IosBrightnessBackend::setBrightness(float brightness)
{
    // the system restores the brightness the user has set when the app goes to the background
    UIScreen.mainScreen.brightness = brightness;
}

float IosBrightnessBackend::maxBrightness() const
{
    return 1.0f;
}
