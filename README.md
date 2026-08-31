# ASMS_OS
Aurora software management system project

ASMS is a operating system made by me that works out with 8 bits FAT and 16 bytes root entries size

current avaible commands:
  **DIR**   : No Arguments, lists root directory files.
  **VER**   : No Arguments, Prints kernel version
  **REBZOO**: No Arguments,Reboots the system.
  **WRITE** : Arg1 = <Filename>, Arg2 = <Data Buffer>, Create a new root directory file with **<Filename>** as name and writes 256 bytes (only 1 cluster) from the provided data in **<Data Buffer>**.
  **DEL**   : Arg1 = <Filename>, Deletes the file with the name **<Filename>** (do not delete **kernel.bin**)
  **CHECK** : Arg1 = <Filename>, Prints the **<Filename>** file size in bytes.
  **RUN**   : Arg1 = <Filename>, Runs **<Filename>** No matter it's extension.

The Entire code was written in assembly and designed to run on CPU 80286 / i286.
