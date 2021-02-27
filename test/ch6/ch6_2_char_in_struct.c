struct Date
{
  short year;
  char month;
  char day;
  char hour;
  char minute;
  char second;
};

unsigned char b[4] = {'a', 'b', 'c', '\0'};

int test_char()
{
  unsigned char a = b[1];
  char c = (char)b[1];
  struct Date date1 = {2021, (char)2, (char)27, (char)17, (char)22, (char)10};
  char m = date1.month;
  char s = date1.second;

  return 0;
}
