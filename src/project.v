`default_nettype none

module tt_um_kateiesa_game_piano_tiles_3 (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire        hsync, vsync, active, frame;
    wire [9:0]  x, y;
    wire [5:0]  rgb;
    wire        audio;

    vga_sync vga (.clk(clk), .rst_n(rst_n), .hsync(hsync), .vsync(vsync),
                  .active(active), .x(x), .y(y), .frame(frame));

    game_core core (
        .clk(clk), .rst_n(rst_n),
        .btn(ui_in[3:0]),
        .x(x), .y(y), .active(active), .frame(frame),
        .audio(audio),
        .rgb(rgb)
    );

    assign uo_out  = {hsync, rgb[0], rgb[2], rgb[4], vsync, rgb[1], rgb[3], rgb[5]};
    assign uio_out = {7'd0, audio};    // uio[0] = audio
    assign uio_oe  = 8'd1;             // only uio[0] is driven

    wire _unused = &{ena, ui_in[7:4], 1'b0};
endmodule
