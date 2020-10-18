# LLVM 后端实践笔记 2

[TOC]

## 2 后端结构

### 2.1 目标机器架构

这一部分代码比较多，主要有以下一些文件，实际内容请参考我提供的代码。

#### 2.1.1 文件新增

##### (1) Cpu0TargetMachine.h/.cpp

这是有关于目标机器的定义，实现了 `Cpu0TargetMachine`，`Cpu0ebTargetMachine`，`Cpu0elTargetMachine` 三个类，后两个类继承第一个类，而第一个类继承自 `LLVMTargetMachine`。其中定义了有关于目标的初始化工作，比如拼装 DataLayout，重定位模式，大小端，核心目的就是生成 TargetMachine 的对象，LLVM 会用。

其中有个函数 getSubtargetImpl()，这个函数可以构造 Subtarget 对象，进而能引用到 Subtarget 的属性和方法。

##### (2) Cpu0FrameLowering.h/.cpp

这是 Frame Lowering 的功能实现，完成栈的管理。基于 `TargetFrameLowering` 实现了 `Cpu0FrameLowering` 类，本身没有太多东西，重要内容都放到 `Cpu0SEFrameLowering.h/.cpp` 文件中了。

Cpu0 的栈也是向下生长，用栈指针指向栈顶，栈内内容通过栈指针加一个正数的偏移来获取。栈中的内容按顺序从高地址到低地址是：函数参数、GP、自由空间、CPU 的 Callee 寄存器、FP、RA、FPU 的 Callee 寄存器。

hasFP() 方法用来判断函数栈中是否包含 FP。

create() 方法用来创建该类的对象，实际要返回的是它的子类对象，比如 Cpu0SEFrameLowering。

##### (3) Cpu0SEFrameLowering.h/.cpp

继承自 `Cpu0FrameLowering` 类实现了 `Cpu0SEFrameLowering` 类，SE 的意思是 stardand edition，在 Mips 里边表示 32 位版本，我们目前的 Cpu0 只有 32 位版本，不过后端还是做了区分，有利于将来再扩展其他版本的后端，比如 16 位 Cpu0。

留了 emitPrologue 和 emitEpilogue 函数的坑，这两个函数在 Frame Lowering 中很重要，用来在进入函数前和从函数返回时插入内容。后边章节会补充这块内容。

##### (4) Cpu0InstrInfo.h/.cpp

这是指令相关的代码，用来基于 tablegen 生成的指令描述完成和指令相关的动作，所以它包含 Cpu0GenInstrInfo.inc。定义了 `Cpu0InstrInfo` 类，继承自 `Cpu0GenInstrInfo`，基类就是由  tablegen 生成的类结构。因为 tablegen 的功能并不够那么灵活（至少不如 C++ 灵活），所以有一些情况需要在 C++ 代码中处理。类里边目前还没有实质性的内容。

其中有个成员是 Subtarget 对象，在构造函数中初始化。反复强调 Subtarget 的原因是，它是所有类结构中占据比较中心的位置。

##### (5) Cpu0SEInstrInfo.h/.cpp

基于 `Cpu0InstrInfo` 类定义的派生类 `Cpu0SEInstrInfo` ，目前也没有什么重要内容。只做了工厂函数。

##### (6) Cpu0ISelLowering.h/.cpp

关于指令选择的功能实现，继承自 `TargetLowering` 定义了 `Cpu0TargetLowering`。

包含了 Cpu0GenCallingConv.inc 文件，该文件由 Cpu0CallingConv.td 文件生成，用到了它里边定义的一些类型。

其中挖了 LowerGlobalAddress的坑，将来会补；LowerRet() 方法返回 Ret 这个 ISDNode。

create() 方法用来生成对象，实际返回的是它的子类对象，比如 Cpu0SEISelLowering。

##### (7) Cpu0SEISelLowering.h/.cpp

定义 `Cpu0SEISelLowering` 类，继承自 `Cpu0ISelLowering` 类。暂没有实质的内容。

##### (8) Cpu0MachineFunctionInfo.h/.cpp

用来处理和函数有关的动作。继承 `MachineFunctionInfo` 类定义 `Cpu0MachineFunctionInfo`类。声明了与参数有关的方法，不过目前都先挖坑，后续补。

##### (9) MCTargetDesc/Cpu0ABIInfo.h/.cpp

定义 ABI 的信息，提供了 O32、S32 和未知三种 ABI 规范。

这套文件在其他一些后端里是没有的，这里参考 Mips 后端的规范和设计，就一并给加上了。

##### (10) Cpu0RegisterInfo.h/.cpp

包含有 Cpu0GenRegisterInfo.inc 文件，基于 `Cpu0GenRegisterInfo` 类定义了 `Cpu0RegisterInfo` 方法。定义了几个和寄存器有关的方法。大多数方法的定义暂时先挖坑。

##### (11) Cpu0SERegisterInfo.h/.cpp

基于 `Cpu0RegisterInfo` 定义的一个子类 `Cpu0SERegisterInfo`。暂时没有啥东西。

##### (12) Cpu0Subtarget.h/.cpp

比较重要的一个类，继承自 `Cpu0GenSubtargetInfo` 定义了 `Cpu0Subtarget`。我们的 Cpu0SubtargetInfo.td 中本身已经定义了和子目标平台相关的信息，这里做的工作并不多，就是维护了一些属性，并建立与其他类之间的调用接口，诸如 getInstrInfo()，getRegisterInfo() 等，同时在其构造函数中，也会初始化这些对象。

##### (13) Cpu0TargetObjectFile.h/.cpp

这块代码实现了一个类 `Cpu0TargetObjectFile`，继承自 `TargetLoweringObjectFileELF`，里边会定义有关于 ELF 文件格式的一些属性和初始化函数。

其中有个点，设计了 .sdata 段和 .sbss 段，这两个段和 .data .bss 段表示一样的功能，但更节省 ELF 文件占用内存，我们会在后续章节再次提到。Initialize 暂时用不到。

##### (14) Cpu0CallingConv.td

这是调用规约的一些说明，定义了 CSR_032 这个 Callee 寄存器。

##### (15) Cpu0InstrInfo.td

新增了很少量的东西，Cmp 和 Slt 的 Predicate 条目定义，将来会用。

##### (16) Cpu0.td 

作为 tablegen 的入口，它将我们新增的那些 td 文件都 include 进来。另外，新增了几个目标机器的 Feature：FeatureCmp，FeatureSlt，FeatureCpu032I，FeatureCpu032II。另外定义了 subtarget 的条目，也就是 cpu032I 和 cpu032II，还基于 td 中的 Target 类定义了 Cpu0 条目。

##### (17) CMakeLists.txt 和 MCTargetDesc/CMakeLists.txt

因为新增了源文件，所以这两个 cmake 配置也要做一下修改。



#### 2.1.2 简要说明

整个类结构中，Cpu0Subtarget 承担着接口的作用，它提供了访问其他类的接口：Cpu0FrameLowering，Cpu0TargetMachine，Cpu0TargetObjectFile，Cpu0RegisterInfo，Cpu0InstrInfo 等。其他这几个类，都携带有 Cpu0Subtarget 的属性。即使你的一个类无法通过标准方式访问其他类，比如没有 Cpu0Subtarget 属性，也可以通过访问 Cpu0TargetMachine 来获取一个 Subtarget （利用 getSubtargetImpl() 方法）。

Tablegen 在这里的作用就很明显了，它通过我们编写的 td 文件，将其翻译为 C++ 的类结构和一些宏、枚举等材料，然后我们在 C++ 代码中就可以灵活的使用这些材料。LLVM 设计 Tablegen 的目的就是将这些目标相关的属性尽量的隔离在 td 文件中，虽然目前还没有完全做到，但已经隔离了很大的一部分（虽然 td 文件的管理也很混乱，但确实有效）。



#### 2.1.3 编译测试

需要重新编译，因为我们修改了很多东西，且更新了 cmake 配置文件。

```shell
$ ninja clean
$ cmake -G Ninja -DLLVM_TARGETS_TO_BUILD=Cpu0 -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang ../llvm
$ ninja
```

编译时，很可能会遇到问题，按 C++ 的语法规则解决就行，我们目前还不会遇到编译器的问题。



#### 2.1.4 检验成果

输入：

```shell
$ build/bin/llc -march=cpu0 -mcpu=help
```

终端会输出 Cpu0 后端和其支持的特性。-mcpu 是用来指定 cpu 类型的（这里的 cpu 是广义的，即使你在做 gpu，也是这个参数，他表示架构之下那一层的分类），它可以控制到 Cpu0Subtarget.h 中的属性 isCpu032I 和 isCpu032II，进而会影响到特性的使能，比如 HasSlt 的返回值。

目前，我们能指定的是 cpu032I 和 cpu032II，不指定这个参数默认是 cpu032II，这是在 Cpu0Subtarget.cpp 中设置的。

输入：

```shell
$ build/bin/clang -target mips-unknown-linux-gnu -c ch2.c -emit-llvm -o ch2.bc
$ build/bin/llc -march=cpu0 -relocation-model=pic -filetype=asm ch2.bc -o ch2.s
```

你会收到一个新的错误：

```bash
Assertion `AsmInfo && "MCAsmInfo not initialized. "
```

这就表示这块已经完成了，我们还没有做汇编输出的动作，下一节中将会增加。

### 2.2 增加 AsmPrinter
这一部分，我们要将 AsmPrinter 支持起来，它在 LLVM 后端中的位置在 CodeGen 中比较重要。
首先我们看一下新增或修改的文件。

#### 2.2.1 文件新增
##### (1) InstPrinter/Cpu0InstPrinter.h/.cpp
我们新增了一个 InstPrinter 文件夹，存放一些 InstPrinter 相关的文件。
Cpu0InstPrinter 这两个文件主要是完成将 MCInst 输出到汇编文件的工作。定义了 Cpu0InstPrinter 这个类，继承自 MCInstPrinter。类中一个比较重要的成员函数，printInstruction() 是由 tblgen 工具根据 Cpu0InstrInfo.td 生成的，另一个自动生成的成员函数是 getRegisterName()，是根据 Cpu0RegisterInfo.td 文件生成的，两个函数都位于 Cpu0GenAsmWriter.inc 文件中。内部的函数 printRegName() ，printInst() ，printOperand()，printUnsignedImm()，printMemOperand()， 均调用前两个函数完成指令的输出。

##### (2) InstPrinter/CMakeLists.txt, InstPrinter/LLVMBuild.txt
因为新增了 InstPrinter 子路径，所以为这个子路径增加编译支持文件。

##### (3) Cpu0MCInstLower.h/.cpp
从名字上可以看出，这两个文件是用来完成将 MI 指令 lower 到 MCInst 指令的工作。
定义了 Cpu0MCInstLower 类，主要的成员函数是 Lower()，它输入一个 MI，输出一个 MCInst，内部处理比较简单，因为我们知道，两种形式相比，MCInst 只是更为底层，所以它大致只需要忽略掉 MI 的一些信息即可。这里主要是设置 Opcode 和 Operand list。

##### (4) MCTargetDesc/Cpu0BaseInfo.h
这个文件中定义了一些宏，将用在 MC 的其他位置。包括操作数标签的 TOF（Target Operand Flag）和指令编码类型。

##### (5) Cpu0MCAsmInfo.h/.cpp
上一节报错中说明要依赖的文件。这两个文件定义了 Cpu0MCAsmInfo 类，继承自 MCAsmInfoELF。其中没啥内容，定义了一些汇编文件格式通用的东西。

##### (6) Cpu0AsmPrinter.h/.cpp
用来将 MI 结构的程序输出到汇编文件的直接入口。
定义了 Cpu0AsmPrinter 类，继承自 AsmPrinter。声明了很多 Emit 函数，各自负责发射对应的内容，比如 EmitInstruction()。
和前边 Cpu0InstPrinter 的区别是，前者是将 MCInst 输出到文件，而 AsmPrinter 是将 MI 发射到文件，在这些 Emit 函数内部，也是先将 MI lower 到 MCInst 之后，再通过 Streamer 发射，而 Streamer 内部也会调用到 MCInst 的 printer 接口。
因为 MI 承载的信息本身就更多，所以值得处理的内容也多一些。另外，汇编文件除了指令本身以外，还会有其他的信息，比如调试信息，文件描述信息等，这些都是在 AsmPrinter 中来发射的。

#### 2.2.2 文件修改
##### (1) Cpu0InstrInfo.td
新增了几个 record。对于内存操作数，若指定 `let PrintMethod = "printMemOperand"`，则 tablegen 会在处理这个 record 时，调用 printMemOperand() 函数。这是本节中比较关键的一个注意点。

##### (2) MCTargetDesc/Cpu0MCTargetDesc.h/.cpp
MC 层的目标描述类中，我们需要为新加的几个MC 处理的类结构做注册工作，添加了不少代码。没有什么要说的，创建对应的对象，通过 TargetRegistry 提供的接口返回去。
一定要分得清 MC 层的东西有啥，他们的大多数描述性的文件都位于 MCTargetDesc 路径下，比如描述指令的 MCInstrInfo，描述寄存器的 MCRegisterInfo，描述指令输出的 MCInstPrinter 等。

##### (3) MCTargetDesc/CMakeLists.txt, MCTargetDesc/LLVMBuild.txt
路径下新增了文件，将它们添加到构建描述文件中。

##### (4) Cpu0ISelLowering.cpp
在构造函数中增加了一个操作，computeRegisterProperties()，这是必需的，用来分析寄存器标记的属性，它实现的位置在 TargetLoweringBase.cpp 文件中，是 TargetLoweringBase 类的方法，不需要我们太关心。

##### (5) Cpu0MachineFunction.h
在构造函数中增加发射 NOAT 的 flag。

##### (6) CMakeLists.txt, LLVMBuild.txt
将新增加的文件和路径加入到构建描述文件中。

#### 2.2.3 简要说明
这一小节比较重要的是 TargetDesc 中的注册部分和 AsmPrinter 的汇编文件输出部分，它们也确实占用了比较大的代码篇幅，不过逻辑上都比较清晰。AsmPrinter 最终输出内容时，是托管给了 Streamer 对象，其实 MCStreamer 结构是非常重要的部分，但因为它已经在 LLVM 公共代码中实现地比较完整，所以不需要我们太关心。最底层的输出便是 MCStreamer，所以最底层的发射其实是 Streamer->Emitxx()。
很多比较细节的东西，其实都是从其他后端参考过来的，尤其是 Mips 后端，前人走过的路，我们便可以放心的去走。

#### 2.2.4 编译测试

需要重新编译，因为我们修改了很多东西，且更新了 cmake 配置文件。

```shell
$ ninja clean
$ cmake -G Ninja -DLLVM_TARGETS_TO_BUILD=Cpu0 -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang ../llvm
$ ninja
```

编译时，很可能会遇到问题，按 C++ 的语法规则解决就行，我们目前还不会遇到编译器的问题。

#### 2.2.5 检验成果

输入：

```shell
$ build/bin/llc -march=cpu0 -relocation-model=pic -filetype=asm ch2.bc -o ch2.cpu0.s
```

你会收到一个新的错误：

```bash
llc: target does not support generation of this file type!
```

这样的话，这部分就结束了。我们实现了较为靠后的一些功能，但其实在前边的功能还不完整。



### 2.3 增加 DAGToDAGISel

AsmPrinter 支持之后，已经可以将 Machine DAG 转成 asm 了，但我们现在还缺少将 LLVM IR DAG 转换成 Machine DAG 的功能，也就是指令选择的部分功能，在 LLVM 机器无关的目标代码生成中，执行选择占据了非常重要的地位。

指令选择的目的就是，把 DAG 中所有的 Node 都转换成目标相关的 Node，虽然在 Lowering LLVM IR 到 DAG 时，我们已经将部分 Node 转换了，但并不是所有，经过这个 pass 之后，所有的 Node 就都是目标机器支持的操作了。

但实际上需要我们做的工作并不是指令选择的功能，这些功能已经被 LLVM 实现了（感兴趣可以看看 `lib/CodeGen/SelectionDAG/SelectionDAGISel.cpp` 中的实现），我们只需要继承已有实现，并将我们的指令系统支持进去（通过 tablegen）即可。这也便是 LLVM 模块化设计下的优势。

先来看看本节新增的文件：

#### 2.3.1 文件新增

##### (1) Cpu0ISelDAGToDAG.h/.cpp

这两个文件定义了 Cpu0DAGToDAGISel 类，继承自 SelectionDAGISel 类，并包含有一些全局化的接口，比如 Select 是指令选择的入口，其中会调用 trySelect 方法，后者是提供给子类的自定义部分指令选择方式的入口，可以先不管。在 Select 函数前边部分都没有选择成功的指令，会最后到 SelectCode 函数，这个函数是由 tablegen 依据 td 文件生成的 Cpu0GenDAGISel.inc 文件中定义的。

虽然 LLVM 的最终目标是让所有和平台相关的信息全部用 td 文件来描述，但目前还没有完全做到（毕竟不同的硬件差异还是挺大的，有些如 X86 的硬件设计还很复杂），所以这些无法用 td 描述的指令选择操作就可以放在这部分 cpp 代码中完成。

还有个 SelectAddr 函数，顾名思义是做关于地址模式的执行选择的，我们知道 IR DAG 中有些 Node 是地址操作数，这些 Node 可以很复杂，目前 Cpu0 把这块代码提出来特殊对待了。我们打开 Cpu0InstrInfo.td 中对 addr 记录的描述，就可以发现，之前已经在这里注册了一个处理函数名称，就叫 SelectAddr，实际上在 tablegen 指令选择时，也会对经由 addr 记录来描述的那些记录（显然会是一些地址 pattern），交给 SelectAddr 函数来处理。

getImm 函数是将一个指定的立即数切入到一个目标支持的 Node 中。

##### (2) Cpu0SEISelDAGToDAG.h/.cpp

这两个文件定义了 Cpu0SEDAGToDAGISel 类，继承自 Cpu0DAGToDAGISel 类，这种双层设计，我们在前边已经描述过了。在这个底层的 SE 类中，实现了 trySelect 类，这个类目前还没有实现什么实质性的内容。目的就是将来留着处理 tablegen 无法自动处理的那些指令的指令选择。

另外还实现了 createCpu0SEISelDAG 函数，用来做 Target 注册。



#### 2.3.2 文件修改

##### (1) Cpu0TargetMachine.cpp

注册一个指令选择器。目前是将 Cpu0SEISelDAG 添加进来。addInstSelector 方法重写了父类 TargetPassConfig 的方法。

##### (2) CMakeLists.txt

因为新增了文件，所以修改这个文件保证编译顺利。



#### 2.3.3 简要说明

目前我们的目标是把整个后端打通，所以没有操刀 td 文件，我们的 td 文件现在还很简单，但足够去跑我们那个很简单的 testcase 了，将来添加其他指令也会是很顺利的事情。

将来随着支持的指令越来越多，尤其是一些复杂指令的支持，cpp 代码中 trySelect 会增加一些手动处理的指令选择代码，这是目前无法避免的问题。

#### 2.2.4 编译测试

```shell
$ ninja clean
$ cmake -G Ninja -DLLVM_TARGETS_TO_BUILD=Cpu0 -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang ../llvm
$ ninja
```

实际上不去手动 `ninja clean`，也可以编译，ninja 会自动检查 CMakeLists 是否被修改了，如果修改则重新编译。

#### 2.2.5 检验成果

输入：

```shell
$ build/bin/llc -march=cpu0 -relocation-model=pic -filetype=asm ch2.bc -o ch2.cpu0.s
```

你会收到一个新的错误：

```bash
LLVM ERROR: Cannot select: t6: ch = Cpu0ISD::Ret t4, Register:i32 $lr
  t5: i32 = Register $lr
In function: main
```

Ret 指令选择卡住了。我们在之前的 Cpu0ISelLowering.cpp 中已经设计了 Cpu0ISD::Ret 节点，在 ISelLowering 中也留下了 LowerReturn 的实现函数，但现在还没有完整实现对它的处理。



### 2.4 处理返回寄存器 $lr

Mips 后端通过 `jr $ra` 来返回到调用者，`$ra` 是一个特殊寄存器，它用来保存调用者（caller）的调用之后的下一条指令的地址，返回值会放到 `$2` 中。如果我们不对返回值做特殊处理，LLVM 会使用任意一个寄存器来存放返回值，这便与 Mips 的调用惯例不符。而且，LLVM 会为 `jr` 指令分配任意一个寄存器来存放返回地址。Mips 允许程序员使用其他寄存器代替 `$ra`，比如 `jr $1`，这样可以实现更加灵活的编程方式，节省时间。

#### 2.4.1 文件新增

无。

#### 2.4.2 文件修改

##### (1) Cpu0CallingConv.td

新增有关于返回的调用约定，增加`RetCC_Cpu0` ，指定将 32 位整形返回值放到 V0、V1、A0、A1 这几个寄存器中。

##### (2) Cpu0InstrFormats.td

新增 `Cpu0Pseudo` 的 Pattern，下边会用到。

##### (3) Cpu0InstrInfo.td

利用刚才的伪指令 Pattern，定义新的 record，`RetLR`，它指定的 SDNode 是 `Cpu0Ret`，后者是我们之前定义好的。

##### (4) Cpu0ISelLowering.h/.cpp

我们新增了一些调用约定的分析函数，关键函数是 analyzeReturn()。该函数中利用了前边调用约定中定义的 `RetCC_Cpu0` 来分析返回值类型、值等信息，阻断不合法的情况。

其次，很重要的一个函数就是 `LowerReturn()`，该函数在早期将 ISD 的 ret 下降成 Cpu0ISD::Ret 节点。我们之前的实现是一句很简单的做法，也就是会忽略返回时的特殊约定，现在重新设计了这块的逻辑，也就是总生成 `ret $lr` 指令。

##### (5) Cpu0MachineFunctionInfo.h

增加了几个和返回寄存器、参数相关的辅助函数。

##### (6) Cpu0SEInstrInfo.h/.cpp

增加伪指令展开部分的内容，也就是展开返回指令，选择 `$lr` 寄存器作为返回地址寄存器，选择 `Cpu0::RET` 作为指令。

#### 2.4.3 简要说明

这一部分，我们处理了函数调用时返回的操作，主要就是对针对 Cpu0 的特殊调用约定下的返回指令做约束，比如返回地址使用 `$lr` 来存储，返回值保存在特殊的寄存器中。

函数 LowerReturn 正确处理了 return 的情况，上一节结尾的错误就是因此而来。函数创建了 `Cpu0ISD::Ret` 节点，并且里边包含了 `%V0` 寄存器的相关关系，这个寄存器保存了返回值，如果不这样做，在 Lower Ret 时，使用 `$lr` 寄存器，所以看起来 `%V0` 寄存器没有用了，进而后边的优化阶段会把这个 CopyToReg 的 Node 给删掉，结果就导致了错误。

#### 2.4.4 检验成果

正常编译工程，不再赘述。
编译之后，进行测试：

```shell
build/bin/clang -target mips-unknown-linux-gnu -c ch2.cpp -emit-llvm -o ch2.bc
```
我们看一下 LLVM IR：
```shell
build/bin/llvm-dis ch2.bc -o -
```
输出的结果：
```shell
define i32 @main() #0 {
  %1 = alloca i32, align 4
  store i32 0, i32* %1
  ret i32 0
}
```
生成的指令中有一条 store 指令，这条指令会将局部变量 0 放到栈中，但是我们目前还没有解决栈帧的管理问题，所以如果把这个代码传给后端，会卡在这里（通过 Ctrl-C 退出）。我们可以通过 O2 来编译，O2 会把局部变量放到寄存器中，避免生成 store 指令，从而可以先验证我们 ret 的功能。
```shell
build/bin/clang -O2 -target mips-unknown-linux-gnu -c ch2.cpp -emit-llvm -o ch2.bc
```
看一下 LLVM IR：
```shell
define i32 @main() #0 {
  ret i32 0
}
```
显然，我们能够输出正确的值了。
```shell
build/bin/llc -march=cpu0 -relocation-model=pic -filetype=asm ch2.bc -o -
```
生成的内容直接输出到终端，能看到，已经正常生成了 `ret $lr` 指令。也能看到返回值 0 通过 `addiu $2, $zero, 0` 这条指令放到了寄存器 `$2` 中，`$2` 就是 `%V0`，我们在 Cpu0RegisterInfo.td 中做过定义。
通过指定 `-print-before-all` 和 `-print-after-all` 参数到 llc，可以打印出 DAG 指令选择前后的状态：
```shell
build/bin/llc -march=cpu0 -relocation-model=pic -filetype=asm -print-before-all -print-after-all ch2.bc -o -
```
其中显示，分别将 `Cpu0ISD::Ret t3, Register::i32 %V0, t3:1` 指令选择到 `RetLR Register:i32 %V0, t3, t3:1`，将 `t1: i32 = Constant<0>` 指令选择到 `t1: i32 = ADDiu Register:i32 %ZERO, TargetConstant:i32<0>`。注意到，RetLR 后续还会做伪指令展开为 `ret $lr`，并隐式使用了 `%V0`（寄存器分配之后，就不用担心 `%V0` 被删掉了，所以可以改成隐式依赖了）。

两条指令从 LLVM IR 到汇编的路径是：

| LLVM IR     | Lower        | ISel              | RVR（重写虚拟寄存器） | Post-RA （寄存器分配之后） | Asm   |
| ----------- | ------------ | ----------------- | --------------------- | -------------------------- | ----- |
| constant  0 | constant 0   | ADDiu             | ADDiu                 | ADDiu                      | addiu |
| ret         | Cpu0ISD::Ret | CopyToReg + RetLR | RetLR                 | RET                        | ret   |

之所以做 CopyToReg 的原因是，ret 指令不能接受一个立即数作为操作数。它通过在 Cpu0InstrInfo.td 中的定义来完成：

```python
def : Pat<i32 immSExt16:$in), (ADDiu ZERO, imm:$in)>;
```

接下来就来处理一下稍微比较复杂的栈帧的管理问题。