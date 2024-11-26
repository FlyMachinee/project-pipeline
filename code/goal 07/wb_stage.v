`include "mycpu_top.h"
`default_nettype wire

module wb_stage (
    input clk,
    input reset,

    // pipeline control
    output wb_allow_in,
    input  mem_to_wb_valid,

    // bus from mem
    input [`MEM_TO_WB_BUS_WIDTH-1:0] mem_to_wb_bus,

    // bus to id (for regfile)
    output [`WB_TO_ID_BUS_WIDTH-1:0] wb_to_id_bus,

    // debug interface
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_we,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
);

  // pipeline registers
  reg [`MEM_TO_WB_BUS_WIDTH-1:0] wb_reg;
  wire [31:0] wb_pc;
  wire [31:0] wb_final_result;
  wire wb_reg_we;
  wire [4:0] wb_reg_waddr;
  assign {wb_pc, wb_final_result, wb_reg_we, wb_reg_waddr} = wb_reg;

  // output bus to ID
  assign wb_to_id_bus = {wb_reg_we, wb_reg_waddr, wb_final_result};

  // pipeline control
  reg  wb_valid;
  wire wb_ready_go;

  assign wb_ready_go = 1;
  assign wb_allow_in = !wb_valid || wb_ready_go;

  always @(posedge clk) begin
    if (reset) begin
      wb_valid <= 1'b0;
    end else if (wb_allow_in) begin
      wb_valid <= mem_to_wb_valid;
    end
  end

  always @(posedge clk) begin
    if (wb_allow_in && mem_to_wb_valid) begin
      wb_reg <= mem_to_wb_bus;
    end
  end

  // debug interface
  assign debug_wb_pc = wb_pc;
  assign debug_wb_rf_we = {4{wb_reg_we}};
  assign debug_wb_rf_wnum = wb_reg_waddr;
  assign debug_wb_rf_wdata = wb_final_result;

endmodule
