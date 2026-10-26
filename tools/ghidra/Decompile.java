// Prints Ghidra's decompiled C for the functions containing the given addresses.
// Headless use (tools/ghidra/decompile.ps1 wraps this):
//   analyzeHeadless <projects> MKSMK -process default.xbe -noanalysis -readOnly
//       -scriptPath tools/ghidra -postScript Decompile.java <out file> 0x9c3f0 0x13954 ...
// A thunk (jmp stub) is followed to its target. Read-only: changes nothing.
//@category MKSMK

import java.io.FileWriter;
import java.io.PrintWriter;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class Decompile extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            println("usage: Decompile.java <out file> <address> [address ...]");
            return;
        }
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        try (PrintWriter out = new PrintWriter(new FileWriter(args[0]))) {
            for (int i = 1; i < args.length; i++) {
                Address addr = toAddr(Long.decode(args[i]));
                Function fn = getFunctionContaining(addr);
                if (fn == null) {
                    disassemble(addr);
                    fn = createFunction(addr, null);
                }
                if (fn == null) {
                    out.println("// " + args[i] + ": no function here\n");
                    continue;
                }
                if (fn.isThunk() && fn.getThunkedFunction(true) != null) {
                    out.println("// " + args[i] + ": thunk to " + fn.getThunkedFunction(true).getEntryPoint());
                    fn = fn.getThunkedFunction(true);
                }
                DecompileResults res = decomp.decompileFunction(fn, 60, monitor);
                out.println("// ===== " + args[i] + " -> " + fn.getName() + " @ " + fn.getEntryPoint());
                if (res.decompileCompleted()) {
                    out.println(res.getDecompiledFunction().getC());
                } else {
                    out.println("// decompile failed: " + res.getErrorMessage() + "\n");
                }
            }
        } finally {
            decomp.dispose();
        }
    }
}
