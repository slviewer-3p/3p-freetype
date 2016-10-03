#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

FREETYPELIB_SOURCE_DIR="freetype"

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

top="$(pwd)"
stage="$(pwd)/stage"

[ -f "$stage"/packages/include/zlib/zlib.h ] || fail "You haven't installed packages yet."

# extract APR version into VERSION.txt
FREETYPE_INCLUDE_DIR="${top}/${FREETYPELIB_SOURCE_DIR}/include/freetype"
major_version=$(perl -ne 's/#\s*define\s+FREETYPE_MAJOR\s+([\d]+)/$1/ && print' "${FREETYPE_INCLUDE_DIR}/freetype.h")
minor_version=$(perl -ne 's/#\s*define\s+FREETYPE_MINOR\s+([\d]+)/$1/ && print' "${FREETYPE_INCLUDE_DIR}/freetype.h")
patch_version=$(perl -ne 's/#\s*define\s+FREETYPE_PATCH\s+([\d]+)/$1/ && print' "${FREETYPE_INCLUDE_DIR}/freetype.h")
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
                CPPFLAGS="-I$stage/packages/include/zlib" \
                LDFLAGS="$opts -Wl,-headerpad_max_install_names -L$stage/packages/lib/release -Wl,-unexported_symbols_list,$stage/packages/lib/release/libz_darwin.exp" \
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
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

##          # Prefer gcc-4.6 if available.
##          if [ -x /usr/bin/gcc-4.6 -a -x /usr/bin/g++-4.6 ]; then
##              export CC=/usr/bin/gcc-4.6
##              export CXX=/usr/bin/g++-4.6
##          fi

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
                CPPFLAGS="-I$stage/packages/include/zlib" \
                LDFLAGS="$opts -L$stage/packages/lib/release -Wl,--exclude-libs,libz" \
                ./configure --with-pic \
                --prefix="$stage" --libdir="$stage"/lib/release/
            make
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
    cp docs/LICENSE.TXT "$stage/LICENSES/freetype.txt"
popd

mkdir -p "$stage"/docs/freetype/
cp -a README.Linden "$stage"/docs/freetype/
