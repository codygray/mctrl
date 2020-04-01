#!/bin/sh
#
# Helper script to make release packages:
#  - mCtrl-$VERSION-src.zip
#  - mCtrl-$VERSION-bin.zip
#
# All packages are put in current directory (and overwritten if exist already).
#
# The script has to be run from MSYS (or cygwin) environment.
# Additionally the following stuff has to be installed on the machine:
#  - CMake 3.14 or newer.
#       - "cmake" has to be in $PATH
#  - gcc-based multitarget toolchain:
#       - Must be capable to target both 32-bit (-m32) and 64-bit (-m64) Windows
#       - 32-bit mingw-builds from mingw-w64 project provides this feature
#  - MS Visual Studio 2017 or 2019 (as well as MSBuild tool)
#       - Must be in the default location.
#       - Optional components for build ARM64 binaries have to be installed.
#  - Doxygen
#       - "doxygen" has to be in $PATH
#  - Zip utility (zip or 7zip should work)
#       - "zip", "7za" or "7z" has to be in $PATH



# We want to control what's going to stdout/err.
exec 3>&1
exec 1>/dev/null 2>&1

# Change dir to project root.
cd `dirname "$0"`/..

CWD=`pwd`
PRJ="$CWD"

# Sanity check we run this script from the right directory:
if [ ! -x $PRJ/scripts/release.sh ]; then
    echo "There is some path mismatch." >&3
    exit 1
fi

# We will do all the real work in $TMP directory:
if [ x$TMP = x ]; then
    TMP=/tmp
fi
if [ ! -d $TMP ]; then
    echo "Directory '$TMP' does not exist." >&3
    exit 1
fi


##################
# Detect version #
##################

echo -n "Detecting mCtrl version... " >&3
VERSION_MAJOR=`grep MCTRL_MAJOR_VERSION CMakeLists.txt | head -1 | sed 's/[^0-9]//g'`
VERSION_MINOR=`grep MCTRL_MINOR_VERSION CMakeLists.txt | head -1 | sed 's/[^0-9]//g'`
VERSION_PATCH=`grep MCTRL_PATCH_VERSION CMakeLists.txt | head -1 | sed 's/[^0-9]//g'`
VERSION=$VERSION_MAJOR.$VERSION_MINOR.$VERSION_PATCH
if [ x$VERSION = x ]; then
    echo "Failed." >&3
    exit 1
fi
echo "$VERSION" >&3


#####################
# Detect a zip tool #
#####################

echo -n "Detecting zip archiver... " >&3
if which 7za; then
    MKZIP="7za a -r -mx9"
elif which 7z; then
    MKZIP="7z a -r -mx9"
elif which zip; then
    MKZIP="zip -r"
else
    echo "Not found." >&3
    exit 1
fi
echo "$MKZIP" >&3


#########################################
# Detect build tool for gcc (mingw-w64) #
#########################################

echo -n "Detected gcc build tool... " >&3
if which ninja; then
    CMAKE_GENERATOR_GCC="Ninja"
    BUILD_GCC="ninja -v"
elif which make; then
    CMAKE_GENERATOR_GCC="MSYS Makefiles"
    BUILD_GCC="make VERBOSE=1"
else
    echo "Not found." >&3
    exit 1
fi
echo "$BUILD_GCC" >&3


########################
# Detect Visual Studio #
########################

echo -n "Detecting MSVC... " >&3

MSVC_2017_BUILDER="Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\MSBuild.exe"
MSVC_2017_GENERATOR="Visual Studio 15 2017"

MSVC_2019_BUILDER="Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe"
MSVC_2019_GENERATOR="Visual Studio 16 2019"

MSVC_LIST="2019 2017"

for msvc in $MSVC_LIST; do
    MSVC_NAME="MSVC ${msvc}"
    eval msvc_builder=$`echo MSVC_${msvc}_BUILDER`
    eval msvc_generator=$`echo MSVC_${msvc}_GENERATOR`

    while read progfiles; do
        if [ -e "${progfiles}/${msvc_builder}" ]; then
            BUILD_MSVC="${progfiles}/${msvc_builder}"
            CMAKE_GENERATOR_MSVC="$msvc_generator"
            break 2
        fi
    done <<EOF
/c/Program Files
/c/Program Files (x86)
EOF
done

if [ -n "$BUILD_MSVC" ]; then
    echo "$MSVC_NAME" >&3
else
    echo "Not found." >&3
    exit 1
fi


############################
# Prepare clean playground #
############################

rm -rf $TMP/mCtrl-$VERSION
git clone . $TMP/mCtrl-$VERSION


##################
# Build with gcc #
##################

function build_gcc()
{
    ARCH=$1
    CONFIG=$2

    echo -n "Build with gcc $ARCH $CONFIG... " >&3
    if [ "$ARCH" = "x86_64" ]; then
        CFLAGS="-m64"
        LDFLAGS="-m64"
        RCFLAGS="--target=pe-x86-64"
        DLLFLAGS="-m;i386:x86-64;-f;--64"
    else
        CFLAGS="-m32"
        LDFLAGS="-m32"
        RCFLAGS="--target=pe-i386"
        DLLFLAGS="-m;i386;-f;--32"
    fi

    BUILDDIR="./build-gcc-$ARCH-$CONFIG"
    mkdir -p "$BUILDDIR"
    (cd "$BUILDDIR"  && \
     cmake -D CMAKE_BUILD_TYPE="$CONFIG" \
           -D CMAKE_C_FLAGS="$CFLAGS" \
           -D CMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
           -D CMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
           -D CMAKE_RC_FLAGS="$RCFLAGS" \
           -D DLLTOOL_FLAGS="$DLLFLAGS" \
           -G "$CMAKE_GENERATOR_GCC" ..  && \
     $BUILD_GCC) > "$PRJ/build-gcc-$ARCH-$CONFIG.log" 2>&1
    if [ $? -eq 0 ]; then
        echo "Done." >&3
    else
        echo "Failed. See $PRJ/build-gcc-$ARCH-$CONFIG.log for more info." >&3
    fi
}

(cd $TMP/mCtrl-$VERSION  && \
 build_gcc x86_64 Release  && \
 build_gcc x86_64 Debug  && \
 build_gcc x86 Release  && \
 build_gcc x86 Debug)


###################
# Build with MSVC #
###################

function build_msvc()
{
    ARCH=$1
    CONFIG=$2

    echo -n "Build with MSVC $ARCH... " >&3
    BUILDDIR="./build-msvc-$ARCH"
    mkdir -p "$BUILDDIR"
    (cd "$BUILDDIR"  && \
     cmake -G "$CMAKE_GENERATOR_MSVC" -A "$ARCH" ..  && \
     "$BUILD_MSVC" "/property:Configuration=$CONFIG" mCtrl.sln) > "$PRJ/build-msvc-$ARCH-$CONFIG.log" 2>&1
    if [ $? -eq 0 ]; then
        echo "Done." >&3
    else
        echo "Failed. See $PRJ/build-msvc-$ARCH-$CONFIG.log for more info." >&3
    fi
}

(cd $TMP/mCtrl-$VERSION  && \
 build_msvc x64 Release && \
 build_msvc x64 Debug && \
 build_msvc Win32 Release && \
 build_msvc Win32 Debug && \
 build_msvc ARM64 Release && \
 build_msvc ARM64 Debug)


##########################
# Generate documentation #
##########################

echo -n "Generate documentation... " >&3
if `which doxygen`; then
    (cd $TMP/mCtrl-$VERSION && ( cat Doxyfile ; echo "PROJECT_NUMBER=$VERSION" ) | doxygen -) > $PRJ/build-doc.log 2>&1
    if [ $? -ne 0 ]; then
        echo "Failed: See build-doc.log."
        exit 1
    fi
    HAVE_DOC=yes
    echo "Done." >&3
else
    echo "Skipped: doxygen not found in PATH." >&3
fi


###############################
# Make mCtrl-$VERSION-bin.zip #
###############################

echo -n "Packing binary package... " >&3
rm -rf $TMP/mCtrl-$VERSION-src
mv $TMP/mCtrl-$VERSION $TMP/mCtrl-$VERSION-src
mkdir $TMP/mCtrl-$VERSION

# x86_64 Release
mkdir -p $TMP/mCtrl-$VERSION/bin64
cp $TMP/mCtrl-$VERSION-src/build-gcc-x86_64-Release/mCtrl.dll $TMP/mCtrl-$VERSION/bin64/
cp $TMP/mCtrl-$VERSION-src/build-gcc-x86_64-Release/example-*.exe $TMP/mCtrl-$VERSION/bin64/
cp $TMP/mCtrl-$VERSION-src/build-gcc-x86_64-Release/test-*.exe $TMP/mCtrl-$VERSION/bin64/
mkdir -p $TMP/mCtrl-$VERSION/lib64
cp $TMP/mCtrl-$VERSION-src/build-gcc-x86_64-Release/libmCtrl.dll.a $TMP/mCtrl-$VERSION/lib64/
cp $TMP/mCtrl-$VERSION-src/build-msvc-x64/Release/mCtrl.lib $TMP/mCtrl-$VERSION/lib64/

# x86_64 Debug
mkdir -p $TMP/mCtrl-$VERSION/bin64/debug-gcc
cp $TMP/mCtrl-$VERSION-src/build-gcc-x86_64-Debug/mCtrl.dll $TMP/mCtrl-$VERSION/bin64/debug-gcc/
mkdir -p $TMP/mCtrl-$VERSION/bin64/debug-msvc
cp $TMP/mCtrl-$VERSION-src/build-msvc-x64/Debug/mCtrl.dll $TMP/mCtrl-$VERSION/bin64/debug-msvc/
cp $TMP/mCtrl-$VERSION-src/build-msvc-x64/Debug/mCtrl.pdb $TMP/mCtrl-$VERSION/bin64/debug-msvc/

# x86 Release
mkdir -p $TMP/mCtrl-$VERSION/bin
cp $TMP/mCtrl-$VERSION-src/build-gcc-x86-Release/mCtrl.dll $TMP/mCtrl-$VERSION/bin/
cp $TMP/mCtrl-$VERSION-src/build-gcc-x86-Release/example-*.exe $TMP/mCtrl-$VERSION/bin/
cp $TMP/mCtrl-$VERSION-src/build-gcc-x86-Release/test-*.exe $TMP/mCtrl-$VERSION/bin/
mkdir -p $TMP/mCtrl-$VERSION/lib
cp $TMP/mCtrl-$VERSION-src/build-gcc-x86-Release/libmCtrl.dll.a $TMP/mCtrl-$VERSION/lib/
cp $TMP/mCtrl-$VERSION-src/build-msvc-Win32/Release/mCtrl.lib $TMP/mCtrl-$VERSION/lib/

# x86 Debug
mkdir -p $TMP/mCtrl-$VERSION/bin/debug-gcc
cp $TMP/mCtrl-$VERSION-src/build-gcc-x86-Debug/mCtrl.dll $TMP/mCtrl-$VERSION/bin/debug-gcc/
mkdir -p $TMP/mCtrl-$VERSION/bin/debug-msvc
cp $TMP/mCtrl-$VERSION-src/build-msvc-Win32/Debug/mCtrl.dll $TMP/mCtrl-$VERSION/bin/debug-msvc/
cp $TMP/mCtrl-$VERSION-src/build-msvc-Win32/Debug/mCtrl.pdb $TMP/mCtrl-$VERSION/bin/debug-msvc/

# ARM64 Release
mkdir -p $TMP/mCtrl-$VERSION/bin-arm64
cp $TMP/mCtrl-$VERSION-src/build-msvc-ARM64/Release/mCtrl.dll $TMP/mCtrl-$VERSION/bin-arm64/
cp $TMP/mCtrl-$VERSION-src/build-msvc-ARM64/Release/example-*.exe $TMP/mCtrl-$VERSION/bin-arm64/
cp $TMP/mCtrl-$VERSION-src/build-msvc-ARM64/Release/test-*.exe $TMP/mCtrl-$VERSION/bin-arm64/
mkdir -p $TMP/mCtrl-$VERSION/lib-arm64
cp $TMP/mCtrl-$VERSION-src/build-msvc-ARM64/Release/mCtrl.lib $TMP/mCtrl-$VERSION/lib-arm64/

# ARM64 Debug
mkdir -p $TMP/mCtrl-$VERSION/bin-arm64/debug-msvc
cp $TMP/mCtrl-$VERSION-src/build-msvc-ARM64/Debug/mCtrl.dll $TMP/mCtrl-$VERSION/bin-arm64/debug-msvc/
cp $TMP/mCtrl-$VERSION-src/build-msvc-ARM64/Debug/mCtrl.pdb $TMP/mCtrl-$VERSION/bin-arm64/debug-msvc/

# Some vanilla contents from the source tree
cp -r $TMP/mCtrl-$VERSION-src/doc $TMP/mCtrl-$VERSION/
cp -r $TMP/mCtrl-$VERSION-src/include $TMP/mCtrl-$VERSION/
cp -r $TMP/mCtrl-$VERSION-src/examples $TMP/mCtrl-$VERSION/
cp $TMP/mCtrl-$VERSION-src/AUTHORS.md $TMP/mCtrl-$VERSION/
cp $TMP/mCtrl-$VERSION-src/COPYING.lib.md $TMP/mCtrl-$VERSION/
cp $TMP/mCtrl-$VERSION-src/CONTRIBUTING.md $TMP/mCtrl-$VERSION/
cp $TMP/mCtrl-$VERSION-src/README.md $TMP/mCtrl-$VERSION/
find $TMP/mCtrl-$VERSION -name .git -exec rm -rf {} \;
find $TMP/mCtrl-$VERSION -name .gitignore -exec rm {} \;
$MKZIP mCtrl-$VERSION-bin.zip $TMP/mCtrl-$VERSION
if [ $? -ne 0 ]; then
    echo "Failed." >&3
    exit 1
fi
rm -rf $TMP/mCtrl-$VERSION
echo "Done." >&3


###############################
# Make mCtrl-$VERSION-src.zip #
###############################

echo -n "Packing source package... " >&3
git archive --prefix=mCtrl-$VERSION/ --output=mCtrl-$VERSION-src.zip HEAD
if [ $? -ne 0 ]; then
    echo "Failed." >&3
    exit 1
fi
echo "Done." >&3

