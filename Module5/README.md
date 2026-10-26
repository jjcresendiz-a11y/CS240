# Module 5: MIPS Assembler and Disassembler (FizzBuzz)

Two Java programs that turn the course FizzBuzz program into machine code and back.

- `Assembler.java` reads `fizzbuzz.asm` and writes `fizzbuzz.mhc-ascii` and `fizzbuzz.mhc-bin`.
- `Disassembler.java` reads either of those files and writes a MIPS assembly file.

## Requirements

- Java 8 or newer with the compiler (`javac`, part of the JDK).
- Programs read and write real files, so run them from a terminal. A browser runtime such as Codevium cannot write files.
- Python 3 is needed only for the optional test emulator `tests/mhc_run.py` and for `run_tests.sh`.

## Files

```
fizzbuzz.asm                   original FizzBuzz source (input)
Assembler.java                 Part 3: assembler
Disassembler.java              Part 4: disassembler
fizzbuzz.mhc-ascii             assembler output, readable 0 and 1 characters
fizzbuzz.mhc-bin               assembler output, raw bytes
fizzbuzz.reconstructed.asm     disassembler output
run_tests.sh, tests/           test script, test inputs, test emulator
test_evidence.txt              output of run_tests.sh
```

## How to run

```
javac Assembler.java Disassembler.java

java Assembler fizzbuzz.asm
java Disassembler fizzbuzz.mhc-bin   fizzbuzz.reconstructed.asm
java Disassembler fizzbuzz.mhc-ascii other.asm

java Assembler fizzbuzz.reconstructed.asm check/fizzbuzz
cmp fizzbuzz.mhc-bin check/fizzbuzz.mhc-bin
```

- `java Assembler [--listing] <input.asm> [output-base]` writes `<output-base>.mhc-ascii` and `<output-base>.mhc-bin`. The base name defaults to the input path without `.asm`. `--listing` also prints each instruction with its source line, pseudoinstruction expansion, type (R, I or J) and bit fields.
- `java Disassembler <input> [output.asm]` detects the format on its own. The output name defaults to `<input>.asm`.
- On Windows use `fc /b a b` instead of `cmp a b`.
- `bash run_tests.sh` runs every test and prints a PASS or FAIL line for each (27 checks).

## Supported features

- Instructions: add, addi, addiu, addu, sub, ori, lui, div, mfhi, sll, beq, bne, j, jal, jr, lw, sw, syscall.
- Pseudoinstructions: li, la, move, rem (nonzero immediate divisor, uses $at), nop.
- Directives: .text, .data, .asciiz (one ASCII string per directive), .globl, .global.
- Labels (code and data), `#` comments, decimal, hex (0x) and character ('A', '\n') immediates, registers by name ($t0) or number ($8).
- Not supported: every other instruction or directive. They are reported as errors.

## Addresses, byte order and timing

- Text segment starts at 0x00400000. Data segment starts at 0x10010000.
- Entry address is the label `main` (the text base if there is no `main`).
- All 32-bit words and all header fields are big-endian: the most significant byte comes first.
- No delay slots (delayed branching off), which is the MARS default.

## File layout: .mhc-bin

All numbers are 32-bit big-endian.

```
offset  size  field
0       4     magic "MHCB" (0x4D 0x48 0x43 0x42)
4       4     text base address   (0x00400000)
8       4     text size in bytes  (4 x number of instructions)
12      4     data base address   (0x10010000)
16      4     data size in bytes
20      4     entry address
24      T     text: one 4-byte word per instruction
24+T    D     data: raw bytes of the .asciiz strings, NUL terminators included
```

For FizzBuzz: 24 + 180 + 10 = 214 bytes.

## File layout: .mhc-ascii

```
MHC-ASCII 1
ORDER big-endian
ENTRY 0x00400000
TEXT 0x00400000 words=45     <- 45 lines, each exactly 32 characters of 0 and 1
DATA 0x10010000 bytes=10     <- 8-character groups, up to 4 per line
END
```

## Telling instructions from data

Both formats carry the sizes of the two segments. In `.mhc-bin` the header gives the text size and data size, so the first T bytes after the header are instructions and the rest are data. In `.mhc-ascii` the `TEXT` and `DATA` header lines start each section and give its word or byte count. The disassembler checks these counts and rejects files that disagree with them.

## What the disassembler reconstructs

- Each NUL-terminated string in the data segment becomes `str_N: .asciiz "..."`.
- Each instruction word becomes one real instruction. A target of a branch or jump gets a label (`L_` plus its address); the entry address is named `main`.
- A `lui` and `ori` pair that loads the address of a string is written as `la`. `sll $zero, $zero, 0` is written as `nop`.
- Comments, original label names and the pseudoinstructions `li`, `move` and `rem` are not recovered. The real instructions they expand to are written instead, so assembling the reconstructed file gives identical bytes.

## Errors

Invalid input stops the program with exit status 1, writes a message to standard error and creates no output files. Examples:

```
Assembly failed: bad.asm: line 3: Unsupported instruction: mul (supported: ...)  [mul $t1, $t0, $t0]
Assembly failed: bad.asm: line 3: Undefined label: Missing  [j Missing]
Disassembly failed: bad.mhc-bin: File size mismatch: the header declares 180 text bytes and 10 data bytes (214 bytes in total) but the file has 100 bytes.
```

## Sources and collaboration

- `Assembler.java` is based on the starter assembler provided by the instructor. It was extended here to read files, write the two output formats, report errors with line numbers, and support add and sub.
- `Disassembler.java`, `run_tests.sh` and `tests/mhc_run.py` were written for this project with help from Claude (an AI assistant made by Anthropic).
- Student: [your name]. Edit this section to match your course's collaboration policy.
