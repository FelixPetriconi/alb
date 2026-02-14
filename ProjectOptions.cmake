include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


include(CheckCXXSourceCompiles)


macro(alb_supports_sanitizers)
  # Emscripten doesn't support sanitizers
  if(EMSCRIPTEN)
    set(SUPPORTS_UBSAN OFF)
    set(SUPPORTS_ASAN OFF)
  elseif((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)

    message(STATUS "Sanity checking UndefinedBehaviorSanitizer, it should be supported on this platform")
    set(TEST_PROGRAM "int main() { return 0; }")

    # Check if UndefinedBehaviorSanitizer works at link time
    set(CMAKE_REQUIRED_FLAGS "-fsanitize=undefined")
    set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=undefined")
    check_cxx_source_compiles("${TEST_PROGRAM}" HAS_UBSAN_LINK_SUPPORT)

    if(HAS_UBSAN_LINK_SUPPORT)
      message(STATUS "UndefinedBehaviorSanitizer is supported at both compile and link time.")
      set(SUPPORTS_UBSAN ON)
    else()
      message(WARNING "UndefinedBehaviorSanitizer is NOT supported at link time.")
      set(SUPPORTS_UBSAN OFF)
    endif()
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    if (NOT WIN32)
      message(STATUS "Sanity checking AddressSanitizer, it should be supported on this platform")
      set(TEST_PROGRAM "int main() { return 0; }")

      # Check if AddressSanitizer works at link time
      set(CMAKE_REQUIRED_FLAGS "-fsanitize=address")
      set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=address")
      check_cxx_source_compiles("${TEST_PROGRAM}" HAS_ASAN_LINK_SUPPORT)

      if(HAS_ASAN_LINK_SUPPORT)
        message(STATUS "AddressSanitizer is supported at both compile and link time.")
        set(SUPPORTS_ASAN ON)
      else()
        message(WARNING "AddressSanitizer is NOT supported at link time.")
        set(SUPPORTS_ASAN OFF)
      endif()
    else()
      set(SUPPORTS_ASAN ON)
    endif()
  endif()
endmacro()

macro(alb_setup_options)
  option(alb_ENABLE_HARDENING "Enable hardening" ON)
  option(alb_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    alb_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    alb_ENABLE_HARDENING
    OFF)

  alb_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR alb_PACKAGING_MAINTAINER_MODE)
    option(alb_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(alb_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(alb_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(alb_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(alb_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(alb_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(alb_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(alb_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(alb_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(alb_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(alb_ENABLE_PCH "Enable precompiled headers" OFF)
    option(alb_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(alb_ENABLE_IPO "Enable IPO/LTO" ON)
    option(alb_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(alb_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(alb_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(alb_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(alb_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(alb_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(alb_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(alb_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(alb_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(alb_ENABLE_PCH "Enable precompiled headers" OFF)
    option(alb_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      alb_ENABLE_IPO
      alb_WARNINGS_AS_ERRORS
      alb_ENABLE_SANITIZER_ADDRESS
      alb_ENABLE_SANITIZER_LEAK
      alb_ENABLE_SANITIZER_UNDEFINED
      alb_ENABLE_SANITIZER_THREAD
      alb_ENABLE_SANITIZER_MEMORY
      alb_ENABLE_UNITY_BUILD
      alb_ENABLE_CLANG_TIDY
      alb_ENABLE_CPPCHECK
      alb_ENABLE_COVERAGE
      alb_ENABLE_PCH
      alb_ENABLE_CACHE)
  endif()

  alb_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (alb_ENABLE_SANITIZER_ADDRESS OR alb_ENABLE_SANITIZER_THREAD OR alb_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(alb_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(alb_global_options)
  if(alb_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    alb_enable_ipo()
  endif()

  alb_supports_sanitizers()

  if(alb_ENABLE_HARDENING AND alb_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR alb_ENABLE_SANITIZER_UNDEFINED
       OR alb_ENABLE_SANITIZER_ADDRESS
       OR alb_ENABLE_SANITIZER_THREAD
       OR alb_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${alb_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${alb_ENABLE_SANITIZER_UNDEFINED}")
    alb_enable_hardening(alb_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(alb_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(alb_warnings INTERFACE)
  add_library(alb_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  alb_set_project_warnings(
    alb_warnings
    ${alb_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  include(cmake/Linker.cmake)
  # Must configure each target with linker options, we're avoiding setting it globally for now

  if(NOT EMSCRIPTEN)
    include(cmake/Sanitizers.cmake)
    alb_enable_sanitizers(
      alb_options
      ${alb_ENABLE_SANITIZER_ADDRESS}
      ${alb_ENABLE_SANITIZER_LEAK}
      ${alb_ENABLE_SANITIZER_UNDEFINED}
      ${alb_ENABLE_SANITIZER_THREAD}
      ${alb_ENABLE_SANITIZER_MEMORY})
  endif()

  set_target_properties(alb_options PROPERTIES UNITY_BUILD ${alb_ENABLE_UNITY_BUILD})

  if(alb_ENABLE_PCH)
    target_precompile_headers(
      alb_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(alb_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    alb_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(alb_ENABLE_CLANG_TIDY)
    alb_enable_clang_tidy(alb_options ${alb_WARNINGS_AS_ERRORS})
  endif()

  if(alb_ENABLE_CPPCHECK)
    alb_enable_cppcheck(${alb_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(alb_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    alb_enable_coverage(alb_options)
  endif()

  if(alb_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(alb_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(alb_ENABLE_HARDENING AND NOT alb_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR alb_ENABLE_SANITIZER_UNDEFINED
       OR alb_ENABLE_SANITIZER_ADDRESS
       OR alb_ENABLE_SANITIZER_THREAD
       OR alb_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    alb_enable_hardening(alb_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
