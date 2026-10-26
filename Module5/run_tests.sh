#!/usr/bin/env bash
# Module 5 test run. Usage: bash run_tests.sh   (writes test_evidence.txt when run as: bash run_tests.sh | tee test_evidence.txt)
set -u
cd "$(dirname "$0")"
if command -v javac >/dev/null 2>&1; then JAVAC=(javac -d classes); else JAVAC=(java -m jdk.compiler/com.sun.tools.javac.Main -d classes); fi
rm -rf classes out out2 && mkdir -p classes out out2
pass=0; fail=0
check() { if [ "$2" = "0" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi; }
expected_output() { python3 -c 'for i in range(1,101): print("FizzBuzz" if i%15==0 else "Fizz" if i%3==0 else "Buzz" if i%5==0 else i)'; }

echo "== Build =="
"${JAVAC[@]}" Assembler.java Disassembler.java; check "javac Assembler.java Disassembler.java" $?
ASM="java -cp classes Assembler"; DIS="java -cp classes Disassembler"

echo; echo "== Test 1 (normal): Part 1 instructions assemble to the hand-calculated words =="
$ASM --listing tests/part1.asm out/part1 | cut -d"#" -f1-3
python3 - <<'PY'
want = [0x20080003, 0x20090005, 0x01095020, 0x01285822]
raw = open("out/part1.mhc-bin", "rb").read()[24:]
got = [int.from_bytes(raw[i:i+4], "big") for i in range(0, len(raw), 4)]
print("expected:", [f"{w:08X}" for w in want]); print("got:     ", [f"{w:08X}" for w in got])
raise SystemExit(0 if got == want else 1)
PY
check "Part 1 encodings match" $?

echo; echo "== Test 2 (normal): assemble FizzBuzz =="
$ASM --listing fizzbuzz.asm out/fizzbuzz | cut -d"#" -f1-3; check "assemble fizzbuzz.asm" ${PIPESTATUS[0]}
ls -l out/fizzbuzz.mhc-ascii out/fizzbuzz.mhc-bin
size=$(wc -c < out/fizzbuzz.mhc-bin); [ "$size" = "214" ]; check "mhc-bin is 24 header + 180 text + 10 data = 214 bytes (got $size)" $?
lines=$(grep -c '^[01]\{32\}$' out/fizzbuzz.mhc-ascii); [ "$lines" = "45" ]; check "mhc-ascii has 45 lines of exactly 32 bit characters (got $lines)" $?

echo; echo "== Test 3 (normal): original machine code prints FizzBuzz (emulator) =="
expected_output > out/expected.txt
python3 tests/mhc_run.py out/fizzbuzz.mhc-bin > out/run_bin.txt;   cmp out/expected.txt out/run_bin.txt;   check "mhc-bin output == FizzBuzz 1..100" $?
python3 tests/mhc_run.py out/fizzbuzz.mhc-ascii > out/run_ascii.txt; cmp out/expected.txt out/run_ascii.txt; check "mhc-ascii output == FizzBuzz 1..100" $?

echo; echo "== Test 4 (normal): disassemble BOTH formats =="
$DIS out/fizzbuzz.mhc-bin   out/from_bin.asm;   check "disassemble .mhc-bin" $?
$DIS out/fizzbuzz.mhc-ascii out/from_ascii.asm; check "disassemble .mhc-ascii" $?
cmp out/from_bin.asm out/from_ascii.asm; check "both formats give identical reconstructed source" $?

echo; echo "== Test 5 (normal): reassemble reconstructed source, compare bytes =="
$ASM out/from_bin.asm out2/fizzbuzz; check "assemble reconstructed source" $?
cmp out/fizzbuzz.mhc-bin   out2/fizzbuzz.mhc-bin;   check "machine-code bytes identical (.mhc-bin)" $?
cmp out/fizzbuzz.mhc-ascii out2/fizzbuzz.mhc-ascii; check "machine-code text identical (.mhc-ascii)" $?
python3 tests/mhc_run.py out2/fizzbuzz.mhc-bin > out/run_recon.txt; cmp out/expected.txt out/run_recon.txt; check "reconstructed program output == FizzBuzz 1..100" $?

echo; echo "== Edge cases: assembler must reject invalid input with a useful message =="
for f in tests/bad_*.asm; do
  echo "--- $f"; $ASM "$f" out/bad 2>&1; rc=$?; [ $rc -ne 0 ]; check "$f rejected (exit $rc)" $?
done
echo "--- missing input file"; $ASM tests/does_not_exist.asm out/bad 2>&1; [ $? -ne 0 ]; check "missing file rejected" $?
[ ! -e out/bad.mhc-bin ]; check "no output files written for rejected input" $?

echo; echo "== Edge cases: disassembler must reject invalid input with a useful message =="
printf 'hello world, not an mhc file' > out/bad_magic.mhc-bin
head -c 100 out/fizzbuzz.mhc-bin > out/bad_truncated.mhc-bin
python3 - <<'PY'
b = bytearray(open("out/fizzbuzz.mhc-bin", "rb").read())
b[24:28] = (0x70000000).to_bytes(4, "big")          # opcode 0b011100 is not supported
open("out/bad_opcode.mhc-bin", "wb").write(bytes(b))
t = open("out/fizzbuzz.mhc-ascii").read().splitlines()
t2 = list(t); t2[4] = "0010010000001001000000000000000"       # 31 characters
open("out/bad_short_line.mhc-ascii", "w").write("\n".join(t2) + "\n")
t3 = [l for l in t if l != "END"]
open("out/bad_no_end.mhc-ascii", "w").write("\n".join(t3) + "\n")
PY
for f in out/bad_magic.mhc-bin out/bad_truncated.mhc-bin out/bad_opcode.mhc-bin out/bad_short_line.mhc-ascii out/bad_no_end.mhc-ascii; do
  echo "--- $f"; $DIS "$f" out/bad.asm 2>&1; rc=$?; [ $rc -ne 0 ]; check "$f rejected (exit $rc)" $?
done

echo; echo "== Summary: $pass passed, $fail failed =="
[ "$fail" = "0" ]
