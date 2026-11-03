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

// Owns terminal instances and their signals for the entire session lifetime,
// including while a tab has no visual slot. The component is supplied by the UI.
QtObject {
    id: pool

    property Item container: null
    property Component terminalComponent: null
    property var _terminals: ({})

    signal sessionFinished(int paneId)
    signal titleChanged(int paneId, string title)
    signal paneClicked(int paneId)

    function getTerminal(paneId) { return _terminals[paneId] || null }

    function createTerminal(paneId) {
        if (!terminalComponent || !container || getTerminal(paneId)) return null
        var terminal = terminalComponent.createObject(container, { paneId: paneId })
        if (!terminal) return null
        _terminals[paneId] = terminal
        terminal.sessionFinished.connect(function() {
            if (pool.getTerminal(paneId) === terminal) pool.sessionFinished(paneId)
        })
        terminal.titleChanged.connect(function() {
            if (pool.getTerminal(paneId) === terminal) pool.titleChanged(paneId, terminal.title)
        })
        terminal.paneClicked.connect(function() {
            if (pool.getTerminal(paneId) === terminal) pool.paneClicked(paneId)
        })
        return terminal
    }

    function destroyTerminal(paneId) {
        var terminal = getTerminal(paneId)
        if (!terminal) return
        delete _terminals[paneId]
        terminal.destroy()
    }

    function clear() {
        var ids = Object.keys(_terminals)
        for (var i = 0; i < ids.length; ++i) destroyTerminal(Number(ids[i]))
    }

    Component.onDestruction: clear()
}
