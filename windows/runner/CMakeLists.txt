cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "face_engine.cc"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")

# ONNX Runtime (loaded dynamically at runtime, no link dependency).
set(ORT_DIR "${CMAKE_SOURCE_DIR}/third_party/onnxruntime-win-x64-1.16.3")
target_include_directories(${BINARY_NAME} PRIVATE "${ORT_DIR}/include")

# Copy the ONNX Runtime DLLs and face models next to the executable so the
# engine can load them at runtime.
set(MODELS_DIR "${CMAKE_SOURCE_DIR}/../assets/models")
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${ORT_DIR}/lib/onnxruntime.dll"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/onnxruntime.dll"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${ORT_DIR}/lib/onnxruntime_providers_shared.dll"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/onnxruntime_providers_shared.dll"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${MODELS_DIR}/face_detection_yunet_2023mar.onnx"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/face_detection_yunet_2023mar.onnx"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${MODELS_DIR}/face_recognition_sface_2021dec.onnx"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/face_recognition_sface_2021dec.onnx"
  COMMENT "Copying ONNX Runtime and face models"
)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
