# LLVM 后端实践笔记 7

## 7 控制流

这一章会介绍与控制流有关的功能实现，比如 if、else、while 和 for 等，还会介绍如何将控制流的 IR 表示转换为机器指令；之后会引入几个后端优化，处理一些跳转需求引入的问题，同时来说明如何编写后端优化的 pass。在条件指令小节中，会介绍 LLVM IR 中的特殊指令 select 和 select_cc，以及如何处理这种指令，从而来支持更细节的控制流支持实现。

### 7.1 控制流语句

#### 7.1.1 简要说明

从机器层面上来看，所有的跳转只分为无条件跳转和有条件跳转，从跳转方式上来分，又分为直接跳转（绝对地址）和间接跳转（相对偏移），所以我们只需要将 LLVM IR 的跳转 node 成功下降到机器跳转指令，并维护好跳转的范围、跳转的重定位信息即可。

Cpu032I 型机器支持 J 类型的跳转指令，比如无条件跳转 JMP，有条件跳转 JEQ、JNE、JLT、JGT、JLE、JGE，这部分指令是需要通过检查 condition code （SW 寄存器）来决定跳转条件的；Cpu032II 型机器除了支持 J 类型跳转指令之外，还支持 B 类型的跳转指令，比如 BEQ 和 BNE，这两个是通过直接比较操作数值关系来决定跳转条件的。相比较，后者的跳转依赖的资源少，指令效率更高。

SelectionDAG 中的 node，无条件跳转是 `ISD::br`，有条件跳转是 `ISD::brcond`，我们需要在 tablegen 中通过指定指令选择 pattern 来对这些 node 做映射。

另外，J 类型指令依赖的 condition code 是通过比较指令（比如 CMP）的结果来设置的，我们在之前的章节已经完成了比较指令，LLVM IR 的 `setcc` node 通常会被翻译为 `addiu reg1, zero, const + cmp reg1, reg2` 指令。

#### 7.1.2 文件修改

##### (1) Cpu0ISelLowering.cpp

设置本章需要的几个 node 为 custom 的 lowering 类型，即我们会通过自定义的 lowering 操作来处理它们，这包括 `BlockAddress`，`JumpTable` 和 `BRCOND`。这分别对应 `lowerBlockAddress()`，`lowerJumpTable()` 和 `lowerBRCOND()` 函数，具体实现可参见代码，其中 `getAddrLocal()` 和 `getAddrNonPIC()` 是我们前边章节已经实现的自定义 node 生成函数。`BRCOND` 是条件跳转节点（包括 condition 的 op 和 condition 为 true 时 跳转的 block 的地址），`BlockAddress` 字面可知是 BasicBlock 的起始地址类型的节点，`JumpTable` 是跳转表类型的节点。后两者是叶子节点类型。

另外，设置 `SETCC` 在 i1 类型时做 Promote。增加了几行代码来说明额外的一些 ISD 的 node 需要做 Expand，有关于 Expand 我们在之前的章节介绍过，就是采用 LLVM 内部提供的一些展开方式来展开这些我们不支持的操作。这些操作包括：`BR_JT`，`BR_CC`，`CTPOP`，`CTTZ`，`CTTZ_ZERO_UNDEF`，`CTLZ_ZERO_UNDEF`。其中 `BR_JT` 操作的其中一个 op 是 `JumpTable` 类型的节点（保存 `JumpTable` 中的一个 index）。`BR_CC` 操作和 `SELECT_CC` 操作类似，区别是它保存有两个 op，通过比较相对大小来选择不同的分支。

##### (2) Cpu0InstrInfo.td

增加两个和跳转有关的操作数类型：`brtarget16` 和 `brtarget24`，前者是 16 位偏移的编码，将用于 `BEQ`、`BNE` 一类的指令，这一类指令是属于 Cpu032II 型号中特有；后者是 24 位偏移的编码，将用于 `JEQ`、`JNE` 一类的指令。两个操作数均指定了编码函数和解码函数的名称。还定义了 `jmptarget` 操作数类型，用来作为无条件跳转 `JMP` 的操作数。

之后便是定义这几条跳转指令，包括它们的匹配 pattern 和编码。

无条件跳转 `JMP` 的匹配 pattern 直接指明到了 `[(br bb::$addr)]`，很好理解。

然后我们做一些优化来定义 比较+跳转指令选择 Pattern，也就是将 `brcond + seteq/setueq/setne/setune/setlt/setult/setgt/setugt/setle/setule/setge/setuge` 系列模式转换为机器指令的比较+跳转指令组合。对于 J 系列的跳转指令，实际上会转换为 `Jxx + CMP` 模式，而对于 B 系列的跳转指令，则直接转换成指令本身。

比如：

```
def : Pat<(brcond (i32 (setne RC:$lhs, RC:$rhs)), bb:$dst), (JNEOp (CMPOp RC:$lhs, RC:$rhs), bb:$dst)>;
def : Pat<(brcond (i32 (setne RC:$lhs, RC:$rhs)), bb:$dst), (BNEOp RC:$lhs, RC:$rhs, bb:$dst)>;
```

需要留意的一个是，我们无法从 C 语言生成 `setueq` 和 `setune` 指令，所以实际上并不会对其做选择（不过考虑到不要过分依赖前端，还是实现了）。

##### (3) Cpu0MCInstLower.cpp

因为跳转的地址既可以是跳转表偏移，也可以是一个 label，所以需要在 `MachineOperand` 这里对相关的类型做 lowering。在 `LowerSymbolOperand()` 函数中增加对 `MO_MachineBasicBlock`、`MO_BlockAddress` 和 `MO_JumpTableIndex` 类型的 lowering。

##### (4) Cpu0MCCodeEmitter.h/cpp

实现地址操作数的编码实现函数，包括 `getBranch16TargetOpValue()`，`getBranch24TargetOpValue()` 和 `getJumpTargetOpValue()` 函数，对 `JMP` 指令同时还是表达式类型的跳转位置的情况，选择正确的 fixups，fixups 类型在 Cpu0FixupKinds.h 文件中定义。

##### (5) Cpu0AsmPrinter.h/cpp

定义一个名为 `isLongBranchPseudo()` 的函数，用来判断指令是否是长跳转的伪指令。

同时在 `EmitInstruction()` 函数中增加当属于长跳转伪指令时，不发射该指令。

##### (6) MCTargetDesc/Cpu0FixupKinds.h

添加重定位类型 `fixup_Cpu0_PC16` 和 `fixup_Cpu0_PC24`。

##### (7) MCTargetDesc/Cpu0ELFObjectWriter.cpp

添加重定位类型的一些设置，在 `getRelocType()` 函数中增加内容。

##### (8) MCTargetDesc/Cpu0AsmBackend.cpp

这里有个小的要点需要留意。Cpu0 的架构和其他 RISC 机器一样，采用五级流水线结构，跳转指令会在 decode 阶段实现跳转动作（也就是将 PC 修改为跳转后的位置），但跳转指令在 fetch 阶段时，PC 会自动先移动到下一条指令位置，fetch 阶段在 decode 阶段之前，所以实际上，在 decode 阶段执行前，PC 已经自动 +4 （一个指令长度），所以实际上跳转指令中的偏移，并不是从跳转指令到目标位置的差，而应该是跳转指令的下一条指令到目标位置的差。

比如说：

```assembly
jne $BB0_2
jmp $BB0_1         # jne 指令 decode 之前，PC 指向这里
$BB0_1:
ld $4, 36($fp)
addiu $4, $4, 1
st $4, 36($fp)
jmp $BB0_2
$BB0_2:
ld $4, 32($fp)     # jne 指令 decode 之后，假设 PC 指向这里
```

jne 指令中的偏移，应该是 jmp 指令到 最后一条 ld 指令之间的距离，也就是 20 （而不是 24）。

为了实现这样的修正，我们在 `adjustFixupValue()` 函数中，针对重定位类型 `fixup_Cpu0_PC16` 和 `fixup_Cpu0_PC24`，指定其 Value 应该在自身的基础上减 4。

#### 7.1.3 检验成果

编译提供的测试用例 ch7_1_controlflow.c， 使用 Cpu032I 生成的汇编如：

```assembly
...
cmp $sw, $3, $2
jne $sw, $BB0_2
jmp $BB0_1
$BB0_1:
ld $4, 4($sp)
addiu $4, $4, 1
st $4, 4($sp)
jmp $BB0_2
$BB0_2:
ld $2, 4($sp)
...
```

可见 Cpu032I 处理器使用 sw 寄存器和 J 系列跳转指令完成控制流操作。

使用 Cpu032II 生成的汇编如：

``` assembly
...
bne $2, $zero, $BB0_2
jmp $BB0_1
$BB0_1:
ld $4, 4($sp)
addiu $4, $4, 1
st $4, 4($sp)
jmp $BB0_2
$BB0_2:
ld $2, 4($sp)
```

Cpu032II 处理器使用 B 系列跳转指令完成控制流操作，指令数更少。

通过 Cpu032I 直接生成二进制代码：

``` bash
build/bin/llc -march=cpu0 -mcpu=cpu032I -relocation-model=pic -filetype=obj ch7_1_controlflow.ll -o ch7_1_controlflow.o
hexdump ch7_1_controlflow.o
```

通过 hexdump 可以将二进制代码输出到终端。从其中找到 ` 31 00 00 14 36 00 00 00 ` 这段编码，`31` 是 jne 指令，`36` 是 jmp 指令，`14` 是 偏移的编码，可见这里偏移是 20，说明我们 Cpu0AsmBackend.cpp 中的设计生效了。



### 7.2 控制流优化：消除无用的 JMP 指令

LLVM 的大多数优化操作都是在中端完成，也就是在 LLVM IR 下完成。除了中端优化以外，其实还有一些依赖于后端特性的优化在后端完成。比如说，Mips 机器中的填充延迟槽优化，就是针对 RISC 下的 pipeline 优化。如果你的后端是一个带有延迟槽的 pipeline RISC 机器，那么也可以使用 Mips 的这一套优化。

这一小节，我们实现一个简单的后端优化，叫做消除无用的 JMP 指令。这个算法简单且高效，可以作为一个优化的教程来学习，通过学习，也可以了解如何新增一个优化 pass，以及如何在真实的工程中编写复杂的优化算法。

#### 7.2.1 简要说明

对于如下汇编指令：

```
    jmp    $BB_0
$BB_0:
    ... other instructions
```

在 jmp 指令的下一条指令，就是 jmp 指令需要跳转的 BasicBlock 块，因为 jmp 指令是无条件跳转，所以这里的控制流必然会做顺序执行，进而可以明确这里的 jmp 指令是多余的，即使删掉这条 jmp 指令，程序流也一样可以执行正确。

所以，我们的目的就是识别这种模式，并删除对应的 jmp 指令。

#### 7.2.2 文件修改

##### (1) CMakeLists.txt

添加新文件 Cpu0DelUselessJMP.cpp。

##### (2) Cpu0.h

声明这个 pass 的工厂函数。

##### (3) Cpu0TargetMachine.cpp

覆盖 `addPreEmitPass()` 函数，在其中添加我们的 pass。调用这个函数表示我们的 pass 会在代码发射之前被执行。

#### 7.2.3 文件新增

##### (1) Cpu0DelUselessJMP.cpp

这是我们实现该优化 pass 的具体代码。有几个具体要留意的点：

代码：

```c
#define DEBUG_TYPE "del-jmp"

...
LLVM_DEBUG(dbgs() << "debug info");
```

这里是为我们的优化 pass 添加一个调试宏，这样我们可以通过在执行编译命令时，指定该调试宏来打印出我们想要的调试信息。注意需要以 debug 模式来编译编译器，并且在执行编译命令时，指定参数：

```
llc -debug-only=del-jmp
```

或直接打开所有调试信息：

```
llc -debug
```



其次，代码：

```
STATISTIC(NumDelJmp, "Number of useless jmp deleted");
```

表示我们定义了一个全局变量 `NumDelJmp`，可以允许我们在执行编译命令时，当执行完毕时，打印出这个变量的值。这个变量的作用是统计这个优化 pass 一共消除了多少的无用 jmp 指令，变量的累加是在实现该 pass 的逻辑中手动设计进去的。

在执行编译命令时，指定参数：

```
llc -stats
```

就可以打印出所有的统计变量的值。



其次，代码：

```c
static cl::opt<bool> EnableDelJmp(
  ...
  ...
);
```

这部分代码是向 LLVM 注册了一个编译参数，参数名称是这里第一个元素，还指定了参数的默认值，描述信息等。我们使用参数名为：`enable-cpu0-del-useless-jmp`，默认是打开的。这就是说，如果我们指定了这个参数，并且令其值为 false，则会关闭这个优化 pass。



具体的实现代码中，继承了 MachineFunctionPass 类，并在 `runOnMachineFunction` 中重写了逻辑，这个函数会在每次进入一个新的 Function 时被执行。在内部逻辑中调用了 `runOnMachineBasicBlock` 函数，同理，这个函数在每进入一个新的 BasicBlock 时被执行。

我们的基本思路是，在每个函数中遍历每一个基本块，直接取其最后一条指令，判断是否为 jmp 指令，如果是，再判断这条指令指向的基本块是否是下一个基本块。如果都满足，则调用 `MBB.erase(I)` 删除 `I` 指向的指令（jmp 指令）并且累加 `NumDelJmp` 变量。

#### 7.2.4 检验成果

执行我提供的测试用例：ch7_2_deluselessjmp.cpp

```
build/bin/llc -march=cpu0 -relocation-model=static -filetype=asm -stats ch7_2_deluselessjmp.ll -o -
```

查看输出汇编，会发现已经没有 jmp 指令，输出 statistics 信息中 `8 del-jmp` 告诉我们删除了 8 条无用的 jmp 指令。可以关闭这个优化再查看汇编（添加 `-enable-cpu0-del-useless-jmp=false`），两次结果做对比。



### 7.3 填充跳转延迟槽

这是个功能性的 pass。很多 RISC 机器采用多级流水线设计，有些 phase 会产生延迟，为了保证软件运行正确，可能会需要软件（编译器）在需要延迟的指令做处理。Cpu0 就符合这种情况，对于所有的跳转指令，需要有一个 cycle 的延迟，编译器需要负责对这些跳转指令做延迟插入指令。为了让实现简单，我们目前的实现只是将一条 nop 指令填充到跳转指令之后。有关于将其他有用的指令插入到跳转之后，可以参考 Mips 的实现（更加有意义，不单单是一条无用的等待），比如 MipsDelaySlotFiller.cpp 文件。

#### 7.3.1 简要说明

对于如下汇编指令：

```
    jne    $sw, $BB_0
    nop    // 这里是插入的指令
$BB_1:
    ... other instructions
```

对于 jne 指令，因为需要为其填充延迟指令，所以实际我们代码运行之后，会在汇编中，jne 的下一条指令，输出一条 nop 指令，这样就可以保证在 jne 执行完毕之后，再进行后续的运行。

与上一节的设计类似，我们依然是设计一个 pass，专门去识别这样一个模式，并创建一个 nop 指令并与跳转指令打到一个 bundle 中。bundle 是 LLVM 在 MI 层支持的一种指令扩展，它会在 bundle emit 之前，将 bundle 看做一条指令，而 bundle 内部却可以包含多条指令。

#### 7.3.2 文件修改

##### (1) CMakeLists.txt

添加新增的文件 Cpu0DelaySlotFiller.cpp。

##### (2) Cpu0.h

添加创建新 pass 的工厂函数。

##### (3) Cpu0TargetMachine.cpp

在 addPreEmitPass() 函数中增加我们的 pass，和上一小节同理。

##### (4) Cpu0AsmPrinter.cpp

这里是汇编代码发射的地方，需要检查要发射的指令是否是 bundle，如果是，则将 bundle 展开，依次发射其中的每一条指令。这一个 while 代码在之前的章节已经添加。如果不做这个检查，则只有 bundle 中的第一条指令会被发射，这将会导致代码错误。

#### 7.2.3 文件新增

##### (1) Cpu0DelaySlotFiller.cpp

新 pass 的实现代码。和上一小节类似的实现就不赘述了。

定义了一个 `hasUnoccupiedSlot()` 函数，用来判断某条指令是否满足我们上文指定的模式，首先判断这条指令是否具有延迟槽，调用 `hasDelaySlot()` 函数，然后判断这条指令是否已经属于一个 bundle 或者是最后一条指令，调用 `isBundledWithSucc()` 函数。这两个函数都是 LLVM 内置函数，在 MachineInstr.h 中实现。

当满足条件时，先使用 BuildMI 创建 nop 指令，并插入到跳转指令的后边；然后调用 `MIBundleBuilder` 函数，将跳转指令和 nop 指令打到一个 bundle。

#### 7.3.4 检验成果

我没有额外提供测试用例，可以通过编译上一节的 ch7_2_deluselessjmp.cpp，查看输出的汇编内容，加 `-stats` 参数，输出共填充了 5 个这样模式的延迟槽。

### 7.4 条件 MOV 指令

#### 7.4.1 简要说明

条件 MOV 指令也叫做 Select 指令，和 C 语言中的 select 操作语义一致，由一个条件值、两个指定值和一个定义值（输出）组成。在满足一个条件时，将指定值赋给定义值，否则把另一个指定值赋给定义值。我们在 Cpu0 中将实现两条 MOV 指令，分别是 `movz` 和 `movn`，表示当条件成立时（或条件不成立时），赋值第一个值，否则，赋值另一个值。

由于编码位有限，通常的条件 MOV 指令和 Select 指令均设计为其中一个指定值与定义值是同一个操作数（或者也有设计为条件值与定义值是同一个操作数）：

```
movz $1, $2, $3;    @ $3 为条件值，当 $3 满足（为 true）时，将 $2 赋值给 $1,
                    @ 否则，保持 $1 值不变
movn $1, $2, $3;    @ $3 为条件值，当 $3 不满足（为 false）时，将 $2 赋值给 $1,
                    @ 否则，保持 $1 值不变
```

可以发现，`movz` 和 `movn` 是可以相互替代的，即：

```
movz $1, $2, $3;    @ 等价于
movn $2, $1, $3;    @ 当然，还需要保证上下文数据正确
```

在 LLVM IR 中，只有一个指令来处理这个情况，叫做 `select` 指令：

```
%ret = select i1 %cond, i32 %a, i32 %b
```

所以我们需要做的就是在后端代码中，将这个 IR 转换为正确的指令表示。

#### 7.4.2 文件修改

##### (1) Cpu0InstrInfo.td

新增和条件 MOV 相关的指令实例和用于窥孔优化的 Pattern 描述。

前者即定义 `movz` 和 `movn` 指令。注意到在 class 中使用 `let Constraints = "$F = $ra"`  的属性来指定两个操作符是同一个值，这种写法通常用于当其中一个 def 操作数同时也需要作为 use 操作数的情况下，比如当前的 select 示例中。

后者是将 IR 过来的 `select` + `cmp` 节点组合优化为一条 `movz` 或 `movn` 指令。`select` 指令的 condition 需要一条比较（或其他起相同作用的）指令来得出条件结果，在 Cpu032I 机器中是 `cmp` 指令，在 Cpu032II 机器中是 `slt` 指令。因为通常比较两个值是否相等，还可以采用 `xor` 指令，所以对于低效的 Cpu032I 比较 `cmp` 指令，可以使用 `xor` 做替换，但对于大于、小于等条件代码则只能继续使用 `cmp` 指令，体现在 .td 文件中就是不特别去优化 `select` 指令组合下的条件指令。

这个优化的路径是：

```
IR:   icmp + (eq, ne, sgt, sge, slt, sle) + br
DAG:  ((seteq, setne, setgt, setge, setlt, setle) + setcc) + select
Cpu0: movz, movn
```



##### (2) Cpu0ISelLowering.h/.cpp

需要做一点配置。首先，LLVM 的后端会默认把 `SetCC` 和 `Select` 两个 Node 合并成一条 `Select_cc` 指令，这是为能够支持 `Select_cc` 指令的后端而准备的，这种指令是通过 condition code 来作为 `select` 指令的条件，比如在 X86 机器中。我们的 Cpu0 不支持这种指令，所以需要在 Cpu0ISelLowering.cpp 中，将 `Select_cc` 设置为 Expand 类型，表示我们希望 LLVM 帮我们替代这个类型的节点。

另一件事是将 `ISD::SELECT` 这个 Node 的默认下降关掉，也就是设置其为 Custom 类型，在我们自定义的下降中，直接将这个 Node 返回。因为我们不希望 select Node 在 lowering 阶段被选择为 select，这样它会无法选到指令。我们的条件 MOV 指令和这里的 select 指令有一些差异，所以只能通过在指令选择时的优化合并来实现从 select Node 到后端指令的 lowering。

#### 7.4.3 检验成果

这一小节提供了 3 个 case，第一个 case （ch7_4_select.c）是最简单的情况，直接使用 C 语言中的三目运算符，clang 会在不开优化的情况下将其生成为 IR Select。

第二个 case (ch7_4_select2.c) 没有使用三目运算符，clang 在不开优化的编译下，会生成两个 BB 块，通过跳转实现功能，只有在启用至少 `-O1` 优化下，才会生成为 IR Select。

第三个 case (ch7_4_select_global_pic.c) 引入了全局变量，测试在全局变量与 select 混合的情况下是否能正常处理代码。

三个 case 的编译命令均与之前相同。



### 7.5 总结

以上就是本章的全部内容。最后再补充几个知识点。静态单赋值形式的表示形式，在对待多分支的控制流时，会遇到多赋值的问题。LLVM IR 处理这个问题的方式是引入 Phi 节点，Phi 节点是一种特殊的操作，它允许操作中通过判断控制流的流向来选择要赋值的值，从而避免了多赋值问题。

这种操作只有在 clang 启用优化的情况下才会生成，如果是 O0 不开优化时，LLVM 则会使用内存访问来解决问题，也就是将值写入同一个内存位置，再在需要赋值时从内存位置读出值，这样也能避免数据的多赋值。但也很显然，这种依赖于内存访问的方式会导致性能变差，所以只会在不开优化的情况下生成这种代码。

测试路径下也有这样的一个测试用例：ch7_5_phinode.c，可以通过 clang -O0 和 clang -O1 来编译生成 LLVM IR，查看代码并确认在 O1 优化下生成了 Phi 节点。

需要注意的是，因为我们目前还没有处理传参的问题，所以将 LLVM IR 编译成汇编代码的过程会出错：

```
Assertion failed: (InVals.size() == Ins.size() && "LowerFormalArguments didn't emit the correct number of values!"), function LowerArguments, file 
```

我们会在下一章开始处理和函数调用有关的功能。

 有关于 Phi 节点更多的细节，可以查看静态单赋值代码形式的 Wiki： https://en.wikipedia.org/wiki/Static_single_assignment_form。



