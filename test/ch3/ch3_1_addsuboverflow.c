
int test_add_overflow()
{
  int a = 0x70000000;
  int b = 0x20000000;
  int c = 0;

  c = a + b;

  return 0;
}

int test_sub_overflow()
{
  int a = -0x70000000;
  int b =  0x20000000;
  int c = 0;

  c = a - b;

  return 0;
}
