cmake_minimum_required(VERSION 3.19)

find_package(Qt6 REQUIRED COMPONENTS
    Core Qml Quick Widgets Sql QuickControls2 ShaderTools
)

# --- App version from git ---
execute_process(
    COMMAND git -C ${CMAKE_CURRENT_SOURCE_DIR}/.. describe --tags --always --dirty=-dirty
    OUTPUT_VARIABLE APP_VERSION
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
if(NOT APP_VERSION)
    set(APP_VERSION "unknown")
endif()

# Compress QRC resources — TTF fonts compress ~60%; shaves 90+ MB off qrc_resources.cpp
set_source_files_properties(qml/resources.qrc PROPERTIES
    AUTORCC_OPTIONS "-compress;9;-threshold;0"
)

# --- Executable ---
qt_add_executable(cool-retro-term
    main.cpp
    fileio.cpp
    fontmanager.cpp
    fontlistmodel.cpp
    curvatureinputfilter.cpp
    fileio.h
    fontmanager.h
    fontlistmodel.h
    curvatureinputfilter.h
    qml/resources.qrc
)

target_compile_definitions(cool-retro-term PRIVATE
    APP_VERSION="${APP_VERSION}"
)

target_include_directories(cool-retro-term PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/KDSingleApplication/src
)

target_link_libraries(cool-retro-term PRIVATE
    Qt6::Core
    Qt6::Qml
    Qt6::Quick
    Qt6::Widgets
    Qt6::Sql
    Qt6::QuickControls2
    KDAB::kdsingleapplication
)

if(APPLE)
    set_target_properties(cool-retro-term PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_ICON_FILE crt.icns
    )
    target_sources(cool-retro-term PRIVATE icons/crt.icns)
    set_source_files_properties(icons/crt.icns PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources"
    )
    target_link_libraries(cool-retro-term PRIVATE "-framework CoreFoundation")
endif()

# QMLTermWidget is loaded at runtime via QML import path, not linked.
# Declare explicit dependency so CLion/cmake --build always builds the plugin first.
add_dependencies(cool-retro-term qmltermwidget)

# Place the binary at the build root (mirrors qmake DESTDIR = $$OUT_PWD/../)
set_target_properties(cool-retro-term PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)

# --- Shader compilation ---
# .qsb files are pre-compiled and committed to the source tree.
# The compile_shaders target regenerates them when source .frag/.vert files change.
# Normal builds use the existing .qsb files via the QRC; run this target after editing shaders.

find_program(QSB_EXECUTABLE qsb
    HINTS
        "${Qt6_DIR}/../../../libexec"
        "${Qt6_DIR}/../../../bin"
)

if(QSB_EXECUTABLE)
    set(SHADERS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/shaders)
    set(QSB_FLAGS --glsl "100 es,120,150" --hlsl 50 --msl 12 --qt6)
    # qsb -O shells out to spirv-opt; only enable when it exists so
    # compile_shaders keeps working on machines without SPIRV-Tools.
    find_program(SPIRV_OPT_EXECUTABLE spirv-opt)
    if(SPIRV_OPT_EXECUTABLE)
        list(APPEND QSB_FLAGS -O)
    endif()
    set(ALL_SHADER_OUTPUTS)

    # All shaders compiled directly — no combinatoric variants
    foreach(SHADER
        burn_in.frag
        burn_in.vert
        terminal_dynamic.frag
        terminal_dynamic.vert
        terminal_frame.frag
        terminal_frame.vert
        terminal_static.frag
        terminal_static.vert
        window_curvature.frag
        window_curvature.vert
    )
        set(INPUT  ${SHADERS_DIR}/${SHADER})
        set(OUTPUT ${SHADERS_DIR}/${SHADER}.qsb)
        add_custom_command(
            OUTPUT  ${OUTPUT}
            COMMAND ${QSB_EXECUTABLE} ${QSB_FLAGS} -o ${OUTPUT} ${INPUT}
            DEPENDS ${INPUT}
            COMMENT "qsb: ${SHADER}"
        )
        list(APPEND ALL_SHADER_OUTPUTS ${OUTPUT})
    endforeach()

    add_custom_target(compile_shaders DEPENDS ${ALL_SHADER_OUTPUTS} COMMENT "Shaders compiled")
else()
    message(STATUS "qsb not found — using pre-compiled .qsb files. Run 'cmake --build . --target compile_shaders' after installing Qt ShaderTools.")
    add_custom_target(compile_shaders
        COMMAND ${CMAKE_COMMAND} -E echo "qsb not found; cannot compile shaders."
    )
endif()

# --- Install ---
include(GNUInstallDirs)

install(TARGETS cool-retro-term
    BUNDLE  DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

if(UNIX AND NOT APPLE)
    install(FILES ${CMAKE_SOURCE_DIR}/cool-retro-term.desktop
        DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
    )
    foreach(SIZE 32 64 128 256)
        install(FILES icons/${SIZE}x${SIZE}/cool-retro-term.png
            DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/${SIZE}x${SIZE}/apps
        )
    endforeach()
endif()
