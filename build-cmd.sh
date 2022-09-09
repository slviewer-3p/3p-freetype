#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

FREETYPELIB_SOURCE_DIR="freetype-2.12.1"

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

top="$(pwd)"
stage="$(pwd)/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

[ -f "$stage"/packages/include/zlib-ng/zlib.h ] || fail "You haven't installed packages yet."

# extract APR version into VERSION.txt
FREETYPE_INCLUDE_DIR="${top}/${FREETYPELIB_SOURCE_DIR}/include/freetype"
major_version="$(sed -n -E 's/#[[:space:]]*define[[:space:]]+FREETYPE_MAJOR[[:space:]]+([0-9]+)/\1/p' "${FREETYPE_INCLUDE_DIR}/freetype.h")"
minor_version="$(sed -n -E 's/#[[:space:]]*define[[:space:]]+FREETYPE_MINOR[[:space:]]+([0-9]+)/\1/p' "${FREETYPE_INCLUDE_DIR}/freetype.h")"
patch_version="$(sed -n -E 's/#[[:space:]]*define[[:space:]]+FREETYPE_PATCH[[:space:]]+([0-9]+)/\1/p' "${FREETYPE_INCLUDE_DIR}/freetype.h")"
version="${major_version}.${minor_version}.${patch_version}"
build=${AUTOBUILD_BUILD_ID:=0}
echo "${version}.${build}" > "${stage}/VERSION.txt"

pushd "$FREETYPELIB_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        windows*)
            load_vsvars

            case "$AUTOBUILD_VSVER" in
                "120")
                    verdir="vc2013"
                    ;;
                "150")
                    # We have not yet updated the .sln and .vcxproj files for
                    # VS 2017. Until we do, those projects and their build
                    # outputs will be found in the same places as before.
                    verdir="vc2013"
                    ;;
                *)
                    echo "Unknown AUTOBUILD_VSVER = '$AUTOBUILD_VSVER'" 1>&2 ; exit 1
                    ;;
            esac

            build_sln "builds/win32/$verdir/freetype.sln" "LIB Release|$AUTOBUILD_WIN_VSPLATFORM"

            mkdir -p "$stage/lib/release"
            cp -a "objs/win32/$verdir"/freetype*.lib "$stage/lib/release/freetype.lib"

            mkdir -p "$stage/include/freetype2/"
            cp -a include/ft2build.h "$stage/include/"
            cp -a include/freetype "$stage/include/freetype2/"
        ;;

        darwin*)
            # Darwin build environment at Linden is also pre-polluted like Linux
            # and that affects colladadom builds.  Here are some of the env vars
            # to look out for:
            #
            # AUTOBUILD             GROUPS              LD_LIBRARY_PATH         SIGN
            # arch                  branch              build_*                 changeset
            # helper                here                prefix                  release
            # repo                  root                run_tests               suffix

            opts="${TARGET_OPTS:--arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD_RELEASE}"

            # Release
            CFLAGS="$opts" \
                CXXFLAGS="$opts" \
                CPPFLAGS="-I$stage/packages/include/zlib-ng" \
                LDFLAGS="$opts -Wl,-headerpad_max_install_names -L$stage/packages/lib/release -Wl" \
                ./configure --with-pic \
                --prefix="$stage" --libdir="$stage"/lib/release/
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                # make test
                echo "No tests"
            fi

            install_name_tool -id "@executable_path/../Resources/libfreetype.6.dylib" "$stage"/lib/release/libfreetype.6.dylib

            make distclean
        ;;

        linux*)
            # Default target per AUTOBUILD_ADDRSIZE
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Release
            CFLAGS="$opts" \
                CXXFLAGS="$opts" \
                CPPFLAGS="-I$stage/packages/include/zlib-ng" \
                LDFLAGS="$opts -L$stage/packages/lib/release -Wl,--exclude-libs,libz" \
                ./configure --with-pic --with-png=no --with-brotli=no\
                --prefix="$stage" --libdir="$stage"/lib/release/
            make -j `nproc`
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                # make test
                echo "No tests"
            fi

            make distclean
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp LICENSE.TXT "$stage/LICENSES/freetype.txt"
popd

mkdir -p "$stage"/docs/freetype/
cp -a README.Linden "$stage"/docs/freetype/
