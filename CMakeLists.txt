cmake_minimum_required(VERSION 3.19)

project(cool-retro-term
    VERSION 0.1
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Default to Release. Must run before add_subdirectory(KDSingleApplication):
# its CMakeLists defaults CMAKE_BUILD_TYPE to Debug whenever the top-level
# source dir contains .git, which silently builds qmltermwidget unoptimized.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    message(STATUS "Setting build type to Release as none was specified.")
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Choose the type of build." FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
                 "Debug" "Release" "MinSizeRel" "RelWithDebInfo")
endif()

include(CheckIPOSupported)
check_ipo_supported(RESULT HRT_IPO_SUPPORTED OUTPUT HRT_IPO_ERROR)
if(HRT_IPO_SUPPORTED)
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)
endif()

find_package(Qt6 6.10 REQUIRED COMPONENTS
    Core Qml Quick Widgets Sql QuickControls2 ShaderTools
)

# KDSingleApplication: static submodule build
set(KDSingleApplication_STATIC   ON  CACHE BOOL "" FORCE)
set(KDSingleApplication_TESTS    OFF CACHE BOOL "" FORCE)
set(KDSingleApplication_EXAMPLES OFF CACHE BOOL "" FORCE)
set(KDSingleApplication_DOCS     OFF CACHE BOOL "" FORCE)
add_subdirectory(KDSingleApplication)

add_subdirectory(qmltermwidget)
add_subdirectory(app)
