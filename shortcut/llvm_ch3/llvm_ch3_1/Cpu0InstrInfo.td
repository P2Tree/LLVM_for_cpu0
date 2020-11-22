//===-- Cpu0InstrInfo.td - Cpu0 Instruction defs -----------*- tablegen -*-===//
//
//                    The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.

//
//===----------------------------------------------------------------------===//
//
// This fiel contains the Cpu0 implementation of the TargetInstrInfo class.
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Cpu0 profiles and nodes
//===----------------------------------------------------------------------===//

def SDT_Cpu0Ret : SDTypeProfile<0, 1, [SDTCisInt<0>]>;

def SDT_Cpu0DivRem : SDTypeProfile<0, 2, [SDTCisInt<0>, SDTCisSameAs<0, 1>]>;

// Return
def Cpu0Ret : SDNode<"Cpu0ISD::Ret", SDTNone,
                     [SDNPHasChain, SDNPOptInGlue, SDNPVariadic]>;

def Cpu0DivRem  : SDNode<"Cpu0ISD::DivRem", SDT_Cpu0DivRem, [SDNPOutGlue]>;
def Cpu0DivRemU : SDNode<"Cpu0ISD::DivRemU", SDT_Cpu0DivRem, [SDNPOutGlue]>;
//===----------------------------------------------------------------------===//
// Cpu0 Instruction Predicate Definitions.
//===----------------------------------------------------------------------===//
def EnableOverflow  : Predicate<"Subtarget->enableOverflow()">;
def DisableOverflow : Predicate<"Subtarget->disableOverflow()">;

def HasCmp          : Predicate<"Subtarget->hasCmp()">;
def HasSlt          : Predicate<"Subtarget->hasSlt()">;
//===----------------------------------------------------------------------===//
// Instruction format superclass
//===----------------------------------------------------------------------===//

include "Cpu0InstrFormats.td"

//===----------------------------------------------------------------------===//
// Cpu0 Operand, Complex Patterns and Transformations Definitions
//===----------------------------------------------------------------------===//

// Instruction operand types

class Cpu0InstAlias<string Asm, dag Result, bit Emit = 0b1> :
  InstAlias<Asm, Result, Emit>;

// Signed Operand
def simm16 : Operand<i32> {
  let DecoderMethod = "DecodeSimm16";
}

def shamt  : Operand<i32>;

def uimm16 : Operand<i32> {
  let PrintMethod = "printUnsignedImm";
}

// Address operand
def mem : Operand<iPTR> {
  let PrintMethod = "printMemOperand";
  let MIOperandInfo = (ops CPURegs, simm16);
  let EncoderMethod = "getMemEncoding";
}

// Node immediate fits as 16-bit sign extended on target immediate.
// e.g. addi, andi
def immSExt16 : PatLeaf<(imm), [{ return isInt<16>(N->getSExtValue()); }]>;

// Transformation Function: get the lower 16 bits.
def LO16 : SDNodeXForm<imm, [{
  return getImm(N, N->getZExtValue() & 0xffff);
}]>;

// Transformation Function: get the higher 16 bits.
def HI16 : SDNodeXForm<imm, [{
  return getImm(N, (N->getZExtValue() >> 16) & 0xffff);
}]>;

// Node immdiate fits as 16-bit zero extended on target immediate.
// The LO16 param means that only the lower 16 bits of the node
// immediate are caught.
// e.g. addiu, sltiu
def immZExt16 : PatLeaf<(imm), [{
  if (N->getValueType(0) == MVT::i32)
    return (uint32_t)N->getZExtValue() == (unsigned short)N->getZExtValue();
  else
    return (uint64_t)N->getZExtValue() == (unsigned short)N->getZExtValue();
}], LO16>;

// Immediate can be loaded with LUi (32-bit int with lower 16-bit cleared).
def immLow16Zero : PatLeaf<(imm), [{
  int64_t Val = N->getSExtValue();
  return isInt<32>(Val) && !(Val & 0xffff);
}]>;

// shamt field must fit in 5 bits.
def immZExt5 : ImmLeaf<i32, [{ return Imm == (Imm & 0x1f); }]>;

// Cpu0 Address Mode! SDNode frameindex could posibily be a match since
// load and store instructions from stack used it.
def addr : ComplexPattern<iPTR, 2, "SelectAddr",
                          [frameindex], [SDNPWantParent]>;

//===----------------------------------------------------------------------===//
// Pattern fragment for load/store
//===----------------------------------------------------------------------===//

class AlignedLoad<PatFrag Node>
  : PatFrag<(ops node:$ptr), (Node node:$ptr),
            [{
              LoadSDNode *LD = cast<LoadSDNode>(N);
              return LD->getMemoryVT().getSizeInBits()/8 <= LD->getAlignment();
            }]>;

class AlignedStore<PatFrag Node>
  : PatFrag<(ops node:$val, node:$ptr), (Node node:$val, node:$ptr),
            [{
              StoreSDNode *ST = cast<StoreSDNode>(N);
              return ST->getMemoryVT().getSizeInBits()/8 <= ST->getAlignment();
            }]>;

// Load/Store PatFrags
def load_a  : AlignedLoad<load>;
def store_a : AlignedStore<store>;

//===----------------------------------------------------------------------===//
// Instructions specific format
//===----------------------------------------------------------------------===//

// Arithmetic and logical instructions with 3 register operands
class ArithLogicR<bits<8> op, string instrAsm, SDNode opNode,
                  InstrItinClass itin, RegisterClass RC, bit isComm = 0>
  : FA<op, (outs GPROut:$ra), (ins RC:$rb, RC:$rc),
       !strconcat(instrAsm, "\t$ra, $rb, $rc"),
       [(set GPROut:$ra, (opNode RC:$rb, RC:$rc))], itin> {
  let shamt = 0;
  let isCommutable = isComm;
  let isReMaterializable = 1;
}

// Arithmetic and logical instructions with 2 register operands
class ArithLogicI<bits<8> op, string instrAsm, SDNode opNode,
                  Operand od, PatLeaf immType, RegisterClass regClass>
  : FL<op, (outs GPROut:$ra), (ins regClass:$rb, od:$imm16),
       !strconcat(instrAsm, "\t$ra, $rb, $imm16"),
       [(set GPROut:$ra, (opNode regClass:$rb, immType:$imm16))], IIAlu> {
  let isReMaterializable = 1;
}

// Shifts with immediate value
class ShiftRotateI<bits<8> op, bits<4> isRotate, string instrAsm,
                   SDNode opNode, PatFrag PF, Operand ImmOperand,
                   RegisterClass RC>
  : FA<op, (outs GPROut:$ra), (ins RC:$rb, ImmOperand:$shamt),
       !strconcat(instrAsm, "\t$ra, $rb, $shamt"),
       [(set GPROut:$ra, (opNode RC:$rb, PF:$shamt))], IIAlu> {
  let rc = 0;
}


// Shifts with register
class ShiftRotateR<bits<8> op, bits<4> isRotate, string instrAsm,
                   SDNode opNode, RegisterClass RC>
  : FA<op, (outs GPROut:$ra), (ins RC:$rb, RC:$rc),
       !strconcat(instrAsm, "\t$ra, $rb, $rc"),
       [(set GPROut:$ra, (opNode RC:$rb, RC:$rc))], IIAlu> {
  let shamt = 0;
}

// Load Upper Immediate
class LoadUpper<bits<8> op, string instrAsm, RegisterClass RC, Operand Imm>
  : FL<op, (outs RC:$ra), (ins Imm:$imm16),
       !strconcat(instrAsm, "\t$ra, $imm16"), [], IIAlu> {
  let rb = 0;
  let isReMaterializable = 1;
}

class FMem<bits<8> op, dag outs, dag ins, string asmStr, list<dag> pattern,
           InstrItinClass itin>
  : FL<op, outs, ins, asmStr, pattern, itin> {
  bits<20> addr;
  let Inst{19-16}   = addr{19-16};
  let Inst{15-0}    = addr{15-0};
  let DecoderMethod = "DecodeMem";
}

// Memory Load/Store
let canFoldAsLoad = 1 in
class LoadM<bits<8> op, string instrAsm, PatFrag opNode, RegisterClass regClass,
            Operand od, bit pseudo>
  : FMem<op, (outs regClass:$ra), (ins od:$addr),
         !strconcat(instrAsm, "\t$ra, $addr"),
         [(set regClass:$ra, (opNode addr:$addr))], IILoad> {
  let isPseudo = pseudo;
}

class StoreM<bits<8> op, string instrAsm, PatFrag opNode, RegisterClass regClass,
             Operand od, bit pseudo>
  : FMem<op, (outs), (ins regClass:$ra, od:$addr),
         !strconcat(instrAsm, "\t$ra, $addr"),
         [(opNode regClass:$ra, addr:$addr)], IIStore> {
  let isPseudo = pseudo;
}

// 32-bit load
multiclass LoadM32<bits<8> op, string instrAsm,
                   PatFrag opNode, bit pseudo=0> {
  def #NAME# : LoadM<op, instrAsm, opNode, GPROut, mem, pseudo>;
}

// 32-bit store
multiclass StoreM32<bits<8> op, string instrAsm,
                    PatFrag opNode, bit pseudo=0> {
  def #NAME# : StoreM<op, instrAsm, opNode, CPURegs, mem, pseudo>;
}

// JumpFR
let isBranch=1, isTerminator=1, isBarrier=1, hasDelaySlot=1,
    isIndirectBranch=1 in
class JumpFR<bits<8> op, string instrAsm, RegisterClass regClass>
  : FL<op, (outs), (ins regClass:$ra),
       !strconcat(instrAsm, "\t$ra"), [(brind regClass:$ra)], IIBranch> {
  let rb = 0;
  let imm16 = 0;
}

// Return
class RetBase<RegisterClass regClass> : JumpFR<0x3c, "ret", regClass> {
  let isReturn = 1;
  let isCodeGenOnly = 1;
  let hasCtrlDep = 1;
  let hasExtraSrcRegAllocReq = 1;
}

// Multiple
class Mult<bits<8> op, string instrAsm, InstrItinClass itin,
           RegisterClass RC, list<Register> DefRegs>
  : FA<op, (outs), (ins RC:$ra, RC:$rb),
       !strconcat(instrAsm, "\t$ra, $rb"), [], itin> {
  let rc = 0;
  let shamt = 0;
  let isCommutable = 1;
  let Defs = DefRegs;
  let hasSideEffects = 0;
}

class Mult32<bits<8> op, string instrAsm, InstrItinClass itin>
  : Mult<op, instrAsm, itin, CPURegs, [HI, LO]>;

// Divid
class Div<SDNode opNode, bits<8> op, string instrAsm, InstrItinClass itin,
          RegisterClass RC, list<Register> DefRegs>
  : FA<op, (outs), (ins RC:$ra, RC:$rb),
       !strconcat(instrAsm, "\t$ra, $rb"),
       [(opNode RC:$ra, RC:$rb)], itin> {
  let rc = 0;
  let shamt = 0;
  let Defs = DefRegs;
}

class Div32<SDNode opNode, bits<8> op, string instrAsm, InstrItinClass itin>
  : Div<opNode, op, instrAsm, itin, CPURegs, [HI, LO]>;

// Move from LO/HI
class MoveFromLOHI<bits<8> op, string instrAsm, RegisterClass RC,
                   list<Register> UseRegs>
  : FA<op, (outs RC:$ra), (ins),
       !strconcat(instrAsm, "\t$ra"), [], IIHiLo> {
  let rb = 0;
  let rc = 0;
  let shamt = 0;
  let Uses = UseRegs;
  let hasSideEffects = 0;
}

// Move to LO/HI
class MoveToLOHI<bits<8> op, string instrAsm, RegisterClass RC,
                 list<Register> DefRegs>
  : FA<op, (outs), (ins RC:$ra),
       !strconcat(instrAsm, "\t$ra"), [], IIHiLo> {
  let rb = 0;
  let rc = 0;
  let shamt = 0;
  let Defs = DefRegs;
  let hasSideEffects = 0;
}

// Move from C0 (co-processor 0) Register
class MoveFromC0<bits<8> op, string instrAsm, RegisterClass RC>
  : FA<op, (outs), (ins RC:$ra, C0Regs:$rb),
       !strconcat(instrAsm, "\t$ra, $rb"), [], IIAlu> {
  let rc = 0;
  let shamt = 0;
  let hasSideEffects = 0;
}

// Move to C0 Register
class MoveToC0<bits<8> op, string instrAsm, RegisterClass RC>
  : FA<op, (outs C0Regs:$ra), (ins RC:$rb),
       !strconcat(instrAsm, "\t$ra, $rb"), [], IIAlu> {
  let rc = 0;
  let shamt = 0;
  let hasSideEffects = 0;
}

// Move from C0 register to C0 register
class C0Move<bits<8> op, string instrAsm>
  : FA<op, (outs C0Regs:$ra), (ins C0Regs:$rb),
       !strconcat(instrAsm, "\t$ra, $rb"), [], IIAlu> {
  let rc = 0;
  let shamt = 0;
  let hasSideEffects = 0;
}

//===----------------------------------------------------------------------===//
// Instruction definition
//===----------------------------------------------------------------------===//

// Load and Store Instructions
// already aligned
defm LD      : LoadM32<0x01,   "ld",   load_a>;
defm ST      : StoreM32<0x02,  "st",   store_a>;

// Arithmetic Instructions (ALU Immediate)
def ADDiu    : ArithLogicI<0x09, "addiu", add, simm16, immSExt16, CPURegs>;
def ORi      : ArithLogicI<0x0d, "ori", or, uimm16, immZExt16, CPURegs>;

def LUi      : LoadUpper<0x0f, "lui", GPROut, uimm16>;

// Arithmetic Instructions (3-Operand, R-Type)
let Predicates = [DisableOverflow] in {
  def ADDu   : ArithLogicR<0x11, "addu", add, IIAlu, CPURegs, 1>;
  def SUBu   : ArithLogicR<0x12, "subu", sub, IIAlu, CPURegs>;
}
let Predicates = [EnableOverflow] in {
  def ADD    : ArithLogicR<0x13, "add", add, IIAlu, CPURegs, 1>;
  def SUB    : ArithLogicR<0x14, "sub", sub, IIAlu, CPURegs>;
}

def MUL      : ArithLogicR<0x17, "mul", mul, IIImul, CPURegs, 1>;
def MULT     : Mult32<0x41, "mult", IIImul>;
def MULTu    : Mult32<0x42, "multu", IIImul>;
def SDIV     : Div32<Cpu0DivRem, 0x43, "div", IIIdiv>;
def UDIV     : Div32<Cpu0DivRem, 0x44, "divu", IIIdiv>;

// Shift Instructions
// shift left
def SHL      : ShiftRotateI<0x1e, 0x00, "shl", shl, immZExt5, shamt, CPURegs>;
// shift right arithmetic
def SRA      : ShiftRotateI<0x1d, 0x00, "sra", sra, immZExt5, shamt, CPURegs>;
// rotate shift left
def ROL      : ShiftRotateI<0x1b, 0x01, "rol", rotl, immZExt5, shamt, CPURegs>;
// rotate shift right
def ROR      : ShiftRotateI<0x1c, 0x01, "ror", rotr, immZExt5, shamt, CPURegs>;
// shift right
def SHR      : ShiftRotateI<0x1f, 0x00, "shr", srl, immZExt5, shamt, CPURegs>;

// shift right arithmetic
def SRAV     : ShiftRotateR<0x20, 0x00, "srav", sra, CPURegs>;
// shift left
def SHLV     : ShiftRotateR<0x21, 0x00, "shlv", shl, CPURegs>;
// shift right
def SHRV     : ShiftRotateR<0x22, 0x00, "shrv", srl, CPURegs>;
// rotate shift left
def ROLV     : ShiftRotateR<0x23, 0x01, "rolv", rotl, CPURegs>;
// rotate shift right
def RORV     : ShiftRotateR<0x24, 0x01, "rorv", rotr, CPURegs>;

// Jump Instructions
def JR       : JumpFR<0x3c, "jr", GPROut>;

def RET      : RetBase<GPROut>;

def MFHI     : MoveFromLOHI<0x46, "mfhi", CPURegs, [HI]>;
def MFLO     : MoveFromLOHI<0x47, "mflo", CPURegs, [LO]>;
def MTHI     : MoveToLOHI<0x48, "mthi", CPURegs, [HI]>;
def MTLO     : MoveToLOHI<0x49, "mtlo", CPURegs, [LO]>;

def MFC0     : MoveFromC0<0x50, "mfc0", CPURegs>;
def MTC0     : MoveToC0<0x51, "mtc0", CPURegs>;

def C0MOVE   : C0Move<0x52, "c0mov">;

// No Operation Instructions
let addr=0 in
  def NOP    : FJ<0, (outs), (ins), "nop", [], IIAlu>;

let isReturn=1, isTerminator=1, hasDelaySlot=1, isBarrier=1, hasCtrlDep=1 in
  def RetLR  : Cpu0Pseudo<(outs), (ins), "", [(Cpu0Ret)]>;

//===----------------------------------------------------------------------===//
// Arbitrary patterns that map to one or more instructions
//===----------------------------------------------------------------------===//

// Small Immediates
def : Pat<(i32 immSExt16:$in), (ADDiu ZERO, imm:$in)>;

def : Pat<(i32 immZExt16:$in), (ORi ZERO, imm:$in)>;

def : Pat<(i32 immLow16Zero:$in), (LUi (HI16 imm:$in))>;

// Arbitrary immediates
def : Pat<(i32 imm:$imm), (ORi (LUi (HI16 imm:$imm)), (LO16 imm:$imm))>;

//===----------------------------------------------------------------------===//
// Instruction aliases
//===----------------------------------------------------------------------===//
def : Cpu0InstAlias<"move $dst, $src",
                    (ADDu GPROut:$dst, GPROut:$src, ZERO), 1>;