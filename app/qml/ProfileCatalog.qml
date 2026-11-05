import QtQuick
import "SettingsCodec.js" as Codec

// Profile model and validation. Persistence is provided by SettingsPersistence.
QtObject {
    property ListModel model: ListModel {}
    signal warning(string message)

    function load(text, builtin) {
        try {
            var parsed = Codec.parseProfiles(text, builtin)
            for (var i = 0; i < parsed.profiles.length; ++i) model.append(parsed.profiles[i])
            if (parsed.errors.length > 0) warning(parsed.errors.join("; "))
            return parsed.errors.length === 0
        } catch (error) {
            warning(error.message)
            return false
        }
    }

    function append(name, text) {
        try {
            model.append(Codec.profile(name, text, false))
            return true
        } catch (error) {
            warning(error.message)
            return false
        }
    }

    function find(name) {
        for (var i = 0; i < model.count; ++i)
            if (model.get(i).text === name) return i
        return -1
    }

    function customProfilesString() {
        var result = []
        for (var i = 0; i < model.count; ++i) {
            var item = model.get(i)
            if (!item.builtin) result.push({ text: item.text, obj_string: item.obj_string, builtin: false })
        }
        return Codec.stringify(result)
    }
}
