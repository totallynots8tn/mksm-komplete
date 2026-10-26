# Ghidra for default.xbe

A decompiler for the game's code, set up once on this PC (outside the repo):

- Ghidra 12.1.4 in `C:\Users\Arcade Machine 1\Tools\ghidra_12.1.4_PUBLIC`
  (SHA-256 checked against the official release);
- the XBE loader (XboxDev/ghidra-xbe, build 202610161023, for Ghidra 12.1.4)
  in its `Ghidra\Extensions`;
- the analysed project `MKSMK` (with `default.xbe`) in
  `C:\Users\Arcade Machine 1\Tools\ghidra-projects`;
- Java: the installed JDK 23 (`C:\Program Files\Java\jdk-23`).

**Decompile from the command line** (read-only, opens nothing on screen):

```
powershell -File tools/ghidra/decompile.ps1 0x9c3f0 0x13954
```

It prints the C for the function containing each address (thunks are
followed) and keeps it in `tools/ghidra/out/last.c`. The paths can be
overridden with `GHIDRA_HOME`, `GHIDRA_PROJECTS` and `JAVA_HOME`.

**Interactive:** run `ghidraRun.bat` in the Ghidra folder and open the project
`MKSMK` from `C:\Users\Arcade Machine 1\Tools\ghidra-projects`.
