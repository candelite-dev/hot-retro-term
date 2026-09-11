/*******************************************************************************
* Copyright (c) 2013-2021 "Filippo Scognamiglio"
* https://github.com/Swordfish90/cool-retro-term
*
* This file is part of cool-retro-term.
*
* cool-retro-term is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*******************************************************************************/
import QtQuick

import "utils.js" as Utils

QtObject {
    id: timeManager

    property bool enableTimer: false
    property real time: 0

    property int framesPerUpdate: Math.max(1, appSettings.effectsFrameSkip)

    // The time source only runs while something actually consumes an
    // advancing `time`: a time-based effect, or an in-progress burn-in fade.
    property bool effectsActive: appSettings.flickering > 0
                                 || appSettings.staticNoise > 0
                                 || appSettings.jitter > 0
                                 || appSettings.horizontalSync > 0
                                 || appSettings.glowingLine > 0

    // Held true while a burn-in trail may still be fading. Re-armed by every
    // content paint (notifyContentPainted); expires one full fade after the
    // last paint, letting the app go fully idle with burn-in enabled.
    property bool burnInHold: false

    property Timer _burnInHoldTimer: Timer {
        interval: Utils.lint(appSettings.minBurnInFadeTime,
                             appSettings.maxBurnInFadeTime,
                             appSettings.burnIn) * 1000 + 250
        onTriggered: timeManager.burnInHold = false
    }

    function notifyContentPainted() {
        if (appSettings.burnIn > 0) {
            burnInHold = true
            _burnInHoldTimer.restart()
        }
    }

    // A Timer, not a FrameAnimation: a running FrameAnimation pins the render
    // loop to vsync and produces identical frames between `time` updates
    // (measured: the frame-skip setting changed neither frame rate nor CPU).
    // With a Timer, a frame is only rendered when `time` actually changes, so
    // effectsFrameSkip becomes a real GPU throttle — 60/skip effect updates
    // per second on any display, refresh-rate-independent.
    // `time` accumulates (never rewinds across restarts): the shaders only
    // need it continuous, and a rewind would freeze the burn-in decay.
    property Timer frameDriver: Timer {
        running: timeManager.enableTimer
                 && (timeManager.effectsActive || timeManager.burnInHold)
        repeat: true
        interval: Math.round(1000 * timeManager.framesPerUpdate / 60)
        onTriggered: timeManager.time += interval / 1000
    }
}
