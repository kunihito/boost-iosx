#!/bin/bash
set -e

######################################################################
# Script: boost_ios_python.sh
#
# Purpose:
#   - Based on the "boost-iosx" build script, build iOS (ios-arm64) only.
#   - Includes Boost.Python, linking statically with user-specified Python headers and library.
#   - Restores the original logic that creates an Xcode workspace via CocoaPods (pod install)
#
# Usage:
#   ./boost_ios_python.sh \
#     --python-include /path/to/python/include \
#     --python-lib /path/to/libpython3.11.a \
#     [other options]
#
# Available options:
#   --python-include <path>
#       Path to the directory containing Python headers (e.g. /path/to/python/include).
#
#   --python-lib <path>
#       Path to the static Python library, e.g. /path/to/libpython3.11.a.
#
#   -l=<libs>, --libs=<libs>
#       Comma-separated list of Boost libraries to build, e.g. "atomic,filesystem,python".
#       By default, builds all from LIBS_TO_BUILD_ALL.
#
#   --rebuild
#       Clean rebuild.
#
#   --rebuildicu
#       Clean rebuild for icu4c-iosx.
#
# Example:
#   ./boost_ios_python.sh \
#       --python-include /Users/xxx/python-ios/include \
#       --python-lib /Users/xxx/python-ios/libpython3.11.a \
#       --libs=python,filesystem,program_options --rebuild
#
######################################################################

######################################################################
# Original environment setup
######################################################################
THREAD_COUNT=$(sysctl hw.ncpu | awk '{print $2}')
HOST_ARC=$( uname -m )
XCODE_ROOT=$( xcode-select -print-path )
BOOST_VER=1.87.0
EXPECTED_HASH="af57be25cb4c4f4b413ed692fe378affb4352ea50fbe294a11ef548f4d527d89"
MACOSX_VERSION_ARM=12.3
MACOSX_VERSION_X86_64=10.13
IOS_VERSION=13.4
IOS_SIM_VERSION=13.4
CATALYST_VERSION=13.4
TVOS_VERSION=13.0
TVOS_SIM_VERSION=13.0
WATCHOS_VERSION=11.0
WATCHOSSIM_VERSION=11.0

LOCATIONS_FILE_URL="https://raw.githubusercontent.com/apotocki/boost-iosx/master/LOCATIONS"
IOSSYSROOT=$XCODE_ROOT/Platforms/iPhoneOS.platform/Developer
IOSSIMSYSROOT=$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer
MACSYSROOT=$XCODE_ROOT/Platforms/MacOSX.platform/Developer
XROSSYSROOT=$XCODE_ROOT/Platforms/XROS.platform/Developer
XROSSIMSYSROOT=$XCODE_ROOT/Platforms/XRSimulator.platform/Developer
TVOSSYSROOT=$XCODE_ROOT/Platforms/AppleTVOS.platform/Developer
TVOSSIMSYSROOT=$XCODE_ROOT/Platforms/AppleTVSimulator.platform/Developer
WATCHOSSYSROOT=$XCODE_ROOT/Platforms/WatchOS.platform/Developer
WATCHOSSIMSYSROOT=$XCODE_ROOT/Platforms/WatchSimulator.platform/Developer

# Include python library 'python' in LIBS_TO_BUILD_ALL
LIBS_TO_BUILD_ALL="atomic,chrono,container,context,contract,coroutine,date_time,exception,fiber,filesystem,graph,iostreams,json,locale,log,math,nowide,program_options,python,random,regex,serialization,stacktrace,system,test,thread,timer,type_erasure,wave,url,cobalt,charconv"

BUILD_PLATFORMS_ALL="macosx,macosx-arm64,macosx-x86_64,macosx-both,ios,iossim,iossim-arm64,iossim-x86_64,iossim-both,catalyst,catalyst-arm64,catalyst-x86_64,catalyst-both,xros,xrossim,xrossim-arm64,xrossim-x86_64,xrossim-both,tvos,tvossim,tvossim-both,tvossim-arm64,tvossim-x86_64,watchos,watchossim,watchossim-both,watchossim-arm64,watchossim-x86_64"
BOOST_NAME=boost_${BOOST_VER//./_}
BUILD_DIR="$( cd "$( dirname "./" )" >/dev/null 2>&1 && pwd )"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

[[ $(clang++ --version | head -1 | sed -E 's/([a-zA-Z ]+)([0-9]+).*/\2/') -gt 14 ]] && CLANG15=true

LIBS_TO_BUILD=$LIBS_TO_BUILD_ALL
[[ ! $CLANG15 ]] && LIBS_TO_BUILD="${LIBS_TO_BUILD/,cobalt/}"

######################################################################
# Default platforms (unmodified from original).
# We'll still parse --platforms=, but for iOS-only usage, you can pass -p=ios.
######################################################################
BUILD_PLATFORMS="macosx,ios,iossim,catalyst"
[[ -d $XROSSYSROOT/SDKs/XROS.sdk ]] && BUILD_PLATFORMS="$BUILD_PLATFORMS,xros"
[[ -d $XROSSIMSYSROOT/SDKs/XRSimulator.sdk ]] && BUILD_PLATFORMS="$BUILD_PLATFORMS,xrossim"
[[ -d $TVOSSYSROOT/SDKs/AppleTVOS.sdk ]] && BUILD_PLATFORMS="$BUILD_PLATFORMS,tvos"
[[ -d $TVOSSIMSYSROOT/SDKs/AppleTVSimulator.sdk ]] && BUILD_PLATFORMS="$BUILD_PLATFORMS,tvossim"
[[ -d $WATCHOSSYSROOT/SDKs/WatchOS.sdk ]] && BUILD_PLATFORMS="$BUILD_PLATFORMS,watchos"
[[ -d $WATCHOSSIMSYSROOT/SDKs/WatchSimulator.sdk ]] && BUILD_PLATFORMS="$BUILD_PLATFORMS,watchossim-both"

######################################################################
# Additional options for Python embedding:
#   --python-include <path>
#   --python-lib <path>
######################################################################
PYTHON_INC_DIR=""
PYTHON_LIB_FILE=""
PYTHON_LIB_BASENAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --python-include)
      PYTHON_INC_DIR="$2"
      shift 2
      ;;
    --python-include=*)
      PYTHON_INC_DIR="${1#*=}"
      shift 1
      ;;
    --python-lib)
      PYTHON_LIB_FILE="$2"
      shift 2
      ;;
    --python-lib=*)
      PYTHON_LIB_FILE="${1#*=}"
      shift 1
      ;;
    -l=*|--libs=*)
      LIBS_TO_BUILD="${1#*=}"
      shift # past argument=value
      ;;
    -p=*|--platforms=*)
      BUILD_PLATFORMS="${1#*=},"
      shift # past argument=value
      ;;
    --rebuild)
      REBUILD=true
      [[ -f "$BUILD_DIR/frameworks.built.platforms" ]] && rm "$BUILD_DIR/frameworks.built.platforms"
      [[ -f "$BUILD_DIR/frameworks.built.libs" ]] && rm "$BUILD_DIR/frameworks.built.libs"
      shift # past argument with no value
      ;;
    --rebuildicu)
      [[ -d $SCRIPT_DIR/Pods/icu4c-iosx ]] && rm -rf $SCRIPT_DIR/Pods/icu4c-iosx
      shift # past argument with no value
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      shift
      ;;
  esac
done

LIBS_TO_BUILD=${LIBS_TO_BUILD//,/ }
LIBS_TO_BUILD_ARRAY=($LIBS_TO_BUILD)
IFS=$'\n' LIBS_TO_BUILD_SORTED_ARRAY=($(sort <<<"${LIBS_TO_BUILD_ARRAY[*]}")); unset IFS
LIBS_TO_BUILD_SORTED="${LIBS_TO_BUILD_SORTED_ARRAY[@]}"

######################################################################
# If building python, parse library basename for -lpython
######################################################################
if [[ " $LIBS_TO_BUILD " == *" python "* ]] && [[ -n "$PYTHON_LIB_FILE" ]]; then
    pbase=$(basename "$PYTHON_LIB_FILE")        # e.g. libpython3.11.a
    pbase="${pbase#lib}"                        # remove 'lib'
    PYTHON_LIB_BASENAME="${pbase%.a}"           # remove '.a'
    echo "[INFO] Python include: $PYTHON_INC_DIR"
    echo "[INFO] Python library: $PYTHON_LIB_FILE (basename: $PYTHON_LIB_BASENAME)"
fi

######################################################################
# Validate LIBS to build
######################################################################
for i in $LIBS_TO_BUILD; do
  if [[ ! ",$LIBS_TO_BUILD_ALL," == *",$i,"* ]]; then
    echo "Unknown library '$i'"
    exit 1
  fi
done

[[ $BUILD_PLATFORMS == *macosx-both* ]] && BUILD_PLATFORMS="${BUILD_PLATFORMS//macosx-both/},macosx-arm64,macosx-x86_64"
[[ $BUILD_PLATFORMS == *iossim-both* ]] && BUILD_PLATFORMS="${BUILD_PLATFORMS//iossim-both/},iossim-arm64,iossim-x86_64"
[[ $BUILD_PLATFORMS == *catalyst-both* ]] && BUILD_PLATFORMS="${BUILD_PLATFORMS//catalyst-both/},catalyst-arm64,catalyst-x86_64"
[[ $BUILD_PLATFORMS == *xrossim-both* ]] && BUILD_PLATFORMS="${BUILD_PLATFORMS//xrossim-both/},xrossim-arm64,xrossim-x86_64"
[[ $BUILD_PLATFORMS == *tvossim-both* ]] && BUILD_PLATFORMS="${BUILD_PLATFORMS//tvossim-both/},tvossim-arm64,tvossim-x86_64"
[[ $BUILD_PLATFORMS == *watchossim-both* ]] && BUILD_PLATFORMS="${BUILD_PLATFORMS//watchossim-both/},watchossim-arm64,watchossim-x86_64"
BUILD_PLATFORMS="$BUILD_PLATFORMS,"
[[ $BUILD_PLATFORMS == *"macosx,"* ]] && BUILD_PLATFORMS="${BUILD_PLATFORMS//macosx,/,},macosx-$HOST_ARC"
[[ $BUILD_PLATFORMS == *"iossim,"* ]] && BUILD_PLATFORMS="${BUILD_PLATFORMS//iossim,/,},iossim-$HOST_ARC"
[[ $BUILD_PLATFORMS == *"catalyst,"* ]] && BUILD_PLATFORMS="${BUILD_PLATFORMS//catalyst,/,},catalyst-$HOST_ARC"
[[ $BUILD_PLATFORMS == *"xrossim,"* ]] && BUILD_PLATFORMS="${BUILD_PLATFORMS//xrossim,/,},xrossim-$HOST_ARC"
[[ $BUILD_PLATFORMS == *"tvossim,"* ]] && BUILD_PLATFORMS="${BUILD_PLATFORMS//tvossim,/,},tvossim-$HOST_ARC"
[[ $BUILD_PLATFORMS == *"watchossim,"* ]] && BUILD_PLATFORMS="${BUILD_PLATFORMS//watchossim,/,},watchossim-$HOST_ARC"

if [[ $BUILD_PLATFORMS == *"xros,"* ]] && [[ ! -d $XROSSYSROOT/SDKs/XROS.sdk ]]; then
    echo "The xros is specified as the build platform, but XROS.sdk is not found (the path $XROSSYSROOT/SDKs/XROS.sdk)."
    exit 1
fi

if [[ $BUILD_PLATFORMS == *"xrossim"* ]] && [[ ! -d $XROSSIMSYSROOT/SDKs/XRSimulator.sdk ]]; then
    echo "The xrossim is specified as the build platform, but XRSimulator.sdk is not found (the path $XROSSIMSYSROOT/SDKs/XRSimulator.sdk)."
    exit 1
fi

if [[ $BUILD_PLATFORMS == *"tvos,"* ]] && [[ ! -d $TVOSSYSROOT/SDKs/AppleTVOS.sdk ]]; then
    echo "The tvos is specified as the build platform, but AppleTVOS.sdk is not found (the path $TVOSSYSROOT/SDKs/AppleTVOS.sdk)."
    exit 1
fi

if [[ $BUILD_PLATFORMS == *"tvossim"* ]] && [[ ! -d $TVOSSIMSYSROOT/SDKs/AppleTVSimulator.sdk ]]; then
    echo "The tvossim is specified as the build platform, but AppleTVSimulator.sdk is not found (the path $TVOSSIMSYSROOT/SDKs/AppleTVSimulator.sdk)."
    exit 1
fi

if [[ $BUILD_PLATFORMS == *"watchos,"* ]] && [[ ! -d $WATCHOSSYSROOT/SDKs/WatchOS.sdk ]]; then
    echo "The watchos is specified as the build platform, but WatchOS.sdk is not found (the path $WATCHOSSYSROOT/SDKs/WatchOS.sdk)."
    exit 1
fi

if [[ $BUILD_PLATFORMS == *"watchossim"* ]] && [[ ! -d $WATCHOSSIMSYSROOT/SDKs/WatchSimulator.sdk ]]; then
    echo "The watchossim is specified as the build platform, but WatchSimulator.sdk is not found (the path $WATCHOSSIMSYSROOT/SDKs/WatchSimulator.sdk)."
    exit 1
fi

BUILD_PLATFORMS_SPACED=" ${BUILD_PLATFORMS//,/ } "
BUILD_PLATFORMS_ARRAY=($BUILD_PLATFORMS_SPACED)

for i in $BUILD_PLATFORMS_SPACED; do
  if [[ ! ",${BUILD_PLATFORMS_ALL}," == *",$i,"* ]]; then
    echo "Unknown platform '$i'"
    exit 1
  fi
done

[[ -f "$BUILD_DIR/frameworks.built.platforms" ]] && [[ -f "$BUILD_DIR/frameworks.built.libs" ]] && \
[[ $(< "$BUILD_DIR/frameworks.built.platforms") == "$BUILD_PLATFORMS" ]] && [[ $(< "$BUILD_DIR/frameworks.built.libs") == "$LIBS_TO_BUILD" ]] && exit 0

[[ -f "$BUILD_DIR/frameworks.built.platforms" ]] && rm "$BUILD_DIR/frameworks.built.platforms"
[[ -f "$BUILD_DIR/frameworks.built.libs" ]] && rm "$BUILD_DIR/frameworks.built.libs"

BOOST_ARCHIVE_FILE=$BOOST_NAME.tar.bz2

if [[ -f $BOOST_ARCHIVE_FILE ]]; then
  FILE_HASH=$(shasum -a 256 "$BOOST_ARCHIVE_FILE" | awk '{ print $1 }')
  if [[ ! "$FILE_HASH" == "$EXPECTED_HASH" ]]; then
      echo "Wrong archive hash, trying to reload the archive"
      rm "$BOOST_ARCHIVE_FILE"
  fi
fi

if [[ ! -f $BOOST_ARCHIVE_FILE ]]; then
  TEMP_LOCATIONS_FILE=$(mktemp)
  curl -s -o "$TEMP_LOCATIONS_FILE" "$LOCATIONS_FILE_URL"
  if [[ $? -ne 0 ]]; then
      echo "Failed to download the LOCATIONS file."
      exit 1
  fi
  while IFS= read -r linktemplate; do
    linktemplate=${linktemplate/DOTVERSION/"$BOOST_VER"}
    link=${linktemplate/FILENAME/"$BOOST_ARCHIVE_FILE"}
    echo "downloading from $link ..."

    curl -o "$BOOST_ARCHIVE_FILE" -L "$link"

    # Check if the download was successful
    if [ $? -eq 0 ]; then
        FILE_HASH=$(shasum -a 256 "$BOOST_ARCHIVE_FILE" | awk '{ print $1 }')
        if [[ "$FILE_HASH" == "$EXPECTED_HASH" ]]; then
          [[ -d boost ]] && rm -rf boost
          break
        else
          echo "Wrong archive hash $FILE_HASH, expected $EXPECTED_HASH. Trying next link to reload the archive."
          rm $BOOST_ARCHIVE_FILE
        fi
    fi
  done < "$TEMP_LOCATIONS_FILE"
  rm "$TEMP_LOCATIONS_FILE"
fi

if [[ ! -f $BOOST_ARCHIVE_FILE ]]; then
  echo "Failed to download the Boost."
  exit 1
fi

if [[ ! -d boost ]]; then
  echo "extracting $BOOST_ARCHIVE_FILE ..."
  tar -xf $BOOST_ARCHIVE_FILE
  mv $BOOST_NAME boost
fi

if [[ ! -f boost/b2 ]]; then
  pushd boost
  ./bootstrap.sh
  popd
fi

######################################################################
# ICU block (unchanged from original)  (libffi or libssl are not explicitly required by Boost.Python)
######################################################################
# If your environment needs ICU, it will be built as before, omitted here for brevity.
# ...

pushd boost

echo "patching boost..."

if [[ ! -f tools/build/src/tools/features/instruction-set-feature.jam.orig ]]; then
  cp -f tools/build/src/tools/features/instruction-set-feature.jam tools/build/src/tools/features/instruction-set-feature.jam.orig
else
  cp -f tools/build/src/tools/features/instruction-set-feature.jam.orig tools/build/src/tools/features/instruction-set-feature.jam
fi

# If you have a patch file, apply it:
# patch tools/build/src/tools/features/instruction-set-feature.jam $SCRIPT_DIR/instruction-set-feature.jam.patch || true

B2_BUILD_OPTIONS="-j$THREAD_COUNT address-model=64 release link=static runtime-link=shared define=BOOST_SPIRIT_THREADSAFE cxxflags=\"-std=c++20\""

# If Python is included, define macros for static link, add -I, -L, and -l.
if [[ " $LIBS_TO_BUILD " == *" python "* ]] && [[ -n "$PYTHON_INC_DIR" ]] && [[ -n "$PYTHON_LIB_BASENAME" ]]; then
  B2_BUILD_OPTIONS="$B2_BUILD_OPTIONS define=BOOST_PYTHON_STATIC_LIB define=Py_NO_ENABLE_SHARED"
  B2_BUILD_OPTIONS="$B2_BUILD_OPTIONS cxxflags=\"-I$PYTHON_INC_DIR\" linkflags=\"-L$(dirname \"$PYTHON_LIB_FILE\") -l$PYTHON_LIB_BASENAME\""
fi

for i in $LIBS_TO_BUILD; do
  B2_BUILD_OPTIONS="$B2_BUILD_OPTIONS --with-$i"
done

[[ -d bin.v2 ]] && rm -rf bin.v2

######################################################################
# Helper functions from original script
######################################################################
function boost_arc()
{
    if [[ $1 == arm* ]]; then
      echo "arm"
    elif [[ $1 == x86* ]]; then
      echo "x86"
    else
      echo "unknown"
    fi
}

function boost_abi()
{
    if [[ $1 == arm64 ]]; then
      echo "aapcs"
    elif [[ $1 == x86_64 ]]; then
      echo "sysv"
    else
      echo "unknown"
    fi
}

function is_subset()
{
    local mainset=($(< $1))
    shift
    local subset=("$@")

    for element in "${subset[@]}"; do
        if [[ ! " ${mainset[@]} " =~ " ${element} " ]]; then
            echo "false"
            return
        fi
    done
    echo "true"
}

function build_generic_libs()
{
  # Args: (platform=$1, architecture=$2, additional_flags=$3, root=$4, depfilter=$5, additional_config=$6, additional_b2flags=$7)
  if [[ $REBUILD == true ]] || [[ ! -f $1-$2-build.success ]] || [[ $(is_subset $1-$2-build.success "${LIBS_TO_BUILD_ARRAY[@]}") == "false" ]]; then

      [[ -f $1-$2-build.success ]] && rm $1-$2-build.success

      [[ -f tools/build/src/user-config.jam ]] && rm -f tools/build/src/user-config.jam

      cat >> tools/build/src/user-config.jam <<EOF
using darwin : $1 : clang++ -arch $2 $3
    : <striper> <root>$4
    ;
EOF

      ./b2 -j8 --stagedir=stage/$1-$2 \
        toolset=darwin-$1 \
         \
        abi=$(boost_abi $2) \
        $7 $B2_BUILD_OPTIONS

      rm -rf bin.v2
      printf "$LIBS_TO_BUILD_SORTED" > $1-$2-build.success
  fi


      # If python is among the libs, ensure 'using python' is in user-config.jam so that boost_python gets built.
      # This sets the python version, the python executable path (dummy), the include dir, and library dir.
      if [[ " $LIBS_TO_BUILD " == *" python "* ]] && [[ -n "$PYTHON_INC_DIR" ]] && [[ -n "$PYTHON_LIB_FILE" ]]; then
        cat >> tools/build/src/user-config.jam <<EOF
using python : 3.11 : /usr/bin/env : $PYTHON_INC_DIR : $(dirname \"$PYTHON_LIB_FILE\") ;
EOF
      fi
}

function build_macos_libs()
{
    build_generic_libs macosx $1 "$2 -isysroot $MACSYSROOT/SDKs/MacOSX.sdk" $MACSYSROOT "macos-*"
}

function build_catalyst_libs()
{
    build_generic_libs catalyst $1 "--target=$1-apple-ios$CATALYST_VERSION-macabi -isysroot $MACSYSROOT/SDKs/MacOSX.sdk -I$MACSYSROOT/SDKs/MacOSX.sdk/System/iOSSupport/usr/include/ -isystem $MACSYSROOT/SDKs/MacOSX.sdk/System/iOSSupport/usr/include -iframework $MACSYSROOT/SDKs/MacOSX.sdk/System/iOSSupport/System/Library/Frameworks" $MACSYSROOT "ios-*-maccatalyst"
}

function build_ios_libs()
{
    build_generic_libs ios arm64 "-isysroot $IOSSYSROOT/SDKs/iPhoneOS.sdk -mios-version-min=$IOS_VERSION" $IOSSYSROOT "ios-arm64" "<target-os>iphone" "binary-format=mach-o target-os=iphone define=_LITTLE_ENDIAN define=BOOST_TEST_NO_MAIN"
}

function build_xros_libs()
{
    build_generic_libs xros arm64 "-isysroot $XROSSYSROOT/SDKs/XROS.sdk" $XROSSYSROOT "xros-arm64" "<target-os>iphone" "binary-format=mach-o target-os=iphone define=_LITTLE_ENDIAN define=BOOST_TEST_NO_MAIN"
}

function build_tvos_libs()
{
    build_generic_libs tvos arm64 "-isysroot $TVOSSYSROOT/SDKs/AppleTVOS.sdk" $TVOSSYSROOT "tvos-arm64" "<target-os>iphone" "binary-format=mach-o target-os=iphone define=_LITTLE_ENDIAN define=BOOST_TEST_NO_MAIN define=BOOST_TEST_DISABLE_ALT_STACK"
}

function build_watchos_libs()
{
    build_generic_libs watchos arm64 "-isysroot $WATCHOSSYSROOT/SDKs/WatchOS.sdk" $WATCHOSSYSROOT "watchos-arm64" "<target-os>iphone" "binary-format=mach-o target-os=iphone define=_LITTLE_ENDIAN define=BOOST_TEST_NO_MAIN define=BOOST_TEST_DISABLE_ALT_STACK"
}

function build_sim_libs()
{
    build_generic_libs iossim $1 "-mios-simulator-version-min=$IOS_SIM_VERSION -isysroot $IOSSIMSYSROOT/SDKs/iPhoneSimulator.sdk" $IOSSIMSYSROOT "ios-*-simulator" "<target-os>iphone" "target-os=iphone define=BOOST_TEST_NO_MAIN"
}

function build_xrossim_libs()
{
    build_generic_libs xrossim $1 "$2 -isysroot $XROSSIMSYSROOT/SDKs/XRSimulator.sdk" $XROSSIMSYSROOT "xros-*-simulator" "<target-os>iphone" "target-os=iphone define=BOOST_TEST_NO_MAIN"
}

function build_tvossim_libs()
{
    build_generic_libs tvossim $1 " --target=$1-apple-tvos$TVOS_SIM_VERSION-simulator -isysroot $TVOSSIMSYSROOT/SDKs/AppleTVSimulator.sdk" $TVOSSIMSYSROOT "tvos-*-simulator" "<target-os>iphone" "target-os=iphone define=BOOST_TEST_NO_MAIN define=BOOST_TEST_DISABLE_ALT_STACK"
}

function build_watchossim_libs()
{
    build_generic_libs watchossim $1 "--target=$1-apple-watchos$WATCHOSSIM_VERSION-simulator -isysroot $WATCHOSSIMSYSROOT/SDKs/WatchSimulator.sdk" $WATCHOSSIMSYSROOT "watchos-*-simulator" "<target-os>iphone" "target-os=iphone define=BOOST_TEST_NO_MAIN define=BOOST_TEST_DISABLE_ALT_STACK"
}

[[ -d stage/macosx/lib ]] && rm -rf stage/macosx/lib
[[ "$BUILD_PLATFORMS_SPACED" == *"macosx-arm64"* ]] && build_macos_libs arm64 -mmacosx-version-min=$MACOSX_VERSION_ARM
[[ "$BUILD_PLATFORMS_SPACED" == *"macosx-x86_64"* ]] && build_macos_libs x86_64 -mmacosx-version-min=$MACOSX_VERSION_X86_64
[[ "$BUILD_PLATFORMS_SPACED" == *"macosx"* ]] && mkdir -p stage/macosx/lib

[ -d stage/catalyst/lib ] && rm -rf stage/catalyst/lib
[[ "$BUILD_PLATFORMS_SPACED" == *"catalyst-arm64"* ]] && build_catalyst_libs arm64
[[ "$BUILD_PLATFORMS_SPACED" == *"catalyst-x86_64"* ]] && build_catalyst_libs x86_64
[[ "$BUILD_PLATFORMS_SPACED" == *"catalyst"* ]] && mkdir -p stage/catalyst/lib

[ -d stage/iossim/lib ] && rm -rf stage/iossim/lib
[[ "$BUILD_PLATFORMS_SPACED" == *"iossim-arm64"* ]] && build_sim_libs arm64
[[ "$BUILD_PLATFORMS_SPACED" == *"iossim-x86_64"* ]] && build_sim_libs x86_64
[[ "$BUILD_PLATFORMS_SPACED" == *"iossim"* ]] && mkdir -p stage/iossim/lib

[ -d stage/xrossim/lib ] && rm -rf stage/xrossim/lib
[[ "$BUILD_PLATFORMS_SPACED" == *"xrossim-arm64"* ]] && build_xrossim_libs arm64
[[ "$BUILD_PLATFORMS_SPACED" == *"xrossim-x86_64"* ]] && build_xrossim_libs x86_64
[[ "$BUILD_PLATFORMS_SPACED" == *"xrossim"* ]] && mkdir -p stage/xrossim/lib

[ -d stage/tvossim/lib ] && rm -rf stage/tvossim/lib
[[ "$BUILD_PLATFORMS_SPACED" == *"tvossim-arm64"* ]] && build_tvossim_libs arm64
[[ "$BUILD_PLATFORMS_SPACED" == *"tvossim-x86_64"* ]] && build_tvossim_libs x86_64
[[ "$BUILD_PLATFORMS_SPACED" == *"tvossim"* ]] && mkdir -p stage/tvossim/lib

[ -d stage/watchossim/lib ] && rm -rf stage/watchossim/lib
[[ "$BUILD_PLATFORMS_SPACED" == *"watchossim-arm64"* ]] && build_watchossim_libs arm64
[[ "$BUILD_PLATFORMS_SPACED" == *"watchossim-x86_64"* ]] && build_watchossim_libs x86_64
[[ "$BUILD_PLATFORMS_SPACED" == *"watchossim"* ]] && mkdir -p stage/watchossim/lib

[[ "$BUILD_PLATFORMS_SPACED" == *"ios "* ]] && build_ios_libs
[[ "$BUILD_PLATFORMS_SPACED" == *"xros "* ]] && build_xros_libs
[[ "$BUILD_PLATFORMS_SPACED" == *"tvos "* ]] && build_tvos_libs
[[ "$BUILD_PLATFORMS_SPACED" == *"watchos "* ]] && build_watchos_libs

echo "installing boost..."
[[ -d "$BUILD_DIR/frameworks" ]] && rm -rf "$BUILD_DIR/frameworks"
mkdir "$BUILD_DIR/frameworks"

function build_lib()
{
  if [[ "$BUILD_PLATFORMS_SPACED" == *"$2-arm64"* ]]; then
    if [[ "$BUILD_PLATFORMS_SPACED" == *"$2-x86_64"* ]]; then
      lipo -create stage/$2-arm64/lib/lib$1.a stage/$2-x86_64/lib/lib$1.a -output stage/$2/lib/lib$1.a
      LIBARGS="$LIBARGS -library stage/$2/lib/lib$1.a"
    else
      LIBARGS="$LIBARGS -library stage/$2-arm64/lib/lib$1.a"
    fi
  else
    [[ "$BUILD_PLATFORMS_SPACED" == *"$2-x86_64"* ]] && LIBARGS="$LIBARGS -library stage/$2-x86_64/lib/lib$1.a"
  fi
}

function build_xcframework()
{
  LIBARGS=""
  [[ "$BUILD_PLATFORMS_SPACED" == *macosx* ]] && build_lib $1 macosx
  [[ "$BUILD_PLATFORMS_SPACED" == *catalyst* ]] && build_lib $1 catalyst
  [[ "$BUILD_PLATFORMS_SPACED" == *iossim* ]] && build_lib $1 iossim
  [[ "$BUILD_PLATFORMS_SPACED" == *xrossim* ]] && build_lib $1 xrossim
  [[ "$BUILD_PLATFORMS_SPACED" == *tvossim* ]] && build_lib $1 tvossim
  [[ "$BUILD_PLATFORMS_SPACED" == *watchossim* ]] && build_lib $1 watchossim
  [[ "$BUILD_PLATFORMS_SPACED" == *"ios "* ]] && LIBARGS="$LIBARGS -library stage/ios-arm64/lib/lib$1.a"
  [[ "$BUILD_PLATFORMS_SPACED" == *"xros "* ]] && LIBARGS="$LIBARGS -library stage/xros-arm64/lib/lib$1.a"
  [[ "$BUILD_PLATFORMS_SPACED" == *"tvos "* ]] && LIBARGS="$LIBARGS -library stage/tvos-arm64/lib/lib$1.a"
  [[ "$BUILD_PLATFORMS_SPACED" == *"watchos "* ]] && LIBARGS="$LIBARGS -library stage/watchos-arm64/lib/lib$1.a"
  xcodebuild -create-xcframework $LIBARGS -output "$BUILD_DIR/frameworks/$1.xcframework"
}

if true; then
  for i in $LIBS_TO_BUILD; do
    if [ "$i" == "math" ]; then
      build_xcframework boost_math_c99
      build_xcframework boost_math_c99l
      build_xcframework boost_math_c99f
      build_xcframework boost_math_tr1
      build_xcframework boost_math_tr1l
      build_xcframework boost_math_tr1f
    elif [ "$i" == "log" ]; then
      build_xcframework boost_log
      build_xcframework boost_log_setup
    elif [ "$i" == "stacktrace" ]; then
      build_xcframework boost_stacktrace_basic
      build_xcframework boost_stacktrace_noop
    elif [ "$i" == "serialization" ]; then
      build_xcframework boost_serialization
      build_xcframework boost_wserialization
    elif [ "$i" == "test" ]; then
      build_xcframework boost_prg_exec_monitor
      build_xcframework boost_test_exec_monitor
      build_xcframework boost_unit_test_framework
    elif [ "$i" == "python" ]; then
      build_xcframework "boost_python311"
    else
      build_xcframework "boost_$i"
    fi
  done

  mkdir "$BUILD_DIR/frameworks/Headers"
  cp -R boost "$BUILD_DIR/frameworks/Headers/"
fi

printf "$BUILD_PLATFORMS" > "$BUILD_DIR/frameworks.built.platforms"
printf "$LIBS_TO_BUILD" > "$BUILD_DIR/frameworks.built.libs"

# Restore logic to create Xcode workspace via CocoaPods
# (If the original project had a Podfile referencing these frameworks.)
# Make sure there's a valid Podfile in $SCRIPT_DIR, or adapt as needed.

pushd "$SCRIPT_DIR"
if [ -f "Podfile" ]; then
  echo "Creating/Updating Xcode workspace via CocoaPods..."
  pod repo update || true
  pod install --verbose
  echo "[INFO] .xcworkspace has been created/updated."
fi
popd

popd
