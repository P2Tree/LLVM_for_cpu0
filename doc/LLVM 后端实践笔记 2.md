# LLVM 后端实践笔记

## 2 后端结构

### 2.1 目标机器架构

这一部分代码比较多，主要有以下一些文件，实际内容请参考我提供的代码。

### 1. 文件新增

#### (1) Cpu0TargetMachine.h/.cpp

这是有关于目标机器的定义，实现了 `Cpu0TargetMachine`，`Cpu0ebTargetMachine`，`Cpu0elTargetMachine` 三个类，后两个类继承第一个类，而第一个类继承自 `LLVMTargetMachine`。其中定义了有关于目标的初始化工作，比如拼装 DataLayout，重定位模式，大小端，核心目的就是生成 TargetMachine 的对象，LLVM 会用。

其中有个函数 getSubtargetImpl()，这个函数可以构造 Subtarget 对象，进而能引用到 Subtarget 的属性和方法。

#### (2) Cpu0FrameLowering.h/.cpp

这是 Frame Lowering 的功能实现，完成栈的管理。基于 `TargetFrameLowering` 实现了 `Cpu0FrameLowering` 类，本身没有太多东西，重要内容都放到 `Cpu0SEFrameLowering.h/.cpp` 文件中了。

Cpu0 的栈也是向下生长，用栈指针指向栈顶，栈内内容通过栈指针加一个正数的偏移来获取。栈中的内容按顺序从高地址到低地址是：函数参数、GP、自由空间、CPU 的 Callee 寄存器、FP、RA、FPU 的 Callee 寄存器。

hasFP() 方法用来判断函数栈中是否包含 FP。

create() 方法用来创建该类的对象，实际要返回的是它的子类对象，比如 Cpu0SEFrameLowering。

#### (3) Cpu0SEFrameLowering.h/.cpp

继承自 `Cpu0FrameLowering` 类实现了 `Cpu0SEFrameLowering` 类，SE 的意思是 stardand edition，在 Mips 里边表示 32 位版本，我们目前的 Cpu0 只有 32 位版本，不过后端还是做了区分，有利于将来再扩展其他版本的后端，比如 16 位 Cpu0。

留了 emitPrologue 和 emitEpilogue 函数的坑，这两个函数在 Frame Lowering 中很重要，用来在进入函数前和从函数返回时插入内容。后边章节会补充这块内容。

#### (4) Cpu0InstrInfo.h/.cpp

这是指令相关的代码，用来基于 tablegen 生成的指令描述完成和指令相关的动作，所以它包含 Cpu0GenInstrInfo.inc。定义了 `Cpu0InstrInfo` 类，继承自 `Cpu0GenInstrInfo`，基类就是由  tablegen 生成的类结构。因为 tablegen 的功能并不够那么灵活（至少不如 C++ 灵活），所以有一些情况需要在 C++ 代码中处理。类里边目前还没有实质性的内容。

其中有个成员是 Subtarget 对象，在构造函数中初始化。反复强调 Subtarget 的原因是，它是所有类结构中占据比较中心的位置。

#### (5) Cpu0SEInstrInfo.h/.cpp

基于 `Cpu0InstrInfo` 类定义的派生类 `Cpu0SEInstrInfo` ，目前也没有什么重要内容。只做了工厂函数。

#### (6) Cpu0ISelLowering.h/.cpp

关于指令选择的功能实现，继承自 `TargetLowering` 定义了 `Cpu0TargetLowering`。

包含了 Cpu0GenCallingConv.inc 文件，该文件由 Cpu0CallingConv.td 文件生成，用到了它里边定义的一些类型。

其中挖了 LowerGlobalAddress的坑，将来会补；LowerRet() 方法返回 Ret 这个 ISDNode。

create() 方法用来生成对象，实际返回的是它的子类对象，比如 Cpu0SEISelLowering。

#### (7) Cpu0SEISelLowering.h/.cpp

定义 `Cpu0SEISelLowering` 类，继承自 `Cpu0ISelLowering` 类。暂没有实质的内容。

#### (8) Cpu0MachineFunctionInfo.h/.cpp

用来处理和函数有关的动作。继承 `MachineFunctionInfo` 类定义 `Cpu0MachineFunctionInfo`类。声明了与参数有关的方法，不过目前都先挖坑，后续补。

#### (9) MCTargetDesc/Cpu0ABIInfo.h/.cpp

定义 ABI 的信息，提供了 O32、S32 和未知三种 ABI 规范。

这套文件在其他一些后端里是没有的，这里参考 Mips 后端的规范和设计，就一并给加上了。

#### (10) Cpu0RegisterInfo.h/.cpp

包含有 Cpu0GenRegisterInfo.inc 文件，基于 `Cpu0GenRegisterInfo` 类定义了 `Cpu0RegisterInfo` 方法。定义了几个和寄存器有关的方法。大多数方法的定义暂时先挖坑。

#### (11) Cpu0SERegisterInfo.h/.cpp

基于 `Cpu0RegisterInfo` 定义的一个子类 `Cpu0SERegisterInfo`。暂时没有啥东西。

#### (12) Cpu0Subtarget.h/.cpp

比较重要的一个类，继承自 `Cpu0GenSubtargetInfo` 定义了 `Cpu0Subtarget`。我们的 Cpu0SubtargetInfo.td 中本身已经定义了和子目标平台相关的信息，这里做的工作并不多，就是维护了一些属性，并建立与其他类之间的调用接口，诸如 getInstrInfo()，getRegisterInfo() 等，同时在其构造函数中，也会初始化这些对象。

#### (13) Cpu0TargetObjectFile.h/.cpp

这块代码实现了一个类 `Cpu0TargetObjectFile`，继承自 `TargetLoweringObjectFileELF`，里边会定义有关于 ELF 文件格式的一些属性和初始化函数。

其中有个点，设计了 .sdata 段和 .sbss 段，这两个段和 .data .bss 段表示一样的功能，但更节省 ELF 文件占用内存，我们会在后续章节再次提到。Initialize 暂时用不到。

#### (14) Cpu0CallingConv.td

这是调用规约的一些说明，定义了 CSR_032 这个 Callee 寄存器。

#### (15) Cpu0InstrInfo.td

新增了很少量的东西，Cmp 和 Slt 的 Predicate 条目定义，将来会用。

#### (16) Cpu0.td 

作为 tablegen 的入口，它将我们新增的那些 td 文件都 include 进来。另外，新增了几个目标机器的 Feature：FeatureCmp，FeatureSlt，FeatureCpu032I，FeatureCpu032II。另外定义了 subtarget 的条目，也就是 cpu032I 和 cpu032II，还基于 td 中的 Target 类定义了 Cpu0 条目。

#### (17) CMakeLists.txt 和 MCTargetDesc/CMakeLists.txt

因为新增了源文件，所以这两个 cmake 配置也要做一下修改。



### 2. 简要说明

整个类结构中，Cpu0Subtarget 承担着接口的作用，它提供了访问其他类的接口：Cpu0FrameLowering，Cpu0TargetMachine，Cpu0TargetObjectFile，Cpu0RegisterInfo，Cpu0InstrInfo 等。其他这几个类，都携带有 Cpu0Subtarget 的属性。即使你的一个类无法通过标准方式访问其他类，比如没有 Cpu0Subtarget 属性，也可以通过访问 Cpu0TargetMachine 来获取一个 Subtarget （利用 getSubtargetImpl() 方法）。

Tablegen 在这里的作用就很明显了，它通过我们编写的 td 文件，将其翻译为 C++ 的类结构和一些宏、枚举等材料，然后我们在 C++ 代码中就可以灵活的使用这些材料。LLVM 设计 Tablegen 的目的就是将这些目标相关的属性尽量的隔离在 td 文件中，虽然目前还没有完全做到，但已经隔离了很大的一部分（虽然 td 文件的管理也很混乱，但确实有效）。



### 3. 编译测试

需要重新编译，因为我们修改了很多东西，且更新了 cmake 配置文件。

```shell
$ ninja clean
$ cmake -G Ninja -DLLVM_TARGETS_TO_BUILD=Cpu0 -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang ../llvm
$ ninja
```

编译时，很可能会遇到问题，按 C++ 的语法规则解决就行，我们目前还不会遇到编译器的问题。



### 4. 检验成果

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