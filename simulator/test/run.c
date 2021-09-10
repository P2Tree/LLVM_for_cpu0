// bash run.sh

/// start

#include "test_all_nolld.h"
#include "../boot/print.h"

int main()
{
  int pass = 1;
  pass = test_nolld();

  print_integer(pass);
  return pass;
}

#include "test_all_nolld.c"
