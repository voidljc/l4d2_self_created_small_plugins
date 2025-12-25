This repository contains a collection of small SourceMod plugins I am developing while learning.这个存储库包含了我正在学习时开发的小型SourceMod插件的集合。

Each plugin focuses on a simple or interesting idea, usually exploring a specific gameplay behavior or mechanic.每个插件都专注于一个简单或有趣的想法，通常探索特定的游戏玩法行为或机制。
They are not intended to be large or complex systems, and some implementations may be incomplete or imperfect as part of the learning process.它们并不打算成为大型或复杂的系统，并且作为学习过程的一部分，一些实现可能是不完整或不完美的。

The goal of these plugins is experimentation and practice: trying ideas, understanding how the engine behaves, and gradually improving through iteration.这些插件的目标是实验和实践：尝试想法，了解引擎的行为方式，并通过迭代逐步改进。
If you find something useful, feel free to adapt or improve it.如果你发现一些有用的东西，请随意调整或改进它。

Prerequisites   先决条件

All plugins in this repository are developed for Source Engine dedicated servers.此存储库中的所有插件都是为Source Engine专用服务器开发的。
This repository contains SourceMod script source files (.sp) only, not precompiled binaries.
To use these plugins, the following components must be installed and properly configured:要使用这些插件，必须安装并正确配置以下组件：

MetaMod:Source   MetaMod:来源
MetaMod:Source is the core plugin loader for Source Engine servers.MetaMod:Source是Source引擎服务器的核心插件加载器。
SourceMod depends on MetaMod:Source to function.
Official website:   官方网站:
https://www.metamodsource.net/

SourceMod
SourceMod is an advanced scripting and plugin platform built on top of MetaMod:Source.SourceMod是一个建立在MetaMod:Source之上的高级脚本和插件平台。
All plugins in this repository require SourceMod to run.
Official website:   官方网站:
https://www.sourcemod.net/

Notes   笔记
All files provided are .sp SourcePawn source files
You must compile them into .smx using the SourceMod compiler (spcomp) before use
Compiled plugins should be placed in the server’s addons/sourcemod/plugins/ directory
Recommended Versions   推荐版本
MetaMod:Source: Latest Stable release or a recent SnapshotMetaMod：来源：最新的稳定版本或最近的快照
SourceMod: Version 1.11+ or 1.12+ recommendedSourceMod：建议版本1.11或1.12

After installation, verify that:安装完成后，请检查：
The command meta list correctly lists MetaMod:Source
The command sm version correctly displays the SourceMod version
