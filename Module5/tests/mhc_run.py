#!/usr/bin/env python3
"""Tiny MIPS emulator used only as TEST EVIDENCE for the Module 5 project.

It loads a .mhc-bin or .mhc-ascii file, runs it from the entry address with
SPIM/MARS-style syscalls (1 print int, 4 print string, 11 print char, 10 exit)
and prints whatever the program prints.  It decodes the machine code by bit
fields on its own, so it is an independent check of the assembler's encoding.

    python3 tests/mhc_run.py fizzbuzz.mhc-bin
"""
import re
import sys


def load(path):
    raw = open(path, "rb").read()
    if raw[:4] == b"MHCB":
        text_base, text_size, data_base, data_size, entry = (
            int.from_bytes(raw[4 + 4 * i:8 + 4 * i], "big") for i in range(5))
        text = raw[24:24 + text_size]
        data = raw[24 + text_size:24 + text_size + data_size]
    else:
        text, data, section, entry = bytearray(), bytearray(), None, 0x00400000
        text_base, data_base = 0x00400000, 0x10010000
        for line in raw.decode("ascii").splitlines():
            line = line.strip()
            if line.startswith("ENTRY"):
                entry = int(line.split()[1], 16)
            elif line.startswith("TEXT"):
                section = "t"; text_base = int(line.split()[1], 16)
            elif line.startswith("DATA"):
                section = "d"; data_base = int(line.split()[1], 16)
            elif re.fullmatch(r"[01]{32}", line):
                text += int(line, 2).to_bytes(4, "big")
            elif section == "d" and re.fullmatch(r"([01]{8} ?)+", line):
                data += bytes(int(g, 2) for g in line.split())
        text, data = bytes(text), bytes(data)
    return text_base, text, data_base, data, entry


def run(path, max_steps=1_000_000):
    text_base, text, data_base, data, entry = load(path)
    mem = {}
    for i, b in enumerate(data):
        mem[data_base + i] = b
    reg = [0] * 32
    reg[29] = 0x7FFFEFFC
    hi = lo = 0
    pc = entry
    out = []

    def s16(x): return x - 0x10000 if x & 0x8000 else x
    def s32(x): return x - (1 << 32) if x & (1 << 31) else x
    def lw(a): return int.from_bytes(bytes(mem.get(a + i, 0) for i in range(4)), "big")
    def sw(a, v):
        for i, b in enumerate(v.to_bytes(4, "big")): mem[a + i] = b

    for _ in range(max_steps):
        off = pc - text_base
        if not 0 <= off < len(text):
            raise RuntimeError(f"pc 0x{pc:08x} left the text segment")
        w = int.from_bytes(text[off:off + 4], "big")
        op, rs, rt, rd = w >> 26, (w >> 21) & 31, (w >> 16) & 31, (w >> 11) & 31
        sh, fn, imm = (w >> 6) & 31, w & 63, w & 0xFFFF
        npc = pc + 4
        if op == 0:
            if fn == 0x00: reg[rd] = (reg[rt] << sh) & 0xFFFFFFFF
            elif fn == 0x08: npc = reg[rs]
            elif fn == 0x0C:
                v0, a0 = reg[2], reg[4]
                if v0 == 1: out.append(str(s32(a0)))
                elif v0 == 4:
                    s = bytearray()
                    while mem.get(a0, 0): s.append(mem[a0]); a0 += 1
                    out.append(s.decode("ascii"))
                elif v0 == 11: out.append(chr(a0 & 255))
                elif v0 == 10: return "".join(out)
                else: raise RuntimeError(f"unsupported syscall {v0}")
            elif fn == 0x10: reg[rd] = hi
            elif fn == 0x1A:
                a, b = s32(reg[rs]), s32(reg[rt])
                q = abs(a) // abs(b) * (1 if (a < 0) == (b < 0) else -1)
                lo, hi = q & 0xFFFFFFFF, (a - q * b) & 0xFFFFFFFF
            elif fn in (0x20, 0x21): reg[rd] = (reg[rs] + reg[rt]) & 0xFFFFFFFF
            elif fn == 0x22: reg[rd] = (reg[rs] - reg[rt]) & 0xFFFFFFFF
            else: raise RuntimeError(f"bad funct {fn:#x} at {pc:#x}")
        elif op == 2: npc = ((pc + 4) & 0xF0000000) | ((w & 0x03FFFFFF) << 2)
        elif op == 3: reg[31] = pc + 4; npc = ((pc + 4) & 0xF0000000) | ((w & 0x03FFFFFF) << 2)
        elif op == 4:
            if reg[rs] == reg[rt]: npc = pc + 4 + s16(imm) * 4
        elif op == 5:
            if reg[rs] != reg[rt]: npc = pc + 4 + s16(imm) * 4
        elif op in (8, 9): reg[rt] = (reg[rs] + s16(imm)) & 0xFFFFFFFF
        elif op == 13: reg[rt] = reg[rs] | imm
        elif op == 15: reg[rt] = imm << 16
        elif op == 35: reg[rt] = lw(reg[rs] + s16(imm))
        elif op == 43: sw(reg[rs] + s16(imm), reg[rt])
        else: raise RuntimeError(f"bad opcode {op} at {pc:#x}")
        reg[0] = 0
        pc = npc
    raise RuntimeError("step limit reached (infinite loop?)")


if __name__ == "__main__":
    sys.stdout.write(run(sys.argv[1]))
