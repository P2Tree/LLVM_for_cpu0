// generate IR select even with clang -O0
int test_movx_1()
{
  volatile int a = 1;
  int c = 0;

  c = !a ? 1 : 3;

  return c;
}

int test_movx_2()
{
  volatile int a = 1;
  int c = 0;

  c = a ? 1 : 3;

  return c;
}
