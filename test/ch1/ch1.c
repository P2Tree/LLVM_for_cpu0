// clang -target mips-unknown-linux-gnu -c ch1.c -emit-llvm -o ch1.bc
// llc -march=cpu0 -relocation-model=pic -filetype=asm ch1.bc -o ch1.cpu0.s
// llc -march=cpu0 -relocation-model=pic -filetype=obj ch1.bc -o ch1.cpu0.o

/// start
int main()
{
  return 0;
}

