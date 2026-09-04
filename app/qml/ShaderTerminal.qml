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

import QtQuick 2.2

import "utils.js" as Utils

Item {
    id: shaderRoot

    property bool splitActive: false

    property ShaderEffectSource source
    property BurnInEffect burnInEffect
    property ShaderEffectSource bloomSource

    property color fontColor: appSettings.fontColor
    property color backgroundColor: appSettings.backgroundColor

    property real screenCurvature: splitActive ? 0
        : appSettings.screenCurvature * appSettings.screenCurvatureSize * terminalWindow.normalizedWindowScale
    property real frameSize: splitActive ? 0
        : appSettings.frameSize * terminalWindow.normalizedWindowScale

    property real chromaColor: appSettings.chromaColor

    property real ambientLight: appSettings.ambientLight * 0.2

    property size virtualResolution
    property size screenResolution

    property real _screenDensity: Math.min(
        screenResolution.width / virtualResolution.width,
        screenResolution.height / virtualResolution.height
    )

    // In unified-CRT mode (splitActive) the window-level unifiedCRT replaces
    // this whole chain; unloading it releases the per-pane FBOs (frameBuffer,
    // the noise copy, and the last texture-provider reference to the pane's
    // kterminalSource) instead of keeping them allocated but inert.
    Loader {
        anchors.fill: parent
        active: !splitActive

        sourceComponent: Item {

            ShaderEffect {
                id: dynamicShader

                property int rasterMode: appSettings.rasterization
                property ShaderEffectSource screenBuffer: frameBuffer
                property ShaderEffectSource burnInSource: shaderRoot.burnInEffect ? shaderRoot.burnInEffect.effectSource : null
                property ShaderEffectSource frameSource: terminalFrameLoader.item

                property color fontColor: shaderRoot.fontColor
                property color backgroundColor: shaderRoot.backgroundColor
                property real screenCurvature: shaderRoot.screenCurvature
                property real chromaColor: shaderRoot.chromaColor
                property real ambientLight: shaderRoot.ambientLight

                property real flickering: appSettings.flickering
                property real horizontalSync: appSettings.horizontalSync
                property real horizontalSyncStrength: Utils.lint(0.05, 0.35, horizontalSync)
                property real glowingLine: appSettings.glowingLine * 0.2

                // Fast burnin properties
                property real burnIn: appSettings.burnIn
                property real burnInLastUpdate: shaderRoot.burnInEffect ? shaderRoot.burnInEffect.lastUpdate : 0
                property real burnInTime: shaderRoot.burnInEffect ? shaderRoot.burnInEffect.burnInFadeTime : 0

                property real jitter: appSettings.jitter
                property size jitterDisplacement: Qt.size(0.007 * jitter, 0.002 * jitter)
                property real staticNoise: appSettings.staticNoise
                property size scaleNoiseSize: Qt.size((width * 0.75) / (noiseTexture.width * appSettings.windowScaling * appSettings.totalFontScaling),
                                                      (height * 0.75) / (noiseTexture.height * appSettings.windowScaling * appSettings.totalFontScaling))

                property size virtualResolution: shaderRoot.virtualResolution

                // Rasterization might display oversamping issues if virtual resolution is close to physical display resolution.
                // We progressively disable rasterization from 4x up to 2x resolution.
                property real rasterizationIntensity: Utils.smoothstep(2.0, 4.0, shaderRoot._screenDensity)

                property real time: timeManager ? timeManager.time : 0
                property ShaderEffectSource noiseSource: noiseShaderSource

                property real frameSize: shaderRoot.frameSize
                property real frameShininess: appSettings.frameShininess
                property real frameActive: terminalFrameLoader.active ? 1.0 : 0.0
                property real bloom: shaderRoot.bloomSource ? appSettings.bloom * 2.5 : 0
                property real windowAlpha: appSettings.windowOpacity

                anchors.fill: parent
                blending: false

                Image {
                    id: noiseTexture
                    source: "images/allNoise512.png"
                    width: 512
                    height: 512
                    fillMode: Image.Tile
                    visible: false
                }
                ShaderEffectSource {
                    id: noiseShaderSource
                    sourceItem: noiseTexture
                    wrapMode: ShaderEffectSource.Repeat
                    live: false
                    visible: false
                    smooth: false
                }

                vertexShader: "qrc:/shaders/terminal_dynamic.vert.qsb"
                fragmentShader: "qrc:/shaders/terminal_dynamic.frag.qsb"

                onStatusChanged: if (log) console.log(log)
            }

            Loader {
                id: terminalFrameLoader

                active: appSettings.frameEnabled
                asynchronous: true

                width: staticShader.width
                height: staticShader.height

                sourceComponent: ShaderEffectSource {

                    sourceItem: terminalFrame
                    hideSource: true
                    visible: false
                    format: ShaderEffectSource.RGBA

                    TerminalFrame {
                        id: terminalFrame
                        blending: false
                        anchors.fill: parent
                    }
                }
            }

            ShaderEffect {
                id: staticShader

                width: parent.width * appSettings.windowScaling
                height: parent.height * appSettings.windowScaling

                property ShaderEffectSource source: shaderRoot.source
                property ShaderEffectSource bloomSource: shaderRoot.bloomSource

                property color fontColor: shaderRoot.fontColor
                property color backgroundColor: shaderRoot.backgroundColor
                property real bloom: bloomSource ? appSettings.bloom * 2.5 : 0

                property real screenCurvature: shaderRoot.screenCurvature

                property real chromaColor: appSettings.chromaColor;

                property real rgbShift: appSettings.rgbShift * (4.0 / width) * appSettings.totalFontScaling

                property real screen_brightness: Utils.lint(0.5, 1.5, appSettings.brightness)
                property real frameShininess: appSettings.frameShininess
                property real frameSize: shaderRoot.frameSize

                blending: false
                visible: false

                vertexShader: "qrc:/shaders/terminal_static.vert.qsb"
                fragmentShader: "qrc:/shaders/terminal_static.frag.qsb"

                onStatusChanged: if (log) console.log(log)
            }

            ShaderEffectSource {
                id: frameBuffer
                visible: false
                sourceItem: staticShader
                hideSource: true
            }
        }
    }
}
