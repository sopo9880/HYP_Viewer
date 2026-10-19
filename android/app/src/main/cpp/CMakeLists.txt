cmake_minimum_required(VERSION 3.22.1)
project(hyp_android_byedpi LANGUAGES C)
set(BYEDPI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/byedpi")
set(BYEDPI_FILES
  "${BYEDPI_DIR}/main.c"
  "${BYEDPI_DIR}/conev.c"
  "${BYEDPI_DIR}/proxy.c"
  "${BYEDPI_DIR}/desync.c"
  "${BYEDPI_DIR}/mpool.c"
  "${BYEDPI_DIR}/extend.c"
  "${BYEDPI_DIR}/packets.c"
)
foreach(source IN LISTS BYEDPI_FILES)
  if(NOT EXISTS "${source}")
    message(FATAL_ERROR "Missing pinned ByeDPI source: ${source}")
  endif()
endforeach()
add_library(hyp_byedpi SHARED ${BYEDPI_FILES} hyp_byedpi_jni.c)
target_include_directories(hyp_byedpi PRIVATE "${BYEDPI_DIR}")
target_compile_features(hyp_byedpi PRIVATE c_std_99)
target_compile_definitions(hyp_byedpi PRIVATE ANDROID_APP _DEFAULT_SOURCE)
target_compile_options(hyp_byedpi PRIVATE -O2 -Wall -Wextra -Wno-unused-parameter -Wno-unused)
target_link_libraries(hyp_byedpi PRIVATE android log)
target_link_options(hyp_byedpi PRIVATE "-Wl,-z,max-page-size=16384" "-Wl,--wrap=daemon")
