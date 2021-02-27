long long test_longlong()
{
  long long a = 0x300000002;
  long long b = 0x100000001;
  int a1 = 0x30010000;
  int b1 = 0x20010000;

  long long c = a + b;    // c = 0x00000004,00000003
  long long d = a - b;    // d = 0x00000002,00000001
  long long e = a * b;    // e = 0x00000005,00000002
  long long f = (long long)a1 * (long long)b1;    // f = 0x00060050,01000000

  return (c+d+e+f);       // (0x0006005b,01000006) = (393307,16777222)
}
