# LLVM 后端实践笔记 10

## 10 汇编

这一章，我们来添加 Cpu0 的汇编功能，这包括独立汇编器和 C 语言内联汇编特性两个部分。

### 10.1 汇编器

独立汇编器可以理解为依赖于 LLVM 后端提供的接口实现的一个独立软件，因为 LLVM 和 gcc 在这个地方的实现逻辑不一样。

在 gcc 中，编译器和汇编器是两个独立的工具，编译器，也就是 cc，只能生成汇编代码，而汇编器 as，才用来将汇编代码翻译为二进制目标代码，gcc 驱动软件 gcc 将这些工具按顺序驱动起来（还包括预处理器、链接器等），最终实现从 C 语言到二进制目标代码的功能。但是，这样的设计有个缺点，每个工具都需要先对输入文件做 parse，然后再输出时写入文件，反复多次的磁盘读写一定程度影响了编译的效率。

而在 LLVM 中，编译器后端本身就可以将中间代码（对应 gcc 中 cc 的中间表示）翻译成二进制目标文件，而不需要发射汇编代码到文件中，再重新 parse 汇编文件。当然它也可以通过配置命令行参数指定将中间代码翻译成汇编代码，方便展示底层程序逻辑。

但我们目前已经实现的这些功能，却无法支持输入汇编代码，输出二进制目标文件，虽然通常情况下已经不再需要手工编写汇编代码，但在特殊情况下，比如引导程序、调试特殊功能、需要优化性能等场合下，还是需要编写汇编代码，所以一个汇编器依然是很重要的。

显然，我们之前的章节已经把和指令相关的汇编表示都在 TableGen 中实现了，这一节中，最核心的就是实现一个汇编器的 parser，并将其注册到 LLVM 后端框架中，并使能汇编功能。并且，汇编器的核心功能在 LLVM 中也已经实现了，原理其实就是一个语法制导的翻译，我们要做的只是重写其中部分和后端架构相关的接口。

我还实现了一个额外的特性。当我们仅使用汇编器时，编译器占用的寄存器 `$sw`，就可以被释放出来当做普通寄存器用了，所以我们重新定义一下 GPROut 这个寄存器类别，并将 `Cpu0.td` 拆分成两份，将它拆分为 `Cpu0Asm.td` 和 `Cpu0Other.td`，前者会在调用汇编器时被使用到，而后者保持和之前一样的设计。

因为 `$sw` 寄存器是编译器用来记录状态的，如果只编写汇编代码，我们认为程序员有义务去维护这个寄存器中的值什么时候是有效的，进而程序员就可以在认为这个寄存器中值无效时，把它当做普通寄存器来使用。我们的标量寄存器有很多，多这样一个寄存器的意义并不是很大，这里依然这么做，其实是想展示一下 TableGen 机制的灵活性。

在 Cpu0 的后端代码路径下，新建一个子目录 AsmParser，在这个路径下新建 Cpu0AsmParser.cpp 用来实现绝大多数功能。

#### 10.1.1 文件新增

##### (1) AsmParser/Cpu0AsmParser.cpp

作为一个独立的功能模块，使能它的 DEBUG 信息名称为 `cpu0-asm-parser`，声明一些新的 class： `Cpu0AsmParser` 作为核心类，用来处理所有汇编 parser 的工作，我们稍后介绍；`Cpu0AssemblerOptions` 这个类用来做汇编器参数的管理；`Cpu0Operand` 类用来解析指令操作数，因为指令操作数可能有各种不同的类型，所以将这部分单独抽出来实现。

在 class 声明之后，就是 class 中成员函数的实现代码。

`Cpu0AsmParser` 类继承了基类 `MCTargetAsmParser`，并重写了部分接口，而有关于汇编 parser 的详细逻辑可以参考 AsmParser.cpp 中的实现。

几个比较重要的重写函数有：

1. `MatchAndEmitInstruction()`
2. `ParseInstruction()`

汇编器在做 parser 时，要先做 Parse，然后再对符合语法规范的指令做指令匹配，前者的关键函数就是第 2 个函数 `ParseInstruction()`，后者的关键函数就是第 1 个 `MatchAndEmitInstruction()`。

在 `ParseInstruction()` 中，根据传入的词法记号，解析指令助记符存入 Operands 容器中，然后在后边依次解析每个操作数，也存入 Operands 中。对于不满足语法规范的输入，比如操作数之间缺逗号等这种问题，直接报错并退出。在解析操作数时，调用了 `ParseOperand()` 接口，这也是一个很重要的接口，专用来解析操作数，我们也重写了这个接口以适应我们的类型，尤其是地址运算符。

`ParseInstruction()` 执行完毕后会返回到 `AsmParser.cpp` 中的 `parseStatement` 方法中，并在做一些分析后，再调用到 `MatchAndEmitInstruction()` 方法。

在 `MatchAndEmitInstruction()` 函数中，将 Operands 容器对象传入。首先调用 `MatchInstructionImpl` 函数，这个函数是 TableGen 参考我们的指令 td 文件生成的 Cpu0GenAsmMatcher.inc 文件自动生成的。

匹配之后如果成功了，还需要做额外的处理，如果这个是伪指令，需要汇编器展开，这种指令我们设计了几条，在之后会提到，这种指令需要调用 `expandInstruction()` 函数来展开，后者根据对应指令调用对应的展开函数，如果不是伪指令，就调用 `EmitInstruction()` 接口来发射编码，这个函数与我们前边章节设计指令输出的接口是同一个，也就是说在汇编 parser 之后的代码，是复用了之前的代码。

匹配如果失败了，则做简单处理并返回，这里我们只实现了几种简单的情况，如果你的后端有一些 TableGen 支持不了的指令形式，也可以在这里做额外的处理，不过还是尽量去依赖 TableGen 的匹配表为好。

在 `ParseOperand()` 函数中，将前边 parse 出来的 Operands 容器对象传入。首先调用 `MatchOperandParserImpl()` 函数来 parse 操作数，这个函数也是 Cpu0GenAsmMatcher.inc 文件中定义好的。如果这个函数 parse 成功，就返回， 否则继续在下边完成一些自定义的 parse 动作，在一个 switch 分支中，根据词法 token 的类型来分别处理。其中，对于 Token，可能是一个寄存器，调用 `tryParseRegisterOperand()` 函数来处理，如果没有解析成功，则按照标识符处理；对于标识符、加减运算符和数字等 Token 的情况，统一调用 `parseExpression()` 来处理；对于百分号 Token，表示可能是一个重定位信息，比如 `%hi($r1)`，则调用 `parseRelocOperand()` 函数来处理。

其他函数就不一一说明了，其中包括很多在 parse 操作数时，不同的操作数下的特殊处理，还有伪指令的展开动作，重定位操作数的格式解析以及生成重定位表达式，寄存器、立即数的 parse，还有汇编宏指令的解析（比如 `.macro`, `.cpload` 这一类）。

在最后，这些代码都实现完毕后，需要调用 `RegisterMCAsmParser` 接口将汇编 parser 注册到 LLVM 中，这个步骤写入到 `LLVMInitializeCpu0AsmParser()` 函数中。

##### (2) AsmParser/CMakeLists.txt

新增加子路径下的编译配置文件。

##### (3) AsmParser/LLVMBuild.txt

同上，添加 LLVM 构建编译配置。

##### (4) Cpu0RegisterInfoGPROutForAsm.td

在这个文件中，我们定义的 GPROut 类别是支持完整的 CPURegs 的。

##### (5) Cpu0RegisterInfoGPROutForOther.td

在这个文件中，我们定义的 GPROut 类别不包含 `$sw` 寄存器。

##### (4) Cpu0Asm.td

由 `Cpu0.td` 拆分出来的文件，和 `Cpu0Other.td` 对应，包含了文件 `Cpu0RegisterInfoGPROutForAsm.td`。

##### (5) Cpu0Other.td

由 `Cpu0.td` 拆分出来的文件，和 `Cpu0Asm.td` 对应，包含了文件 `Cpu0RegisterInfoGPROutForOther.td`。

#### 10.1.2 文件修改

##### (1) CMakeLists.txt

添加子路径的配置。同时，还需要添加一个新的 tablegen 配置项，要求 TableGen 生成 Cpu0GenAsmMatcher.inc 文件用来做汇编指令匹配。

##### (2) LLVMBuild.txt

同上。

##### (3) Cpu0.td

删掉 Target.td、Cpu0RegisterInfo.td 文件的包含。添加汇编器 parser 在 td 中的定义，并注册到 Cpu0 的属性中。这些都是常规操作。

##### (4) Cpu0InstrFormats.td

增加针对伪指令的描述性 class，继承自 `Cpu0Pseudo` 类。

##### (5) Cpu0InstrInfo.td

增加 Operand 操作数 class 中 `ParserMatchClass` 和 `ParserMethod` 属性的描述，只有这样，td 中的操作数才会支持汇编 parse。

定义伪指令 `LoadImm32Reg`, `LoadAddr32Reg`, `LoadAddr32Imm`，这几个指令会在 `Cpu0AsmParser.cpp` 中实现对应的展开函数 `expandLoadImm()`, `expandLoadAddressImm` 和 `expandLoadAddressReg`，这些函数统一放到 `expandInstruction()` 中管理，后者在 `MatchAndEmitInstruction()` 函数中被调用。

##### (6) Cpu0RegisterInfo.td

将 GPROut 的定义移动到 `Cpu0RegisterInfoGPROutForAsm.td` 和 `Cpu0RegisterInfoGPROutForOther.td` 中。

#### 10.1.3 验证结果

这些函数的部分调用关系如下：

```
1. ParseInstruction() -> ParseOperand() -> MatchOperandParserImpl() -> tryCustomParseOperand() -> parseMemOperand() -> parseMemOffset(), tryParseRegisterOperand()
2. MatchAndEmitInstruction() -> MatchInstructionImpl(), needsExpansion(), expandInstruction()
3. parseMemOffset() -> parseRelocOperand() -> getVariantKind()
4. tryParseRegisterOperand() -> tryParseRegister() -> matchRegisterName() -> getReg(), matchRegisterByNumber()
5. expandInstruction() ->expandLoadImm(), expandLoadAddressImm(), expandLoadAddressReg() -> EmitInstruction()
6. ParseDirective() -> parseDirectiveSet() -> parseSetReorderDirective(), parseSetNoReorderDirective(), parseSetMacroDirective(), parseSetNoMacroDirective() -> reportParseError()
```



编译本章第一个 case ch10_1.s，这是一个汇编文件，LLVM 的独立汇编器软件名为 llvm-mc，mc 意指 MCInstr 表示格式，它是一种比 MI 格式更底层的一种中间表示，清除很多信息，在汇编器中使用。

```bash
build/bin/llvm-mc -triple=cpu0 -filetype=obj ch10_1.s -o ch10_1.o
```

如果没有出错，那就成功汇编了，使用 llvm-objdump 工具反汇编代码来查看结果。

```bash
build/bin/llvm-objdump -d ch10_1.o
```



### 10.2 内联汇编

当 c 程序需要直接访问特殊寄存器、指令或内存时，就需要内联汇编的支持，内联汇编允许直接在 c 程序中嵌入汇编代码，来完成机器层次级别的操作。clang 支持内联汇编，但因为汇编是后端的概念，所以内联汇编也自然需要后端来配合支持。

#### 10.2.1 简要说明

一个简单的内联汇编格式是：

```
__asm__ __volatile__ ("addu %0, %1, %2"
                      : "=r" (a)
                      : "r" (b), "r" (c));
```

其中第一行的 `__asm__` 是必须要有的，用来指明后边是内联汇编表达式；`__volatile__` 用来告诉编译器不要对这段代码做调整和优化，可以选择加上。

括号中第一行是要添加的指令，可以多行加入多个这样的字符串，用来一次性添加多条指令，指令字符串末尾不带分号；除了`%` 开头的操作数以外，其他内容要与标准汇编格式一致，`%` 开头的操作数作为占位符，会在内联汇编中用于与 c 变量或内存做绑定；这种占位符形式与下边变量的绑定是按照数字顺序依次对应，比如本例中 `%0` 对应 `a` 变量，`%1` 对应 `b` 变量。除此之外，还有一种命名绑定法，不再详细介绍。

第一个 `:` 之后的内容是输出的定义，这里的输出，包括下边的输入和 clobber list，都是用来修饰整个内联汇编块的，如果有多条指令，这里也仅表示整个指令块的输出，而不是某一条指令的输出；后边第一个字符串是操作数约束 constraint，用来描述这个操作数的类型，具体类型有很多，可以参考 gcc 标准内联汇编的格式，LLVM 采用兼容 gcc 标准内联汇编的策略，绝大多数约束保持了一致；之后小括号中的内容是 c 语言代码中的变量名，表示要绑定的变量。

第二个 `:` 之后的内容是输入的定义，与输出定义表现方式一致。

其实还可能有第三个 `:`，用来表示特殊约束 clobber，不展开介绍。

这三个 `:` 之后的内容可以选择性省略，但不能省略 `:`。

虽然内联汇编的格式挺复杂，但庆幸的是这些 parse 的工作大部分都已经由 clang 和 LLVM 完成了，clang 不需要我们做修改，凡是字符串中的内容，都会直接传给后端，而显然内联汇编的格式也依照此策略方便的隔离了前后端（意思是字符串中的内容才和后端相关，非字符串的格式由前端处理）。

我们需要做的工作在后端，主要是对一些自定义的类型、操作方式和约束做定义，如果你的后端是一个很简单的后端，甚至在这里都不需要做什么工作，LLVM 本身已经支持了很多标准操作。



#### 10.2.1 修改文件

##### (1) Cpu0AsmPrinter.h/.cpp

重写 `PrintAsmOperand()` 函数，该函数用来指定内联汇编表达式的自定义输出样式，比如当修饰符是 `z` 时，表示这个值是一个非负立即数，我们希望在立即数为 0 时，不输出 0 而是输出 `$0`，就在这里完成。如果没有匹配到，就会调用 LLVM 内建的 `AsmPrinter::PrintAsmOperand()` 函数完成默认处理。如果没有指定约束类型，则会走到 `printOperand()` 函数打印出可能的重定位形式的汇编代码。

重写`PrintAsmMemoryOperand()` 函数，与上边同理，这个函数只负责处理内存操作的操作数。我们额外定义了我们自己的汇编格式中对内存访问的表示形式，即 `10($2)` 这种样式。

##### (2) Cpu0ISelDAGToDAG.h/.cpp

这里重写了一个函数`SelectInlineAsmMemoryOperand()`，该函数用来约定内存操作数在指令选择时的动作，对于内存操作，因为其表现是重定位字符串，所以不需要在编译器这里做处理，所以直接将 OP，就是对应的 node，保存下来并返回 false，告诉 LLVM 不需要对其进行下降。

##### (3) Cpu0ISelLowering.h/.cpp

除了特殊的地址操作数之外，就剩下寄存器和立即数操作数了，立即数操作数会由 LLVM 自动的依据 Cpu0GenRegisterInfo.inc 中的信息做绑定，留下特殊的立即数操作数需要我们做处理。因为立即数编码是指令中的一部分，LLVM 公共环境并不知道我们可能支持哪些宽度的立即数，所以其代码需要手动添加。

我们重写了几个函数，其中关键的一个是 `LowerAsmOperandForConstraint()` ，这个函数对所有可能的自定义的约束做处理，处理完特殊情况之后，会转到 LLVM 公共的 `TargetLowering::LowerAsmOperandForConstraint()`。

其他几个函数用来配合寄存器约束的解析，具体可以参考代码中注释。

另外，内联汇编还支持将一个操作数约束成多个可能的类型，比如一个立即数，可以约束为几个不同有效编码范围的立即数类型。后端会使用 `getSingleConstraintMatchWeight()` 函数来决定一个权重，根据权重来选择最佳匹配的类型。

##### (4) Cpu0InstrInfo.cpp

增加计算内联汇编指令长度的计算代码。



LLVM 中处理内联汇编的主要逻辑在 `TargetLowering.cpp` 文件中，对于我们上边几个文件中重写的接口函数都有调用，而且因为核心逻辑是标准的，只要我们不在内联汇编的代码语法上做调整，就不需要修改到公共代码。至于如寄存器类型多而导致寄存器约束多（比如可能会自定义多种向量寄存器，新建如 `v`， `t` 等约束）， 或者立即数编码形式多、内存寻址方式多，都可以在后端的上述几个函数中做调整。



#### 10.2.3 检验成果

运行 ch10_2.c 的代码，其中已经编写了几种简单的内联汇编的代码。

```
build/bin/clang -target mips-unknown-linux-gnu -c ch10_2.c -S -emit-llvm -o ch10_2.ll
```

检查 IR 文件。LLVM IR 也有一种特殊的内联汇编表现样式：

```
%1 = call i32 asm sideeffect "addu $0, $1, $2", "=r,r,r,~{$1}"(i32 %0, i32 %1) #1, !srcloc !2
```

它用 `asm` 作为一个特殊的操作节点，这个节点在后端会被当做内联汇编的块做 lowering。

编译为汇编代码：

```
build/bin/llc -march=cpu0 -mcpu=cpu032I -relocation-model=pic -filetype=asm ch10_2.ll -o -
```

检查汇编文件中，使用 `#APP` 和 `#NO_APP` 包含在中间的代码就是内联汇编代码。内联汇编默认的标识是 `#APP`，这个符号也可以修改。

