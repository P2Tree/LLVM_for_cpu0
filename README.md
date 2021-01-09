# Introduction

## 前言

项目路径：[https://github.com/P2Tree/LLVM\_for\_cpu0](https://github.com/P2Tree/LLVM_for_cpu0)

### 介绍

这个项目是一个学习 LLVM 的教程，我实现了一个 LLVM 框架下的后端，用来编译能够在 Cpu0 上执行的可执行代码，Cpu0 是一个简单易学的 RISC 处理器。另外，我还编写了一份详细的中文文档作为 LLVM 初学者的指南，它们放在 `doc` 路径下。

这个目录和其子目录下包含着完整的 LLVM 的源代码，目前是 8.0.0 版本，以及用于构建优化编译器、优化器和运行时环境的工具包。

大多数代码都放到 `src/lib/Target/Cpu0` 这个路径下，不过也有少量代码在其他位置，配合修改了公共代码。

### 使用方法

你可以把文档的每个章节作为指南来阅读和学习，并把工程中的代码作为参考。 我把每个章节修改过的文件都放到了 `shortcut/ch_x` 的各个路径下，如果在编码是有困惑，可以辅助查看。 我知道，目前代码和文档里依然会有问题，如果你有任何疑问，欢迎告知我。

### 感谢

正如我在文档中写到的，教程文档高度参考了一本教程，这个教程叫 `Tutorial: Creating an LLVM Backend for Cpu0 Architecture`，其作者叫 Chen Chung-Shu，他的教程对我学习 LLVM 非常有帮助。不过，因为完成较早，教程依赖的 LLVM 版本比较旧，大概是 3.0 版本，所以我重新用新版本实现了一遍。 所以，我诚挚的感谢 Chen Chung-Shu，感谢他的细致工作。

## Preface

Project path: [https://github.com/P2Tree/LLVM\_for\_cpu0](https://github.com/P2Tree/LLVM_for_cpu0)

### Introduction

This is a tutorial to learn LLVM, I realize a backend in LLVM infrastructure to compiler execute code for Cpu0 which is a simple RISC cpu. And I also write a detailed tutorial document by Chinese as a guidance for Chinese LLVM beginner. You can find it in the `doc`.

This directory and its subdirectories contain source code for LLVM \( LLVM 8.0.0 currently \), a toolkit for the construction of highly optimized compilers, optimizers, and runtime environments.

Most of the code about Cpu0 backend is located in the `src/lib/Target/Cpu0` but some are in other path to change public code.

### Usage

You can read and learn each chapter in the document for a guide and use code of this project as a reference. I put every changed file into the `shortcut/ch_x` and you can check it if you have some trouble with coding. I think there are also have some bugs and drawbacks in the document and the code, please feel free to tell me if you have any problem.

### Grateful

As I told you in the document, this tutorial document is reference extensively to a guide with Chen Chung-Shu which name is `Tutorial: Creating an LLVM Backend for Cpu0 Architecture`, this guide is very helpful for me to learn LLVM. As the guidence is so old with LLVM \( LLVM 3.0 probably \), I achieved again with a new version of LLVM. So I express heartfelt thanks to Chen Chung-Shu and his careful work.

