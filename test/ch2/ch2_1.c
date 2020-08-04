// clang -target mips-unknown-linux-gnu -c ch2.c -emit-llvm -o ch2.bc
// llc -march=cpu0 -relocation-model=pic -filetype=asm ch2.bc -o ch2.cpu0.s
// llc -march=cpu0 -relocation-model=pic -filetype=obj ch2.bc -o ch2.cpu0.o


/// start
int main()
{
  return 0;
}

