`include "mycpu_top.h"

module id_stage (
    input clk,
    input reset,

    // pipeline control
    output id_allow_in,
    input  if_to_id_valid,
    input  exe_allow_in,
    output id_to_exe_valid,

    // hazard detection
    input exe_rf_we,
    input [4:0] exe_rf_waddr,
    input exe_valid,
    input mem_rf_we,
    input [4:0] mem_rf_waddr,
    input mem_valid,
    input wb_valid,

    // bus from if
    input [`IF_TO_ID_BUS_WIDTH-1:0] if_to_id_bus,

    // bus to exe
    output [`ID_TO_EXE_BUS_WIDTH-1:0] id_to_exe_bus,

    // bus to if (for branch)
    output [`ID_TO_IF_BUS_WIDTH-1:0] id_to_if_bus,

    // bus from wb (for regfile)
    input [`WB_TO_ID_BUS_WIDTH-1:0] wb_to_id_bus
);
  // pipeline registers
  reg [`IF_TO_ID_BUS_WIDTH-1:0] id_reg;
  wire [31:0] id_pc;
  wire [31:0] id_inst;
  assign {id_pc, id_inst} = id_reg;

  // input bus from WB (for regfile)
  wire wb_rf_we;
  wire [4:0] wb_rf_waddr;
  wire [31:0] wb_rf_wdata;
  assign {wb_rf_we, wb_rf_waddr, wb_rf_wdata} = wb_to_id_bus;

  // output bus to EXE
  wire [31:0] rj_value;
  wire [31:0] rkd_value;
  wire [31:0] imm;
  wire [11:0] alu_op;
  wire        src1_is_pc;
  wire        src2_is_imm;
  wire        res_from_mem;
  wire        reg_we;
  wire        mem_en;
  wire [ 3:0] mem_we;
  wire [ 4:0] reg_waddr;
  assign id_to_exe_bus = {
    id_pc,
    rj_value,
    rkd_value,
    imm,
    alu_op,
    src1_is_pc,
    src2_is_imm,
    res_from_mem,
    reg_we,
    mem_en,
    mem_we,
    reg_waddr
  };

  // output bus to IF (for branch)
  wire        br_taken;
  wire [31:0] br_target;
  wire        br_taken_cancel;  // for branch cancel
  assign id_to_if_bus = {br_taken, br_target, br_taken_cancel};

  // pipeline control
  reg  id_valid;
  wire id_ready_go;

  // assign id_ready_go = 1; nope for hazard happening
  assign id_allow_in = !id_valid || (id_ready_go && exe_allow_in);
  assign id_to_exe_valid = id_valid && id_ready_go;

  always @(posedge clk) begin
    if (reset) begin
      id_valid <= 1'b0;
    end else if (br_taken_cancel) begin
      id_valid <= 1'b0;
    end else if (id_allow_in) begin
      id_valid <= if_to_id_valid;
    end
  end

  always @(posedge clk) begin
    if (id_allow_in && if_to_id_valid) begin
      id_reg <= if_to_id_bus;
    end
  end

  // internal signals
  wire        dst_is_r1;
  wire        src_reg_is_rd;
  wire [31:0] br_offs;
  wire [31:0] jirl_offs;

  wire [ 5:0] op_31_26;
  wire [ 3:0] op_25_22;
  wire [ 1:0] op_21_20;
  wire [ 4:0] op_19_15;
  wire [ 4:0] rd;
  wire [ 4:0] rj;
  wire [ 4:0] rk;
  wire [11:0] i12;
  wire [19:0] i20;
  wire [15:0] i16;
  wire [25:0] i26;

  wire [63:0] op_31_26_d;
  wire [15:0] op_25_22_d;
  wire [ 3:0] op_21_20_d;
  wire [31:0] op_19_15_d;

  wire        inst_add_w;
  wire        inst_sub_w;
  wire        inst_slt;
  wire        inst_sltu;
  wire        inst_nor;
  wire        inst_and;
  wire        inst_or;
  wire        inst_xor;
  wire        inst_slli_w;
  wire        inst_srli_w;
  wire        inst_srai_w;
  wire        inst_addi_w;
  wire        inst_ld_w;
  wire        inst_st_w;
  wire        inst_jirl;
  wire        inst_b;
  wire        inst_bl;
  wire        inst_beq;
  wire        inst_bne;
  wire        inst_lu12i_w;

  wire        need_ui5;
  wire        need_si12;
  wire        need_si16;
  wire        need_si20;
  wire        need_si26;
  wire        src2_is_4;

  wire [ 4:0] rf_raddr1;
  wire [31:0] rf_rdata1;
  wire [ 4:0] rf_raddr2;
  wire [31:0] rf_rdata2;
  wire        rf_we;
  wire [ 4:0] rf_waddr;
  wire [31:0] rf_wdata;

  // ID stage
  assign op_31_26 = id_inst[31:26];
  assign op_25_22 = id_inst[25:22];
  assign op_21_20 = id_inst[21:20];
  assign op_19_15 = id_inst[19:15];
  assign rd       = id_inst[4:0];
  assign rj       = id_inst[9:5];
  assign rk       = id_inst[14:10];
  assign i12      = id_inst[21:10];
  assign i20      = id_inst[24:5];
  assign i16      = id_inst[25:10];
  assign i26      = {id_inst[9:0], id_inst[25:10]};
  decoder_6_64 u_dec0 (
      .in (op_31_26),
      .out(op_31_26_d)
  );
  decoder_4_16 u_dec1 (
      .in (op_25_22),
      .out(op_25_22_d)
  );
  decoder_2_4 u_dec2 (
      .in (op_21_20),
      .out(op_21_20_d)
  );
  decoder_5_32 u_dec3 (
      .in (op_19_15),
      .out(op_19_15_d)
  );

  assign inst_add_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
  assign inst_sub_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
  assign inst_slt = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
  assign inst_sltu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
  assign inst_nor = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
  assign inst_and = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
  assign inst_or = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
  assign inst_xor = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
  assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
  assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
  assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
  assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
  assign inst_ld_w = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
  assign inst_st_w = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
  assign inst_jirl = op_31_26_d[6'h13];
  assign inst_b = op_31_26_d[6'h14];
  assign inst_bl = op_31_26_d[6'h15];
  assign inst_beq = op_31_26_d[6'h16];
  assign inst_bne = op_31_26_d[6'h17];
  assign inst_lu12i_w = op_31_26_d[6'h05] & ~id_inst[25];

  assign alu_op[0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w | inst_jirl | inst_bl;  // add
  assign alu_op[1] = inst_sub_w;  // sub
  assign alu_op[2] = inst_slt;  // slt
  assign alu_op[3] = inst_sltu;  // sltu
  assign alu_op[4] = inst_and;  // and
  assign alu_op[5] = inst_nor;  // nor
  assign alu_op[6] = inst_or;  // or
  assign alu_op[7] = inst_xor;  // xor
  assign alu_op[8] = inst_slli_w;  // sll
  assign alu_op[9] = inst_srli_w;  // srl
  assign alu_op[10] = inst_srai_w;  // sra
  assign alu_op[11] = inst_lu12i_w;  // lui

  assign need_ui5 = inst_slli_w | inst_srli_w | inst_srai_w;
  assign need_si12 = inst_addi_w | inst_ld_w | inst_st_w;
  assign need_si16 = inst_jirl | inst_beq | inst_bne;
  assign need_si20 = inst_lu12i_w;
  assign need_si26 = inst_b | inst_bl;
  assign src2_is_4 = inst_jirl | inst_bl;

  assign imm = src2_is_4 ? 32'h4 : need_si20 ? {i20[19:0], 12'b0} :
      /*need_ui5 || need_si12*/{{20{i12[11]}}, i12[11:0]};

  assign br_offs = need_si26 ? {{4{i26[25]}}, i26[25:0], 2'b0} : {{14{i16[15]}}, i16[15:0], 2'b0};

  assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

  assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w;

  assign src1_is_pc = inst_jirl | inst_bl;

  assign src2_is_imm   = inst_slli_w |
                       inst_srli_w |
                       inst_srai_w |
                       inst_addi_w |
                       inst_ld_w   |
                       inst_st_w   |
                       inst_lu12i_w|
                       inst_jirl   |
                       inst_bl     ;

  assign res_from_mem = inst_ld_w;
  assign dst_is_r1 = inst_bl;
  assign reg_waddr = dst_is_r1 ? 5'd1 : rd;
  assign reg_we = id_valid && (~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b) && |(reg_waddr);

  assign mem_en = inst_ld_w || inst_st_w;
  assign mem_we = {4{inst_st_w}};

  assign rf_raddr1 = rj;
  assign rf_raddr2 = src_reg_is_rd ? rd : rk;
  regfile u_regfile (
      .clk   (clk),
      .raddr1(rf_raddr1),
      .rdata1(rf_rdata1),
      .raddr2(rf_raddr2),
      .rdata2(rf_rdata2),
      .we    (rf_we),
      .waddr (rf_waddr),
      .wdata (rf_wdata)
  );
  assign rj_value  = rf_rdata1;
  assign rkd_value = rf_rdata2;

  wire rj_eq_rd = (rj_value == rkd_value);
  assign br_taken = id_valid && ( inst_beq  &&  rj_eq_rd
                   || inst_bne  && !rj_eq_rd
                   || inst_jirl
                   || inst_bl
                   || inst_b
                  ) && id_ready_go;
  assign br_target = (inst_beq || inst_bne || inst_bl || inst_b) ? (id_pc + br_offs) :
      /*inst_jirl*/ (rj_value + jirl_offs);


  assign rf_we = wb_rf_we;
  assign rf_waddr = wb_rf_waddr;
  assign rf_wdata = wb_rf_wdata;

  // hazard detection
  wire use_rf_rdata1 = id_valid && (!inst_lu12i_w && !inst_b && !inst_bl);
  wire use_rf_rdata2 = id_valid && (
      inst_add_w ||
      inst_sub_w ||
      inst_slt ||
      inst_sltu ||
      inst_nor ||
      inst_and ||
      inst_or ||
      inst_xor ||
      inst_st_w ||
      inst_beq ||
      inst_bne
    );

  // case waddr is 0 has already been handled in line 250
  // which means that if waddr is 0, rf_we is 0
  wire rf_rdata1_hazard = use_rf_rdata1 && (
    (exe_valid && exe_rf_we && (rf_raddr1 == exe_rf_waddr)) ||
    (mem_valid && mem_rf_we && (rf_raddr1 == mem_rf_waddr)) ||
    (wb_valid && wb_rf_we && (rf_raddr1 == wb_rf_waddr))
  );
  wire rf_rdata2_hazard = use_rf_rdata2 && (
    (exe_valid && exe_rf_we && (rf_raddr2 == exe_rf_waddr)) ||
    (mem_valid && mem_rf_we && (rf_raddr2 == mem_rf_waddr)) ||
    (wb_valid && wb_rf_we && (rf_raddr2 == wb_rf_waddr))
  );
  assign id_ready_go = !rf_rdata1_hazard && !rf_rdata2_hazard;

  assign br_taken_cancel = id_valid && id_ready_go && br_taken;
endmodule
