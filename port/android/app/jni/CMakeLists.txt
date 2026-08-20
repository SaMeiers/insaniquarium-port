# Punto de entrada del build nativo para Android.
#
# No duplica nada: reusa el mismo port/CMakeLists.txt que se usa en escritorio.
# Alli, cuando ANDROID esta definido, el juego se construye como libreria
# compartida "main" (libmain.so) en vez de ejecutable.
cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

project(InsaniquariumAndroid)

# port/ esta tres niveles arriba: android/app/jni -> android/app -> android -> port
add_subdirectory(${CMAKE_CURRENT_LIST_DIR}/../../.. winfish_build)
