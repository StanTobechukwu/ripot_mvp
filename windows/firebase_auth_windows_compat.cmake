# Backport the Windows-only MSVC fix from FlutterFire PR #16840 while the
# Android/web dependency versions remain pinned. Patch a build-directory copy;
# never modify Flutter's generated files or the shared Pub package cache.
# https://github.com/firebase/flutterfire/pull/16840
function(ripot_apply_firebase_auth_windows_compat)
  if(NOT TARGET firebase_auth_plugin)
    return()
  endif()

  get_target_property(auth_source_dir firebase_auth_plugin SOURCE_DIR)
  set(original_source "${auth_source_dir}/firebase_auth_plugin.cpp")
  file(READ "${original_source}" original_content)
  string(REPLACE
    "return EncodableValue(variant.blob_data());"
    "return EncodableValue(flutter::CustomEncodableValue(variant.blob_data()));"
    patched_content "${original_content}")
  string(REPLACE
    "return EncodableValue(variant.mutable_blob_data());"
    "return EncodableValue(flutter::CustomEncodableValue(variant.mutable_blob_data()));"
    patched_content "${patched_content}")
  if(patched_content STREQUAL original_content)
    return()
  endif()

  set(patched_dir "${CMAKE_CURRENT_BINARY_DIR}/ripot_windows_compat")
  file(MAKE_DIRECTORY "${patched_dir}")
  set(patched_source "${patched_dir}/firebase_auth_plugin.cpp")
  file(WRITE "${patched_source}" "${patched_content}")

  get_target_property(auth_sources firebase_auth_plugin SOURCES)
  set(replacement_sources)
  set(replaced_source FALSE)
  foreach(source IN LISTS auth_sources)
    if(source MATCHES "^\\$<")
      list(APPEND replacement_sources "${source}")
    else()
      get_filename_component(absolute_source "${source}" ABSOLUTE
        BASE_DIR "${auth_source_dir}")
      if(absolute_source STREQUAL original_source)
        list(APPEND replacement_sources "${patched_source}")
        set(replaced_source TRUE)
      else()
        list(APPEND replacement_sources "${absolute_source}")
      endif()
    endif()
  endforeach()
  if(NOT replaced_source)
    message(FATAL_ERROR "Cannot locate firebase_auth's Windows source to apply its MSVC fix.")
  endif()
  set_property(TARGET firebase_auth_plugin PROPERTY SOURCES "${replacement_sources}")
  target_include_directories(firebase_auth_plugin PRIVATE "${auth_source_dir}")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${original_source}")
  message(STATUS "Applied FlutterFire #16840 to the Windows build copy of firebase_auth")
endfunction()

ripot_apply_firebase_auth_windows_compat()
