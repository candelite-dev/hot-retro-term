find_package(Qt6 REQUIRED COMPONENTS Test QuickTest)

qt_add_executable(hrt_qml_tests quicktest.cpp)
target_link_libraries(hrt_qml_tests PRIVATE Qt6::QuickTest)
target_compile_definitions(hrt_qml_tests PRIVATE QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml")
add_test(NAME qml_regressions COMMAND hrt_qml_tests)
set_tests_properties(qml_regressions PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")

# Load the same resource bundle and C++ QML types as the app, with temporary settings
# and a controlled shell command. Binary RCC avoids compiling the font bundle twice.
set(TEST_RESOURCES "${CMAKE_CURRENT_BINARY_DIR}/app-resources.rcc")
file(GLOB_RECURSE RESOURCE_INPUTS CONFIGURE_DEPENDS "${PROJECT_SOURCE_DIR}/app/qml/*" "${PROJECT_SOURCE_DIR}/app/shaders/*")
add_custom_command(OUTPUT "${TEST_RESOURCES}"
    COMMAND Qt6::rcc --binary -compress 9 -o "${TEST_RESOURCES}" "${PROJECT_SOURCE_DIR}/app/qml/resources.qrc"
    DEPENDS ${RESOURCE_INPUTS}
)
qt_add_executable(hrt_startup_test startup.cpp
    ../app/launchoptions.cpp ../app/fileio.cpp ../app/fontmanager.cpp ../app/fontlistmodel.cpp ../app/curvatureinputfilter.cpp
    "${TEST_RESOURCES}"
)
target_include_directories(hrt_startup_test PRIVATE ../app)
target_link_libraries(hrt_startup_test PRIVATE Qt6::Test Qt6::Widgets Qt6::Quick Qt6::QuickControls2)
target_compile_definitions(hrt_startup_test PRIVATE
    TEST_RESOURCES="${TEST_RESOURCES}"
    TEST_PLUGIN_PATH="${CMAKE_BINARY_DIR}/qmltermwidget"
)
add_dependencies(hrt_startup_test qmltermwidget)
add_test(NAME app_startup COMMAND hrt_startup_test)
set_tests_properties(app_startup PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QML_DISABLE_DISK_CACHE=1"
    TIMEOUT 30
)

qt_add_executable(hrt_launchoptions_test launchoptions_test.cpp ../app/launchoptions.cpp)
target_include_directories(hrt_launchoptions_test PRIVATE ../app)
target_link_libraries(hrt_launchoptions_test PRIVATE Qt6::Test)
add_test(NAME launch_options COMMAND hrt_launchoptions_test)

# These must work without initializing a graphical platform, even when flags precede them.
add_test(NAME cli_help COMMAND $<TARGET_FILE:cool-retro-term> --verbose --help)
add_test(NAME cli_version COMMAND $<TARGET_FILE:cool-retro-term> --verbose --version)
set_tests_properties(cli_help cli_version PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=hrt-no-such-platform"
    TIMEOUT 10
)
set_tests_properties(cli_help PROPERTIES PASS_REGULAR_EXPRESSION "Usage: cool-retro-term")
set_tests_properties(cli_version PROPERTIES PASS_REGULAR_EXPRESSION "cool-retro-term")
