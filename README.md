# LLVM for Cpu0

中文文档可参考 [README\_cn.md](https://github.com/P2Tree/LLVM_for_cpu0/blob/main/README_cn.md)。

## Introduction

This is a tutorial to learn LLVM, I realize a backend in LLVM infrastructure to compiler execute code for Cpu0 which is a simple RISC cpu. And I also write a detailed tutorial document by Chinese as a guidance for Chinese LLVM beginner. You can find it in the `doc`.

This directory and its subdirectories contain source code for LLVM \( LLVM 8.0.0 currently \), a toolkit for the construction of highly optimized compilers, optimizers, and runtime environments.

Most of the code about Cpu0 backend is located in the `src/lib/Target/Cpu0` but some are in other path to change public code.

## Usage

You can read and learn each chapter in the document for a guide and use code of this project as a reference. I put every changed file into the `shortcut/ch_x` and you can check it if you have some trouble with coding. I think there are also have some bugs and drawbacks in the document and the code, please feel free to tell me if you have any problem.

## Grateful

As I told you in the document, this tutorial document is reference extensively to a guide with Chen Chung-Shu which name is `Tutorial: Creating an LLVM Backend for Cpu0 Architecture`, this guide is very helpful for me to learn LLVM. As the guidence is so old with LLVM \( LLVM 3.0 probably \), I achieved again with a new version of LLVM. So I express heartfelt thanks to Chen Chung-Shu and his careful work.

