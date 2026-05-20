OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
  DMEM (rwx) : ORIGIN = 0x00010000, LENGTH = 32K
}

SECTIONS
{
  .text : ALIGN(4)
  {
    KEEP(*(.init))
    *(.text .text.*)
  } > IMEM

  .data : ALIGN(4)
  {
    __global_pointer$ = . + 0x800;
    *(.srodata .srodata.*)
    *(.rodata .rodata.*)
    *(.sdata .sdata.*)
    *(.data .data.*)
  } > DMEM

  .bss (NOLOAD) : ALIGN(4)
  {
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    __bss_end = .;
  } > DMEM

  . = ALIGN(16);
  __stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
  PROVIDE(_end = .);
}
