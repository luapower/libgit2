C="-arch i386 src/unix/*.c" P=osx32 \
    L="-arch i386 -install_name @loader_path/libgit2.dylib" \
    D=libgit2.dylib A=libgit2.a ./build.sh
