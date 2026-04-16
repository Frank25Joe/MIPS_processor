`include "defs.vh"

module Processor(input clk, output halt, input reset, output reg [7:0] pc, input [31:0] ins, output [31:0] io_reg1, output [31:0] io_reg2, output [31:0] io_reg3, output [31:0] io_reg4, input copied_io_regs, output io_stall, output reg [1:0] io_reg_index, input [31:0] input_value, input input_value_valid, output reg waiting_for_input, input [31:0] load_value, output [7:0] data_addr, output data_addr_valid, output [1:0] data_mem_command, output reg [31:0] store_value);
    wire [5:0] opcode; // Extracted from ins
    wire [5:0] func; // Extracted from ins
    wire [4:0] shift_amount; // Extracted from ins
    wire [4:0] src1_addr; // rs extracted from ins (input to RF)
    wire [4:0] src2_addr; // rt extracted from ins (input to RF)
    wire [31:0] src1; // Output of RF, input to ALU
    wire [31:0] src2; // Output of RF, input to ALU
    reg [31:0] alu_src2_reg;
    reg [4:0] dest_addr; // rt/rd extracted from ins (input to RF)
    wire [31:0] dest_data; // Output of ALU, input to RF
    wire dest_data_valid; // Output of ALU, input to RF
    wire [7:0] next_pc; // Next instruction address
    wire [15:0] imm; // Immediate extracted from ins
    reg [31:0] io_reg [0:3]; // Circular I/O buffer
    reg fetched; // Is first instruction fetched?
    reg printed; // Is first io_print executed?
    reg is_mem_op; // Is it a memory operation?
    
    reg [1:0] state; // State tracker for FSM
    reg write_enable_reg;
    reg [4:0] write_addr_reg;
    reg [31:0] write_data_reg;
    reg [5:0] opcode_reg;
    reg [5:0] func_reg;
    reg [4:0] shift_amount_reg;
    reg [31:0] src1_reg;
    reg [31:0] src2_reg;
    reg [15:0] imm_reg;
    reg input_read; // To track if keyboard input has been read; Required because input_valid signal may change much slower than clk period

    assign io_reg1 = io_reg[0];
    assign io_reg2 = io_reg[1];
    assign io_reg3 = io_reg[2];
    assign io_reg4 = io_reg[3];

    wire [31:0] branch_offset; // Input to ALU
    reg [4:0] rt; // Input to ALU
    wire branch_taken; // Output of ALU
    reg [25:0] target_reg;

    assign branch_offset = ((opcode_reg == `OP_J) || (opcode_reg == `OP_JAL)) ? {6'b0, target_reg} : {{16{imm_reg[15]}}, imm_reg};
    
    reg [31:0] clean_load_value;

    always @(*) begin
        case (opcode_reg)
            `OP_SW: begin
                store_value = src2_reg;
            end
            `OP_SH: begin
                store_value = (dest_data[1:0] == 2'b00) ? {src2_reg[15:0], load_value[15:0]} : {load_value[31:16], src2_reg[15:0]};
            end
            `OP_SB: begin
                case (dest_data[1:0])
                    2'b00: begin
                        store_value = {src2_reg[7:0], load_value[23:0]};
                    end
                    2'b01: begin
                        store_value = {load_value[31:24], src2_reg[7:0], load_value[15:0]};
                    end
                    2'b10: begin
                        store_value = {load_value[31:16], src2_reg[7:0], load_value[7:0]};
                    end
                    2'b11: begin
                        store_value = {load_value[31:8], src2_reg[7:0]};
                    end
                endcase
            end
            default: begin
                store_value = 32'b0;
            end
        endcase
    end

    always @(*) begin
        case (opcode_reg)
            `OP_LW: begin
                clean_load_value = load_value;
            end
            `OP_LH: begin
                clean_load_value = (dest_data[1:0] == 2'b00) ? {{16{load_value[31]}}, load_value[31:16]} : {{16{load_value[15]}}, load_value[15:0]};
            end
            `OP_LHU: begin
                clean_load_value = (dest_data[1:0] == 2'b00) ? {16'b0, load_value[31:16]} : {16'b0, load_value[15:0]};
            end
            `OP_LB: begin
                case (dest_data[1:0])
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
                case (dest_data[1:0])
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

    assign data_addr = dest_data[9:2];
    assign data_mem_command = (opcode_reg == `OP_SW) ? `WRITE_COMMAND : (opcode_reg == `OP_SH || opcode_reg == `OP_SB) ? `SUBWORD_WRITE_COMMAND : `READ_COMMAND;
    assign data_addr_valid = (state == 2'b01 && is_mem_op) ? 1'b1 : 1'b0;

    RegisterFile rf (src1_addr, src2_addr, src1, src2, write_addr_reg, write_data_reg, write_enable_reg, clk);
    ALU alu (src1_reg, alu_src2_reg, shift_amount_reg, opcode_reg, func_reg, dest_data, dest_data_valid, pc, branch_offset, rt, branch_taken);

    assign next_pc = (fetched & ~halt) ? (
        (opcode_reg == `OP_JAL) ? ins[7:0] :
        ((opcode_reg == `OP_REG) && (func_reg == `FUNC_JALR)) ? src1_reg[7:0] :
        (branch_taken) ? dest_data[7:0] :
        pc + 1
    ) : 8'b0;

    always @(posedge clk) begin
        if (reset) begin
            pc <= 8'b0;
            io_reg_index <= 2'b0;
            fetched <= 1'b0;
            printed <= 1'b0;
            state <= 2'b0;
            write_enable_reg <= 1'b0;
            input_read <= 1'b0;
            waiting_for_input <= 1'b0;
            alu_src2_reg <= 32'b0;
            is_mem_op <= 1'b0;
        end
        else begin
            fetched <= 1'b1;
            case(state)
                2'b00: begin
                    opcode_reg <= opcode;
                    func_reg <= func;
                    shift_amount_reg <= shift_amount;
                    src1_reg <= src1;
                    src2_reg <= src2;
                    imm_reg <= imm;
                    dest_addr <= (opcode == `OP_REG) ? ins[15:11] : ((opcode == `OP_JAL) ? 5'd31 : ins[20:16]);
                    alu_src2_reg <= (opcode != `OP_REG) && (opcode != `OP_BEQ) && (opcode != `OP_BNE) ? imm : src2;
                    is_mem_op <= (opcode == `OP_SW || opcode == `OP_SH || opcode == `OP_SB || opcode == `OP_LW || opcode == `OP_LH || opcode == `OP_LB || opcode == `OP_LHU || opcode == `OP_LBU);
                    rt <= ins[20:16];
                    target_reg <= ins[25:0];
                    state <= 2'b01;
                end
                2'b01: begin
                    if (io_stall) begin
                        state <= 2'b01;
                    end
                    else if ((opcode_reg == `OP_REG) && (func_reg == `FUNC_SYSCALL) && (src1_reg == `SYS_read)) begin
                        if (~input_read && input_value_valid) begin
                            write_data_reg <= input_value;
                            input_read <= 1'b1;
                            waiting_for_input <= 1'b0;
                            state <= 2'b01;
                        end
                        else if (input_read && input_value_valid) begin
                            state <= 2'b01;
                        end
                        else if (input_read && ~input_value_valid) begin
                            write_enable_reg <= 1'b1;
                            write_addr_reg <= dest_addr;
                            input_read <= 1'b0;
                            state <= 2'b10;
                        end
                        else if (~input_read && ~input_value_valid) begin
                            waiting_for_input <= 1'b1;
                            state <= 2'b01;
                        end
                    end
                    else begin
                        write_enable_reg <= dest_data_valid;
                        write_addr_reg <= dest_addr;
                        write_data_reg <= (opcode_reg == `OP_LW || opcode_reg == `OP_LH || opcode_reg == `OP_LHU || opcode_reg == `OP_LB || opcode_reg == `OP_LBU) ? clean_load_value : dest_data;
                        state <= 2'b10;
                    end
                end
                2'b10: begin
                    pc <= halt ? pc : next_pc;
                    write_enable_reg <= 1'b0;
                    state <= 2'b00;
                end
            endcase
            if ((opcode_reg == `OP_REG) && (func_reg == `FUNC_SYSCALL) && (src1_reg == `SYS_write) && (state == 2'b01) && ~io_stall) begin
                io_reg_index <= io_reg_index + 1;
                io_reg[io_reg_index] <= src2_reg;
                printed <= 1'b1;
            end
        end
    end
    
    // Decode instruction
    assign opcode = ins[31:26];
    assign src1_addr = ins[25:21];
    assign src2_addr = ins[20:16];
    assign shift_amount = ins[10:6];
    assign func = ins[5:0];
    assign imm = ins[15:0];

    assign io_stall = ((opcode_reg == `OP_REG) && (func_reg == `FUNC_SYSCALL) && (src1_reg == `SYS_write) && (state == 2'b01) && (io_reg_index == 2'b00) && printed && ~copied_io_regs) ? 1'b1 : 1'b0;
    assign halt = (reset | ~fetched) ? 1'b0 : (((opcode_reg == `OP_REG) && (func_reg == `FUNC_SYSCALL) && (src1_reg == `SYS_exit)) ? 1'b1 : 1'b0);
endmodule