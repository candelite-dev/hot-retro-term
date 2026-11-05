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
import QtQuick.LocalStorage

// SQLite access only. Settings/profile interpretation belongs to the codec and persistence layer.
QtObject {
    readonly property string dbMajorVersion: "2"
    readonly property string dbMinorVersion: "1.0"
    property bool initialized: false

    function getDatabase() {
        return LocalStorage.openDatabaseSync("coolretroterm" + dbMajorVersion, dbMinorVersion, "StorageDatabase", 100000)
    }

    function initialize() {
        getDatabase().transaction(function(tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS settings(setting TEXT UNIQUE, value TEXT)")
        })
        initialized = true
    }

    function getSetting(key) {
        if (!initialized) initialize()
        var value
        getDatabase().readTransaction(function(tx) {
            var rows = tx.executeSql("SELECT value FROM settings WHERE setting=?", [key]).rows
            if (rows.length > 0) value = rows.item(0).value
        })
        return value
    }

    function setSettings(entries) {
        if (!initialized) initialize()
        getDatabase().transaction(function(tx) {
            for (var key in entries)
                tx.executeSql("INSERT OR REPLACE INTO settings VALUES (?,?)", [key, entries[key]])
        })
        return true
    }

    function setSetting(key, value) {
        var entries = {}
        entries[key] = value
        return setSettings(entries) ? "OK" : "Error"
    }

    function dropSettings() {
        getDatabase().transaction(function(tx) { tx.executeSql("DROP TABLE IF EXISTS settings") })
        initialized = false
    }
}
