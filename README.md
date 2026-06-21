# Miniature MIPS Processor

## Overview

A 32-bit processor implemented in Verilog. This CPU features a 4-stage pipeline, data forwarding to resolve read-after-write (RAW) hazards, pipeline stalling for load hazards, and built-in system call support for basic I/O operations.

This processor was fully optimized, synthesized, implemented and deployed on a PYNQ-Z2 FPGA board as part of the CS220 (Computer Organization) course at IIT Kanpur under the supervision of Prof. Mainak Chaudhuri.

## Four-Stage Pipeline Flow

To maximize instruction throughput, the processor divides execution into four distinct pipeline stages. Pipeline registers (`id_ex`, `ex_mem`, `mem_wb`) safely propagate control signals and data between stages.

* **Stage 1: Fetch & Decode (FD):** The processor fetches the 32-bit instruction from Instruction Memory. It combinationally decodes the opcode and function fields, extracts immediate values, and reads operands from the Register File.
* **Stage 2: Execute (EX):** The combinational ALU processes the data. It computes arithmetic/logical results, calculates branch/jump target addresses, and determines memory access addresses. Data forwarding multiplexers safely inject bypassed data into the ALU if a read-after-write hazard is detected. System calls for I/O (`SYS_read`, `SYS_write`) also trigger state changes here, potentially asserting stall signals.
* **Stage 3: Memory (MEM):** The processor interacts with the Data Memory. It issues `READ`, `WRITE`, or `SUBWORD_WRITE` commands.
* **Stage 4: Writeback (WB):** Clean data, either computed by the ALU or loaded from Memory, is written back to the Register File on the negative edge of the clock to prevent intra-cycle structural hazards.

## Architecture Highlights

* **Pipelined Datapath:** Utilizes instruction decode/execute (`id_ex`), execute/memory (`ex_mem`), and memory/writeback (`mem_wb`) pipeline registers to maximize throughput.
* **Hazard Resolution:**
    * **Data Forwarding:** Implements bypass logic to forward data directly from the `ex_mem` and `mem_wb` stages, eliminating unnecessary stalls on RAW dependencies.
    * **Stalls & Flushes:** Automatically detects load hazards to stall the pipeline and flushes control-flow instructions on taken branches.
* **Memory Subsystem (Harvard Architecture):** Utilizes separate instruction and data memory modules, each of 1024 Bytes (256 x 32-bit words). This separation resolves structural hazards between the Fetch and Memory pipeline stages. It also features custom alignment logic allowing for byte, half-word and full-word memory accesses.
* **System Calls:** Features dedicated hardware logic to handle basic system calls, including program exit (`1001`), keyboard input waiting (`1003`), and I/O buffer printing (`1004`).
* **Buffered Output:** Incorporates a 4-slot circular I/O register buffer to manage print outputs smoothly, including pipeline stalls that block new writes until the environment safely copies the buffered data.

## Supported Instruction Set

The processor decodes 32-bit MIPS instructions into the appropriate fields based on the 3 instruction formats:

* **R-Type (Register Format)**
    * Used for instructions with only register operands
    * **Supported Instructions:** sll, srl, sra, sllv, srlv, srav, syscall, add, sub, and, or, xor, nor, jr, jalr, slt, sltu
    * **Encoding:** `opcode (6)` | `rs (5)` | `rt (5)` | `rd (5)` | `shamt (5)` | `function (6)`

* **I-Type (Immediate Format)**
    * **Description:** Used for instructions with an immediate operand
    * **Supported Instructions:** addi, andi, ori, xori, bltz, bgez, beq, bne, blez, bgtz, slti, sltiu, lui, lb, lh, lw, lbu, lhu, sb, sh, sw
    * **Encoding:** `opcode (6)` | `rs (5)` | `rt (5)` | `immediate (16)`

* **J-Type (Jump Format)**
    * Used for instructions with immediate jump target
    * **Supported Instructions:** j, jal
    * **Encoding:** `opcode (6)` | `jump_target (26)`

## Project Structure

* **`Computer.v`**: The top-level integration module. It instantiates the processor core and wires it to the independent instruction and data memory units.
* **`Processor.v`**: The core CPU logic. Manages the 4-stage datapath, pipeline registers, stall signals (`pipeline_stall`, `io_stall`), and data forwarding rules.
* **`ALU.v`**: The entirely combinational Arithmetic Logic Unit. Responsible for execution-stage calculations, determining branch conditions, and calculating jump/branch target offsets.
* **`RegisterFile.v`**: A 32-register, 32-bit wide registerfile supporting asynchronous reads and synchronous writes.
* **`Memory.v`**: A generic memory module utilized for both the instruction memory (`im`) and data memory (`dm`).
* **`defs.vh`**: The global header file containing all macro definitions for instruction opcodes, ALU function codes, and system call constants.