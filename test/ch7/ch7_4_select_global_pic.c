// compile with clang -O1 to generate IR select
volatile int a = 1;
volatile int b = 2;

int gI = 100;
int gJ = 50;

int test_select_global_pic()
{
  if (a < b)
    return gI;
  else
    return gJ;
}
