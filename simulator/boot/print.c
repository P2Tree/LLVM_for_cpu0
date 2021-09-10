
/// start
#include "print.h"
#include "itoa.c"

// For memory IO
void print_char(const char c)
{
  char *p = (char*)OUT_MEM;
  *p = c;

  return;
}

void print_string(const char *str)
{
  const char *p;

  for (p = str; *p != '\0'; p++)
    print_char(*p);
  print_char(*p);
  print_char('\n');

  return;
}

// For memory IO
void print_integer(int x)
{
  char *str;
  str = itoa(x);
  print_string(str);

  return;
}

