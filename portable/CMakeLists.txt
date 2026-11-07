cmake_minimum_required(VERSION 3.16)
project(SonanceEQCore VERSION 0.1.0 LANGUAGES CXX)

add_library(sonance_eq INTERFACE)
target_include_directories(sonance_eq INTERFACE include)
target_compile_features(sonance_eq INTERFACE cxx_std_17)

include(CTest)
if(BUILD_TESTING)
  add_executable(sonance_eq_tests tests/core_tests.cpp)
  target_link_libraries(sonance_eq_tests PRIVATE sonance_eq)
  add_test(NAME sonance_eq_core COMMAND sonance_eq_tests)

  add_executable(sonance_eq_coefficients tests/coefficients.cpp)
  target_link_libraries(sonance_eq_coefficients PRIVATE sonance_eq)
endif()
