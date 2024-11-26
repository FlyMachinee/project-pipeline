`include "mycpu_top.h"

module if_stage (
    input clk,
    input reset,

    // pipeline control
    input  id_allow_in,
    output if_to_id_valid,

    // bus to id
    output [`IF_TO_ID_BUS_WIDTH-1:0] if_to_id_bus,

    // bus from id
    input [`ID_TO_IF_BUS_WIDTH-1:0] id_to_if_bus,

    // cpu interface
    output        inst_sram_en,
    output [ 3:0] inst_sram_we,
    output [31:0] inst_sram_addr,
    output [31:0] inst_sram_wdata,
    input  [31:0] inst_sram_rdata
);

  // input bus from ID (for branch)
  wire        br_taken;
  wire [31:0] br_target;
  wire        br_taken_cancel;
  assign {br_taken, br_target, br_taken_cancel} = id_to_if_bus;

  // output bus to ID
  reg  [31:0] if_pc;
  wire [31:0] inst;
  assign if_to_id_bus = {if_pc, inst};

  // internal signals
  wire [31:0] seq_pc;
  wire [31:0] nextpc;

  // pipeline control
  reg if_valid;
  wire pre_if_valid;
  wire if_allow_in;
  wire if_ready_go;

  always @(posedge clk) begin
    if (reset) begin
      if_valid <= 1'b0;
    end else if (if_allow_in) begin
      if_valid <= pre_if_valid;
    end else if (br_taken_cancel) begin
      if_valid <= 1'b0;
    end
  end

  // pre-IF stage
  assign seq_pc = if_pc + 3'h4;
  assign nextpc = br_taken ? br_target : seq_pc;
  assign pre_if_valid = ~reset;  // && if_allow_in;

  // IF stage
  assign if_ready_go = 1;
  assign if_to_id_valid = if_valid && if_ready_go;
  assign if_allow_in = !if_valid || (if_ready_go && id_allow_in);

  always @(posedge clk) begin
    if (reset) begin
      if_pc <= 32'h1bfffffc;  //trick: to make nextpc be 0x1c000000 during reset
    end else if (if_allow_in && pre_if_valid) begin
      if_pc <= nextpc;
    end
  end

  assign inst_sram_en    = pre_if_valid && if_allow_in;
  assign inst_sram_we    = 4'b0000;
  assign inst_sram_addr  = nextpc;
  assign inst_sram_wdata = 32'b0;
  assign inst            = inst_sram_rdata;

endmodule
