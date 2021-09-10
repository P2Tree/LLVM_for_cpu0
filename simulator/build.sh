#!/usr/bin/env bash

source functions.sh

sh_name=build.sh
argNum=$#
arg1=$1
arg2=$2

DEFFLAGS=""
if [ "$arg1" == cpu032II ] ; then
  DEFFLAGS=${DEFFLAGS}" -DCPU032II"
fi
echo ${DEFFLAGS}

prologue;

CLANGDIR=../../build/bin/

${CLANGDIR}/clang ${DEFFLAGS} -target mips-unknown-linux-gnu -c test/run.c \
-emit-llvm -o build/run.bc
${TOOLDIR}/llc -march=cpu0${endian} -mcpu=${CPU} -relocation-model=static \
-filetype=obj -enable-cpu0-tail-calls build/run.bc -o build/run.o
# print must at the same line, otherwise it will spilt into 2 lines
${TOOLDIR}/llvm-objdump -section=.text -d build/run.o | tail -n +8| awk \
'{print "/* " $1 " */\t" $2 " " $3 " " $4 " " $5 "\t/* " $6"\t" $7" " $8" " $9" " $10 "\t*/"}' \
 > build/cpu0.hex.comment
less -S build/cpu0.hex.comment | grep -v '[0-9a-z]\{16\}' > cpu0.hex

if [ "$arg2" == le ] ; then
  echo "1   /* 0: big endian, 1: little endian */" > build/cpu0.config
else
  echo "0   /* 0: big endian, 1: little endian */" > build/cpu0.config
fi
cat build/cpu0.config
