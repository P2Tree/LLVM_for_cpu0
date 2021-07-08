# LLVM 后端实践笔记 6

## 6 更多数据类型

之前的章节只实现了 int 和 32 位的 long 类型数据，这一章会新增很多更复杂的数据类型，比如 char, bool, short, long long，还会增加结构体，浮点，和向量类型。这一部分内容相对比较简单，其实这些类型也都是标准语言都支持的类型，所以 LLVM 自身已经实现了很大一部分功能，只要我们的后端不那么奇怪，就很容易填补缺失的内容。

### 6.1 实现类型

#### 6.1.1 局部指针

我们需要在 td 文件中添加内存操作数的描述片段。具体参见代码描述部分。

#### 6.1.2 char, short int 和 bool 类型

char 和 short int 比较简单，参见代码描述。

bool 类型因为不是 C 标准的类型，而是 C++ 特性，所以我们不能使用 clang 来编译，测试时通过 LLVM IR 来测试（少有的 IR 测试用例）。

#### 6.1.3 long long 类型

与 Mips 一致，long long 类型是 64 位数据长度。支持 64 位宽的数据，需要新增对该类型的加减法和乘法操作，需要考虑进位，所以会对 DAG 做调整。具体参见代码描述部分。

#### 6.1.4 float 和 double 类型

Cpu0 硬件指令只支持整形，浮点指令需要通过调用函数库的方式实现，很多简单的处理器都是通过软件来实现浮点运算的，只有相对复杂的一些处理器，才会有自己的浮点运算单元。

因为我们还没有实现函数调用的功能，所以目前这部分代码还无法测试，不过有一些小工作可以先做了。具体见代码描述部分。

#### 6.1.5 数组和结构体类型

我们需要实现对全局变量带偏移的寻址模式，稍微有点复杂，参见代码实现。

#### 6.1.6 向量类型

向量类型的运算可以实现 SIMD 运算，也就是一条指令同时计算多个数据，硬件上这样设计可以提高数据并行性，使运算速率更快。因为 LLVM 原生支持向量类型的运算，所以留给我们要实现的部分不多。

Mips 支持 LLVM IR :`icmp slt` 和 `sext` 的向量类型计算，Cpu0 也同样会支持。

C 语言的扩展是支持向量类型的，需要通过 `__attribute__` 来修饰，参见测试部分。

### 6.2 代码修改

和之前一样，我还是把所有内容的代码放到这里进行说明。

#### 6.2.1 文件新增

##### (1) Cpu0InstrInfo.td

到目前，因为我们添加数据类型的很多实现代码已经在公共 LLVM 代码中实现，所以实际上大多数修改都在 td 文件中。

新增一个 mem_ea 的操作数类型，这是一个 complexpattern，会定义其 encoding 操作和 printinst 等操作，它用来描述指令 pattern 中的地址表示；然后要定义一个 LEA_ADDiu 的模式，这是一个不会输出成指令的模式，它实际上是计算地址+偏移的结果，这和 sparc 处理器中的 LEA_ADDRi 是一样的效果。

新增 i8 和 i16 相关的 extend 类型以及对应的 ld/st，命名为 LB, LBu, SB, LH, LHu, SH。LB, LH 处理有符号的 i8/i16 类型 load，LBu, LHu 处理无符号的 i8/i16 类型 load，SB, SH 同理。

新增 CountLeading0 和 CountLeading1 的 pattern，用来选择到计算前导 0 和计算前导 1 的指令，llvm 内置了 ctlz 的 node（count leading zero），可以直接把 clz 指令接过去，不过对于 count leading 1 是没有对应的 node 的，不过可以通过先对值取反然后求前导 0 的方式实现前导 1 的计算，即 `ctlz (not RC:$rb)`。

因为 C 语言没有对求前导 0 和前导 1 的原生语法，所以实际上会使用 builtin 接口来实现，也就是说，在 C 语言描述中，为了实现这种功能，需要调用 `__builtin_ctz()` 函数（ctls 就是先对参数取反再调用 ctlz 的 builtin），因为我们使用了内置的 node，所以这部分是 llvm 帮我们实现了。要等函数调用完成之后才能测试。

##### (2) Cpu0ISelLowering.h/.cpp

有关于对 bool 类型的处理，这里增加了一些对 i1 类型 Promote 的合法化描述，告诉 LLVM 在遇到对 i1 类型的 extend 时要做 Promote。Promote 是将较小宽度的数据类型扩展成对应的能够支持的更宽的数据宽度类型，在指令选择的类型合法化阶段会起到作用。

另外，还继承了 setBooleanContents() 和 setBooleanVectorContents() 函数，暂时不提供实现代码。

在 long long 实现中，在 Lowering 的位置还需要增加对 long long 类型的移位操作合法化。

覆盖一个函数 isOffsetFoldingLegal() ，直接返回 false，避免带偏移的全局地址展开，Cpu0 和 Mips 一样无法处理这种情况。我们实现的 getAddrNonPIC() 方法中，将全局符号地址展开成一条加法指令，对地址的高低位做加法运算。所以实际上我们会将一条全局地址带偏移的寻址展开成加法运算 base，然后再把结果与 offset 相加的 DAG（在 Cpu0ISelDAGToDAG.cpp 中的 SelectAddr 中提取这种情况的 node Value，此时就已经是两个 add node 了）。

最后，还需要对向量类型的支持做一小部分改动，覆盖 getSetCCResultType() 方法，如果是向量类型，使用 VT.changeVectorElementTypeToInteger() 方法返回 CC 值。

##### (3) Cpu0SEISelDAGToDAG.cpp

定义了一个 selectAddESubE() 方法，用来处理带进位的加减法运算的指令选择。在 trySelect() 方法中，将对 ISD::SUBE, ISD::ADDE, 的情况选择用 selectAddESubE() 来处理。

selectAddESubE() 方法为符合条件的 node 新增了一个操作数节点，该节点会读取状态字中进位是否是 1，并将结果叠加到运算中；在 Cpu032I 处理器中，使用 CMP 指令和 ANDi 指令来获取进位状态，在 Cpu032II 处理器中，则使用 SLT 指令直接判断进位。

另外，还要处理 SMUL_LOHI 和 UMUL_LOHI 节点，这是能够直接返回两个运算结果的节点（高低位）。

在 SelectAddr() 方法中，对于全局基址加常量偏移的情况，提取其基址和偏移。



### 6.3 检验成果

#### 6.3.1 局部指针

运行我提供的 ch6_1_localpointer.c 文件：

```c
int test_local_pointer() {
  int b = 3;
  int *p = &b;
  return *p;    // 这里还对不了，我们还没实现 call
}
```

使用 clang 进行编译：

```bash
build/bin/clang -target mips-unknown-linux-gnu -c ch6_1_localpointer.c -emit-llvm -S -o ch6_1_localpointer.ll
build/bin/llc -march=cpu0 -relocation-model=pic -filetype=asm ch6_1_localpointer.ll -o ch6_1_localpointer.s
```

得到的汇编内容如下，参见注释：

```
addiu $sp, $sp, -8
addiu $2, $zero, 3
st $2, 4($sp)        // 赋值局部变量为 3 并存入栈
addiu $2, $sp, 4     // 读出栈中局部变量的地址
st $2, 0($sp)        // 将指向局部变量的指针存入栈
ld $2, 0($sp)        // 读出栈中指向局部变量的指针的值
ld $2, 0($2)         // 读出局部变量的指针指向的值 
```

#### 6.3.2 char 类型

运行提供的 ch6_2_char_in_struct.c 文件：

```c
struct Date {
  short year;
  char month;
  char day;
  char hour;
  char minute;
  char second;
};
unsigned char b[4] = {'a', 'b', 'c', '\0'};
int test_char() {
  unsigned char a = b[1];  // 访问数组里的 char 成员
  char c = (char)b[1];
  struct Date date1 = {2021, (char)2, (char)27, (char)17, (char)22, (char)10};
  char m = date1.month;    // 访问结构体里的 char 成员
  char s = date1.second;
}
```

使用 clang 进行编译：

```bash
build/bin/clang -target mips-unknown-linux-gnu -c ch6_2_char_in_struct.c -emit-llvm -S -o ch6_2_char_in_struct.ll
build/bin/llc -march=cpu0 -relocation-model=pic -filetype=asm ch6_2_char_in_struct.ll -o ch6_2_char_in_struct.s
```

得到的汇编内容如下，参见注释：

```
lui $2, %got_hi(b)
addu $2, $2, $gp
ld $2, %got_lo(b)($2)    // 获取 b 数组的地址
addiu $2, $2, 1
lbu $3, 0($2)            // 获取 b[1] 的值
sb $3, 20($sp)
lbu $2, 0($2)            // 再次获取 b[1] 的值
sb $2, 16($sp)
ld $2, %got($__const.test_char.date1)($gp)
ori $2, $2, %lo($__const.test_char.date1)    // 获取要写入局部结构体对象的常量地址
addiu $3, $2, 6
lhu $3, 0($3)
addiu $4, $2, 4
lhu $4, 0($4)
shl $4, $4, 16
or $3, $4, $3            // 从常量区读出 word 长度的值
addiu $4, $sp, 8         // 这里的 8 是考虑到对齐的结构体在栈中的存放大小
ori $5, $4, 4            // 获取局部结构体对象 date1 的地址
st $3, 0($5)             // 存放 hour, minute, second 到 date1(12($sp))
addiu $3, $2, 2
lhu $3, 0($3)
lhu $2, 0($2)
shl $2, $2, 16
or $2, $2, $3            // 从常量区读出第二个 word 长度的值
st $2, 8($sp)            // 存放 year, month, day 到 date1(8($sp))
ori $2, $4, 2
lbu $2, 0($2)
sb $2, 4($sp)            // 读出 date1.month 并存入栈上 m
ori $2, $4, 6
lbu $2, 0($2)
sb $2, 0($sp)            // 读出 date1.second 并存入栈上 s
```

#### 6.3.3 short 类型

运行提供的 ch6_2_char_short.c 文件：

```c
int test_signed_char()
{
  char a = 0x80;
  int i = (signed int)a;
  i = i + 2; // i = (-128 + 2) = -126

  return i;
}

int test_unsigned_char()
{
  unsigned char c = 0x80;
  unsigned int ui = (unsigned int)c;
  ui = ui + 2; // ui = (128 + 2) = 130

  return (int)ui;
}

int test_signed_short()
{
  short a = 0x8000;
  int i = (signed int)a;
  i = i + 2; // i = (-32768 + 2) = -32766

  return i;
}

int test_unsigned_short()
{
  unsigned short c = 0x8000;
  unsigned int ui = (unsigned int)c;
  ui = ui + 2; // ui = (32768 + 2) = 32770

  return (int)ui;
}
```

编译方式与前边相同。

得到的汇编内容为（只截取 short 部分，char 部分供对比参考）：

```
// test_signed_short
ori $2, $zero, 32768
sh $2, 4($sp)             // 0x8000 写入栈
lh $2, 4($sp)             // lh 是 load sign half word
st $2, 0($sp)
ld $2, 0($sp)             // 通过 ld/st 转换类型从 short 到 int
addiu $2, $2, 2
st $2, 0($sp)             // 加法运算

// test_unsigned_short
ori $2, $zero, 32768
sh $2, 4($sp)             // 0x8000 写入栈
lhu $2, 4($sp)            // 注意这里是 lhu，load 之后采用无符号扩展到 word
st $2, 4($sp)
ld $2, 0($sp)             // 转换
addiu $2, $2, 2
st $2, 0($sp)

```

#### 6.3.4 bool 类型

目前提供了两个 case，第一个 case ch6_2_bool.c 因为标准 C 中不支持 bool 类型，所以无法编译，可以尝试通过 clang++ 进行编译，得到的 IR 和第二个 case 类似。第二个 case ch6_2_bool2.ll，通过 LLVM IR 来完成测试。

直接使用 llc 编译：

```bash
build/bin/llc -march=cpu0 -relocation-model=pic -filetype=asm ch6_2_bool2.ll -o ch6_2_bool2.s
```

 得到的汇编内容为：

```
addiu $2, $zero, 1
sb $2, 7($sp)           // 使用 sb 将 bool 类型的 1 写入栈，这是我们做了合法化之后的效果
```

#### 6.3.5 long long 类型

运行提供的 case ch6_3_longlong.c：

```c
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
```

编译命令与之前一致（Cpu032I 处理器），结果不详细罗列，举个例子，比如加法：

```
addu $3, $3, $5        // 高位加法，不带进位
addu $4, $2, $4        // 低位加法，不带进位
cmp $sw, $4, $2
andi $2, $sw, 1        // Cpu032I 获取低位加法进位信息
addu $2, $3, $2        // 将可能的进位加到高位加法的结果
st $4, 28($sp)         // 保存低位加法结果
st $2, 24($sp)         // 保存高位加法结果
```

可以换成 Cpu032II 类型处理器重新编译，可以看到不同的结果，编译命令要加上 `-mcpu=cpu032II` 参数，得到的该部分的汇编代码：

```
addu $3, $3, $5        // 高位加法，不带进位
addu $4, $2, $4        // 低位加法，不带进位
sltu $2, $4, $2        // 判断低位加法是否产生了进位
addu $2, $3, $2        // 将可能的进位加到高位加法的结果
st $4, 28($sp)         // 保存低位加法结果
st $2, 24($sp)         // 保存高位加法结果
```

#### 6.3.6 数组和结构体类型

先测试局部数组变量，运行 ch6_5_localarrayinit.c：

```c
int main() {
  int a[3] = {0, 1, 2};
  return 0;
}
```

编译后的结果为：

```
addiu $3, $sp, 0         // 栈基址
addiu $4, $3, 8          // 移动到保存第 3 个参数的位置
lui $5, %hi($__const.main.a)
ori $5, $5, %lo($__const.main.a)
addiu $6, $5, 8          // 获取到 a 数组的全局基址
ld $6, 0($6)             // 获取第 3 个值 a[2]：2
st $6, 0($4)             // 保存到栈上
addiu $3, $3, 4          // 移动到保存第 2 个参数的位置
addiu $4, $5, 4          // 获取到 a 数组的全局基址偏移一个 word 的位置
ld $4, 0($4)             // 获取第 2 个值 a[1]：1
st $4, 0($3)             // 保存到栈上
ld $3, 0($5)             // 获取第 1 个值 a[0]：0 （等于基址，所以不用移动）
st $3, 0($sp)            // 保存到栈上（等于栈基址，不用移动）
```

然后试着编译全局数组变量和结构体，运行 ch6_5_globalstructoffset.c：

```c
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
```

编译后的结果为：

```
lui $2, %got_hi(date)
addu $2, $2, $gp
ld $2, %got_lo(date)($2)       // 获取到 date 的全局地址
addiu $2, $2, 8
ld $2, 0($2)                   // 获取 date 第 3 个值 day：27
st $2, 4($sp)                  // 保存到栈上
lui $2, %got_hi(a)
addu $2, $2, $gp
ld $2, %got_lo(a)($2)
addiu $2, $2, 4
ld $2, 0($2)                   // 获取 a 第 2 个值 a[1]：2
st $2, 0($sp)                  // 保存到栈上
ld $2, 0($sp)
ld $3, 4($sp)
addu $2, $2, $3                // 做加法
```

#### 6.3.8 向量类型

需要测试的 case ：

```c
typedef long vector8long __attribute__((__vector_size__(32)));
typedef long vector8short __attribute__((__vector_size__(16)));

int test_cmplt_short()
{
  volatile vector8short a0 = {0, 1, 2, 3};
  volatile vector8short b0 = {2, 2, 2, 2};
  volatile vector8short c0;
  c0 = a0 < b0;

  return (int)(c0[0] + c0[1] + c0[2] + c0[3]);
}

int test_cmplt_long()
{
  volatile vector8long a0 = {2, 2, 2, 2, 1, 1, 1, 1};
  volatile vector8long b0 = {1, 1, 1, 1, 2, 2, 2, 2};
  volatile vector8long c0;
  c0 = a0 < b0;

  return (c0[0] + c0[1] + c0[2] + c0[3] + c0[4] + c0[5] + c0[6] + c0[7]);
}
```

编译后即可得到正确的汇编代码，比较指令也一样是区分 cpu032I 和 cpu032II 两种处理器的。

### 6.4 本章总结

这一章我们添加了很多的额外数据类型，这些数据类型在 C 编程中都比较常用。

因为 LLVM 优秀的框架设计，很多通用编程语言的数据类型都已经在公共代码中支持，所以如果是设计一个标准的程序语言的编译器，在 LLVM 框架下会省力很多，实现也会简单很多。

