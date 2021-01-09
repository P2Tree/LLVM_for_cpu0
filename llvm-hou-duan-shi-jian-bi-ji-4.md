# LLVM 后端实践笔记 4

## 4 生成目标文件

之前的章节只介绍了汇编代码生成的内容，这一章，我们将介绍对 ELF 目标格式文件的支持以及如何使用 objdump 工具来验证生成的目标文件。在 LLVM 代码框架下，只需要增加少量的代码，Cpu0 后端就可以生成支持大端或小端编码的目标文件。目标注册机制以及它的结构也在本章介绍。

### 4.1 ELF 目标文件代码

#### 4.1.1 文件新增

##### (1) Cpu0TargetStreamer.h/.cpp

定义了一个叫 Cpu0TargetStreamer 的类，继承自 MCTargetStreamer 类。

定义了一个叫 Cpu0TargetAsmStreamer 的类，继承自 Cpu0TargetStreamer 类，这个类用来完成汇编器 Streamer 的功能。AsmStreamer 对象会注册到后端模块中。

##### (2) MCTargetDesc/Cpu0ELFStreamer.h/.cpp

定义了一个叫 Cpu0ELFStreamer 的类，继承自 MCELFStreamer 类。另外定义了这个类的工厂函数 `createCpu0ELFStreamer()`，用来返回其对象。ELFStreamer 对象会注册到后端模块中。

TargetStreamer 和 ELFStreamer 在生成 ELF 文件中同时起作用，ELFStreamer 是我们自定义的一个类，在其中可以做一些钩子来调整输出内容。

目前这些文件中都还是比较空的状态，我们先搭建整个框架。

##### (3) MCTargetDesc/Cpu0AsmBackend.h/.cpp

比较重要的一个文件，实现了 Cpu0AsmBackend 类，继承自 MCAsmBackend 类。这个类作为汇编器后端实现类，目前对 Fixup 信息的操作提供了接口，比如 `applyFixup()` 用来使能 Fixup 状态，`getFixupKindInfo()` 用来获取 Fixup 类型信息，`getNumFixupKinds()` 用来获取 Fixup 类型的数量，`mayNeedRelaxation()` 返回需要 relaxation 的指令的状态（目前是空），`fixupNeedsRelaxation()` 返回给定 fixup 下的指令是否需要 relaxation 的状态（目前是空）。

已经定义了一些常用的 fixup 类型，比如 32 位类型：`fixup_Cpu0_32`, `fixup_Cpu0_HI16`, `fixup_Cpu0_LO16`，还有 GOT 的一些 fixup 类型。

这些函数都是对基类函数的覆写，有关于重定向的功能都将在之后的章节讲解，所以目前会留空。

我们还在其中实现了两个工厂函数，`createCpu0AsmBackendEL32()` 和 `createCpu0AsmBackendEB32()`，用来返回一个 AsmBackend 的实例。

##### (4) MCTargetDesc/Cpu0FixupKinds.h

这个头文件中定义了 `llvm::Cpu0::Fixups`，这里的定义顺序必须与 Cpu0AsmBackend.cpp 中的 MCFixupKindInfo 保持一致。

##### (5) MCTargetDesc/Cpu0MCCodeEmitter.h/.cpp

另一个比较重要的类，用来为 Streamer 类提供直接发射编码的实现接口。定义了比如 `encodeInstruction()` 等重要接口。

由于 Cpu0 中，NOP 指令和 SHL 指令的编码是 0，所以我们在 `encodeInstruction()` 中特殊处理，做编码输出的排除。同时，伪指令不参与编码，也要做排除。`getBinaryCodeForInstr()` 函数是 TableGen 自动生成的，可以通过传入给定的 MI 指令，获取该指令的编码。

它也有对应的工厂函数 `createCpu0MCCodeEmitterEB()` 和 `createCpu0MCCodeEmitterEL()`。

##### (6) MCTargetDesc/Cpu0ELFObjectWriter.cpp

定义了一个叫 Cpu0ELFObjectWriter 的类，继承自 MCELFObjectTargetWriter 类。这个类将用来完成最终的 ELF 文件格式的写入任务。

其中提供了 `getRelocType()` 方法用来获取重定位类型，`needsRelocateWithSymbol()` 判断某种重定位类型是否是符号重定位，默认大多数都是符号重定位。

##### (7) MCTargetDesc/Cpu0MCExpr.h/.cpp

针对操作数是表达式的情况，我们需要额外做处理。其中定义了 Cpu0MCExpr 类，继承自 MCTargetExpr 类。其中声明了表达式类型 Cpu0ExprKind，还提供了 `create()`, `getKind()` 等接口。

#### 4.1.2 文件修改

##### (1) MCTargetDesc/Cpu0MCTargetDesc.h/.cpp

我们知道这个文件中会完成注册一些后端模块的功能。

首先定义了两个函数，`createMCStreamer()` 调用 `createCpu0ELFStreamer()` 用来建立 ELFStreamer 对象，`createCpu0AsmTargetStreamer()` 直接建立 Cpu0TargetAsmStreamer 对象。

然后就是调用 `TargetRegistry::RegisterELFStreamer()` 和 `TargetRegistry::RegisterAsmTargetStreamer()` 来注册这两个对象模块。另外，还调用 `TargetRegistry::RegisterMCCodeEmitter()` 来注册大小端的 MCCodeEmitter 对象，以及调用 `TargetRegistry::RegisterMCAsmBackend()` 来注册大小端的 MCAsmBackend 对象。

##### (2) CMakeLists.txt

将新增文件加入构建配置中。

##### (3) Cpu0MCInstLower.h

增加 Cpu0MCExpr.h 文件包含。

##### (4) InstPrinter/Cpu0InstPrinter.cpp

增加 Cpu0MCExpr.h 文件包含。

##### (5) MCTargetDesc/Cpu0BaseInfo.h

增加 Cpu0FixupKinds.h 文件包含。

#### 4.1.3 简要说明

##### (1) 编码

当 llc 指定 -filetype=obj 时，编译器会生成目标文件（而不是汇编文件），此时，AsmPrinter::OutStreamer 所引用的是 MCObjectStreamer（汇编时引用的是 MCAsmStreamer）。LLVM 官方认为这个结构是后端代码生成阶段非常好的一个设计。

最重要的一个接口是 `Cpu0AsmPrinter::EmitInstruction()`，这个接口调用 `MCObjectStreamer::EmitInstruction()` ，进而根据选择生成的目标文件格式（ELF，COFF等）调用对应的编码发射函数，如 ELF 使用 `MCELFStreamer()::EmitInstToData()`。此时会进入到 Cpu0MCCodeEmitter.cpp 文件的实现中，调用 `Cpu0MCCodeEmitter::encodeInstruction()`，配合 TableGen 生成的 `Cpu0MCCodeEmitter::getBinaryCodeForInstr()`等接口完成最后的发射。

获取待发射指令编码的调用过程为：

- `Cpu0MCCodeEmitter::encodeInstruction()` 中，调用 TableGen 生成的 Cpu0GenMCCodeEmitter.inc 中的 `getBinaryCodeForInstr()`，传入 MI.Opcode；
- `getBinaryCodeForInstr()` 将 MI.Operand 传入 `Cpu0MCCodeEmitter::getMachineOpValue()` 来获取操作数的编码，这还需要再配合 Cpu0GenRegisterInfo.inc 和 Cpu0GenInstrInfo.inc 中的编码信息；
- `getBinaryCodeForInstr()` 将操作数的编码和指令操作码统一返回给 `encodeInstruction()`

比如一个加法操作，`%0 = add %1, %2` 生成为 `adds $v0, $at, $v1`，除了 adds 指令的编码需要在 Cpu0GenInstrInfo.inc 中查看外，还需要通过 getEncodingValue(Reg) 到 Cpu0GenRegisterInfo.inc 中查看寄存器的编码，寄存器的编码和编码位置都在 Cpu0RegisterInfo.td 文件中描述了。

对于更复杂的操作数，比如内存操作数，我们在描述 .td 中，定义了一个 mem 的 pattern：

```python
def mem : Operand<iPTR> {
  let PrintMethod = "printMemOperand";
  let MIOperandInfo = (ops CPURegs, simm16);
  let EncoderMethod = "getMemEncoding";
}
```

对于使用这个操作数类型的指令，比如 ld/st 指令，当代码解析其操作数时，会调用 `getMemEncoding()` 函数完成编码。后者便定义在 Cpu0MCCodeEmitter.cpp 文件中。

##### (2) 重定位

Cpu0AsmBackend.cpp 中的 `applyFixup()` 函数将修正后边章节将会增加的**地址控制流**语句或**函数调用**语句，如 jeq, jub 等。Cpu0ELFObjectWriter.cpp 中的 needsRelocateWithSymbol() 函数中的每个重定位记录都依据这个重定位记录在链接阶段是否要调整而设置为 true 或 false。如果是 true，在链接阶段就会根据重定位信息来修正这个类型的值，否则，将不修正。

有关于重定位修正的功能将在后续 ELF 支持章节实现。

##### (3) 发射

重要的接口函数是 `Cpu0ELFStreamer::EmitInstToData()`。

最后的代码发射是由 Cpu0ELFStreamer.cpp 和 Cpu0ObjectWriter.cpp 几个函数实现的，最终将 buffer 的信息写入内存文件中。

##### (4) 注册

这一章重要的强调如何注册后端对象，比如我们这次新增加的 ELFStreamer， AsmBackend，MCCodeEmitter。重点参考 Cpu0MCTargetDesc.cpp 文件中的 TargetRegistry 接口，将具体的对象传入并完成注册。

#### 4.1.4 检验成果

用 clang 编译后，输入后端编译命令：

```shell
build/bin/llc -march=cpu0 -relocation-model=pic -filetype=obj ch4.ll -o ch4.o
```

通过 objdump 可以查看二进制文件结构：

```shell
build/bin/llvm-objdump -s ch4.o
```

llvm 自己有其二进制测试工具 llvm-objdump，也可以使用 gcc 的 objdump。有关于其更多的参数和功能，可以使用 help 参数来了解，这里不再介绍。
