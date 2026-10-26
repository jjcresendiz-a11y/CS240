import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Map;
import java.util.TreeMap;
import java.util.TreeSet;

/*
 * MIPS disassembler for Module 5 (Assembler and Disassembler Project). Java 8+.
 * Reads a file written by Assembler.java and writes a MIPS assembly file that
 * Assembler.java can assemble back into the same machine-code bytes.
 *
 * Build and run:
 *   javac Disassembler.java
 *   java Disassembler fizzbuzz.mhc-bin                 -> fizzbuzz.mhc-bin.asm
 *   java Disassembler fizzbuzz.mhc-ascii               -> fizzbuzz.mhc-ascii.asm
 *   java Disassembler fizzbuzz.mhc-bin reconstructed.asm
 *
 * The input format is detected from the first bytes of the file:
 *   "MHCB"       -> .mhc-bin   (24-byte big-endian header, text bytes, data bytes)
 *   "MHC-ASCII"  -> .mhc-ascii (TEXT / DATA sections of 0 and 1 characters)
 * The exact layouts are documented at the top of Assembler.java and in the README.
 *
 * What is reconstructed:
 *   - .data: every NUL-terminated string becomes  str_N: .asciiz "..."
 *   - .text: one real instruction per 32-bit word (add, addi, addiu, addu, sub,
 *     ori, lui, div, mfhi, sll, beq, bne, j, jal, jr, lw, sw, syscall)
 *   - labels for every branch/jump target; the entry address is named main
 *   - a lui/ori pair that loads the address of a string is written as la
 *   - sll $zero, $zero, 0 is written as nop
 * Original comments, label names and other pseudoinstruction spellings (li, move,
 * rem) are not recovered; the real instructions they expand to are written instead.
 *
 * Errors (bad magic, truncated file, unknown opcode, ...) are reported with a
 * message that says what is wrong and where, and the program exits with status 1.
 */
public class Disassembler {
    static final int TEXT_BASE = 0x00400000;
    static final int DATA_BASE = 0x10010000;

    private static final String[] REG = {
        "zero", "at", "v0", "v1", "a0", "a1", "a2", "a3",
        "t0", "t1", "t2", "t3", "t4", "t5", "t6", "t7",
        "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7",
        "t8", "t9", "k0", "k1", "gp", "sp", "fp", "ra"
    };

    /** The decoded contents of an .mhc file, independent of which format it came from. */
    static class Image {
        int textBase, dataBase, entry;
        byte[] text, data;
    }

    static class DisassemblyException extends Exception {
        DisassemblyException(String message) { super(message); }
    }

    public static void main(String[] args) {
        if (args.length < 1 || args.length > 2) {
            System.out.println("Usage: java Disassembler <file.mhc-bin | file.mhc-ascii> [output.asm]");
            System.out.println("Output defaults to <input>.asm");
            System.exit(2);
        }
        String input = args[0];
        String output = args.length == 2 ? args[1] : input + ".asm";
        try {
            byte[] bytes;
            try {
                bytes = Files.readAllBytes(Paths.get(input));
            } catch (IOException e) {
                throw new DisassemblyException("Cannot read input file (not found or not readable)");
            }
            Image image = load(bytes);
            String asm = disassemble(image);
            try {
                Files.write(Paths.get(output), asm.getBytes(StandardCharsets.US_ASCII));
            } catch (IOException e) {
                throw new DisassemblyException("Cannot write output file '" + output + "' (" + e.getClass().getSimpleName() + ")");
            }
            System.out.println("Disassembled " + input + ": " + (image.text.length / 4)
                + " instructions, " + image.data.length + " data bytes");
            System.out.println("Wrote " + output);
        } catch (DisassemblyException e) {
            System.err.println("Disassembly failed: " + input + ": " + e.getMessage());
            System.exit(1);
        }
    }

    // ---------------------------------------------------------------- loading

    static Image load(byte[] bytes) throws DisassemblyException {
        if (bytes.length >= 4 && bytes[0] == 'M' && bytes[1] == 'H' && bytes[2] == 'C' && bytes[3] == 'B') {
            return loadBinary(bytes);
        }
        String start = new String(bytes, 0, Math.min(bytes.length, 9), StandardCharsets.ISO_8859_1);
        if (start.equals("MHC-ASCII")) {
            return loadAscii(new String(bytes, StandardCharsets.ISO_8859_1));
        }
        throw new DisassemblyException("Unrecognized file format: expected magic \"MHCB\" (.mhc-bin) "
            + "or first line \"MHC-ASCII 1\" (.mhc-ascii).");
    }

    private static int word(byte[] b, int offset) {
        return ((b[offset] & 255) << 24) | ((b[offset + 1] & 255) << 16)
             | ((b[offset + 2] & 255) << 8) | (b[offset + 3] & 255);
    }

    static Image loadBinary(byte[] b) throws DisassemblyException {
        if (b.length < 24) {
            throw new DisassemblyException("File is truncated: the .mhc-bin header needs 24 bytes but the file has "
                + b.length + ".");
        }
        Image image = new Image();
        image.textBase = word(b, 4);
        long textSize = word(b, 8) & 0xFFFFFFFFL;
        image.dataBase = word(b, 12);
        long dataSize = word(b, 16) & 0xFFFFFFFFL;
        image.entry = word(b, 20);
        if (24 + textSize + dataSize != b.length) {
            throw new DisassemblyException("File size mismatch: the header declares " + textSize + " text bytes and "
                + dataSize + " data bytes (" + (24 + textSize + dataSize) + " bytes in total) but the file has "
                + b.length + " bytes.");
        }
        image.text = java.util.Arrays.copyOfRange(b, 24, 24 + (int) textSize);
        image.data = java.util.Arrays.copyOfRange(b, 24 + (int) textSize, b.length);
        return image;
    }

    static Image loadAscii(String content) throws DisassemblyException {
        String[] lines = content.split("\\r\\n|\\r|\\n");
        Image image = new Image();
        image.textBase = TEXT_BASE;
        image.dataBase = DATA_BASE;
        image.entry = -1;
        java.io.ByteArrayOutputStream text = new java.io.ByteArrayOutputStream();
        java.io.ByteArrayOutputStream data = new java.io.ByteArrayOutputStream();
        String section = "";
        long expectedWords = -1, expectedBytes = -1;
        boolean sawEnd = false, sawHeader = false, sawOrder = false;
        for (int i = 0; i < lines.length; i++) {
            String line = lines[i];
            int hash = line.indexOf('#');
            if (hash >= 0) line = line.substring(0, hash);
            line = line.trim();
            if (line.isEmpty()) continue;
            int n = i + 1;
            if (line.startsWith("MHC-ASCII")) {
                if (!line.equals("MHC-ASCII 1")) {
                    throw new DisassemblyException("line " + n + ": unsupported version '" + line + "' (expected \"MHC-ASCII 1\").");
                }
                sawHeader = true;
            } else if (line.startsWith("ORDER")) {
                if (!line.equals("ORDER big-endian")) {
                    throw new DisassemblyException("line " + n + ": unsupported byte order '" + line + "' (expected \"ORDER big-endian\").");
                }
                sawOrder = true;
            } else if (line.startsWith("ENTRY")) {
                image.entry = (int) parseNumber(line.substring(5).trim(), n);
            } else if (line.startsWith("TEXT ") || line.startsWith("DATA ")) {
                String[] parts = line.split("\\s+");
                boolean isText = parts[0].equals("TEXT");
                String sizeKey = isText ? "words=" : "bytes=";
                if (parts.length != 3 || !parts[2].startsWith(sizeKey)) {
                    throw new DisassemblyException("line " + n + ": expected \"" + parts[0] + " <address> " + sizeKey + "<count>\" but found '" + line + "'.");
                }
                long address = parseNumber(parts[1], n);
                long count = parseNumber(parts[2].substring(sizeKey.length()), n);
                if (isText) { image.textBase = (int) address; expectedWords = count; }
                else { image.dataBase = (int) address; expectedBytes = count; }
                section = parts[0];
            } else if (line.equals("END")) {
                sawEnd = true;
                break;
            } else if (section.equals("TEXT")) {
                if (!line.matches("[01]{32}")) {
                    throw new DisassemblyException("line " + n + ": a TEXT line must be exactly 32 '0'/'1' characters but found '" + line + "'.");
                }
                long w = Long.parseLong(line, 2);
                for (int shift = 24; shift >= 0; shift -= 8) text.write((int) (w >>> shift));
            } else if (section.equals("DATA")) {
                for (String group : line.split("\\s+")) {
                    if (!group.matches("[01]{8}")) {
                        throw new DisassemblyException("line " + n + ": a DATA group must be exactly 8 '0'/'1' characters but found '" + group + "'.");
                    }
                    data.write(Integer.parseInt(group, 2));
                }
            } else {
                throw new DisassemblyException("line " + n + ": unexpected content before a TEXT or DATA header: '" + line + "'.");
            }
        }
        if (!sawHeader) throw new DisassemblyException("missing \"MHC-ASCII 1\" header line.");
        if (!sawOrder) throw new DisassemblyException("missing \"ORDER big-endian\" line.");
        if (!sawEnd) throw new DisassemblyException("missing END line (file may be truncated).");
        if (expectedWords < 0) throw new DisassemblyException("missing TEXT section header.");
        if (expectedBytes < 0) throw new DisassemblyException("missing DATA section header.");
        image.text = text.toByteArray();
        image.data = data.toByteArray();
        if (image.text.length != expectedWords * 4) {
            throw new DisassemblyException("TEXT section declares " + expectedWords + " words but contains "
                + (image.text.length / 4) + ".");
        }
        if (image.data.length != expectedBytes) {
            throw new DisassemblyException("DATA section declares " + expectedBytes + " bytes but contains "
                + image.data.length + ".");
        }
        if (image.entry == -1) image.entry = image.textBase;
        return image;
    }

    private static long parseNumber(String s, int line) throws DisassemblyException {
        try {
            if (s.startsWith("0x") || s.startsWith("0X")) return Long.parseLong(s.substring(2), 16);
            return Long.parseLong(s);
        } catch (NumberFormatException e) {
            throw new DisassemblyException("line " + line + ": invalid number '" + s + "'.");
        }
    }

    // ----------------------------------------------------------- disassembling

    private static String hex8(int value) {
        String h = Integer.toHexString(value);
        return "00000000".substring(h.length()) + h;
    }

    private static String reg(int number) {
        return "$" + REG[number];
    }

    static String disassemble(Image image) throws DisassemblyException {
        if (image.textBase != TEXT_BASE || image.dataBase != DATA_BASE) {
            throw new DisassemblyException("Unsupported segment base addresses (text 0x" + hex8(image.textBase)
                + ", data 0x" + hex8(image.dataBase) + "); this toolchain only supports text 0x"
                + hex8(TEXT_BASE) + " and data 0x" + hex8(DATA_BASE) + ".");
        }
        if (image.text.length % 4 != 0) {
            throw new DisassemblyException("Text size " + image.text.length + " is not a multiple of 4 bytes.");
        }
        int count = image.text.length / 4;
        int textEnd = TEXT_BASE + image.text.length;
        if (image.entry < TEXT_BASE || image.entry > textEnd || (image.entry & 3) != 0) {
            throw new DisassemblyException("Entry address 0x" + hex8(image.entry) + " is not an instruction address in the text segment.");
        }

        // Data: split into NUL-terminated strings.
        Map<Integer, String> dataLabels = new TreeMap<>();
        Map<Integer, String> dataStrings = new TreeMap<>();
        int start = 0, stringIndex = 0;
        for (int i = 0; i < image.data.length; i++) {
            int c = image.data[i] & 255;
            if (c == 0) {
                String name = "str_" + stringIndex++;
                dataLabels.put(DATA_BASE + start, name);
                dataStrings.put(DATA_BASE + start, escape(image.data, start, i, DATA_BASE + start));
                start = i + 1;
            }
        }
        if (start != image.data.length) {
            throw new DisassemblyException("Data segment does not end with a NUL byte; the last string starting at 0x"
                + hex8(DATA_BASE + start) + " is not terminated, so it cannot be written as .asciiz.");
        }

        // Pass 1: decode every word and find branch/jump targets.
        int[] words = new int[count];
        TreeSet<Integer> targets = new TreeSet<>();
        for (int i = 0; i < count; i++) {
            int w = word(image.text, i * 4);
            words[i] = w;
            int address = TEXT_BASE + i * 4;
            int op = w >>> 26;
            if (op == 4 || op == 5) {
                int target = address + 4 + ((short) w) * 4;
                checkTarget(target, textEnd, address, w);
                targets.add(target);
            } else if (op == 2 || op == 3) {
                int target = ((address + 4) & 0xF0000000) | ((w & 0x03FFFFFF) << 2);
                checkTarget(target, textEnd, address, w);
                targets.add(target);
            }
        }
        Map<Integer, String> labels = new HashMap<>();
        for (int t : targets) labels.put(t, t == image.entry ? "main" : "L_" + hex8(t));
        if (!labels.containsKey(image.entry)) labels.put(image.entry, "main");

        StringBuilder out = new StringBuilder();
        out.append("# Reconstructed by Disassembler.java\r\n");
        out.append("# Labels, formatting and pseudoinstructions are regenerated, not recovered.\r\n\r\n");
        if (!dataLabels.isEmpty()) {
            out.append(".data\r\n");
            for (Map.Entry<Integer, String> e : dataLabels.entrySet()) {
                out.append(e.getValue()).append(": .asciiz \"").append(dataStrings.get(e.getKey())).append("\"\r\n");
            }
            out.append("\r\n");
        }
        out.append(".text\r\n.globl main\r\n\r\n");

        // Pass 2: write instructions.
        for (int i = 0; i < count; i++) {
            int address = TEXT_BASE + i * 4;
            if (labels.containsKey(address)) out.append(labels.get(address)).append(":\r\n");
            int w = words[i];
            // la = lui + ori on the same register, pointing at the start of a string.
            if ((w >>> 26) == 15 && i + 1 < count && !labels.containsKey(address + 4)) {
                int next = words[i + 1];
                int rt = (w >>> 16) & 31;
                if ((w >>> 21 & 31) == 0 && (next >>> 26) == 13 && ((next >>> 21) & 31) == rt
                        && ((next >>> 16) & 31) == rt) {
                    int value = ((w & 0xFFFF) << 16) | (next & 0xFFFF);
                    if (dataLabels.containsKey(value)) {
                        out.append("    la ").append(reg(rt)).append(", ").append(dataLabels.get(value)).append("\r\n");
                        i++;
                        continue;
                    }
                }
            }
            out.append("    ").append(decode(w, address, labels)).append("\r\n");
        }
        if (labels.containsKey(textEnd)) out.append(labels.get(textEnd)).append(":\r\n");
        return out.toString();
    }

    private static void checkTarget(int target, int textEnd, int address, int w) throws DisassemblyException {
        if (target < TEXT_BASE || target > textEnd || (target & 3) != 0) {
            throw new DisassemblyException("Instruction 0x" + hex8(w) + " at address 0x" + hex8(address)
                + " branches or jumps to 0x" + hex8(target) + ", which is outside the text segment.");
        }
    }

    private static String escape(byte[] data, int from, int to, int address) throws DisassemblyException {
        StringBuilder sb = new StringBuilder();
        for (int i = from; i < to; i++) {
            int c = data[i] & 255;
            if (c == '\n') sb.append("\\n");
            else if (c == '\r') sb.append("\\r");
            else if (c == '\t') sb.append("\\t");
            else if (c == '\\') sb.append("\\\\");
            else if (c == '"') sb.append("\\\"");
            else if (c >= 32 && c <= 126) sb.append((char) c);
            else {
                throw new DisassemblyException("Data byte 0x" + Integer.toHexString(c) + " at address 0x"
                    + hex8(address + (i - from)) + " is not printable ASCII, so it cannot be written as .asciiz.");
            }
        }
        return sb.toString();
    }

    /** Decode one instruction word; every unused field must be zero so the text re-assembles to the same word. */
    static String decode(int w, int address, Map<Integer, String> labels) throws DisassemblyException {
        int op = w >>> 26;
        int rs = (w >>> 21) & 31, rt = (w >>> 16) & 31, rd = (w >>> 11) & 31, shamt = (w >>> 6) & 31;
        int funct = w & 63;
        short imm = (short) w;
        switch (op) {
            case 0:
                switch (funct) {
                    case 0x00:
                        if (rs != 0) break;
                        if (w == 0) return "nop";
                        return "sll " + reg(rd) + ", " + reg(rt) + ", " + shamt;
                    case 0x08:
                        if (rt != 0 || rd != 0 || shamt != 0) break;
                        return "jr " + reg(rs);
                    case 0x0C:
                        if (w != 0x0000000C) break;
                        return "syscall";
                    case 0x10:
                        if (rs != 0 || rt != 0 || shamt != 0) break;
                        return "mfhi " + reg(rd);
                    case 0x1A:
                        if (rd != 0 || shamt != 0) break;
                        return "div " + reg(rs) + ", " + reg(rt);
                    case 0x20: case 0x21: case 0x22:
                        if (shamt != 0) break;
                        String name = funct == 0x20 ? "add" : funct == 0x21 ? "addu" : "sub";
                        return name + " " + reg(rd) + ", " + reg(rs) + ", " + reg(rt);
                    default:
                }
                throw unsupported(w, address, "R-type instruction with funct 0b" + Integer.toBinaryString(64 | funct).substring(1)
                    + " (or non-zero unused fields)");
            case 2: case 3: {
                int target = ((address + 4) & 0xF0000000) | ((w & 0x03FFFFFF) << 2);
                return (op == 2 ? "j " : "jal ") + labels.get(target);
            }
            case 4: case 5: {
                int target = address + 4 + imm * 4;
                return (op == 4 ? "beq " : "bne ") + reg(rs) + ", " + reg(rt) + ", " + labels.get(target);
            }
            case 8: return "addi " + reg(rt) + ", " + reg(rs) + ", " + imm;
            case 9: return "addiu " + reg(rt) + ", " + reg(rs) + ", " + imm;
            case 13: return "ori " + reg(rt) + ", " + reg(rs) + ", " + (w & 0xFFFF);
            case 15:
                if (rs != 0) break;
                return "lui " + reg(rt) + ", " + (w & 0xFFFF);
            case 35: return "lw " + reg(rt) + ", " + imm + "(" + reg(rs) + ")";
            case 43: return "sw " + reg(rt) + ", " + imm + "(" + reg(rs) + ")";
            default:
        }
        throw unsupported(w, address, "opcode 0b" + Integer.toBinaryString(64 | op).substring(1));
    }

    private static DisassemblyException unsupported(int w, int address, String what) {
        return new DisassemblyException("Unsupported machine code 0x" + hex8(w) + " at address 0x" + hex8(address)
            + ": " + what + ". Supported: add, addi, addiu, addu, sub, ori, lui, div, mfhi, sll, beq, bne, j, jal, jr, lw, sw, syscall.");
    }
}
