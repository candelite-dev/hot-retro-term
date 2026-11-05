import QtQuick
import "SettingsCodec.js" as Codec

// SQLite I/O and recovery policy. Invalid saved entries stay untouched during this
// session; healthy entries still load/save. --default-settings explicitly resets current settings.
QtObject {
    property var settingsTarget: null
    property var storage: null
    property var _protectedKeys: ({})
    signal warning(string message)

    function read(key) {
        try {
            return storage.getSetting(key)
        } catch (error) {
            protect(key, error.message)
            return undefined
        }
    }

    function protect(key, reason) {
        _protectedKeys[key] = true
        warning("Keeping saved " + key + " unchanged: " + reason)
    }

    function loadEntry(key, scope) {
        var text = read(key)
        if (text === undefined || text === null || text === "") return
        try {
            Codec.apply(settingsTarget, Codec.parseSettings(text, scope), scope)
        } catch (error) {
            protect(key, error.message)
        }
    }

    function loadCurrent() {
        loadEntry("_CURRENT_SETTINGS", "settings")
        loadEntry("_CURRENT_PROFILE", "profile")
    }

    function loadCustomProfiles(catalog) {
        var text = read("_CUSTOM_PROFILES")
        if (text !== undefined && text !== null && text !== "" && !catalog.load(text, false))
            protect("_CUSTOM_PROFILES", "invalid profiles")
    }

    function write(entries) {
        var healthy = {}
        for (var key in entries)
            if (!_protectedKeys[key]) healthy[key] = entries[key]
        if (Object.keys(healthy).length === 0) return true
        try {
            if (storage.setSettings(healthy)) return true
            warning("Unable to save settings")
        } catch (error) {
            warning("Unable to save settings: " + error.message)
        }
        return false
    }

    function storeCurrent() {
        return write({
            _CURRENT_SETTINGS: Codec.stringify(Codec.compose(settingsTarget, "settings")),
            _CURRENT_PROFILE: Codec.stringify(Codec.compose(settingsTarget, "profile"))
        })
    }

    function storeCustomProfiles(catalog) {
        return write({ _CUSTOM_PROFILES: catalog.customProfilesString() })
    }
}
