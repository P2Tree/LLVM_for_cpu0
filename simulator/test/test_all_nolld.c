
/// start
#define TEST_ROXV
#define RUN_ON_VERILOG

#include "../boot/print.c"

#include "../../test/ch3/ch3_1_math.c"
#include "../../test/ch3/ch3_1_rotate.c"
#include "../../test/ch3/ch3_1_mod.c"
#include "../../test/ch3/ch3_1_div.c"
#include "../../test/ch3/ch3_2_logic.c"
#include "../../test/ch6/ch6_1_localpointer.c"
#include "../../test/ch7/ch7_2_deluselessjmp.c"

int test_rotate()
{
  int a = test_rotate_left1(); // rolv 4, 30 = 1
  int b = test_rotate_left(); // rol 8, 30  = 2
  int c = test_rotate_right(); // rorv 1, 30 = 4

  return (a+b+c);
}

int test_nolld()
{
  int a = 0;

  a = test_math();
  print_integer(a);

  a = test_rotate();
  print_integer(a);

  a = test_div();
  print_integer(a);

  a = test_mod();
  print_integer(a);

  a = test_div();
  print_integer(a);

  a = test_local_pointer();
  print_integer(a);

  a = test_andorxornot();
  print_integer(a);

  a = test_setxx();
  print_integer(a);

  a = test_deluselessjmp();
  print_integer(a);

  return 0;
}
