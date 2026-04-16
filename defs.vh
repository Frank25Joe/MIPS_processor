`define OP_REG 6'h0
`define OP_ADDI 6'h8
`define OP_ANDI 6'hc
`define OP_ORI 6'hd
`define OP_XORI 6'he
`define OP_BLTZ_BGEZ 6'h1
`define OP_BEQ 6'h4
`define OP_BNE 6'h5
`define OP_BLEZ 6'h6
`define OP_BGTZ 6'h7
`define OP_SLTI 6'ha
`define OP_SLTIU 6'hb
`define OP_J 6'h2
`define OP_JAL 6'h3
`define OP_LUI 6'hf
`define OP_LB 6'h20
`define OP_LH 6'h21
`define OP_LW 6'h23
`define OP_LBU 6'h24
`define OP_LHU 6'h25
`define OP_SB 6'h28
`define OP_SH 6'h29
`define OP_SW 6'h2b

`define FUNC_SLL 6'h0
`define FUNC_SRL 6'h2
`define FUNC_SRA 6'h3
`define FUNC_SLLV 6'h4
`define FUNC_SRLV 6'h6
`define FUNC_SRAV 6'h7
`define FUNC_SYSCALL 6'hc
`define FUNC_ADD 6'h20
`define FUNC_SUB 6'h22
`define FUNC_AND 6'h24
`define FUNC_OR 6'h25
`define FUNC_XOR 6'h26
`define FUNC_NOR 6'h27
`define FUNC_JR 6'h8
`define FUNC_JALR 6'h9
`define FUNC_SLT 6'h2a
`define FUNC_SLTU 6'h2b
`define READ_COMMAND 2'b00 // Memory read command
`define WRITE_COMMAND 2'b01 // Memory write command
`define SUBWORD_WRITE_COMMAND 2'b10 // Memory subword write command
`define SYS_exit 32'd1001 // Syscall number for exit
`define SYS_write 32'd1004 // Syscall number for print
`define SYS_read 32'd1003 // syscall for keyboard input