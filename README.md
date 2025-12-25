This repository contains a collection of small SourceMod plugins I am developing while learning.

Each plugin focuses on a simple or interesting idea, usually exploring a specific gameplay behavior or mechanic.
They are not intended to be large or complex systems, and some implementations may be incomplete or imperfect as part of the learning process.

The goal of these plugins is experimentation and practice: trying ideas, understanding how the engine behaves, and gradually improving through iteration.
If you find something useful, feel free to adapt or improve it.

Prerequisites

All plugins in this repository are developed for Source Engine dedicated servers.
This repository contains SourceMod script source files (.sp) only, not precompiled binaries.
To use these plugins, the following components must be installed and properly configured:

MetaMod:Source
MetaMod:Source is the core plugin loader for Source Engine servers.
SourceMod depends on MetaMod:Source to function.
Official website:
https://www.metamodsource.net/
Official installation guide (Wiki):
https://wiki.alliedmods.net/Metamod:Source_Installation

SourceMod
SourceMod is an advanced scripting and plugin platform built on top of MetaMod:Source.
All plugins in this repository require SourceMod to run.
Official website:
https://www.sourcemod.net/
Official installation guide (Wiki):
https://wiki.alliedmods.net/Installing_SourceMod
Notes
All files provided are .sp SourcePawn source files
You must compile them into .smx using the SourceMod compiler (spcomp) before use
Compiled plugins should be placed in the server’s addons/sourcemod/plugins/ directory
Recommended Versions
MetaMod:Source: Latest Stable release or a recent Snapshot
SourceMod: Version 1.11+ or 1.12+ recommended

After installation, verify that:
The command meta list correctly lists MetaMod:Source
The command sm version correctly displays the SourceMod version
