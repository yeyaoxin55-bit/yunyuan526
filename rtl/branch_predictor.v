module branch_predictor #(
    parameter BHT_DEPTH = 128,
    parameter BHR_WIDTH = 4,
    parameter BTB_DEPTH = 64,
    parameter LOCAL_HISTORY = 1,
    parameter INIT_TAKEN = 0,
    parameter BTB_INDEX_HASH = 0
) (
    input wire clk,
    input wire rst,
    input wire [31:0] pc_i,
    output wire predict_taken_o,
    output wire [31:0] predict_target_o,
    input wire update_i,
    input wire update_uncond_i,
    input wire [31:0] update_pc_i,
    input wire actual_taken_i,
    input wire [31:0] actual_target_i
);
    localparam BHT_INDEX_W = $clog2(BHT_DEPTH);
    localparam BTB_INDEX_W = $clog2(BTB_DEPTH);
    localparam [1:0] INIT_COUNTER = (INIT_TAKEN != 0) ? 2'b10 : 2'b01;

    reg [1:0] bht [0:BHT_DEPTH-1];
    reg btb_valid [0:BTB_DEPTH-1];
    reg btb_uncond [0:BTB_DEPTH-1];
    reg [31:0] btb_tag [0:BTB_DEPTH-1];
    reg [31:0] btb_target [0:BTB_DEPTH-1];
    reg update_valid_q;
    reg [BHT_INDEX_W-1:0] update_bht_index_q;
    reg [BTB_INDEX_W-1:0] update_btb_index_q;
    reg [31:0] update_pc_q;
    reg update_taken_q;
    reg update_uncond_q;
    reg [31:0] update_target_q;
    integer i;

    function [BTB_INDEX_W-1:0] btb_index_for_pc;
        input [31:0] pc_value;
        integer bit_i;
        begin
            btb_index_for_pc = pc_value[BTB_INDEX_W+1:2];
            if (BTB_INDEX_HASH != 0) begin
                for (bit_i = 0; bit_i < BTB_INDEX_W; bit_i = bit_i + 1) begin
                    if ((BTB_INDEX_HASH + bit_i) < 32) begin
                        btb_index_for_pc[bit_i] = btb_index_for_pc[bit_i] ^ pc_value[BTB_INDEX_HASH + bit_i];
                    end
                end
            end
        end
    endfunction

    wire [BHT_INDEX_W-1:0] bht_index = pc_i[BHT_INDEX_W+1:2];
    wire [BTB_INDEX_W-1:0] btb_index = btb_index_for_pc(pc_i);
    wire [BHT_INDEX_W-1:0] update_bht_index = update_pc_i[BHT_INDEX_W+1:2];
    wire [BTB_INDEX_W-1:0] update_btb_index = btb_index_for_pc(update_pc_i);
    wire btb_hit = btb_valid[btb_index] && (btb_tag[btb_index] == pc_i);
    wire bht_predict_taken = bht[bht_index][1];
    wire direction_predict_taken;

    assign predict_taken_o = btb_hit && (btb_uncond[btb_index] || direction_predict_taken);
    assign predict_target_o = predict_taken_o ? btb_target[btb_index] : (pc_i + 32'd4);

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < BHT_DEPTH; i = i + 1) begin
                bht[i] <= INIT_COUNTER;
            end
            for (i = 0; i < BTB_DEPTH; i = i + 1) begin
                btb_valid[i] <= 1'b0;
                btb_uncond[i] <= 1'b0;
                btb_tag[i] <= 32'h00000000;
                btb_target[i] <= 32'h00000000;
            end
            update_valid_q <= 1'b0;
            update_bht_index_q <= {BHT_INDEX_W{1'b0}};
            update_btb_index_q <= {BTB_INDEX_W{1'b0}};
            update_pc_q <= 32'h00000000;
            update_taken_q <= 1'b0;
            update_uncond_q <= 1'b0;
            update_target_q <= 32'h00000000;
        end else begin
            update_valid_q <= update_i;
            if (update_i) begin
                update_bht_index_q <= update_bht_index;
                update_btb_index_q <= update_btb_index;
                update_pc_q <= update_pc_i;
                update_taken_q <= actual_taken_i;
                update_uncond_q <= update_uncond_i;
                update_target_q <= actual_target_i;
            end

            if (update_valid_q) begin
                if (update_uncond_q) begin
                    btb_valid[update_btb_index_q] <= 1'b1;
                    btb_uncond[update_btb_index_q] <= 1'b1;
                    btb_tag[update_btb_index_q] <= update_pc_q;
                    btb_target[update_btb_index_q] <= update_target_q;
                end else if (update_taken_q) begin
                    if (bht[update_bht_index_q] != 2'b11) begin
                        bht[update_bht_index_q] <= bht[update_bht_index_q] + 2'b01;
                    end
                    btb_valid[update_btb_index_q] <= 1'b1;
                    btb_uncond[update_btb_index_q] <= 1'b0;
                    btb_tag[update_btb_index_q] <= update_pc_q;
                    btb_target[update_btb_index_q] <= update_target_q;
                end else begin
                    if (bht[update_bht_index_q] != 2'b00) begin
                        bht[update_bht_index_q] <= bht[update_bht_index_q] - 2'b01;
                    end
                end
            end
        end
    end

    generate
        if (LOCAL_HISTORY != 0) begin : gen_local_history
            localparam PHT_DEPTH = BHT_DEPTH * (1 << BHR_WIDTH);
            localparam PHT_INDEX_W = $clog2(PHT_DEPTH);

            reg [BHR_WIDTH-1:0] bhr [0:BHT_DEPTH-1];
            reg [1:0] pht [0:PHT_DEPTH-1];
            reg [BHR_WIDTH-1:0] update_bhr_q;
            integer hist_i;
            integer pht_init_i;

            wire [PHT_INDEX_W-1:0] pht_index = {bht_index, bhr[bht_index]};
            wire [PHT_INDEX_W-1:0] update_pht_index_q = {update_bht_index_q, update_bhr_q};
            wire pht_predict_taken = pht[pht_index][1];
            wire pht_strong = (pht[pht_index] == 2'b00) || (pht[pht_index] == 2'b11);

            assign direction_predict_taken = pht_strong ? pht_predict_taken : bht_predict_taken;

            initial begin
                for (pht_init_i = 0; pht_init_i < PHT_DEPTH; pht_init_i = pht_init_i + 1) begin
                    pht[pht_init_i] = INIT_COUNTER;
                end
            end

            always @(posedge clk) begin
                if (rst) begin
                    for (hist_i = 0; hist_i < BHT_DEPTH; hist_i = hist_i + 1) begin
                        bhr[hist_i] <= {BHR_WIDTH{1'b0}};
                    end
                    update_bhr_q <= {BHR_WIDTH{1'b0}};
                end else begin
                    if (update_i) begin
                        update_bhr_q <= bhr[update_bht_index];
                    end

                    if (update_valid_q && !update_uncond_q) begin
                        if (update_taken_q) begin
                            if (pht[update_pht_index_q] != 2'b11) begin
                                pht[update_pht_index_q] <= pht[update_pht_index_q] + 2'b01;
                            end
                        end else begin
                            if (pht[update_pht_index_q] != 2'b00) begin
                                pht[update_pht_index_q] <= pht[update_pht_index_q] - 2'b01;
                            end
                        end
                        bhr[update_bht_index_q] <= {update_bhr_q[BHR_WIDTH-2:0], update_taken_q};
                    end
                end
            end
        end else begin : gen_no_local_history
            assign direction_predict_taken = bht_predict_taken;
        end
    endgenerate
endmodule
