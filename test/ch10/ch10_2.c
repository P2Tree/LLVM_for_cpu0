int inlineasm_addu() {
  int a = 10;
  int b = 15;

  __asm__ __volatile__("addu %0, %1, %2"
                       : "=r" (a)
                       : "r" (a), "r" (b)
                       );
  return a;
}

int inlineasm_addr() {
  int a = 10;
  int b = 15;
  int *p = &b;

  __asm__ __volatile__("ld %0, %1"
                       : "=r" (a)
                       : "m" (*p)
                       );
  return a;
}

int inlineasm_constraint() {
  int a = 10;
  int b = 15;

  __asm__ __volatile__("addiu %0, %1, %2"
                       : "=r" (a)
                       : "r" (a), "I" (2)
                       );
  return a;
}

int inlineasm_arg(int a, int b) {
  int r;

  __asm__ __volatile__("addu %0, %1, %2"
                       : "=r" (r)
                       : "r" (a), "r" (b)
                       );
  return r;
}

int g[3] = {1, 2, 3};

int inlineasm_global() {
  int r;
  __asm__ __volatile__("addiu %0, %1, %2"
                       : "=r" (r)
                       : "r" (g[1]), "r" (g[2])
                       );
  return r;
}

