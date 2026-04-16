`include "defs.vh"

module Computer(input reset, input [7:0] ins_addr, input [31:0] ins, input clk, input done_storing, input copied_io_regs, input [31:0] input_value, input input_value_valid, output reg done, output [31:0] out_reg1, output [31:0] out_reg2, output [31:0] out_reg3, output [31:0] out_reg4, output [31:0] total_cycles, output [31:0] proc_cycles, output io_stall, output [1:0] io_reg_index, output waiting_for_input);
    wire [7:0] pc; // Output of Processor
    wire [31:0] ins_fetched; // Output of Memory
    wire [1:0] ins_mem_command; // Input to Memory
    reg [31:0] counter_total; // Counts total_cycles
    reg [31:0] counter_proc; // Counts proc_cycles
    wire halt; // Output of Processor

    wire data_addr_valid; // Processor output
    wire [31:0] word_fetched; // Output of memory (same as ins_fetched)
    wire [31:0] word_stored; // Input of memory (Output of processor)
    wire [1:0] proc_mem_command; // Memory command from processor
    wire [7:0] mem_addr; // Memory address accessed
    wire [7:0] proc_data_addr; // Memory addr requested to be accessed by processor

    Memory mem(~reset, clk, ins_mem_command, mem_addr, done_storing ? word_stored : ins, ins_fetched);
    Processor proc(clk, halt, ~done_storing, pc, ins_fetched, out_reg1, out_reg2, out_reg3, out_reg4, copied_io_regs, io_stall, io_reg_index, input_value, input_value_valid, waiting_for_input, word_fetched, proc_data_addr, data_addr_valid, proc_mem_command, word_stored);
    
    assign total_cycles = counter_total;
    assign proc_cycles = counter_proc;
    assign ins_mem_command = done_storing ? (data_addr_valid ? proc_mem_command : `READ_COMMAND) : `WRITE_COMMAND;
    assign mem_addr = done_storing ? (data_addr_valid ? proc_data_addr : pc) : ins_addr;

    assign word_fetched = ins_fetched;

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