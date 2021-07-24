int countLeadingZero() {
  int a, b;
  b = __builtin_clz(a);
  return b;
}

int countLeadingOne() {
  int a, b;
  b = __builtin_clz(~a);
  return b;
}
