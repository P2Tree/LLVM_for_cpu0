// Only generate IR select with clang -O1
// clang -O0 won't generate IR select.
volatile int a = 1;
volatile int b = 2;

int test_movx_3()
{
  int c = 0;

  if (a < b)
    return 1;
  else
    return 2;
}

int test_movx_4()
{
  int c = 0;

  if (a)
    c = 1;
  else
    c = 3;

  return c;
}
