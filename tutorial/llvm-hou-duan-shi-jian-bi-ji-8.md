# LLVM 后端实践笔记 8

## 8 函数调用

在这一章，我们会在 Cpu0 后端中增加对子过程/函数调用的翻译功能，会添加大量代码。这一章首先会介绍 Mips 的栈帧结构，我们的 Cpu0 也会借用 Mips 的栈帧设计，大多数 RISC 机器的栈帧设计都是类似的，如果你对这块的背景知识有困惑，需要先查阅其他书籍，比如《深入理解计算机系统》这类计算机体系结构的书。

### 8.1 栈帧结构

Cpu0 函数调用的第一件事是设计好如何使用栈帧，比如在调用函数时，如何保存参数。

具体如下表所示，保存函数参数有两种设计，第一种是将所有参数都保存在栈帧上，第二种是选出一部分寄存器，将部分参数先保存在这些寄存器中，如果参数过多，超出的那些再保存在栈帧上。比如 Mips 设计中，将前 4 个参数保存在寄存器 `$a0`, `$a1`, `$a2`, `$a3` 中，然后再把多余的其他参数保存在栈帧。

| 基址寄存器与偏移 | 保存内容             | 当前栈帧 |
| ------------------- | -------------------- | ----- |
|                     | 未定义的其他位置 ... | 高地址 |
| 旧 $sp    ...    +15 | 输入参数保存（高位参数，共 4 个） |       |
| 旧 $sp    ...    +0 | 输入参数保存（低位参数） | 前一个栈帧 |
|                     | 局部变量和临时变量 | 当前栈帧 |
|                     | 通用寄存器保存 |       |
|                     | 浮点寄存器保存 |  |
| 新 $sp    ...    +0 | 其他位置 | 低地址 |

保存在寄存器中的参数，和栈帧没有关系。

栈帧管理部分也需要我们在后端编写代码，我们已经在第二章添加了这些代码，主要实现了 EmitPrologue() 和 EmitEpilogue() 函数，所以这一节我们不需要额外增加新的代码，case 就可以正常工作。

可以先尝试运行 ch8_1.c 的测试用例，使用 `-march=mips` 来编译输出汇编代码：

在 main 函数中：

```assembly
...
addiu $1, $zero, 6
sw $1, 20($sp)            # 第六个参数存入栈偏移 20 位置
addiu $1, $zero, 5
sw $1, 16($sp)            # 第五个参数存入栈偏移 16 位置
lw $25, %call16(sum_i)($gp)    # 获得 sum_i 地址
addiu $4, $zero, 1        # 第一个参数存入 $4
addiu $5, $zero, 2        # 第二个参数存入 $5
addiu $6, $zero, 3        # 第三个参数存入 $6
jalr $25                  # 跳转到 sum_i
addiu $7, $zero, 4        # 延迟一个 cycle，第四个参数存入 $7
...
```

在 sum_i 函数中：

```assembly
...
lui $2, %hi(_gp_disp)
addiu $2, $2, %lo(_gp_disp)
addu $1, $2, $25
lw $1, %got(gI)($1)      # 前几个指令，获取全局变量 gI 的地址
sw $4, 16($fp)           # 第一个参数存入栈
sw $5, 12($fp)           # 第二个参数存入栈
sw $6, 8($fp)            # 第三个参数存入栈
sw $7, 4($fp)            # 第四个参数存入栈
lw $1, 0($1)             # 全局变量 gI 的值存入 $1
...
```



### 8.2 传入参数

在开始之前，先使用 `-march=cpu0` 执行 ch8_1.c，检查报错信息：

```
Assertion failed: (InVals.size() == Ins.size() && "LowerFormalArguments didn't emit the correct number of values!"), function LowerArguments, file .../SelectionDAGBuilder.cpp
```

目前，我们 LowerFormalArgument 函数依然是空的，所以才会得到这个错误，在定义函数内容之前，我们要处理如何传入参数。

我们决定，设置一个编译参数：`-cpu0-s32-calls`，默认值为 false，当为 false 时，Cpu0 将前 2 个参数放入寄存器传递，其他更多参数存入栈帧；当为 true 时，Cpu0 将所有参数存入栈帧。

#### 8.2.1 代码修改

##### (1) Cpu0ISelLowering.h/.cpp

ISelLowering 中实现了几个重要的函数。其中之一就是 LowerFormalArgument，回顾一下之前全局变量的实现代码，当时实现了 LowerGlobalAddress 函数，然后在 td 文件中实现指令选择模板，当代码中存在全局变量的访问时，LLVM 就会访问这个函数。LowerFormalArgument 也是同样的道理，会在函数被调用时被访问。它从 CCInfo 对象中获取输入参数的信息，比如 ArgLocs.size() 就是传入参数的数量，而每个参数的内容就放在 ArgLocs[i] 中，当 VA.isRegLoc() 为 true 时，表示参数放到寄存器中传递，而 VA.isMemLoc() 为 true 时，就表示参数放到栈上传递，在访问参数时，根据这个值，就可以根据实际情况来做处理加载参数的过程。它内部有一个 for 循环，来依次处理每个参数的情况。

当访问寄存器时，它会先激活寄存器（Live-in），然后拷贝其中的值，当时内存传递参数时，它会创建栈的偏移对象，然后使用 load 节点来加载值。

编译参数 `-cpu0-s32-calls=false` 时，它会选择将前两个参数从寄存器中读取，否则，所有参数都从栈中 load 出来。

在加载参数前，会先调用 analyzeFormalArguments 函数，在内部使用 fixedArgFn 来返回函数指针 CC_Cpu0O32 或 CC_Cpu0S32，这两个函数分别是处理两种不同的参数加载方式，即前两个参数从寄存器读取还是全部都从栈上加载。ArgFlags.isByVal 用于处理结构体指针的关键信息，在遇到结构体指针时，会返回 true。

当 `-cpu0-s32-calls=false` 时，栈帧偏移从 8 开始，这就是为了保证前两个从寄存器传递的参数有可能 spill 的情况，当编译参数为 true 时，栈帧偏移就从 0 开始了。

传递结构体参数比较特殊，在函数结尾前，有一个和前边一样的 for 循环，再一次遍历所有的参数，并判断如果这个参数存在一个 SRet 标记，就将对应参数的值拷贝到以一个 SRet 寄存器为 base 的栈的偏移中，通过调用 getSRetReturnReg() 获取 SRet 寄存器，通常为 $2。在下一节 LowerCall() 中，如果是一个 struct 传值的返回值，Flags.isByVal 是为 true，就会将结构体的值依次存入栈中。

在我们的示例中，对于参数全部放在栈帧上加载的情况，LowerFormalArgument 会被调用 2 次，第一次是在子函数被调用时，第二次是 main 函数被调用时。

我们还需要一些辅助的函数，比如 loadRegFromStackSlot 函数，用来将参数从栈帧 load 到寄存器中。

几个主要函数的实现还有一些细节，需要从代码中学习。

##### (2) Cpu0SEISelLowering.h/.cpp

重写了一个函数 isEligibleForTailCallOptimization()，用于 call 尾调用优化的事情。暂时和这一节关系不大。

#### 8.2.2 检验成果

编译 ch8_incoming.c 这个测试用例，这个用例只有传参的代码，而没有函数调用的代码，可以编译出 cpu0 后端的汇编代码。

通过选择编译参数 `-cpu0-s32-calls=false/true` 给 llc 来编译两种不同的汇编，查看差别。

编译 ch8_1.c 这个测试用例，会发现之前的错误解决了，取而代之的是另一个错误：

```
Assertion failed: ((CLI.IsTailCall || InVals.size() == CLI.Ins.size()) && "LowerCall didn't emit the correct number of values!"), function LowerCallTo, fill .../SelectionDAGBuilder.cpp
```

这个问题我们在下一节解决。



## 8.3 函数返回

上一节我们介绍了如何实现在被调用函数内部将参数传递到被调用函数，实现了 LowerFormalArguments() 函数；现在，我们来实现另一部分，即如何在函数调用时将实参传入栈，以及如何将函数执行结束后的返回值传递回调用函数，LowerCall() 函数用来实现这个功能。

#### 8.3.1 文件修改

##### (1) Cpu0ISelLowering.h/.cpp

这个文件中会新增大量的代码，核心函数就是 LowerCall()，和 LowerFormalArgument() 一样，我们为了避免函数过长，将一部分功能提取出来单独实现，让代码更清晰。

在 LowerCall 函数中，前边先调用了 analyzeCallOperands() 函数，分析 call 操作的操作数，为之后分配地址空间做准备。

然后会调用尾调用优化函数 isEligibleForTailCallOptimization()，这里做这样的优化，可以避免尾递归情况下函数频繁开栈空间的问题。通常支持递归的栈式处理器程序都需要对尾调用做额外处理。

之后，插入 CALLSEQ_START 节点，标记进入 call 的输出过程。

内部使用一个大循环，对所有参数做遍历，将需要通过寄存器传递的参数 push_back 到 RegsToPass 中，调用了 passByValArg() 函数生成存入寄存器的行为节点链。并在参数大小不满足调用约定的参数做 promote。然后对于通过栈传递的参数，将其加入到 MemOpChains 中，调用了 passArgOnStack() 函数来生成存入栈的行为节点链。

可以展开来看 passByValArg() 函数和 passArgOnStack() 函数的内部实现。

如果被调用函数是一个外部函数，包括全局函数（基本都满足这种情况），需要生成一个外部符号加载，这里需要创建一个 TargetGlobalAddress 或 TargetExternalSymbol 节点，从而避免合法化阶段去操作它。其他部分的代码会将这里的节点转换成 load 外部符号的指令并发射。

之后将所有 call 节点参数（所有节点参数，包括实参、返回值、chain 等）使用 getOpndList 汇总起来做处理，在这个函数中，针对不同的参数类型和属性，分别创建不同的操作方式，比如对于需要通过寄存器传递的实参，创建一系列的 copy to reg 操作。最后把所有操作都打包到 Ops 中返回。

如果是 PIC 模式，编译器会生成一条 load 重定位的 call 符号的地址 + 一条 jarl；如果不是，则会生成 jsub + 符号地址；PIC 模式会留给链接器之后再去重定位。 

最后，生成一条跳转节点 Cpu0ISD::JmpLink，跳转到被调用函数的符号地址，Ops 作为 call 节点参数被引入。对于尾调用，需要额外生成 Cpu0ISD::TailCall 节点。

插入 CALLSEQ_END 节点，标记结束 call 动作。

最后会调用 LowerCallResult() 函数处理调用结束返回时的动作。其中调用了 analyzeCallResult 分析返回 call 的参数，并处理所有返回参数，还原 caller saved register。

需要提及的是，我们在 Cpu0CallConv.td 中定义的 caller register 和 callee register 会在这里参与指导流程，我们通过调用 `Cpu0CCInfo` 对象来访问这些配置化的属性。

定义了一个统计参数 NumTailCalls，用来计数 case 中尾调用的数量。

##### (2) Cpu0FrameLowering.h/cpp

这里实现了一个消除 call frame 伪指令 .cpload 和 .cprestore 的函数 eliminateCallFramePseudoInstr()，因为没有额外的事情要做，所以这里就直接 `MBB.erase(I)` 就可以了。

##### (3) Cpu0InstrInfo.td

加入了一条链接并跳转指令 `jalr` 和 `jsub`，两者的差别是前者是将跳转地址保存到寄存器，后者是直接通过 label 传递。

加入了两条伪指令：ADJCALLSTACKDOWN 和 ADJCALLSTACKUP，这两个指令用来标记调用栈开始和结束的位置，其中 sdnode 使用的是我们重新覆写的 callseq_start 和 callseq_end，需要说明的一点，ISD::CALLSEQ_START 和 ISD::CALLSEQ_END 这两个 node，虽然是原生 node，但因为它们和后端平台又有相关性，所以必须在 td 中重新覆写。

加入一条伪指令：CPRESTORE，在处理 PIC 模式时，汇编器需要将其展开生成 .cpload 和 .cprestore directives（汇编伪指令）。我们必须在这里做伪指令，从而避免汇编器输出 warning。下一节我们再处理这部分内容。

两个关于 Cpu0JmpLink 的 Pat，是用来映射调整并链接的 node 生成的指令，前后顺序要保持为先下降全局符号，再下降外部符号，我们假设全局符号的 call 要频繁于外部符号。

##### (4) Cpu0InstrInfo.cpp

将伪指令 ADJCALLSTACKDOWN, ADJCALLSTACKUP 注册到 Cpu0GenInstrInfo 对象中。

##### (5) Cpu0MCInstLowering.h/cpp

这里定义了编译器输出的 call 的符号类型，新增了 Cpu0MCExpr::CEK_GOT_CALL。还增加了外部符号 MO_ExternalSymbol 的计算方式，全局符号 MO_GlobalSymbol 的代码已经在之前章节添加。

##### (6) Cpu0MachineFunctionInfo.h/cpp

新增了一些辅助函数和属性，这些函数和属性是继承自 TargetMachineFunction，我们希望在其他代码中调用到这些属性来辅助生成正确的代码。

##### (7) Cpu0SEFrameLowering.h/cpp

实现了一个函数 spillCalleeSavedRegisters()，用来定义 callee saved register 的 spill 动作，里边比较简单，就是遍历所有 callee saved register 并调用 storeRegToStackSlot() 函数将他们存入栈。需要注意 $lr 寄存器如果保存了返回地址，则不需要 spill。

##### (8) MCTargetDesc/Cpu0AsmBackend.cpp

新建一个重定位类型 fixup_Cpu0_CALL16。

##### (9) MCTargetDesc/Cpu0ELFObjectWriter.cpp

新建重定位类型的 Type，ELF::R_CPU0_CALL16。

##### (10) MCTargetDesc/Cpu0FixupKinds.h

还是这个重定位类型的声明。

##### (11) MCTargetDesc/Cpu0MCCodeEmitter.cpp

修改 getJumpTargetOpValue()，对于 JSUB 指令，也发射重定位信息。

#### 8.3.2 检验成果

##### (1) 测试普通参数

编译我们上一节未通过的 case ch8_1.c，这次就可以完全编译通过了，使用编译参数 `-cpu0-s32-calls=true` 和 `false`， 分别查看两者的区别，前者会将所有参数通过栈来传递，后者会将前两个参数通过寄存器传递，其他参数通过栈传递。

```
build/bin/llc -march=cpu0 -mcpu=cpu032I -cpu0-s32-calls=true -relocation-model=pic -filetype=asm ch8_1.c -o -
```

生成的汇编部分代码如：

```assembly
sum_i:
   ...
   addiu $sp, $sp, -8
   lui $2, %got_hi(gI)
   addu $2, $2, $gp
   ld $2, %got_lo(gI)($2)    # 加载全局变量
   ld $2, 0($2)
   ld $3, 8($sp)      # 第一个参数
   addu $2, $2, $3
   ...
   ld $3, 28($sp)     # 最后一个参数
   addu $2, $2, $3    
   st $2, 4($sp)
   ld $2, 4($sp)      # 计算结果存入 $2
   addiu $sp, $sp, 8
   ret $lr            # 返回 main
main:
   ...
   addiu $sp, $sp, -40
   st $lr, 36($sp)     # 是调用 main 的返回地址
   addiu $2, $zero, 0
   st $2, 32($sp)
   addiu $2, $zero, 6
   st $2, 20($sp)
   ...
   addiu $2, $zero, 1
   st $2, 0($sp)        # 保存这 6 个实参到栈
   ld $6, %call16(sum_i)($gp)
   jalr $6              # 这条指令会更新 $lr 并跳转到 $6 地址处
   nop
   st $2, 28($sp)       # 从 $2 中取出 sum_i 的计算结果，存入 main 的栈
   ld $2, 28($sp)       # 再次取出计算结果存入 $2，因为 main 也是将计算结果直接返回
   ld $lr, 36($sp)
   addiu $sp, $sp, 40
   ...
```

使用 `-cpu0-s32-calls=false` 的结果也是类似的，不再展示。



第二个要测试的参数是 `-relocation-model=static`，因为我们对于 PIC 模式和静态模式处理全局符号/外部符号的方式是不一样的。如果我们以静态模式编译：

```
build/bin/llc -march=cpu0 -mcpu=cpu032I -cpu0-s32-calls=true -relocation-model=static -filetype=asm ch8_1.c -o -
```

 得到的汇编是：

```assembly
main:
   ...         # 我把参数传递都省略了
   jsub sum_i  # 这是函数调用的跳转
   nop
   ...
```

除了使用 `jsub` 代替了 `ld + jalr`，其他都是类似的。

##### (2) 测试结构体参数

执行 ch8_struct.c，运行一个结构体作为参数的测试用例，其中分别将结构体作为值来传递和作为指针来传递。当作为值传递时，可以留意检查一下在被调用函数中是否生成了 SRet 寄存器和保存结构体内容的 st 动作，如下：

```assembly
test_func_arg_struct:
    ...
    addiu $2, $sp, 88 # 调用函数中先设定 SRet
    st $2, 0($sp)     
    ld $2, %got(copyDateByVal)($gp)
    ori $6, $2, %lo(copyDateByVal)
    jalr $6
    nop
    ...
getDateByVal:
    ...
    ld $3, 0($sp)    # 加载 SRet 参数到 $3
    ld $4, 20($2)    # 加载其他传值结构体内容
    st $4, 20($3)    # 存到 $3 作为栈 base 指定的地址
    ...              # 省略其他结构体项
    ret $lr
    nop
    ...
getDateByAddr:
    ...
    ld $2, 0($sp)
    ret $lr          # 传指针的方式就非常简单了
    nop
```

##### (3) 测试字符串

另外我们还可以测试一下字符串初始化代码，因为一般情况下，LLVM 会为字符串初始化生成一条 memcpy 动作，在执行时需要配合 C 库中的 memcpy 完成初始化。不过 LLVM 为我们提供了一条优化，可以在字符串比较短时，使用 `ld+st` 来替代 call 一个 memcpy。

执行 ch8_2.c，自行检查结果，会生成一条 call 的跳转和一段 `ld+st` 代码，后者会依次搬移字符串段的内容到栈上。

##### (4) 测试浮点运算

在第 6 章中，我们在实现浮点类型支持时，因为 Cpu0 没有浮点运算单元，所以浮点类型和运算必须通过调用软件函数库的方式实现，当时还没有实现函数调用，所以无法生成正确的代码。所以现在，我们来测试一下。

运行 ch6_4_float.c 测试用例，会生成：

```assembly
    jsub __adddf3    # double 类型浮点加法
    jsub __fixdfsi   # double 类型浮点转 int
    jsub __addsf3    # float 类型浮点加法
    jsub __fixsfsi   # float 类型浮点转 int
```

之类的指令。

我们现在还没有支持函数库，所以这里没有办法进一步做链接。

##### (5) 测试 builtin 函数

在第 6 章中，同样的原因，我们还没有测试 builtin 函数的支持情况，当时我们设计了两条指令，分别是计算前导 0 和计算前导 1 的数量，需要在 C 语言端调用 builtin 函数实现。

运行 ch6_7_clz.c 测试用例，汇编代码中会生成：

```assembly
    clz $2, $2
    clo $2, $2
```

 留意看一下 count leading zero 的 C 代码，是对变量先取反后调用 __builtin_clz() 函数。



### 8.4 函数调用优化

这一节我们简单涉及尾调用优化和循环展开递归调用。

#### 8.4.1 尾调用优化

当调用函数在返回时的最后一刻调用了一个被调用函数，因为被调用函数和调用函数可以共享一块栈帧空间，避免开辟新的栈帧，从而能节省时间和空间成本，达到优化的目的，尤其是当在递归调用中，使用尾调用优化，可以一定程度上避免了栈溢出问题。

我们在前边小节中的代码已经加入了一些尾调用的代码，这里再简单说下。

在 LowerCall() 函数中，检查是否可以进行尾调用优化。这个状态是 Clang 给出的，Clang 在前端就可以分析是否满足尾调用特征，并在开优化的情况下生成 tail call 的 IR。如果是尾调用优化，就不必再发射 callseq_start 到 callseq_end 的这段代码了。取而代之的是在指令选择时选择到伪代码 TAILCALL，并在指令发射时展开成 JMP 指令。

新增代码到 Cpu0AsmPrinter.cpp 中，在 EmitInstruction() 中的指令循环时，插入如果满足 emitPseudoExpansionLowering() 时做调用，后者是由 tablegen 自动生成的一个函数，在 Cpu0GenMCPseudoLowering.inc 文件中定义。

尾调用优化是 Clang 支持的一种优化，需要使能至少 O1 优化级别。

#### 8.4.2 循环展开递归调用

我们知道，递归调用层次太深，即使使用了尾调用优化，但依然需要频繁的访问栈。使用循环来替代递归是一种不错的解决问题的方式，Clang 支持这种优化，会分析在尾调用满足循环替代递归的特性时做变换。

不需要添加代码。

#### 8.4.3 检验成果

执行 ch8_tailcall.c 文件，这是一个尾调用和递归函数的示例代码。

先使用 Clang O1 级别编译：

```
build/bin/clang -target mips-unknown-linux-gnu -c ch8_tailcall.c -emit-llvm -S -o ch8_tailcall.ll -O1
build/bin/llc -march=cpu0 -mcpu=cpu032I -relocation-model=static -filetype=asm -enable-cpu0-tail-calls -stats ch8_tailcall.ll -o -
```

触发尾调用优化后，会生成 jmp 指令来调用被调用函数，jmp 指令只会跳转，而不会生成 jsub 指令。jmp 跳转到被调用函数后，被调用函数采用循环展开替代递归调用，并在递归结束后，直接返回到调用函数的 $lr，也就是直接返回调用函数应该返回的地方

因为我们还设置了一个统计参数，所以还可以查看打印的统计数据，可以看到尾调用优化完成 1 次。

使用 Clang O3 级别编译：

```
build/bin/clang -target mips-unknown-linux-gnu -c ch8_tailcall.c -emit-llvm -S -o ch8_tailcall.ll -O3
build/bin/llc -march=cpu0 -mcpu=cpu032I -relocation-model=static -filetype=asm -enable-cpu0-tail-calls -stats ch8_tailcall.ll -o -
```

依然触发了一样的优化，但更激进的，调用函数不再需要跳转到被调用函数的代码，而是直接将被调用函数的逻辑搬到调用函数中直接循环执行。



### 8.5 总结

到目前为止，Cpu0 后端代码已经可以处理整形的函数调用和控制条件了。它已经能够编译简单的 C 程序代码了（实际上 C++ 代码中非 C++ 特性的代码也一样能够支持，毕竟这是 Clang 前端在做的事情）。LLVM 对编译技术的完美实践，使得我们能够在它的基础上灵活轻松的支持任何形式的机器架构。三段式的编译结构，可以让后端伴随着前端支持不同编程语言的同时，得到自由的发展。

下一章，我们要实现输出 ELF 文件的功能支持，虽然我们的 Cpu0 后端没有实际的硬件，只能通过模拟器运行，但假设这是一个实际的硬件后端，只有能够输出标准的可执行二进制文件，才能在真正的机器上运行，所以这部分功能依然是后端不可缺少的一部分。