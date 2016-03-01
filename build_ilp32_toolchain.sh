#! /bin/bash
set -e
trap 'previous_command=$this_command; this_command=$BASH_COMMAND' DEBUG
trap 'echo FAILED COMMAND: $previous_command' EXIT

#----------------------------------------------------------------------
# This script is used to build an ilp32 toolchain by downloading the
# required packages and installing the needed dependencies on the
# system then building the toolchain. The process of it is to first
# build an LP64 toolchain that is then capable of producing an ilp32
# toolchain. It is similar to building a cross compiler. For references
# to the process and basis for this script you can go to: 
# http://preshing.com/20141119/how-to-build-a-gcc-cross-compiler

# This script assumes you are running it with sudo.
# Customize the INSTALL_PATH as desired.
#----------------------------------------------------------------------

# Set up the variables
INSTALL_PATH_LP64=/opt/lp64
INSTALL_PATH_ILP32=/opt/ilp32
TARGET_LP64=aarch64-leap-linux-gnu
TARGET_ILP32=aarch64_ilp32-linux-gnu
GCC_CONFIG_LP64="--enable-languages=c,c++,fortran"
GCC_CONFIG_ILP32="${GCC_CONFIG_LP64} --with-multilib-list=ilp32"

GLIBC_COMMON="--disable-multilib --disable-profile --disable-debug \
              --disable-werror --without-gd --enable-shared \
              --enable-static-nss --enable-obsolete-rpc libc_cv_forced_unwind=yes"

GLIBC_CONFIG_LP64="--build=$MACHTYPE --host=${TARGET_LP64} --target=${TARGET_LP64} \
                   --with-headers=${INSTALL_PATH_LP64}/${TARGET_LP64}/include/ \
                   ${GLIBC_COMMON}"

GLIBC_CONFIG_ILP32="--build=$MACHTYPE --host=${TARGET_ILP32} --target=${TARGET_ILP32} \
                    --with-headers=${INSTALL_PATH_ILP32}/${TARGET_ILP32}/include/ \ 
                    ${GLIBC_COMMON}"
PMAKE=-j10

# Build directory prefixes
B_LP64=build-lp64
B_ILP32=build-ilp32

export PATH=${INSTALL_PATH_ILP32}/bin:${INSTALL_PATH_LP64}/bin:$PATH

# Grab the necessary dependencies and tools from the LEAP repo
yum install gcc gcc-c++ bison flex gperf texinfo automake wget

# Create a directory to work in
mkdir -p build-tools
cd build-tools

# Download toolchain sources and untar them
wget http://korea.internal.cdot.systems/ilp32/ilp32.tar.gz
tar -xvf ilp32.tar.gz

# Set up build directories
mkdir ${B_LP64}-{binutils-gdb,gcc,glibc}
mkdir ${B_ILP32}-{binutils-gdb,gcc,glibc}

#--- Start building the LP64 middleman toolchain ---#

# Step 1. Build binutils-gdb and install them
cd ${B_LP64}-binutils-gdb
../binutils-gdb/configure --prefix=$INSTALL_PATH_LP64 --target=$TARGET_LP64
make $PMAKE
make install
cd ..

# Step 2. Install the kernel header
cd kernel
make ARCH=arm64 INSTALL_HDR_PATH=${INSTALL_PATH_LP64}/${TARGET_LP64} headers_install
cd ..

# Step 3. Build gcc's compilers only and install them
cd ${B_LP64}-gcc
../gcc/configure --prefix=${INSTALL_PATH_LP64} --target=${TARGET_LP64} ${GCC_CONFIG_LP64}
make $PMAKE all-isl
make $PMAKE all-gcc
make install-gcc
cd ..

# Step 4. Install standard C library headers and start up files (headers + C runtimes)
cd ${B_LP64}-glibc
../glibc/configure --prefix=${INSTALL_PATH_LP64}/${TARGET_LP64} ${GLIBC_CONFIG_LP64} CC="${TARGET_LP64}-gcc -O2"
make install-bootstrap-headers=yes install-headers
make $PMAKE csu/subdir_lib
install csu/crt1.o csu/crti.o csu/crtn.o ${INSTALL_PATH_LP64}/${TARGET_LP64}/lib
${TARGET_LP64}-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o ${INSTALL_PATH_LP64}/${TARGET_LP64}/lib/libc.so
touch ${INSTALL_PATH_LP64}/${TARGET_LP64}/include/gnu/stubs.h
cd ..

# Step 5. Build the compiler support library - libgcc
cd ${B_LP64}-gcc
make $PMAKE all-target-libgcc
make install-target-libgcc
cd ..

# Step 6. Build the standard C library
cd ${B_LP64}-glibc
make $PMAKE
make install
cd ..

# Step 7. Build the standard C++ libary to finish off GCC
cd ${B_LP64}-gcc
make $PMAKE all-libcpp
make $PMAKE
make install
cd ..

#--- Repeat the above process but this time build the ILP32 toolchain with the one we just built. ---#

# Step 1. Build binutils-gdb and install them
cd ${B_ILP32}-binutils-gdb
../binutils-gdb/configure --prefix=$INSTALL_PATH_ILP32 --target=$TARGET_ILP32
make $PMAKE
make install
cd ..

# Step 2. Install the kernel header
cd kernel
make ARCH=arm64 INSTALL_HDR_PATH=${INSTALL_PATH_ILP32}/${TARGET_ILP32} headers_install
cd ..

# Step 3. Build gcc's compilers only and install them
cd ${B_ILP32}-gcc
../gcc/configure --prefix=${INSTALL_PATH_ILP32} --target=${TARGET_ILP32} ${GCC_CONFIG_ILP32}
make $PMAKE all-isl
make $PMAKE all-gcc
make install-gcc
cd ..

# Step 4. Install standard C library headers and start up files (headers + C runtimes)
cd ${B_ILP32}-glibc
../glibc/configure --prefix=${INSTALL_PATH_ILP32}/${TARGET_ILP32} ${GLIBC_CONFIG_ILP32} CC="${TARGET_ILP32}-gcc -mabi=ilp32 -O2"
make install-bootstrap-headers=yes install-headers
make $PMAKE csu/subdir_lib
install csu/crt1.o csu/crti.o csu/crtn.o ${INSTALL_PATH_ILP32}/${TARGET_ILP32}/lib
${TARGET_ILP32}-gcc -mabi=ilp32 -nostdlib -nostartfiles -shared -x c /dev/null -o ${INSTALL_PATH_ILP32}/${TARGET_ILP32}/lib/libc.so
touch ${INSTALL_PATH_ILP32}/${TARGET_ILP32}/include/gnu/stubs.h
cd ..

# Step 5. Build the compiler support library - libgcc
cd ${B_ILP32}-gcc
make $PMAKE all-target-libgcc
make install-target-libgcc
cd ..

# Step 6. Build the standard C library
cd ${B_ILP32}-glibc
make $PMAKE
make install
cd ..

# Step 7. Build the standard C++ libary to finish off GCC
cd ${B_ILP32}-gcc
make $PMAKE all-libcpp
make $PMAKE
make install
cd ..

#--- DONE BUILDING ---#

trap - EXIT
echo 'Success!' 
