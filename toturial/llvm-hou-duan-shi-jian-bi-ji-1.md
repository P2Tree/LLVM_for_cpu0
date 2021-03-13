# 第 1 章 新后端初始化和软件编译

## 1 新后端初始化和软件编译

这一章介绍 Cpu0 的硬件配置，以及简单介绍 LLVM 代码的结构和编译方法。然后，我们会搭建起后端的框架，并能让 LLVM build 通过，通过完成一些后端注册的操作，可以让 llc 识别到我们新后端的存在。

### 1.1 Cpu0 处理器架构介绍

（注意：公开的 Cpu0 的设计会发生变化，本节描述仅服务于本教程使用）

#### 1. 基本介绍

* 32 位 RISC 架构；
* 16 个通用寄存器，R0 到 R15；
  * R0 是常数 0 寄存器（CR, Constant Register）；
  * R1-R10 是通用寄存器（GPR, General Purpose Register）；
  * R11 是全局指针寄存器（GP, Global Pointer register）
  * R12 是帧指针寄存器（FP, Frame Pointer register）
  * R13 是栈指针寄存器（SP, Stack Pointer register）
  * R14 是链接寄存器（LR, Link Register）
  * R15 是状态字寄存器（SW, Status Word register）
* 协处理寄存器，PC 和 EPC；
  * PC 是程序计数器（Program Counter）
  * EPC 是错误计数器（Error Program Counter）
* 其他寄存器；
  * IR 是指令寄存器（Instruction Register）
  * MAR 是内存地址寄存器（Memory Address Register）
  * MDR 是内存数据寄存器（Memory Data Register）
  * HI 是 MULT 指令的结果的高位存储（HIgh part）
  * Lo 是 MULT 指令的结果的低位存储（LOw part）

#### 2. 指令集

指令分为 3 类，A 类（Arithmetic 类）：用来做算术运算；L 类（Load/Store 类）：用来访问内存；J 类（Jump 类）：用来改变控制流。三种指令有各自统一的位模式。

* A 型：

  | 操作码编码 OP | 返回寄存器编码 Ra | 输入寄存器编码 Rb | 输入寄存器编码 Rc | 辅助操作编码 Cx |
  | :--- | :--- | :--- | :--- | :--- |
  | 31-24 | 23-20 | 19-16 | 15-12 | 11-0 |

* L 型：

  | 操作码编码 OP | 返回寄存器编码 Ra | 输入寄存器编码 Rb | 辅助操作编码 Cx |
  | :--- | :--- | :--- | :--- |
  | 31-24 | 23-20 | 19-16 | 15-0 |

* J 型：

  | 操作码编码 OP | 辅助操作编码 Cx |
  | :--- | :--- |
  | 31-24 | 23-0 |

具体支持的指令和涵义，我这里暂时先不抄了，感兴趣的朋友可以到：[http://ccckmit.wikidot.com/ocs:cpu0](http://ccckmit.wikidot.com/ocs:cpu0) 查看。

我们这个教程中支持的 Cpu0 架构有两款处理器，所以会对应两款不同的 ISA （Instruction Set），第一套叫 cpu032I，第二套是在第一套的基础上新增了几条指令，叫 cpu032II。cpu032I 中的比较指令继承自 ARM 的 CMP，而 cpu032II 中的比较指令新增了继承自 Mips 的 SLT，BEQ 等指令。设计两套处理器，我们就会涉及到后端 Subtarget 的设计。具体新增了哪些指令，也可以在上边链接中查看。

#### 3. 状态字寄存器

SW 寄存器用来标记一些状态，它的位模式为：

| 保留 | 中断标记 I | 保留 | 模式标记 M | 调试标记 D | 保留 | 溢出标记 V | 进位标记 C | 零标记 Z | 负数标记 N |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 31-14 | 13 | 12-9 | 8-6 | 5 | 4 | 3 | 2 | 1 | 0 |

注意：这个位模式是本文用到的编码模式。上边网址中是另一套描述，和这里不符，以这里为准。cmp 指令主动设置这个寄存器，条件分支指令会参考这里的值作为条件来跳转。

#### 4. 指令流水线

Cpu0 的指令采用 5 级流水线：取指（IF, Instruction Fetch）、解码（ID, Instruction Decode）、执行（EX, EXecute）、内存访问（MEM, MEMory access）、写回（WB, Write Back）。

取指、解码、执行时任何指令都会做的步骤，内存访问是针对 load/store 指令，写回是针对 load。

指令流水线这块，会和调度有关系，Cpu0 的调度策略也很简单。

### 1.2 LLVM 代码结构

这部分内容参考了：[http://llvm.org/docs/GettingStarted.html\#getting-started](http://llvm.org/docs/GettingStarted.html#getting-started)

#### 1. 目录结构

LLVM 的目录中，我挑几个比较重要的介绍一下：

* docs/

  放着一些文档，很多文档在官方上能找到。

* examples/

  存放着一些官方认可的示例，比如有很简单的 Fibonacci 计算器实现，简单的前端案例 Kaleidoscope（这个是有个教程的），介绍 JIT 的 HowToUseJIT。不过这里没有后端的东西。

* include/

  存放 llvm 中作为库的那部分接口代码的 API 头文件。注意不是所有头文件，内部使用的头文件不放在这里。其中我们关心的都在 include/llvm 中，那个 include/llvm-c 我没用到过。

  include/llvm 中，按库的名称来划分子目录，比如 Analysis，CodeGen，Target 等。

* lib/

  存放绝大多数的源码。

  * lib/Analysis

    两个 LLVM IR 核心功能之一，各种程序分析，比如变量活跃性分析等。

  * lib/Transforms

    两个 LLVM IR 核心功能之二，做 IR 到 IR 的程序变换，比如死代码消除，常量传播等。

  * lib/IR

    LLVM IR 实现的核心，比如 LLVM IR 中的一些概念，比如 BasicBlock，会在这里定义。

  * lib/AsmParser

    LLVM 汇编的 parser 实现，注意 LLVM 汇编不是机器汇编。

  * lib/Bitcode

    LLVM 位码 \(bitcode\) 的操作。

  * lib/Target

    目标架构下的所有描述，包括指令集、寄存器、机器调度等等和机器相关的信息。我们的教程主要新增代码都在这个路径下边。这个路径下又会细分不同的后端平台，比如 X86，ARM，我们新增的后端，会在这里新开一个目录 Cpu0。

  * lib/CodeGen

    代码生成库的实现核心。LLVM 官方会把后端分为目标相关的（target dependent）代码和目标无关的（target independent）代码。这里就存放这目标无关的代码，比如指令选择，指令调度，寄存器分配等。这里的代码一般情况下不用动，除非你的后端非常奇葩。

  * lib/MC

    存放与 Machine Code 有关的代码，MC 是后端到挺后边的时候，代码发射时的一种中间表示，也是整个 LLVM 常规编译流程中最后一个中间表示。这里提供的一些类是作为我们 lib/Target/Cpu0 下的类的基类。

  * lib/ExecutionEngine

    解释执行位码文件和 JIT 的一些实现代码。

  另外还有一些目录我就不介绍了，比如 Object 里存放和目标文件相关的信息，Linker 中存放链接器的代码，LTO 中放着和链接时优化有关的代码，TableGen 中存放 TableGen 的实现代码。因为与咱们的开发关系不太大，我也不大熟悉，感兴趣的同学自行查看吧。

* projects/

  刚开始接触 LLVM 时，以为这里是开发的重点，实际并不是。这个路径下会放一些不是 LLVM 架构，但会基于它的库来开发的一些第三方的程序工程。如果你不是在 LLVM 上搭建一个前端或后端或优化，而是基于他们的一部分功能来实现自己的需求，可以把代码放在这里边。

* test/

  LLVM 支持一整套完整的测试，测试工具叫 lit，这个路径下放着各种测试用例。LLVM 的测试用例有一套自己的规范。

* unittests/

  顾名思义，这里放着单元测试的测试用例。

* tools/

  这个目录里边放着各种 LLVM 的工具的源码（也就是驱动那些库的驱动程序），比如做 LLVM IR 汇编的 llvm-as，后端编译器 llc，优化驱动器 opt 等。注意，驱动程序的源码和库的源码是分开的，这是 LLVM 架构的优势，你完全可以说不喜欢 llc，然后自己在这里实现一个驱动来调你的后端。

* utils/

  一些基于 LLVM 源码的工具，这些工具可能比较重要，但不是 LLVM 架构的核心。 里边有个目录用 vim 或 emacs 的朋友一定要看一下，就是 utils/vim 和 utils/emacs，里边有些配置文件，比如自动化 LLVM 格式规范的配置，高亮 TableGen 语法的配置，调一调，开心好几天有没有。

#### 2. 如何编译

LLVM 的源码下载可以看着官方文档来。

LLVM 的工程是使用 cmake 来管理的，cmake 会检查 build 所需的环境条件，并生成 Makefile 或其他编译配置文件。对于第一次编译 LLVM 的同学，一定会在这里遇到问题，如果你没有动过代码，那么 100% 是因为你的环境有问题。

拉下来后先创建一个 build 目录，我习惯在 llvm 的同一级创建，比如这样：

```text
~/llvm
|--- build
|--- llvm
    |--- lib
    |--- tools
    ...
```

然后，进入 build 目录，输入：

```bash
cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug ../llvm
```

最后一个参数是 build 相对你的 llvm 工程文件的相对路径。

`-G` 后边的那个配置是指定 cmake 生成哪种编译配置文件，比如 `"Unix Makfile"` 就是 make 使用的，还可以指定 `Ninja` 或 `Xcode`，它会对应生成 ninja 的编译文件或 xcode 的编译文件。我喜欢用 ninja，编译输出更清晰，但后两个需要你有环境，比如自己安装 ninja 软件或 xcode，而 make 在 Linux 机器和 Mac 机器上是自带的。下文中涉及到编译时，我会使用 ninja，当然这些都不重要。

cmake 还可以指定其他参数，比如：`-DLLVM_TARGETS_TO_BUILD=Cpu0`，这个表示只编译 Cpu0 后端，这样编译会快一些，毕竟 LLVM 的后端太多了，都编译没必要（不过我们还没实现 Cpu0 的后端，如果你不希望编译时炸出一堆错误，目前还是不要加这个参数了）。`-DCMAKE_BUILD_TYPE=Debug`可以改成 Release，编译会快一些，但如果需要调试编译器的话，还是需要使用 Debug 模式。

指定 `-DMAKE_INSTALL_PREFIX=path`可以指定安装路径，也就是 `make install` 时输出的位置。我一般不指定这个参数，主要是觉得没必要，我直接从 build/bin 下边拿编好程序。

cmake 时可能会出问题，导致失败，只要你最后没看到 configuring done，那就表示失败了，看上边的输出来具体解决，可能是系统里缺少一些库或工具。

没问题之后就可以编译了，输入 `make` 或 `ninja` 或 `xcodebuild`。第一次编译会比较耗时间，取决于你的机器性能，通常来说你可以去上个厕所或买个下午茶了，友情提示，如果自己改过代码，就不要那么浪了。之后如果不涉及 CMake 配置变更，可以使用增量编译，通常会快很多。

注意：MacOS 的朋友请注意，在测试你的编译器时，把环境变量搞对，不要调用到系统自带的编译器（系统的编译器和你的编译器都叫 clang）。

### 1.3 Cpu0 后端初始化

#### 1. TableGen 描述文件

实现一个后端，我们需要编写和目标相关的描述文件，也就是 .td 文件，这些 .td 文件，会在build 编译器时，由 TableGen 的工具 llvm-tblgen 翻译成 C++ 源码，这些源码就可以被我们的代码中使用了。.td 文件在被处理之后，会在 build 路径下的 `lib/Target/Cpu0/` 下，生成一些 .inc 文件，而这些文件就可以被我们的代码所 include。生成的规范是我们在 CMakeLists.txt 中明确的。

实际上的逻辑是，我们在写 .td 文件时，就应当明白 .td 文件生成的 C++ 源码是什么样子的，然后在我们的代码中直接使用这些还没有生成的代码，静态检查可能会过不去，但没关系，build 编译器时，TableGen 是首先被调用了，编译是能过的（只要你 .td 没错）。另外最怕的一点是，你的 .td 没语法错误，但有逻辑错误，调试会比较困难。

.td 文件会有多个，分门别类的来描述目标平台的各种信息，比如寄存器信息、指令信息、调度信息等。

它的语法我就不再介绍了，需要了解的同学可以看我的其他文章。

我们来看一下代码吧。

本章编写的所有代码我均放到了 `shortcut/llvm\_ch1/` 中，可以按目录查看，后续章节的代码也是同理。

第一个文件是 `Cpu0.td`。这个文件，目前就是包含了其他几个 .td 文件，然后定义了一个基于 Target 类的子类 Cpu0。

第二个文件是 `Cpu0InstrFormats.td`。这个文件，描述了指令集的一些公共属性，一些高层的、互通的格式说明，比如 Cpu0 的指令最高层的类 `Cpu0Inst`，继承自 `Instruction` 类。另外还有因为 Cpu0 的指令分为三类：A、L、J，所以会基于 Cpu0Inst 再延生出三个子类 FA、FL、FJ。Instruction 类中的一个属性，叫 Format，我们做了一层包装，给不同的子类指令指定了值。

第三个文件是 `Cpu0InstrInfo.td`。可以看到，这个文件里 include 了 Cpu0InstrFormats.td，所以实际上两个文件可以写在一起，但大家的公认做法是适当分开。这个文件里，会有一些 SDNode 节点的定义，比如 `Cpu0Ret`，还有操作数类型定义，比如 `simm16`，还有最多的是指令的定义，这些指令，同样会做不同的 class，最后基于这些 class 来定义具体的指令模式。值得留意的是，其中会有一个参数叫 pseudo，默认是 0，这个参数指明要定义的指令是否是一个伪指令，在 build 编译器之后，会发现生成了一个 `Cpu0GenMCPseudoLowering.inc` 文件，目前这个文件里还没啥实质的东西，因为我们还没涉及到伪指令。

第四个文件是 `Cpu0RegisterInfo.td`。这个文件中定义了所有的寄存器和寄存器集合（RegisterClass）。一个基本类 `Cpu0Reg` 继承自 `Register`，而后衍生出 `Cpu0GPRReg` 和 `Cpu0C0Reg`。我们特别定义了一个寄存器组 `GPROut`，表示除 SW 寄存器以外的寄存器，因为 SW 寄存器不参与寄存器分配，所以这样划分易于使用。能注意到，这些寄存器都是有别名的。

第五个文件是 `Cpu0Schedule.td`。定义了一些调度方式，它们基于一个类 `InstrItinClass`，通常简写叫 IIC，这些调度信息会在其他位置被用到。

在这些文件中，我们会遇到一个 namespace 的变量或属性，都被指定为 Cpu0，在最后生成的代码中，它就对应着 C++ 中的 namespace 的概念，比如 ZERO 寄存器属于 namespace = Cpu0，那么我们最后使用这个寄存器，就需要指明 `Cpu0::ZERO`。

以上就是目前涉及到的 .td 文件，我按最简单的方式来编写这几个文件，注释中明显分块。目前，我们还没有完整的把这些 .td 文件写完，为了能尽快看到一个能编译通过的版本，我们只搭框架。在后续的几章中，这些文件的内容还会被反复修改。

#### 2. 目标注册

这一部分，我们会修改一些公共代码，把我们要编写的 Cpu0 注册到 LLVM 架构中，让 LLVM 知道我们新增了一个后端。

在 Cpu0 的路径下，先创建一个 `Cpu0.h` 的文件，做了一些包含操作。然后创建 `Cpu0TargetMachine.cpp` 文件和对应头文件，里边只写了一个 `LLVMInitializeCpu0Target()` 的函数，并且暂时没有内容，我们目前还是只搭框架。

然后，创建一个子目录 `lib/Target/Cpu0/TargetInfo/`，在这个路径下新建 `Cpu0TargetInfo.cpp`，这个文件中，我们调用了 `RegisterTarget` 接口来注册我们的目标，需要做两次注册，分别完成 cpu0 和 cpu0el 的注册。

还需要创建一个子目录 `lib/Target/Cpu0MCTargetDesc.cpp` 文件和其对应的头文件，这里写了一个 `LLVMInitializeCpu0TargetMC()` 的函数，也暂时留空。

放这两个额外的子目录，在其他后端中也同样这么做，究其原因，是每个后端都会提供多个库，我们的 Cpu0/ 路径下会生成一个叫 libLLVMCpu0CodeGen.a 的库，而这两个子目录会生成 libLLVMCpu0Desc.a 和 libLLVMCpu0Info.a 这两个库，关于库的生成控制是在 CMakeLists.txt 中完成的。

以上工作做完之后，我们需要对公共代码进行修改。

需要修改的文件有：

* `lib/Object/ELF.cpp`
* `lib/Support/Triple.cpp`
* `include/llvm/ADT/Triple.cpp`
* `include/llvm/BinaryFormat/ELF.h`
* `include/llvm/Object/ELFObjectFile.h`

新增一个文件：`include/llvm/BinaryFormat/ELFRelocs/Cpu0.def`

可以暂时不管它们是做什么用的，先按着其他后端的位置，把我们的 Cpu0 后端补上去就可以了。

#### 3. 构建文件

我们需要编写一些 cmake 文件 和 LLVMBuild 文件，前者是 cmake 执行时需要查找的，后者是 LLVM 构建时辅助的描述文件。每个路径下都需要有这两个文件，所以我们需要在 `lib/Target/Cpu0/`，`lib/Target/Cpu0/TargetInfo/`，和 `lib/Target/Cpu0/MCTargetDesc/` 路径下都扔一个 `CMakeLists.txt` 文件和一个 `LLVMBuild.txt` 文件。

有关于 LLVMBuild.txt 的参考资料可以见这篇文章：[http://llvm.org/docs/LLVMBuild.html](http://llvm.org/docs/LLVMBuild.html)

#### 4. 检验成果

接下来就可以 build 编译器了。

进入到 build 路径下，输入：

```bash
cmake -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang -DCMAKE_BUILD_TYPE=Debug -G "Ninja" ../llvm
```

一切正常后，输入：

```bash
ninja
```

看看会出什么错误，很可能会出问题，并且暴露信息也会很清晰，检查我们的代码并做修改，直到全部正确编译。

找到我们的 llc，它通常在编译好的目录的 bin 路径下，输入：

```bash
build/bin/llc --version
```

如果正常的话，会输出 llc 的各种信息，其中包括它支持的后端名称，其中就可以找到我们的后端 cpu0、cpu0el。这里的 cpu0 的 c 是小写，这是因为我们 `Cpu0/TargetInfo/Cpu0TargetInfo.cpp` 中注册目标平台时的一个参数，指定了输出的名称，是小写的 cpu0、cpu0el。

之后，我们就可以只针对我们的后端平台做编译了，编译会更快一些，比如 cmake 命令参数可改为：

```bash
cmake -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang -DCMAKE_BUILD_TYPE=Debug -DLLVM_TARGETS_TO_BUILD=Cpu0 -G "Ninja" ../llvm
```

在 `build/lib/Target/Cpu0/` 路径下，你会发现很多 .inc 文件，这些文件就是由我们的 .td 文件生成的 C++ 代码。

编写一个空的 main 函数的 C 代码，拿我们的编译器来编译一下。

测试代码：

```cpp
// filename: ch1.c
int main() {
  return 0;
}
```

我们的 clang 用着标准的那一套，所以不用操心它，不过我们的 cpu0 后端没有自己的 ABI，于是使用了 Mips 的 ABI，输入：

```bash
build/bin/clang -target mips-unknown-linux-gnu -c ch1.c -emit-llvm -o ch1.bc
```

`-emit-llvm` 参数指示 clang 在 LLVM IR 的地方停下来，输出 IR。执行之后会生成一个 ch1.bc，这是 LLVM IR 的位码文件。

输入：

```bash
build/bin/llvm-dis ch1.bc -o -
```

llvm-dis 是 LLVM IR 的反汇编器，它将位码文件反汇编成可读的 LLVM 汇编，因为指定 `-o -`，它将结果直接输出在终端。检查 LLVM 汇编，并与我们的源程序作对比。

输入：

```bash
build/bin/llc -march=cpu0 -relocation-model=pic -filetype=asm ch1.bc -o ch1.s
```

这里报错了，提示：

```bash
Assertion 'target.get() && "Could not allocate target machine!"' failed
```

一个 assert 阻止了异常操作。这里报错是正常的，毕竟我们后端啥都没做呢，没那么轻松就能生成汇编，看到这个提示，这一章的验证就结束了。在下一章，我们会解决这个问题，并能正常输出简单程序的汇编文件。

