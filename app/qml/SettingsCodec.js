.pragma library
.import "SettingsSchema.js" as Schema

// JSON shape/type validation and schema mapping. This file never reads storage or changes UI.
function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
}

function stringify(value) {
    return JSON.stringify(value, function(key, item) {
        return typeof item === "number" ? Number(item.toFixed(4)) : item
    }, 2)
}

function compose(target, scope) {
    var result = {}
    for (var i = 0; i < Schema.schema.length; ++i) {
        var e = Schema.schema[i]
        if (e.scope === scope) result[e.k] = target[e.p]
    }
    return result
}

function parseSettings(text, scope) {
    var object = JSON.parse(text)
    if (!isObject(object)) throw new Error("Expected a JSON object")
    var result = {}
    for (var i = 0; i < Schema.schema.length; ++i) {
        var e = Schema.schema[i]
        if (e.scope !== scope || !Object.prototype.hasOwnProperty.call(object, e.k)) continue
        var value = object[e.k]
        var valid = e.type === "bool" ? typeof value === "boolean"
                  : e.type === "string" ? typeof value === "string"
                  : e.type === "color" ? typeof value === "string" && /^#[0-9a-fA-F]{6}$/.test(value)
                  : typeof value === "number" && isFinite(value)
        if (valid && e.type === "int")
            valid = Math.floor(value) === value && value >= -2147483648 && value <= 2147483647
        if (valid && e.positive) valid = value > 0
        if (valid && e.min !== undefined) valid = value >= e.min
        if (valid && e.max !== undefined) valid = value <= e.max
        if (!valid) throw new Error("Invalid value for " + e.k)
        result[e.k] = value
    }
    return result
}

function apply(target, values, scope) {
    for (var i = 0; i < Schema.schema.length; ++i) {
        var e = Schema.schema[i]
        if (e.scope === scope && values[e.k] !== undefined) target[e.p] = values[e.k]
    }
}

function profile(name, text, builtin) {
    if (typeof name !== "string" || name.trim() === "") throw new Error("A profile needs a name")
    if (typeof text !== "string") throw new Error("A profile needs a JSON object")
    parseSettings(text, "profile")
    return { text: name.trim(), obj_string: text, builtin: builtin }
}

function parseProfiles(text, builtin) {
    var entries = JSON.parse(text)
    if (!Array.isArray(entries)) throw new Error("Expected a profile list")
    var result = { profiles: [], errors: [] }
    for (var i = 0; i < entries.length; ++i) {
        try {
            if (!isObject(entries[i])) throw new Error("Expected a profile object")
            result.profiles.push(profile(entries[i].text, entries[i].obj_string, builtin))
        } catch (error) {
            result.errors.push("Profile " + (i + 1) + ": " + error.message)
        }
    }
    return result
}
