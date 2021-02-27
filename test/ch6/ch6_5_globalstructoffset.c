struct Date
{
  int year;
  int month;
  int day;
};

struct Date date = {2021, 2, 27};
int a[3] = {2021, 2, 27};

int test_struct()
{
  int day = date.day;
  int i = a[1];

  return (i+day);  // 2 + 27 = 29
}
