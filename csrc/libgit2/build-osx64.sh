C="-arch x86_64 src/unix/*.c" P=osx64 \
    L="-arch x86_64 -install_name @loader_path/libgit2.dylib" \
    D=libgit2.dylib A=libgit2.a ./build.sh
