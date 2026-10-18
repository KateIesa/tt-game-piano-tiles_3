`default_nettype none

module game_core #(
    parameter DB = 100000
) (
    input  wire       clk, rst_n,
    input  wire [3:0] btn,
    input  wire [9:0] x, y,
    input  wire       active,
    input  wire       frame,
    output wire       audio,      // ← NEW
    output wire [5:0] rgb
);
    reg  [19:0] db_cnt;
    reg  [3:0]  btn_clean;
    wire        db_tick = (db_cnt == DB[19:0] - 20'd1);

    always @(posedge clk) begin
        if (!rst_n)       db_cnt <= 20'd0;
        else if (db_tick) db_cnt <= 20'd0;
        else              db_cnt <= db_cnt + 20'd1;
    end

    always @(posedge clk) begin
        if (!rst_n)       btn_clean <= 4'b0;
        else if (db_tick) btn_clean <= btn;
    end

    ip_tiles tiles (
        .clk(clk), .rst_n(rst_n),
        .step(frame),
        .btn(btn_clean),
        .x(x), .y(y), .active(active),
        .audio(audio),            // ← NEW
        .rgb(rgb)
    );
endmodule
