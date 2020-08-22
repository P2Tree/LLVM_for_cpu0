//===-- Cpu0MCTargetDesc.cpp - Cpu0 Target Descriptions ---------*- C++ -*-===//
//
//                    The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file provides Cpu0 specific target descirptions.
//
//===----------------------------------------------------------------------===//

#include "Cpu0MCTargetDesc.h"
#include "InstPrinter/Cpu0InstPrinter.h"
#include "Cpu0MCAsmInfo.h"
#include "llvm/MC/MachineLocation.h"
#include "llvm/MC/MCELFStreamer.h"
#include "llvm/MC/MCInstrAnalysis.h"
#include "llvm/MC/MCInstPrinter.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/MCSymbol.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/FormattedStream.h"
#include "llvm/Support/TargetRegistry.h"

using namespace llvm;

#define GET_INSTRINFO_MC_DESC
#include "Cpu0GenInstrInfo.inc"

#define GET_SUBTARGETINFO_MC_DESC
#include "Cpu0GenSubtargetInfo.inc"

#define GET_REGINFO_MC_DESC
#include "Cpu0GenRegisterInfo.inc"

// Select the Cpu0 Architecture Feature for the given triple and cpu name.
// The function will be called at command 'llvm-objdump -d' for Cpu0 elf input.
static StringRef selectCpu0ArchFeature(const Triple &TT, StringRef CPU) {
  std::string Cpu0ArchFeature;
  if (CPU.empty() || CPU == "generic") {
    if (TT.getArch() == Triple::cpu0 || TT.getArch() == Triple::cpu0el) {
      if (CPU.empty() || CPU == "cpu032II") {
        Cpu0ArchFeature = "+cpu032II";
      } else if (CPU == "cpu032I") {
        Cpu0ArchFeature = "+cpu032I";
      }
    }
  }
  return Cpu0ArchFeature;
}

static MCInstrInfo *createCpu0MCInstrInfo() {
  MCInstrInfo *X = new MCInstrInfo();
  InitCpu0MCInstrInfo(X); // defined in Cpu0GenInstrInfo.inc
  return X;
}

static MCRegisterInfo *createCpu0MCRegisterInfo(const Triple &TT) {
  MCRegisterInfo *X = new MCRegisterInfo();
  InitCpu0MCRegisterInfo(X, Cpu0::SW); // defined in Cpu0GenRegisterInfo.inc
  return X;
}

static MCSubtargetInfo *createCpu0MCSubtargetInfo(const Triple &TT,
                                                  StringRef CPU, StringRef FS) {
  std::string ArchFS = selectCpu0ArchFeature(TT, CPU);
  if (!FS.empty()) {
    if (!ArchFS.empty()) {
      ArchFS = ArchFS + "," + FS.str();
    } else {
      ArchFS = FS;
    }
  }
  return createCpu0MCSubtargetInfoImpl(TT, CPU, ArchFS);
  // createCpu0MCSubtargetInfoImpl defined in Cpu0GenSubtargetInfo.inc
}

static MCAsmInfo *createCpu0MCAsmInfo(const MCRegisterInfo &MRI,
                                      const Triple &TT) {
  MCAsmInfo *MAI = new Cpu0MCAsmInfo(TT);

  unsigned SP = MRI.getDwarfRegNum(Cpu0::SP, true);
  MCCFIInstruction Inst = MCCFIInstruction::createDefCfa(nullptr, SP, 0);
  MAI->addInitialFrameState(Inst);

  return MAI;
}

static MCInstPrinter *createCpu0MCInstPrinter(const Triple &TT,
                                              unsigned SyntaxVariant,
                                              const MCAsmInfo &MAI,
                                              const MCInstrInfo &MII,
                                              const MCRegisterInfo &MRI) {
  return new Cpu0InstPrinter(MAI, MII, MRI);
}

namespace {
class Cpu0MCInstrAnalysis : public MCInstrAnalysis {
public:
  Cpu0MCInstrAnalysis(const MCInstrInfo *Info) : MCInstrAnalysis(Info) { }
};
}

static MCInstrAnalysis *createCpu0MCInstrAnalysis(const MCInstrInfo *Info) {
  return new Cpu0MCInstrAnalysis(Info);
}

extern "C" void LLVMInitializeCpu0TargetMC() {
  Target &TheCpu0Target = getTheCpu0Target();
  Target &TheCpu0elTarget = getTheCpu0elTarget();
  for (Target *T : {&TheCpu0Target, &TheCpu0elTarget}) {
    // Register the MC asm info
    RegisterMCAsmInfoFn X(*T, createCpu0MCAsmInfo);

    // Register the MC instruction info
    TargetRegistry::RegisterMCInstrInfo(*T, createCpu0MCInstrInfo);

    // Register the MC register info
    TargetRegistry::RegisterMCRegInfo(*T, createCpu0MCRegisterInfo);

    // Register the MC Subtarget info
    TargetRegistry::RegisterMCSubtargetInfo(*T, createCpu0MCSubtargetInfo);

    // Register the MC instruction analyzer
    TargetRegistry::RegisterMCInstrAnalysis(*T, createCpu0MCInstrAnalysis);

    // Register the MC instruction printer
    TargetRegistry::RegisterMCInstPrinter(*T, createCpu0MCInstPrinter);
  }
}
