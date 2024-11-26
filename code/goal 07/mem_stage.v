`include "mycpu_top.h"

module mem_stage (
    input clk,
    input reset,

    // pipeline control
    output mem_allow_in,
    input  exe_to_mem_valid,
    input  wb_allow_in,
    output mem_to_wb_valid,

    // bus from exe
    input [`EXE_TO_MEM_BUS_WIDTH-1:0] exe_to_mem_bus,

    // bus to wb
    output [`MEM_TO_WB_BUS_WIDTH-1:0] mem_to_wb_bus,

    // cpu interface
    input [31:0] data_sram_rdata
);

  // pipeline registers
  reg [`EXE_TO_MEM_BUS_WIDTH-1:0] mem_reg;

  wire [31:0] mem_pc;
  wire [31:0] mem_alu_result;
  wire mem_res_from_mem;
  wire mem_reg_we;
  wire [4:0] mem_reg_waddr;
  assign {mem_pc, mem_alu_result, mem_res_from_mem, mem_reg_we, mem_reg_waddr} = mem_reg;

  // output bus to WB
  wire [31:0] final_result;
  assign mem_to_wb_bus = {mem_pc, final_result, mem_reg_we, mem_reg_waddr};

  // pipeline control
  reg  mem_valid;
  wire mem_ready_go;

  assign mem_ready_go = 1;
  assign mem_allow_in = !mem_valid || (mem_ready_go && wb_allow_in);
  assign mem_to_wb_valid = mem_valid && mem_ready_go;

  always @(posedge clk) begin
    if (reset) begin
      mem_valid <= 1'b0;
    end else if (mem_allow_in) begin
      mem_valid <= exe_to_mem_valid;
    end
  end

  always @(posedge clk) begin
    if (mem_allow_in && exe_to_mem_valid) begin
      mem_reg <= exe_to_mem_bus;
    end
  end

  // internal signals
  wire [31:0] mem_result;

  // MEM stage
  assign mem_result   = data_sram_rdata;
  assign final_result = mem_res_from_mem ? mem_result : mem_alu_result;

endmodule
