cmake_minimum_required(VERSION 3.19)

find_package(Qt6 REQUIRED COMPONENTS Core Qml Quick Widgets)

set(QMLTERMWIDGET_SOURCES
    lib/ColorScheme.cpp
    lib/Emulation.cpp
    lib/Filter.cpp
    lib/History.cpp
    lib/HistorySearch.cpp
    lib/KeyboardTranslator.cpp
    lib/konsole_wcwidth.cpp
    lib/kprocess.cpp
    lib/ProcessInfo.cpp
    lib/Screen.cpp
    lib/ScreenWindow.cpp
    lib/Session.cpp
    lib/ShellCommand.cpp
    lib/TerminalCharacterDecoder.cpp
    lib/TerminalDisplay.cpp
    lib/tools.cpp
    lib/Vt102Emulation.cpp
    lib/ksession.cpp
    src/qmltermwidget_plugin.cpp
)

if(WIN32)
    list(APPEND QMLTERMWIDGET_SOURCES
        lib/PtyWin.cpp
        lib/PtyWin.h
    )
else()
    list(APPEND QMLTERMWIDGET_SOURCES
        lib/BlockArray.cpp
        lib/kpty.cpp
        lib/kptydevice.cpp
        lib/kptyprocess.cpp
        lib/Pty.cpp
    )
endif()

add_library(qmltermwidget MODULE ${QMLTERMWIDGET_SOURCES})

if(WIN32)
    target_compile_definitions(qmltermwidget PRIVATE
        QTERMWIDGET_LIBRARY
        NOMINMAX
        WIN32_LEAN_AND_MEAN
        _WIN32_WINNT=0x0A00
        WINVER=0x0A00
    )
else()
    target_compile_definitions(qmltermwidget PRIVATE
        QTERMWIDGET_LIBRARY
        HAVE_POSIX_OPENPT
        HAVE_SYS_TIME_H
    )

    if(APPLE)
        target_compile_definitions(qmltermwidget PRIVATE
            HAVE_UTMPX
            _UTMPX_COMPAT
            HAVE_PTSNAME
            HAVE_UNLOCKPT
            HAVE_GRANTPT
        )
    endif()
endif()

target_include_directories(qmltermwidget PRIVATE lib src)

target_link_libraries(qmltermwidget PRIVATE
    Qt6::Core
    Qt6::Qml
    Qt6::Quick
    Qt6::Widgets
)

# Output the plugin to qmltermwidget/QMLTermWidget/ so the app's import path resolves it.
# main.cpp adds applicationDirPath()+"/qmltermwidget" (Linux) and
# applicationDirPath()+"/../../../qmltermwidget" (macOS bundle) to the import path list.
set_target_properties(qmltermwidget PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qmltermwidget/QMLTermWidget"
)

# Copy plugin assets alongside the .dylib/.so
add_custom_command(TARGET qmltermwidget POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_CURRENT_SOURCE_DIR}/lib/color-schemes
        ${CMAKE_BINARY_DIR}/qmltermwidget/QMLTermWidget/color-schemes
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_CURRENT_SOURCE_DIR}/lib/kb-layouts
        ${CMAKE_BINARY_DIR}/qmltermwidget/QMLTermWidget/kb-layouts
    COMMAND ${CMAKE_COMMAND} -E copy
        ${CMAKE_CURRENT_SOURCE_DIR}/src/qmldir
        ${CMAKE_BINARY_DIR}/qmltermwidget/QMLTermWidget/qmldir
    COMMAND ${CMAKE_COMMAND} -E copy
        ${CMAKE_CURRENT_SOURCE_DIR}/src/QMLTermScrollbar.qml
        ${CMAKE_BINARY_DIR}/qmltermwidget/QMLTermWidget/QMLTermScrollbar.qml
    COMMENT "Copying QMLTermWidget plugin assets"
)

# Install
include(GNUInstallDirs)
set(QML_INSTALL_DIR ${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}/qt6/qml)

install(TARGETS qmltermwidget
    LIBRARY DESTINATION ${QML_INSTALL_DIR}/QMLTermWidget
)
install(FILES
    src/qmldir
    src/QMLTermScrollbar.qml
    DESTINATION ${QML_INSTALL_DIR}/QMLTermWidget
)
install(DIRECTORY lib/color-schemes lib/kb-layouts
    DESTINATION ${QML_INSTALL_DIR}/QMLTermWidget
)
