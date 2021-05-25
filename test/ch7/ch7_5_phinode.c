int test_phinode(int a, int b, int c)
{
  int d = 2;

  if (a == 0) {
    a++;
  }
  else if (b != 0) {
    a--;
  }
  else if (c == 0) {
    a += 2;
  }
  d = a + b;

  return d;
}
