
struct Date {
  int year;
  int month;
  int day;
  int hour;
  int minute;
  int second;
};
static struct Date gDate = {2021, 6, 18, 1, 2, 3};

struct Time {
  int hour;
  int minute;
  int second;
};
static struct Time gTime = {2, 20, 30};

static struct Date getDate() {
  return gDate;
}

static struct Date copyDateByVal(struct Date date) {
  return date;
}

static struct Date* copyDateByAddr(struct Date* date) {
  return date;
}

static struct Time copyTimeByVal(struct Time time) {
  return time;
}

static struct Time* copyTimeByAddr(struct Time* time) {
  return time;
}

int test_func_arg_struct() {
  struct Time time1 = {1, 10, 12};
  struct Date date1 = getDate();
  struct Date date2 = copyDateByVal(date1);
  struct Date *date3 = copyDateByAddr(&date1);
  struct Time time2 = copyTimeByVal(time1);
  struct Time *time3 = copyTimeByAddr(&time1);

  return 0;
}
