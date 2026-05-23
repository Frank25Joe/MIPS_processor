`include "defs.vh"
`include "Memory.v"

module Computer(input reset, input [7:0] ins_addr, input [31:0] ins, input clk, input done_storing, input copied_io_regs, input [31:0] input_value, input input_value_valid, output reg done, output [31:0] out_reg1, output [31:0] out_reg2, output [31:0] out_reg3, output [31:0] out_reg4, output [31:0] total_cycles, output [31:0] proc_cycles, output io_stall, output [1:0] io_reg_index, output waiting_for_input);
    wire [7:0] pc; // Output of Processor
    wire [31:0] ins_fetched; // Output of IMemory
    wire [1:0] ins_command; // Input of IMemory
    reg [31:0] counter_total; // Counts total_cycles
    reg [31:0] counter_proc; // Counts proc_cycles
    wire halt; // Output of Processor

    wire data_addr_valid; // Processor output
    wire [31:0] word_fetched; // Output of DMemory
    wire [31:0] word_stored; // Input of DMemory (Output of processor)
    wire [1:0] proc_data_command; // DMemory command from processor
    wire [7:0] data_addr; // DMemory address accessed
    wire [7:0] proc_data_addr;

    Memory im(~reset & ~done_storing, clk, ins_command, done_storing ? pc : ins_addr, ins, ins_fetched);
    Memory dm(~reset & data_addr_valid, clk, proc_data_command, data_addr, word_stored, word_fetched);
    Processor proc(clk, halt, ~done_storing, pc, ins_fetched, out_reg1, out_reg2, out_reg3, out_reg4, copied_io_regs, io_stall, io_reg_index, input_value, input_value_valid, waiting_for_input, word_fetched, proc_data_addr, data_addr_valid, proc_data_command, word_stored);
    
    assign total_cycles = counter_total;
    assign proc_cycles = counter_proc;
    assign ins_command = done_storing ? `READ_COMMAND : `WRITE_COMMAND;
    assign data_addr = data_addr_valid ? proc_data_addr : 8'b0;

    always @(posedge clk) begin
        if (reset) begin
            counter_total <= 32'b0;
            counter_proc <= 32'b0;
            done <= 1'b0;
        end
        else begin
            done <= halt;
            counter_total <= counter_total + 1;
            counter_proc <= (done_storing & ~halt & ~io_stall & ~waiting_for_input) ? counter_proc + 1 : counter_proc;
        end
    end
endmodule