import QtQuick
import QtTest
import "../../app/qml" as App
import "../../app/qml/SettingsCodec.js" as Codec

TestCase {
    name: "SettingsRecovery"
    QtObject {
        id: values
        property real windowScaling: 1
        property real bloom: 0.55
    }
    QtObject {
        id: fakeStorage
        property var entries: ({})
        property bool failReads: false
        property bool failWrites: false
        function getSetting(key) {
            if (failReads) throw new Error("storage unavailable")
            return entries[key]
        }
        function setSettings(next) {
            if (failWrites) throw new Error("disk full")
            for (var key in next) entries[key] = next[key]
            return true
        }
    }
    App.SettingsPersistence { id: persistence; settingsTarget: values; storage: fakeStorage }
    App.ProfileCatalog { id: catalog }
    SignalSpy { id: warnings; target: persistence; signalName: "warning" }
    function init() {
        values.windowScaling = 1
        values.bloom = 0.55
        fakeStorage.entries = ({})
        fakeStorage.failReads = false
        fakeStorage.failWrites = false
        persistence._protectedKeys = ({})
        catalog.model.clear()
        warnings.clear()
    }
    function test_partialSettingsLoadWithoutProfile() {
        fakeStorage.entries = ({_CURRENT_SETTINGS: '{"windowScaling":0.8}'})
        persistence.loadCurrent()
        compare(values.windowScaling, 0.8)
        compare(values.bloom, 0.55)
    }
    function test_badSettingsDoNotBlockValidAppearance() {
        fakeStorage.entries = ({_CURRENT_SETTINGS: '{broken', _CURRENT_PROFILE: '{"bloom":0.8}'})
        persistence.loadCurrent()
        compare(values.windowScaling, 1)
        compare(values.bloom, 0.8)
        verify(warnings.count > 0)
        persistence.storeCurrent()
        compare(fakeStorage.entries._CURRENT_SETTINGS, '{broken')
        compare(JSON.parse(fakeStorage.entries._CURRENT_PROFILE).bloom, 0.8)
    }
    function test_invalidObjectOrField_data() {
        return [
            {tag: "null", raw: 'null'},
            {tag: "list", raw: '[]'},
            {tag: "scalar", raw: '123'},
            {tag: "wrong type", raw: '{"windowScaling":"0.8"}'},
            {tag: "zero scale", raw: '{"windowScaling":0}'},
            {tag: "negative scale", raw: '{"windowScaling":-2}'},
            {tag: "integer overflow", raw: '{"effectsFrameSkip":1e20}'},
            {tag: "invalid later field", raw: '{"windowScaling":0.8,"effectsFrameSkip":0}'}
        ]
    }
    function test_invalidObjectOrField(data) {
        fakeStorage.entries = ({_CURRENT_SETTINGS: data.raw})
        persistence.loadCurrent()
        compare(values.windowScaling, 1)
        persistence.storeCurrent()
        compare(fakeStorage.entries._CURRENT_SETTINGS, data.raw)
    }
    function test_storageFailureDoesNotThrow() {
        fakeStorage.failReads = true
        persistence.loadCurrent()
        compare(values.windowScaling, 1)
        fakeStorage.failReads = false
        persistence._protectedKeys = ({})
        fakeStorage.failWrites = true
        compare(persistence.storeCurrent(), false)
        verify(warnings.count > 0)
    }
    function test_customProfilesCannotClaimToBeBuiltin() {
        verify(catalog.load('[{"text":"Mine","obj_string":"{}","builtin":true}]', false))
        compare(catalog.model.count, 1)
        compare(catalog.model.get(0).builtin, false)
        compare(JSON.parse(catalog.customProfilesString()).length, 1)
    }
    function test_badCustomProfileKeepsHealthySiblingsAndSavedData() {
        var raw = JSON.stringify([{text:"Good",obj_string:'{"bloom":0.4}'},
                                  {text:"Bad",obj_string:'null'}])
        fakeStorage.entries = ({_CUSTOM_PROFILES: raw})
        persistence.loadCustomProfiles(catalog)
        compare(catalog.model.count, 1)
        compare(catalog.model.get(0).text, "Good")
        persistence.storeCustomProfiles(catalog)
        compare(fakeStorage.entries._CUSTOM_PROFILES, raw)
    }
    function test_badImportDoesNotChangeCatalog() {
        verify(catalog.append("Good", '{}'))
        compare(catalog.append("Bad", '{"bloom":null}'), false)
        compare(catalog.model.count, 1)
        compare(catalog.append("   ", '{}'), false)
        compare(catalog.model.count, 1)
    }
    function test_serializationAcceptsNullAndKeepsPrecision() {
        compare(JSON.parse(Codec.stringify({value:null, real:0.123456})), {value:null, real:0.1235})
    }
    function test_unknownKeysAreIgnored() {
        compare(Codec.parseSettings('{"future":123,"bloom":0.4}', 'profile'), {bloom:0.4})
    }
    function test_legacyTabBarScaleIsIgnored_data() {
        return [{tag: "old default", value: 3}, {tag: "custom", value: 5},
                {tag: "invalid obsolete value", value: "unused"}]
    }
    function test_legacyTabBarScaleIsIgnored(data) {
        fakeStorage.entries = ({_CURRENT_SETTINGS: JSON.stringify({
            windowScaling: 0.8, tabBarScale: data.value
        })})
        persistence.loadCurrent()
        compare(values.windowScaling, 0.8)
        compare(warnings.count, 0)
        verify(persistence.storeCurrent())
        var saved = JSON.parse(fakeStorage.entries._CURRENT_SETTINGS)
        compare(saved.windowScaling, 0.8)
        verify(!saved.hasOwnProperty("tabBarScale"))
    }
}
