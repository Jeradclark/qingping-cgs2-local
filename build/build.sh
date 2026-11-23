#!/bin/bash
# Builds a fully static aarch64 Squeezelite (ALSA output; FLAC/Vorbis/PCM codecs).
# Static means the device's glibc version does not matter.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
OUT="${OUT:-/out}"
W="${W:-/tmp/slbuild}"
P="$W/prefix"

apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates git make cmake \
  autoconf automake libtool pkg-config gcc-aarch64-linux-gnu \
  libc6-dev-arm64-cross file binutils >/dev/null

mkdir -p "$W" "$P" "$OUT"
cd "$W"

printf '%s\n' \
  'set(CMAKE_SYSTEM_NAME Linux)' \
  'set(CMAKE_SYSTEM_PROCESSOR aarch64)' \
  'set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)' \
  "set(CMAKE_FIND_ROOT_PATH $P)" \
  'set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)' \
  'set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)' \
  'set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)' > tc.cmake

clone() { git clone -q --depth 1 --branch "$2" "$1" "$3" 2>/dev/null; }

echo "== libogg =="
clone https://github.com/xiph/ogg.git v1.3.5 ogg
cmake -S ogg -B b-ogg -DCMAKE_TOOLCHAIN_FILE="$W/tc.cmake" -DCMAKE_INSTALL_PREFIX="$P" \
  -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_TESTING=OFF >/dev/null
cmake --build b-ogg -j"$(nproc)" >/dev/null && cmake --install b-ogg >/dev/null

echo "== libvorbis =="
clone https://github.com/xiph/vorbis.git v1.3.7 vorbis
cmake -S vorbis -B b-vorbis -DCMAKE_TOOLCHAIN_FILE="$W/tc.cmake" -DCMAKE_INSTALL_PREFIX="$P" \
  -DCMAKE_PREFIX_PATH="$P" -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DBUILD_TESTING=OFF >/dev/null
cmake --build b-vorbis -j"$(nproc)" >/dev/null && cmake --install b-vorbis >/dev/null

echo "== libFLAC =="
clone https://github.com/xiph/flac.git 1.4.3 flac
cmake -S flac -B b-flac -DCMAKE_TOOLCHAIN_FILE="$W/tc.cmake" -DCMAKE_INSTALL_PREFIX="$P" \
  -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DWITH_OGG=OFF \
  -DBUILD_CXXLIBS=OFF -DBUILD_PROGRAMS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF \
  -DBUILD_DOCS=OFF -DINSTALL_MANPAGES=OFF >/dev/null
cmake --build b-flac -j"$(nproc)" >/dev/null && cmake --install b-flac >/dev/null

echo "== alsa-lib (config path matches the device: /usr/share/alsa) =="
clone https://github.com/alsa-project/alsa-lib.git v1.2.12 alsa-lib
( cd alsa-lib && autoreconf -fi >/dev/null 2>&1 \
  && ./configure --host=aarch64-linux-gnu --prefix="$P" --enable-static --disable-shared \
       --disable-python --disable-old-symbols --disable-aload --disable-ucm --disable-topology \
       --with-configdir=/usr/share/alsa --with-plugindir=/usr/lib/alsa-lib CFLAGS="-O2" >/dev/null \
  && make -j"$(nproc)" >/dev/null && make install >/dev/null )

echo "== squeezelite (pinned upstream commit) =="
git clone -q https://github.com/ralph-irving/squeezelite.git squeezelite
( cd squeezelite && git checkout -q cc7ee7c0d00bd2aa691a574a7d429d5cd13c858b \
  && make CC=aarch64-linux-gnu-gcc \
       CFLAGS="-Wall -O2 -fcommon -std=gnu99 -I$P/include" \
       OPTS="-DLINKALL -DNO_FAAD -DNO_MAD -DNO_MPG123" \
       LDFLAGS="-static -L$P/lib" \
       LDADD="-lFLAC -lvorbisfile -lvorbis -logg -lasound -lm -lpthread -ldl -lrt" >/dev/null 2>&1 )

aarch64-linux-gnu-strip squeezelite/squeezelite
cp squeezelite/squeezelite "$OUT/squeezelite"
echo "== done =="
file "$OUT/squeezelite"
sha256sum "$OUT/squeezelite"
