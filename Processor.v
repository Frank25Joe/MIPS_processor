`include "defs.vh"
`include "ALU.v"
`include "RegisterFile.v"

module Processor(input clk, output reg halt, input reset, output reg [7:0] pc, input [31:0] ins, output [31:0] io_reg1, output [31:0] io_reg2, output [31:0] io_reg3, output [31:0] io_reg4, input copied_io_regs, output io_stall, output reg [1:0] io_reg_index, input [31:0] input_value, input input_value_valid, output reg waiting_for_input, input [31:0] load_value, output [7:0] data_addr, output data_addr_valid, output [1:0] data_mem_command, output reg [31:0] store_value);
    wire [5:0] opcode; // Extracted from ins
    wire [5:0] func; // Extracted from ins
    wire [4:0] shift_amount; // Extracted from ins
    wire [4:0] src1_addr; // rs extracted from ins (input to RF)
    wire [4:0] src2_addr; // rt extracted from ins (input to RF)
    wire [31:0] src1; // Output of RF, input to ALU
    wire [31:0] src2; // Output of RF, possible input to ALU
    wire [31:0] alu_src1; // Input to ALU
    wire [31:0] alu_src2; // Input to ALU
    wire [25:0] jump_target; // Extracted from ins
    wire [4:0] dest_addr; // rt/rd extracted from ins (input to RF)
    wire [31:0] dest_data; // Output of ALU, input to RF
    wire dest_data_valid; // Output of ALU, input to RF
    wire [7:0] next_pc; // Next instruction address
    wire using_imm; // Is the ins which is currently in execute stage using imm field?
    wire [15:0] imm; // Immediate extracted from ins
    wire is_mem_op; // Is it a memory operation?
    wire is_load; // Is the ins currently in execute stage a load operation?
    wire load_hazard;
    wire [4:0] rt; // Distinguish between bltz, bgez
    
    // Pipeline registers
    reg mem_wb_write_enable_reg;
    reg [4:0] mem_wb_write_addr_reg;
    reg [31:0] mem_wb_write_data_reg;
    reg [5:0] id_ex_opcode_reg;
    reg [5:0] id_ex_func_reg;
    reg [4:0] id_ex_shift_amount_reg;
    reg [4:0] id_ex_src1_addr_reg;
    reg [4:0] id_ex_src2_addr_reg;
    reg [31:0] id_ex_src1_reg;
    reg [31:0] id_ex_src2_reg;
    reg id_ex_using_imm_reg;
    reg [15:0] id_ex_imm_reg;
    reg [4:0] id_ex_dest_addr_reg;
    reg [25:0] id_ex_jump_target_reg;
    reg id_ex_is_mem_op_reg;
    reg [4:0] id_ex_rt;
    reg [5:0] ex_mem_opcode_reg;
    reg [7:0] ex_mem_data_addr_reg;
    reg [1:0] ex_mem_data_mem_command_reg;
    reg ex_mem_data_addr_valid_reg;
    reg ex_mem_write_enable_reg;
    reg [4:0] ex_mem_write_addr_reg;
    reg [31:0] ex_mem_write_data_reg;
    reg [31:0] ex_mem_store_value_reg;
    
    wire ex_mem_bypass_src1;
    wire ex_mem_bypass_src2;
    wire mem_wb_bypass_src1;
    wire mem_wb_bypass_src2;
    wire [31:0] final_src1;
    wire [31:0] final_src2;
    
    wire pipeline_stall;
    wire is_sys_write; // Is the ins which is currently in execute stage write syscall?
    wire is_sys_read; // Is the ins which is currently in execute stage read syscall?
    wire is_sys_exit; // Is the ins which is currently in execute stage exit syscall?

    reg [31:0] io_reg [0:3]; // Circular I/O buffer
    reg [31:0] keyboard_input;
    reg fetched; // Is first instruction fetched?
    reg printed; // Is first io_print executed?
    reg input_read; // To track if keyboard input has been read; Required because input_valid signal may change much slower than clk period
    
    assign io_reg1 = io_reg[0];
    assign io_reg2 = io_reg[1];
    assign io_reg3 = io_reg[2];
    assign io_reg4 = io_reg[3];

    wire [31:0] branch_offset; // Input to ALU
    wire branch_taken; // Output of ALU

    assign branch_offset = ((id_ex_opcode_reg == `OP_J) || (id_ex_opcode_reg == `OP_JAL)) ? {6'b0, id_ex_jump_target_reg} : {{16{id_ex_imm_reg[15]}}, id_ex_imm_reg};
    
    reg [31:0] clean_load_value;

    always @(*) begin
        case (ex_mem_opcode_reg)
            `OP_SW: begin
                store_value = ex_mem_store_value_reg;
            end
            `OP_SH: begin
                store_value = (ex_mem_write_data_reg[1:0] == 2'b00) ? {ex_mem_store_value_reg[15:0], load_value[15:0]} : {load_value[31:16], ex_mem_store_value_reg[15:0]};
            end
            `OP_SB: begin
                case (ex_mem_write_data_reg[1:0])
                    2'b00: begin
                        store_value = {ex_mem_store_value_reg[7:0], load_value[23:0]};
                    end
                    2'b01: begin
                        store_value = {load_value[31:24], ex_mem_store_value_reg[7:0], load_value[15:0]};
                    end
                    2'b10: begin
                        store_value = {load_value[31:16], ex_mem_store_value_reg[7:0], load_value[7:0]};
                    end
                    2'b11: begin
                        store_value = {load_value[31:8], ex_mem_store_value_reg[7:0]};
                    end
                endcase
            end
            default: begin
                store_value = 32'b0;
            end
        endcase
    end

    always @(*) begin
        case (ex_mem_opcode_reg)
            `OP_LW: begin
                clean_load_value = load_value;
            end
            `OP_LH: begin
                clean_load_value = (ex_mem_write_data_reg[1:0] == 2'b00) ? {{16{load_value[31]}}, load_value[31:16]} : {{16{load_value[15]}}, load_value[15:0]};
            end
            `OP_LHU: begin
                clean_load_value = (ex_mem_write_data_reg[1:0] == 2'b00) ? {16'b0, load_value[31:16]} : {16'b0, load_value[15:0]};
            end
            `OP_LB: begin
                case (ex_mem_write_data_reg[1:0])
                    2'b00: begin
                        clean_load_value = {{24{load_value[31]}}, load_value[31:24]};
                    end
                    2'b01: begin
                        clean_load_value = {{24{load_value[23]}}, load_value[23:16]};
                    end
                    2'b10: begin
                        clean_load_value = {{24{load_value[15]}}, load_value[15:8]};
                    end
                    2'b11: begin
                        clean_load_value = {{24{load_value[7]}},  load_value[7:0]};
                    end
                endcase
            end
            `OP_LBU: begin
                case (ex_mem_write_data_reg[1:0])
                    2'b00: begin
                        clean_load_value = {24'b0, load_value[31:24]};
                    end
                    2'b01: begin
                        clean_load_value = {24'b0, load_value[23:16]};
                    end
                    2'b10: begin
                        clean_load_value = {24'b0, load_value[15:8]};
                    end
                    2'b11: begin
                        clean_load_value = {24'b0,  load_value[7:0]};
                    end
                endcase
            end
            default: begin
                clean_load_value = 32'b0;
            end
        endcase
    end
    
    assign data_addr = ex_mem_data_addr_reg;
    assign data_mem_command = ex_mem_data_mem_command_reg;
    assign data_addr_valid = ex_mem_data_addr_valid_reg;

    RegisterFile rf (src1_addr, src2_addr, src1, src2, mem_wb_write_addr_reg, mem_wb_write_data_reg, mem_wb_write_enable_reg, clk);
    ALU alu (alu_src1, alu_src2, id_ex_shift_amount_reg, id_ex_opcode_reg, id_ex_func_reg, dest_data, dest_data_valid, pc, branch_offset, id_ex_rt, branch_taken);

    assign next_pc = (fetched & ~halt) ? (
        (id_ex_opcode_reg == `OP_JAL) ? id_ex_jump_target_reg[7:0] :
        ((id_ex_opcode_reg == `OP_REG) && (id_ex_func_reg == `FUNC_JALR)) ? final_src1[7:0] :
        (branch_taken) ? dest_data[7:0] :
        pc + 1
    ) : 8'b0;
    
    always @(posedge clk) begin
        if (reset) begin
            pc <= 8'b0;
            halt <= 1'b0;
            io_reg_index <= 2'b0;
            fetched <= 1'b0;
            printed <= 1'b0;
            input_read <= 1'b0;
            waiting_for_input <= 1'b0;
            id_ex_opcode_reg <= 6'b0;
            id_ex_src1_addr_reg <= 5'b0;
            id_ex_src2_addr_reg <= 5'b0;
            id_ex_src1_reg <= 32'b0;
            id_ex_src2_reg <= 32'b0;
            id_ex_dest_addr_reg <= 5'b0;
            id_ex_shift_amount_reg <= 5'b0;
            id_ex_func_reg <= 6'b0;
            id_ex_using_imm_reg <= 1'b0;
            id_ex_imm_reg <= 16'b0;
            id_ex_rt <= 5'b0;
            id_ex_is_mem_op_reg <= 1'b0;
            id_ex_jump_target_reg <= 26'b0;
            ex_mem_data_addr_valid_reg <= 1'b0;
            ex_mem_opcode_reg <= 6'b0;
            ex_mem_write_enable_reg <= 1'b0;
            ex_mem_write_addr_reg <= 5'b0;
            ex_mem_write_data_reg <= 32'b0;
            ex_mem_data_addr_reg <= 8'b0;
            mem_wb_write_enable_reg <= 1'b0;
            mem_wb_write_addr_reg <= 5'b0;
            mem_wb_write_data_reg <= 32'b0;
            keyboard_input <= 32'b0;
        end
        else if(pipeline_stall) begin
            id_ex_src1_reg <= final_src1;
            id_ex_src2_reg <= final_src2;

            if(is_sys_read) begin
                if(~input_read & ~input_value_valid) begin
                    waiting_for_input <= 1'b1;
                end
                else if(~input_read & input_value_valid) begin
                    waiting_for_input <= 1'b0;
                    input_read <= 1'b1;
                    keyboard_input <= input_value;
                end
            end

            mem_wb_write_enable_reg <= ex_mem_write_enable_reg; 
            mem_wb_write_addr_reg <= ex_mem_write_addr_reg;
            mem_wb_write_data_reg <= (ex_mem_opcode_reg == `OP_LW || ex_mem_opcode_reg == `OP_LH || ex_mem_opcode_reg == `OP_LHU || ex_mem_opcode_reg == `OP_LB || ex_mem_opcode_reg == `OP_LBU) ? clean_load_value : ex_mem_write_data_reg;
            ex_mem_opcode_reg <= 6'b0;
            ex_mem_write_enable_reg <= 1'b0;
            ex_mem_data_addr_valid_reg <= 1'b0;
            
            pc <= pc;
        end
        else begin
            if(fetched && is_sys_exit) begin
                halt <= 1'b1;
            end

            // FETCH
            fetched <= 1'b1;

            // DECODE
            id_ex_opcode_reg <= opcode;
            id_ex_src1_addr_reg <= src1_addr;
            id_ex_src2_addr_reg <= src2_addr;
            id_ex_src1_reg <= src1;
            id_ex_src2_reg <= src2;
            id_ex_dest_addr_reg <= dest_addr;
            id_ex_shift_amount_reg <= shift_amount;
            id_ex_func_reg <= func;
            id_ex_using_imm_reg <= using_imm;
            id_ex_imm_reg <= imm;
            id_ex_rt <= rt;
            id_ex_is_mem_op_reg <= is_mem_op;
            id_ex_jump_target_reg <= jump_target;

            // EXECUTE: Done by ALU
            ex_mem_opcode_reg <= id_ex_opcode_reg;
            ex_mem_write_enable_reg <= dest_data_valid;
            ex_mem_write_data_reg <= dest_data;
            ex_mem_data_addr_reg <= dest_data[9:2];
            ex_mem_write_addr_reg <= id_ex_dest_addr_reg;
            ex_mem_data_mem_command_reg <= (id_ex_opcode_reg == `OP_SW) ? `WRITE_COMMAND : (id_ex_opcode_reg == `OP_SH || id_ex_opcode_reg == `OP_SB) ? `SUBWORD_WRITE_COMMAND : `READ_COMMAND;
            ex_mem_data_addr_valid_reg <= id_ex_is_mem_op_reg;
            ex_mem_store_value_reg <= final_src2;
            
            // MEMORY

            // Control hazards, load hazard (RAW dependence) and halt
            if(branch_taken || load_hazard || is_sys_exit || halt) begin
                id_ex_opcode_reg <= 6'b0;
                id_ex_src1_addr_reg <= 5'b0;
                id_ex_src2_addr_reg <= 5'b0;
                id_ex_src1_reg <= 32'b0;
                id_ex_src2_reg <= 32'b0;
                id_ex_dest_addr_reg <= 5'b0;
                id_ex_shift_amount_reg <= 5'b0;
                id_ex_func_reg <= 6'b0;
                id_ex_using_imm_reg <= 1'b0;
                id_ex_imm_reg <= 16'b0;
                id_ex_rt <= 5'b0;
                id_ex_is_mem_op_reg <= 1'b0;
            end

            if(is_sys_read) begin
                input_read <= 1'b0;
                ex_mem_write_enable_reg <= 1'b1;
                ex_mem_write_addr_reg <= id_ex_dest_addr_reg;
                ex_mem_write_data_reg <= keyboard_input;
            end
            else if(is_sys_write) begin
                io_reg[io_reg_index] <= final_src2;
                io_reg_index <= io_reg_index + 1;
                printed <= 1'b1;
                ex_mem_write_enable_reg <= 1'b0;
                ex_mem_write_addr_reg <= 5'b0;
                ex_mem_write_data_reg <= 32'b0;
            end

            mem_wb_write_enable_reg <= ex_mem_write_enable_reg;
            mem_wb_write_addr_reg <= ex_mem_write_addr_reg;
            mem_wb_write_data_reg <= (ex_mem_opcode_reg == `OP_LW || ex_mem_opcode_reg == `OP_LH || ex_mem_opcode_reg == `OP_LHU || ex_mem_opcode_reg == `OP_LB || ex_mem_opcode_reg == `OP_LBU) ? clean_load_value : ex_mem_write_data_reg;

            // WRITE BACK: Done by RegisterFile
            // PC update
            pc <= (halt || load_hazard) ? pc : next_pc;
        end
    end

    // Decode instruction
    assign opcode = ins[31:26];
    assign src1_addr = ins[25:21];
    assign src2_addr = ins[20:16];
    assign dest_addr = (opcode == `OP_REG) ? ins[15:11] : ((opcode == `OP_JAL) ? 5'd31 : ins[20:16]);
    assign shift_amount = ins[10:6];
    assign func = ins[5:0];
    assign imm = ins[15:0];
    assign rt = ins[20:16];
    assign jump_target = ins[25:0];

    // Helper signals
    assign is_mem_op = (opcode == `OP_SW || opcode == `OP_SH || opcode == `OP_SB || opcode == `OP_LW || opcode == `OP_LH || opcode == `OP_LB || opcode == `OP_LHU || opcode == `OP_LBU);
    assign using_imm = (opcode != `OP_REG) && (opcode != `OP_BEQ) && (opcode != `OP_BNE);
    assign is_sys_write = (id_ex_opcode_reg == `OP_REG) && (id_ex_func_reg == `FUNC_SYSCALL) && (final_src1 == `SYS_write);
    assign is_sys_read = (id_ex_opcode_reg == `OP_REG) && (id_ex_func_reg == `FUNC_SYSCALL) && (final_src1 == `SYS_read);
    assign is_sys_exit = (id_ex_opcode_reg == `OP_REG) && (id_ex_func_reg == `FUNC_SYSCALL) && (final_src1 == `SYS_exit);
    assign is_load = (id_ex_opcode_reg == `OP_LW || id_ex_opcode_reg == `OP_LH || id_ex_opcode_reg == `OP_LB || id_ex_opcode_reg == `OP_LHU || id_ex_opcode_reg == `OP_LBU);

    // Data hazards (Read after Write dependence)
    assign mem_wb_bypass_src1 = (mem_wb_write_enable_reg) && (mem_wb_write_addr_reg != 5'b0) && (mem_wb_write_addr_reg == id_ex_src1_addr_reg);
    assign mem_wb_bypass_src2 = (mem_wb_write_enable_reg) && (mem_wb_write_addr_reg != 5'b0) && (mem_wb_write_addr_reg == id_ex_src2_addr_reg);
    assign ex_mem_bypass_src1 = (ex_mem_write_enable_reg) && (ex_mem_write_addr_reg != 5'b0) && (ex_mem_write_addr_reg == id_ex_src1_addr_reg);
    assign ex_mem_bypass_src2 = (ex_mem_write_enable_reg) && (ex_mem_write_addr_reg != 5'b0) && (ex_mem_write_addr_reg == id_ex_src2_addr_reg);
    assign final_src1 = ex_mem_bypass_src1 ? ex_mem_write_data_reg : mem_wb_bypass_src1 ? mem_wb_write_data_reg : id_ex_src1_reg;
    assign final_src2 = ex_mem_bypass_src2 ? ex_mem_write_data_reg : mem_wb_bypass_src2 ? mem_wb_write_data_reg : id_ex_src2_reg;
    assign alu_src1 = final_src1;
    assign alu_src2 = id_ex_using_imm_reg ? {16'b0, id_ex_imm_reg} : final_src2;
    assign load_hazard = is_load && (id_ex_dest_addr_reg != 5'b0) && ((id_ex_dest_addr_reg == src1_addr) || (id_ex_dest_addr_reg == src2_addr));

    // Stall signals
    assign io_stall = (is_sys_write && (io_reg_index == 2'b00) && printed && ~copied_io_regs);
    assign pipeline_stall = (is_sys_read && ~(input_read && ~input_value_valid)) || io_stall;
endmodule
