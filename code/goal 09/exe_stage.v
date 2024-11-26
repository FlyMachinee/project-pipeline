`include "mycpu_top.h"

module exe_stage (
    input clk,
    input reset,

    // pipeline control
    output exe_allow_in,
    input  id_to_exe_valid,
    input  mem_allow_in,
    output exe_to_mem_valid,

    // hazard detection && bypass
    output reg exe_valid,
    output [`BYPASS_BUS_WIDTH-1:0] exe_to_id_bypass_bus,
    output exe_is_load,

    // bus from id
    input [`ID_TO_EXE_BUS_WIDTH-1:0] id_to_exe_bus,

    // bus to mem
    output [`EXE_TO_MEM_BUS_WIDTH-1:0] exe_to_mem_bus,

    // cpu interface
    output        data_sram_en,
    output [ 3:0] data_sram_we,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata
);

  // pipeline registers
  reg [`ID_TO_EXE_BUS_WIDTH-1:0] exe_reg;

  wire [31:0] exe_pc;
  wire [31:0] exe_rj_value;
  wire [31:0] exe_rkd_value;
  wire [31:0] exe_imm;
  wire [11:0] exe_alu_op;
  wire exe_src1_is_pc;
  wire exe_src2_is_imm;
  wire exe_res_from_mem;
  wire exe_reg_we;
  wire exe_mem_en;
  wire [3:0] exe_mem_we;
  wire [4:0] exe_reg_waddr;
  assign {
    exe_pc,
    exe_rj_value,
    exe_rkd_value,
    exe_imm,
    exe_alu_op,
    exe_src1_is_pc,
    exe_src2_is_imm,
    exe_res_from_mem,
    exe_reg_we,
    exe_mem_en,
    exe_mem_we,
    exe_reg_waddr
  } = exe_reg;

  // output bus to MEM
  wire [31:0] alu_result;
  assign exe_to_mem_bus = {exe_pc, alu_result, exe_res_from_mem, exe_reg_we, exe_reg_waddr};

  // pipeline control
  // reg  exe_valid;
  wire exe_ready_go;

  assign exe_ready_go = 1;
  assign exe_allow_in = !exe_valid || (exe_ready_go && mem_allow_in);
  assign exe_to_mem_valid = exe_valid && exe_ready_go;

  always @(posedge clk) begin
    if (reset) begin
      exe_valid <= 1'b0;
    end else if (exe_allow_in) begin
      exe_valid <= id_to_exe_valid;
    end
  end

  always @(posedge clk) begin
    if (exe_allow_in && id_to_exe_valid) begin
      exe_reg <= id_to_exe_bus;
    end
  end

  // internal signals
  wire [11:0] alu_op;
  wire [31:0] alu_src1;
  wire [31:0] alu_src2;
  // wire [31:0] alu_result;

  // EXE stage
  assign alu_op   = exe_alu_op;
  assign alu_src1 = exe_src1_is_pc ? exe_pc : exe_rj_value;
  assign alu_src2 = exe_src2_is_imm ? exe_imm : exe_rkd_value;

  alu u_alu (
      .alu_op    (alu_op),
      .alu_src1  (alu_src1),
      .alu_src2  (alu_src2),
      .alu_result(alu_result)
  );

  assign data_sram_en    = exe_mem_en && exe_valid;
  assign data_sram_we = exe_mem_we;
  assign data_sram_addr  = data_sram_en ? alu_result : 32'b0;
  assign data_sram_wdata = exe_rkd_value;

  // hazard detection && bypass to ID
  assign exe_to_id_bypass_bus = {exe_reg_we, exe_reg_waddr, alu_result};
  assign exe_is_load = exe_mem_en && !exe_mem_we[0];

endmodule
