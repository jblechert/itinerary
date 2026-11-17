/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#ifndef IOSBRIGHTNESSBACKEND_H
#define IOSBRIGHTNESSBACKEND_H

#include "brightnessmanager.h"

/** Screen brightness control on iOS, via UIScreen. */
class IosBrightnessBackend : public BrightnessBackend
{
public:
    explicit IosBrightnessBackend(QObject *parent = nullptr);
    ~IosBrightnessBackend() override;

    void setBrightness(float brightness) override;
    float brightness() const override;
    float maxBrightness() const override;
};

#endif // IOSBRIGHTNESSBACKEND_H
