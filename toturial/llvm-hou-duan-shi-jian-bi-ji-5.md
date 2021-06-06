# LLVM 后端实践笔记 5

## 5 全局变量

之前的几章，只访问了局部变量，在这一章中，我们要处理全局变量的访问。全局变量的 DAG 翻译不同于之前的 DAG 翻译。它的 DAG 翻译，需要额外依据 `llc -relocation-model` 参数（指定重定位模式是静态重定位还是运行时重定位），在后端创建 IR DAG 节点，而其他的 DAG 只需根据输入文件来直接做 DAG 的翻译 （伪指令除外）。大家需要专注于如何在执行时创建 DAG 节点而增加的代码，以及如何在 td 文件中定义 Pat 结构。另外，全局变量的机器指令打印功能也需要完成。

### 5.1 全局变量编译选项

和 Mips 相同，Cpu0 同时支持静态模式和 PIC 模式的全局变量重定位模式。这个选项通过 `-relocation-mode` 指定。另外，还区分两种不同的 layout，用来控制将数据放到 .data/.bss 段还是 .sdata/.sbss 段，后者使用 16 位地址寻址，寻址效率更高（需要指令数少），但寻址空间变小。这个选项通过 `-cpu0-use-small-section` 指定。

两个选项组合成 4 种类型，用来指导生成 4 种不同的可执行文件：

| 类型                                 | -relocation-model (默认 pic) | -cpu0-use-small-section (默认 false) |
| ------------------------------------ | ---------------------------- | ------------------------------------ |
| 静态重定位模式，不使用 small section | static                       | false                                |
| 静态重定位模式，使用 small section   | static                       | true                                 |
| PIC 重定位模式，不使用 small section | pic                          | false                                |
| PIC 重定位模式，使用 small section   | pic                          | true                                 |

本章大多数代码都是用来实现这 4 种模式，文章也会分章节介绍 4 种模式的要点。

以下为 4 种模式下处理全局变量的 DAG 状态和指令结果（`gI` 是全局变量的数据段 label）：

#### 5.1.1 静态模式，不使用 small section

1. 地址模式：绝对地址

2. 地址计算：绝对地址

3. 合法化选择 DAG：

   ```
   (add Cpu0ISD::Hi<gI offset Hi16>, Cpu0ISD::Lo<gI offset Lo16>)
   ```

4. 汇编：

   ```
   lui $2, %hi(gI);
   ori $2, $2, %lo(gI);
   ```

5. 重定位阶段：链接阶段

#### 5.1.2 静态模式，使用 small section

1. 地址模式：`$gp` 的相对地址（`$gp` 寄存器成为保留寄存器，用来指定 .sdata 段的开头）

2. 地址计算：`$gp + offset`

3. 合法化选择 DAG：

   ```
   (add register %GP, Cpu0ISD::GPRel<gI offset>)
   ```

4. 汇编：

   ```
   ori $2, $gp, %gp_rel(gI);
   ```

5. 重定位阶段：链接阶段

#### 5.1.3 PIC 模式，不使用 small section

1. 地址模式：`$gp` 的相对地址（`$gp` 寄存器作为保留寄存器，用来指定 .data 段的开头）

2. 地址计算：`$gp + offset`

3. 合法化选择 DAG：

   ```
   (load (Cpu0ISD::Wrapper register %GP, <gI offset>))
   ```

4. 汇编：

   ```
   ld $2, %got(gI)($gp);
   ```

5. 重定位阶段：链接或加载阶段

#### 5.1.4 PIC 模式，使用 small section

1. 地址模式：`$gp` 的相对地址（`$gp` 寄存器作为保留寄存器，用来指定 .sdata 段的开头）

2. 地址计算：`$gp + offset`

3. 合法化选择 DAG：

   ```
   (load EntryToken, (Cpu0ISD::Wrapper (add Cpu0ISD::Hi<gI offset Hi16>, Register %GP), Cpu0ISD::Lo<gI offset Lo16>))
   ```

4. 汇编：

   ```
   lui $2, %got_hi(gI);
   add $2, $2, $gp;
   ld $2, %got_lo(gI)($2);
   ```

5. 重定位阶段：链接或加载阶段

### 5.2 代码修改

我把两块的代码统一在这里展示。

#### 5.2.1 文件新增

##### (1) Cpu0Subtarget.h/.cpp

增加了处理编译选项的代码，提供了三个编译选项：`cpu0-use-small-section`、`cpu0-reserve-gp`、`cpu0-no-cpload`。第一个是控制是否使用 small section 的选项，后两个选项是将在编译器中用到的配置，分别是是否保留 `$gp` 作为特殊寄存器以及是否发射 `.cpload` 伪指令。

##### (2) Cpu0BaseInfo.h

声明全局变量偏移表的类型枚举，增加 MO_GOT16 和 MO_GOT 两个类型。

GOT：global offset table，全局变量偏移表，是位于目标文件中的一块数据引用，里边存放着全局变量的地址。

##### (3) Cpu0TargetObjectFile.h/.cpp

声明并定义了几个判断 small section 的实现方法，属于 Cpu0TargetObjectFile 的成员方法。判断某个地址是否是合法的 small section 地址、判断是否能放到 small section 内。

##### (4) Cpu0RegisterInfo.cpp

保留寄存器集合中增加 `$gp`，但通过宏来控制是否使能对保留寄存器 `$gp` 的判断，`globalBaseRegFixed()` 函数在 Cpu0MachineFunctionInfo.cpp 中定义。

##### (5) Cpu0ISelLowering.h/.cpp

在构造函数中，使用 `setOperationAction(ISD::GlobalAddress, MVT::i32, Custom)` 来告诉 llc，我们实现了全局变量的自定义实现。在 `LowerOperation()` 函数中，新增一个 switch 分支，当处理 `ISD::GlobalAddress` 时，跳转到我们自定义的 `lowerGlobalAddress()` 方法。而后者也在这里实现，这一部分比较关键，会根据设置好的条件，选择下降成 PIC 模式还是 static 模式，small section 还是标准 section，该函数会返回一个 DAG Node。

虽然IR操作中所有用户类型都是在 Cpu0TargetLowering 的构造函数中使用 `setOperationAction` 来声明，从而让llvm在合法化选择DAG阶段调用 `LowerOperation()` ，但全局变量访问操作仍然需要通过检查DAG节点的 GlobalAddress 来验证是否是  `ISD::GlobalAddress`。

另外还实现了一些创建地址模式 node 的函数，用来创建不同配置下的 node，比如静态模式，PIC 标准 section 模式等。

函数 `getTargetNodeName()` 用来返回节点的名字，在其中增加了 `GPRel` 和 `Wrapper` 节点，用来实现对全局变量类型的打印功能。

##### (6) Cpu0ISelDAGToDAG.h/.cpp

实现获取基地址的指令，也就是通过指令将 GOT 地址加载到寄存器。填充 Select 函数，对 `ISD::GLOBAL_OFFSET_TABLE` 做替换，将其更改为针对我们指定寄存器作为基地址寄存器的 Node。同时还填充了 SelectAddr 函数，对 PIC 模式，返回节点的操作数。

##### (7) Cpu0InstrInfo.td

定义了 Cpu0Hi、Cpu0Lo、Cpu0GPRel、Cpu0Wrapper 几个 Node，被用来处理全局地址（注意与寄存器 Hi、Lo 的区分）。

实现了几个 Pat，这种 td 结构指示在 lower DAG 时，将指定的 llvm node 下降为另一种机器相关的 DAG node。比如：

```
def : Pat<(Cpu0Hi tglobaladdr:$in), (LUi tglobaladdr:$in)>;
```

这表示将 Cpu0Hi 的 node 下降为 LUi 节点。

##### (8) Cpu0AsmPrinter.cpp

在 `EmitFunctionBodyStart()` 函数中增加了对 .cpload 的输出，.cpload 是一条伪指令，它用来标记一段伪代码，将会被展开成多条指令。另外，.set nomacro 用来判断汇编器的操作生成超过一种机器语言，并输出警告信息。

```
.set     noreorder
.cpload  $6
.set     nomacro
```

伪指令展开是在 Cpu0MCInstLower.h 中完成的，`LowerCPLOAD()` 函数。

##### (9) Cpu0MCInstLower.h/.cpp

实现对 MCInst 指令的 lower，在 `LowerOperand()` 函数中，针对 MO_GlobalAddress 类型的操作数做特殊处理，实现 `LowerSymbolOperand()` 函数，也就是对符号操作数的处理，当处理全局变量时，能够返回一个符号表达式（比如 `%got_lo` 这种）。

另外，实现了 `LowerCPLOAD()` 函数，该函数用来对伪指令 `.cpload` 进行展开，展开内容为：

```assembly
lui    $gp, %hi(_gp_disp)
addiu  $gp, $gp, %lo(_gp_disp)
addu   $gp, $gp, $t9
```

`_gp_disp` 是一个重定位符号，它的值是函数开头到 GOT 表的偏移，加载器在加载时填充这个值。展开的指令中，我们能看到，`$gp` 存放的就是 sdata 段的起始地址，而将 `$gp` 与 `$t9` 相加（`$t9` 用来保存函数调用的函数地址），就调整好了在某次函数调用时的 sdata 段数据的起始位置。`$gp` 是需要参与栈调整的，它是 callee saved 寄存器。

##### (10) Cpu0MachineFunctionInfo.h/.cpp

实现获取全局基地址寄存器的几个辅助函数。



### 5.3 检验成果

使用的测试程序是 ch5.c：

```c
int gStart = 3;
int gI = 100;
int test_global()
{
  int c = 0;
  
  c = gI;
  
  return c;
}
```

使用 clang 编译 LLVM 文件：

```bash
build/bin/clang -target mips-unknown-linux-gnu -c ch5.c -emit-llvm -S -o ch5.ll
```

#### 5.3.1 静态模式

##### (1) 存放在 data 段

使用 llc 编译汇编文件：

```bash
build/bin/llc -march=cpu0 -relocation-model=static -cpu0-use-small-section=false -filetype=asm ch5.ll -o ch5.s
```

 生成的汇编文件中，比较关键的代码如下：

```assembly
...
  lui $2, %hi(gI)
  ori $2, $2, %lo(gI)
  ld  $2, 0($2)
...
  .type        gStart,@object             # @gStart
  .data
  .globl       gStart
  .p2align     2
gStart:
  .4byte       3
  .size        gStart, 4
  
  .type        gI,@object                # @gI
  .globl       gI
  .p2align     2
gI:
  .4byte       100
  .size        gI, 4
```

`lui` 指令将一个值的低 16 位放到一个寄存器的高 16 位，寄存器的低 16 位填 0。

代码中，首先加载 `gI` 的高 16 位部分，放到 `$2` 中高 16 位，低 16 位填 0；然后将 `$2` 与 `gI` 的低 16 位做或运算，最后，通过 ld 指令，将 `$2` 指向的内容（此时 `$2` 保存的是指向 `gI` 的地址）取出来，放到 `$2` 中，标量数据偏移是 0。

还注意到，`gStart` 和 `gI` 都存放在 .data 段。

##### (2) 存放在 sdata 段

然后，我们看一下存放到 sdata/sbss 段的结果：

使用 llc 编译：

```bash
build/bin/llc -march=cpu0 -relocation-model=static -cpu0-use-small-section=true -filetype=asm ch5.ll -o ch5.s
```

生成的汇编文件中：

```assembly
...
  ori $2, $gp, %gp_rel(gI)
  ld  $2, 0($2)
...
  .type      gStart,@object               # @gStart
  .section   .sdata,"aw",@progbits
  .globl     gStart
  .p2align   2
gStart:
  .4byte     3
  .size      gStart, 4
  .type      gI,@object                   # @gI
  .globl     gI
  .p2align   2
gI:
  .4byte     100
  .size      gI, 4
```

其中 `$gp` 保存了 .sdata 的起始绝对地址，在加载时赋值（此时 `$gp` 不能被当做普通寄存器分配），`gp_rel(gI)` 是计算 `gI` 相对于段起始的相对偏移，在链接时会计算，所以第一条指令结束时，`$2` 中就保存了 `gI` 的绝对地址。第二条指令做 `gI` 的取值操作。

注意到，`gStart` 和 `gI` 都存放在 .sdata 段。因为 sdata 是自定义段，所以汇编选用了 .section 伪指令来描述。

这种模式下，`$gp` 的内容是在链接阶段被赋值的， `gI` 相对于 .sdata 段的相对地址也能在链接时计算，并替换在 `%gp_rel(gI)` 的位置，所以整个重定位过程是静态完成的（运行开始时地址都已经固定好了）。

#### 5.3.2 PIC 模式

##### (1) 存放在 data 段

使用 llc 编译：

```bash
build/bin/llc -march=cpu0 -relocation-model=pic -cpu0-use-small-section=false -filetype=asm ch5.ll -o ch5.s
```

生成的汇编代码中：

```assembly
...
  .set      noreorder
  .cpload   $t9
  .set      nomacro
...
  lui $2, %got_hi(gI)
  addu $2, $2, $gp
  ld $2, %got_lo(gI)($2)
  ld $2, 0($2)
...
  .type     gStart,@object              # @gStart
  .data
  .globl    gStart
  .p2align  2
.gStart:
  .4byte    3
  .size     gStart, 4
  
  .type     gI,@object                  # @gI
  .globl    gI
  .p2align  2
gI:
  .4byte    100
  .size     gI, 4
```

由于全局数据放到了 data 段，所以 `$gp` 中保存了在这个函数中全局变量在 data 段的起始地址。通过 `%got_hi(gI)` 和 `%got_lo(gI)` 就可以获得全局变量的 GOT 偏移，进而得到它在运行时的地址。值得一提的是，这些汇编代码，都是在 td 文件中被定义如何展开的。

.cpload 伪指令会在汇编之后被展开为：

```assembly
lui    $gp, %hi(_gp_disp)
addiu  $gp, $gp, %lo(_gp_disp)
addu   $gp, $gp, $t9
```

从而用来加载动态链接时的 data 段地址。详细说明见前边代码部分描述。

##### (2) 存放在 sdata 段

使用 llc 编译：

```bash
build/bin/llc -march=cpu0 -relocation-model=pic -cpu0-use-small-section=true -filetype=asm ch5.ll -o ch5.s
```

生成的汇编代码中：

```assembly
...
  .set      noreorder
  .cpload   $6
  .set      nomacro
...
  ld $2, %got(gI)($gp)
  ld $2, 0($2)
...
  .type     gStart,@object               # @gStart
  .sdata    gStart,"aw",@progbits
  .globl    gStart
  .p2align  2
gStart:
  .4byte    3
  .size     gStart, 4
  
  .type     gI,@object                   # @gI
  .globl    gI
  .p2align  2
gI:
  .4byte    100
  .size     gI, 4
```

Cpu0 使用 .cpload 和 `ld $2, %got(gI)($gp)` 指令来访问全局变量。此时，我们无法假设 `$gp` 总是能指向 sdata 的开头（因为`$gp` 会被栈调整时修改）。

注意到，数据存放在 sdata 段。

### 5.4 总结

DAG 翻译中的全局变量指令选择不同于通常的 IR 节点翻译，它包括静态模式（绝对地址）和 PIC 模式。后端通过在 `lowerGlobalAddress()` 函数中创建 DAG 节点来实现其翻译，这个函数被 `lowerOperation()` 函数调用。而 `lowerOperand()` 函数处理所有需要自定义类型的翻译操作。

后端在 Cpu0TargetLowering 构造函数中通过 `setOperationAction(ISD::GlobalAddress, VT::i32, Custom)` 来指定将全局变量设置为自定义操作。有多种不同类型的操作动作，除了 Custom，比如 Promote 和 Expand，但只有 Custom 需要开发自定义的代码来处理。

需要说明的一点是，通过指定将全局变量保存在 sdata/sbss 段的行为，可能在链接阶段发现 sdata 段数据溢出的问题。当这种问题发生时，链接器就需要指出这个问题，并要求用户选择是否调整为 data 段存放全局数据。一个使用原则是，尽可能把小且频繁使用的变量放到 sdata 段。