#!/bin/zsh
# Builds the two helper tools used to drive Wine windows without touching the Mac desktop.
set -e
cd "$(dirname "$0")"
x86_64-w64-mingw32-gcc -O2 -static -o wintool/wintool.exe wintool/wintool.c -lgdi32 -luser32   # brew install mingw-w64
swiftc -O -o winlist winlist.swift                                                               # Xcode CLT
echo "built tools/wintool/wintool.exe and tools/winlist"
