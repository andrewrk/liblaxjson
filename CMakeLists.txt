cmake_minimum_required(VERSION 2.8)
project(laxjson C)

set(VERSION_MAJOR 0)
set(VERSION_MINOR 0)
set(VERSION_PATCH 0)

set(VERSION "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}")
message("Configuring laxjson version ${VERSION}")

file(GLOB_RECURSE SOURCES ${PROJECT_SOURCE_DIR}/src/*.c)
file(GLOB_RECURSE HEADERS ${PROJECT_SOURCE_DIR}/src/*.h)

set(LIB_CFLAGS "-pedantic -Werror -Wall -Werror=strict-prototypes -Werror=old-style-definition -Werror=missing-prototypes")
set(EXAMPLE_CFLAGS "-pedantic -Werror -Wall")
include_directories("${PROJECT_SOURCE_DIR}/include")

add_library(laxjson_static STATIC ${SOURCES} ${HEADERS})
set_target_properties(laxjson_static PROPERTIES
  OUTPUT_NAME laxjson
  COMPILE_FLAGS "${LIB_CFLAGS} -fPIC")

add_library(laxjson SHARED ${SOURCES} ${HEADERS})
set_target_properties(laxjson PROPERTIES
  SOVERSION ${VERSION_MAJOR}
  VERSION ${VERSION}
  COMPILE_FLAGS ${LIB_CFLAGS})

add_executable(token_list example/token_list.c)
set_target_properties(token_list PROPERTIES
  COMPILE_FLAGS ${EXAMPLE_CFLAGS})
target_link_libraries(token_list laxjson)

install(TARGETS laxjson laxjson_static DESTINATION lib)
