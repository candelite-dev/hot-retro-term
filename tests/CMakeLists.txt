find_package(Qt6 REQUIRED COMPONENTS Test QuickTest)

qt_add_executable(hrt_qml_tests quicktest.cpp)
target_link_libraries(hrt_qml_tests PRIVATE Qt6::QuickTest)
target_compile_definitions(hrt_qml_tests PRIVATE QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml")
add_test(NAME qml_regressions COMMAND hrt_qml_tests -o -,txt)
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
add_test(NAME app_startup COMMAND hrt_startup_test -o -,txt)
set_tests_properties(app_startup PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QML_DISABLE_DISK_CACHE=1"
    TIMEOUT 60
)

qt_add_executable(hrt_launchoptions_test launchoptions_test.cpp ../app/launchoptions.cpp)
target_include_directories(hrt_launchoptions_test PRIVATE ../app)
target_link_libraries(hrt_launchoptions_test PRIVATE Qt6::Test)
add_test(NAME launch_options COMMAND hrt_launchoptions_test -o -,txt)

qt_add_executable(hrt_terminal_input_test terminal_input.cpp)
target_link_libraries(hrt_terminal_input_test PRIVATE Qt6::Test Qt6::Widgets Qt6::Quick)
target_compile_definitions(hrt_terminal_input_test PRIVATE TEST_PLUGIN_PATH="${CMAKE_BINARY_DIR}/qmltermwidget")
add_dependencies(hrt_terminal_input_test qmltermwidget)
add_test(NAME terminal_input COMMAND hrt_terminal_input_test -o -,txt)
set_tests_properties(terminal_input PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QML_DISABLE_DISK_CACHE=1"
    TIMEOUT 30
)

if(WIN32)
    add_executable(hrt_console_helper console_helper.cpp)
    target_compile_definitions(hrt_console_helper PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
    target_compile_definitions(hrt_terminal_input_test PRIVATE TEST_CONSOLE_HELPER="$<TARGET_FILE:hrt_console_helper>")
    add_dependencies(hrt_terminal_input_test hrt_console_helper)
    qt_add_executable(hrt_conpty_test conpty.cpp ../qmltermwidget/lib/PtyWin.cpp
        ../qmltermwidget/lib/kprocess.cpp ../qmltermwidget/lib/ShellCommand.cpp)
    target_include_directories(hrt_conpty_test PRIVATE ../qmltermwidget/lib)
    target_link_libraries(hrt_conpty_test PRIVATE Qt6::Test)
    target_compile_definitions(hrt_conpty_test PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN
        _WIN32_WINNT=0x0A00 WINVER=0x0A00 NTDDI_VERSION=0x0A000006
        TEST_CONSOLE_HELPER="$<TARGET_FILE:hrt_console_helper>")
    add_dependencies(hrt_conpty_test hrt_console_helper)
    add_test(NAME conpty COMMAND hrt_conpty_test -o -,txt)
    set_tests_properties(conpty PROPERTIES TIMEOUT 90)
endif()

# These must work without initializing a graphical platform, even when flags precede them.
qt_add_executable(hrt_cli_test cli.cpp)
target_link_libraries(hrt_cli_test PRIVATE Qt6::Test)
target_compile_definitions(hrt_cli_test PRIVATE TEST_APP_BINARY="$<TARGET_FILE:cool-retro-term>")
add_dependencies(hrt_cli_test cool-retro-term)
add_test(NAME cli_streams COMMAND hrt_cli_test -o -,txt)
set_tests_properties(cli_streams PROPERTIES TIMEOUT 30)
add_test(NAME cli_help COMMAND $<TARGET_FILE:cool-retro-term> --verbose --help)
add_test(NAME cli_version COMMAND $<TARGET_FILE:cool-retro-term> --verbose --version)
set_tests_properties(cli_help cli_version PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=hrt-no-such-platform"
    TIMEOUT 10
)
set_tests_properties(cli_help PROPERTIES PASS_REGULAR_EXPRESSION "Usage: cool-retro-term")
set_tests_properties(cli_version PROPERTIES PASS_REGULAR_EXPRESSION "cool-retro-term")
