int test_deluselessjmp() {
  int a = 1; int b = -2; int c = 3;

  if (a == 0) {
    a++;
  }
  if (b == 0) {
    a = a + 3;
    b++;
  } else if (b < 0) {
    a = a + b;
    b--;
  }
  if (c > 0) {
    a = a + c;
    c++;
  }

  return a;
}
