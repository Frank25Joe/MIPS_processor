`include "defs.vh"

module ALU (input [31:0] src1, input [31:0] src2, input [4:0] shift_amount, input [5:0] opcode, input [5:0] func, output [31:0] dest, output dest_valid, input [7:0] pc, input [31:0] branch_offset, input [4:0] rt, output reg branch_taken);
    reg [31:0] result;
    reg result_valid;
    
    assign dest = result; // Used as write data for register file (RF)
    assign dest_valid = result_valid; // Used as write enable for RF

    always @(*) begin
        case (opcode)
            `OP_REG: begin
                case (func)
                    `FUNC_SLL: begin
                        result = src2 << shift_amount;
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    `FUNC_SRL: begin
                        result = src2 >> shift_amount;
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    `FUNC_SRA: begin
                        result = $signed(src2) >>> shift_amount;
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    `FUNC_SLLV: begin
                        result = src2 << src1[4:0];
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    `FUNC_SRLV: begin
                        result = src2 >> src1[4:0];
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    `FUNC_SRAV: begin
                        result = $signed(src2) >>> src1[4:0];
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    `FUNC_ADD: begin
                        result = src1 + src2;
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    `FUNC_SUB: begin
                        result = src1 - src2;
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    `FUNC_AND: begin
                        result = src1 & src2;
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    `FUNC_OR: begin
                        result = src1 | src2;
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    `FUNC_XOR: begin
                        result = src1 ^ src2;
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    `FUNC_NOR: begin
                        result = ~(src1 | src2);
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    `FUNC_JR: begin
                        result = src1;
                        result_valid = 1'b0;
                        branch_taken = 1'b1;
                    end
                    `FUNC_JALR: begin
                        result = {24'b0, pc} + 1;
                        result_valid = 1'b1;
                        branch_taken = 1'b1;
                    end
                    `FUNC_SLT: begin
                        result = ($signed(src1) < $signed(src2)) ? 32'b1 : 32'b0;
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    `FUNC_SLTU: begin
                        result = (src1 < src2) ? 32'b1 : 32'b0;
                        result_valid = 1'b1;
                        branch_taken = 1'b0;
                    end
                    default: begin
                        result = 32'b0;
                        result_valid = 1'b0;
                        branch_taken = 1'b0;
                    end
                endcase
            end
            `OP_ADDI: begin
                result = src1 + {{16{src2[15]}}, src2[15:0]};
                result_valid = 1'b1;
                branch_taken = 1'b0;
            end
            `OP_ANDI: begin
                result = src1 & {{16{1'b0}}, src2[15:0]};
                result_valid = 1'b1;
                branch_taken = 1'b0;
            end
            `OP_ORI: begin
                result = src1 | {{16{1'b0}}, src2[15:0]};
                result_valid = 1'b1;
                branch_taken = 1'b0;
            end
            `OP_XORI: begin
                result = src1 ^ {{16{1'b0}}, src2[15:0]};
                result_valid = 1'b1;
                branch_taken = 1'b0;
            end
            `OP_BLTZ_BGEZ: begin
                case (rt)
                    5'b0: begin
                        result = ($signed(src1) < $signed(32'b0)) ? {24'b0, pc} + branch_offset : {24'b0, pc};
                        result_valid = 1'b0;
                        branch_taken = ($signed(src1) < $signed(32'b0)) ? 1'b1 : 1'b0;
                    end
                    5'b1: begin
                        result = ($signed(src1) >= $signed(32'b0)) ? {24'b0, pc} + branch_offset : {24'b0, pc};
                        result_valid = 1'b0;
                        branch_taken = ($signed(src1) >= $signed(32'b0)) ? 1'b1 : 1'b0;
                    end
                    default: begin
                        result = 32'b0;
                        result_valid = 1'b0;
                        branch_taken = 1'b0;
                    end
                endcase
            end
            `OP_BEQ: begin
                result = (src1 == src2) ? {24'b0, pc} + branch_offset : {24'b0, pc};
                result_valid = 1'b0;
                branch_taken = (src1 == src2) ? 1'b1 : 1'b0;
            end
            `OP_BNE: begin
                result = (src1 != src2) ? {24'b0, pc} + branch_offset : {24'b0, pc};
                result_valid = 1'b0;
                branch_taken = (src1 != src2) ? 1'b1 : 1'b0;
            end
            `OP_BLEZ: begin
                result = ($signed(src1) <= $signed(32'b0)) ? {24'b0, pc} + branch_offset : {24'b0, pc};
                result_valid = 1'b0;
                branch_taken = ($signed(src1) <= $signed(32'b0)) ? 1'b1 : 1'b0;
            end
            `OP_BGTZ: begin
                result = ($signed(src1) > $signed(32'b0)) ? {24'b0, pc} + branch_offset : {24'b0, pc};
                result_valid = 1'b0;
                branch_taken = ($signed(src1) > $signed(32'b0)) ? 1'b1 : 1'b0;
            end
            `OP_SLTI: begin
                result = ($signed(src1) < $signed({{16{src2[15]}}, src2[15:0]})) ? 32'b1 : 32'b0;
                result_valid = 1'b1;
                branch_taken = 1'b0;
            end
            `OP_SLTIU: begin
                result = (src1 < {{16{src2[15]}}, src2[15:0]}) ? 32'b1 : 32'b0;
                result_valid = 1'b1;
                branch_taken = 1'b0;
            end
            `OP_J: begin
                result = branch_offset;
                result_valid = 1'b0;
                branch_taken = 1'b1;
            end
            `OP_JAL: begin
                result = {24'b0, pc} + 1;
                result_valid = 1'b1;
                branch_taken = 1'b1;
            end
            `OP_LUI: begin
                result = {src2[15:0], 16'b0};
                result_valid = 1'b1;
                branch_taken = 1'b0;
            end
            `OP_LB: begin
                result = src1 + branch_offset;
                result_valid = 1'b1;
                branch_taken = 1'b0;
            end
            `OP_LH: begin
                result = src1 + branch_offset;
                result_valid = 1'b1;
                branch_taken = 1'b0;
            end
            `OP_LW: begin
                result = src1 + branch_offset;
                result_valid = 1'b1;
                branch_taken = 1'b0;
            end
            `OP_LBU: begin
                result = src1 + branch_offset;
                result_valid = 1'b1;
                branch_taken = 1'b0;
            end
            `OP_LHU: begin
                result = src1 + branch_offset;
                result_valid = 1'b1;
                branch_taken = 1'b0;
            end
            `OP_SB: begin
                result = src1 + branch_offset;
                result_valid = 1'b0;
                branch_taken = 1'b0;
            end
            `OP_SH: begin
                result = src1 + branch_offset;
                result_valid = 1'b0;
                branch_taken = 1'b0;
            end
            `OP_SW: begin
                result = src1 + branch_offset;
                result_valid = 1'b0;
                branch_taken = 1'b0;
            end
            default: begin
                result = 32'b0;
                result_valid = 1'b0;
                branch_taken = 1'b0;
            end
        endcase
    end
endmodule