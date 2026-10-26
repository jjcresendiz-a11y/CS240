# Module 5: MIPS Assembler and Disassembler

Name: Jesus Resendiz
Course: CS240
Project: MIPS FizzBuzz

## What this project does

For this project, I made an assembler and a disassembler in Java.

- The assembler reads `fizzbuzz.asm` and creates machine code.
- The disassembler reads the machine code and creates MIPS assembly again.
- I tested the original program and the reconstructed program to make sure they produce the same FizzBuzz output.

## What is needed

- Java 8 or newer with `javac`.
- Python 3 is only needed for the test script and test emulator.
- Run the commands from inside the `Module5` folder.

## Files

```
fizzbuzz.asm                  original FizzBuzz program
Assembler.java                Part 3 assembler
Disassembler.java             Part 4 disassembler
fizzbuzz.mhc-ascii            machine code as readable 0s and 1s
fizzbuzz.mhc-bin              machine code as raw binary bytes
fizzbuzz.reconstructed.asm    assembly created by the disassembler
run_tests.sh                  test script
tests/                        test programs and emulator
test_evidence.txt             test results
mars_fizzbuzz_output.png      MARS output screenshot
```

## How to run the programs

First compile both Java programs:

```
javac Assembler.java Disassembler.java
```

Assemble the original FizzBuzz program:

```
java Assembler fizzbuzz.asm
```

This creates:

- `fizzbuzz.mhc-ascii`
- `fizzbuzz.mhc-bin`

Disassemble the binary file:

```
java Disassembler fizzbuzz.mhc-bin fizzbuzz.reconstructed.asm
```

Disassemble the ASCII file:

```
java Disassembler fizzbuzz.mhc-ascii from_ascii.asm
```

To assemble the reconstructed program and compare the binary files:

```
java Assembler fizzbuzz.reconstructed.asm rebuilt
cmp fizzbuzz.mhc-bin rebuilt.mhc-bin
```

The `cmp` command should not print anything when the files are identical. On Windows, use `fc /b` instead of `cmp`.

To run all tests:

```
bash run_tests.sh
```

The test script runs 27 checks, including normal input, invalid input, both machine-code formats, disassembly, and the round trip.

## Features supported by my assembler

Instructions:

`add`, `addi`, `addiu`, `addu`, `sub`, `ori`, `lui`, `div`, `mfhi`, `sll`, `beq`, `bne`, `j`, `jal`, `jr`, `lw`, `sw`, and `syscall`.

Pseudoinstructions:

`li`, `la`, `move`, `rem`, and `nop`.

Directives and other features:

- `.text` and `.data`
- `.asciiz` strings
- `.globl` and `.global`
- Labels in the text and data sections
- Comments beginning with `#`
- Decimal, hexadecimal, and character values
- Registers such as `$t0` or register numbers such as `$8`

Instructions or directives outside this list are rejected with an error message.

## Addresses and byte order

- The text section starts at `0x00400000`.
- The data section starts at `0x10010000`.
- The entry point is the `main` label.
- Words and header fields use big-endian byte order. The most significant byte comes first.
- Delayed branching is off, which matches the MARS setting used for this project.

## Machine-code file formats

The `.mhc-bin` file is a binary file. It starts with a 24-byte header:

```
4 bytes   magic value MHCB
4 bytes   text starting address
4 bytes   text size
4 bytes   data starting address
4 bytes   data size
4 bytes   entry address
```

After the header are the instruction bytes followed by the data bytes.

The `.mhc-ascii` file is a text file. It has `TEXT` and `DATA` sections. Each instruction is written as 32 readable `0` and `1` characters. The section sizes show the disassembler where the instructions end and the data begins.

For this FizzBuzz program, there are 45 instructions and 10 data bytes. The binary file is 214 bytes total: 24 header bytes, 180 instruction bytes, and 10 data bytes.

## Disassembler result

The disassembler can read either machine-code format. It creates real MIPS instructions and new labels when needed. It does not recover the original comments, label names, or pseudoinstruction spellings.

The reconstructed program was assembled again, and its machine-code bytes matched the original files. The program also produced the correct FizzBuzz output in the test emulator and in MARS. The MARS screenshot is included as `mars_fizzbuzz_output.png`.

## Error handling

Invalid input is rejected with a useful error message. The tests include unsupported instructions, bad directives, duplicate labels, undefined labels, invalid registers, out-of-range values, bad machine-code files, and missing files.

## Sources and collaboration

I started with the assembler code provided by my instructor. I extended it so it could read a source file, create both required machine-code formats, and report errors.

I used Claude and ChatGPT/Codex to help me understand the assignment, organize the project, write and debug parts of the code, and test the assembler and disassembler. I reviewed the code and ran the tests myself.