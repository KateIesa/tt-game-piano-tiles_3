`default_nettype none

module ip_tiles #(
    parameter MAX_TILES = 3,
    parameter [10:0] TILE_W = 120,
    parameter [10:0] TILE_H = 80,
    parameter [10:0] HIT_Y = 400,
    parameter [10:0] HIT_ZONE = 60,
    parameter [3:0] LEVEL_UP_AT = 4'd15
) (
    input  wire       clk, rst_n, step,
    input  wire [3:0] btn,
    input  wire [9:0] x, y,
    input  wire       active,
    output wire       audio,
    output reg  [5:0] rgb
);
    localparam IDX_W = $clog2(MAX_TILES);

    // ------------------------------------------------------------------
    // button edge detection
    // ------------------------------------------------------------------
    reg  [3:0] btn_prev;
    always @(posedge clk) btn_prev <= btn;
    wire [3:0] btn_pushed = btn & ~btn_prev;
    wire       any_pushed = |btn_pushed;

    wire [3:0] lane_active = btn;

    // ------------------------------------------------------------------
    // 4-bit free-running entropy counter
    // ------------------------------------------------------------------
    reg  [3:0] entropy_ctr;
    always @(posedge clk) begin
        if (!rst_n) entropy_ctr <= 4'd0;
        else        entropy_ctr <= entropy_ctr + 4'd1;
    end

    // ------------------------------------------------------------------
    // per-tile state
    // ------------------------------------------------------------------
    reg  [9:0]  tile_y     [0:MAX_TILES-1];
    reg  [1:0]  tile_lane  [0:MAX_TILES-1];
    reg  [10:0] tile_x     [0:MAX_TILES-1];
    reg         tile_alive [0:MAX_TILES-1];

    // game-state registers
    reg  [5:0] spawn_count;
    reg  [7:0] lfsr;
    reg  [3:0] level_progress;
    reg  [2:0] level;
    reg        ended;
    reg        is_win;
    reg        first_run;

    reg  [4:0] speed_cur;
    reg  [5:0] interval_cur;

    wire restart_clear = ended && any_pushed;

    always @(posedge clk) begin
        case (level)
            3'd2: begin speed_cur <= 5'd6;  interval_cur <= 6'd20; end
            3'd3: begin speed_cur <= 5'd8;  interval_cur <= 6'd15; end
            3'd4: begin speed_cur <= 5'd10; interval_cur <= 6'd14; end
            3'd5: begin speed_cur <= 5'd12; interval_cur <= 6'd12; end
            default: begin speed_cur <= 5'd4; interval_cur <= 6'd30; end
        endcase
    end

    // ------------------------------------------------------------------
    // tile geometry + zone checks
    // ------------------------------------------------------------------
    wire [10:0] tile_bottom [0:MAX_TILES-1];
    wire [MAX_TILES-1:0] in_zone, miss_vec, hittable;
    genvar g;
    generate
        for (g = 0; g < MAX_TILES; g = g + 1) begin : tile_eval
            assign tile_bottom[g] = {1'b0, tile_y[g]} + TILE_H;
            assign miss_vec[g]    = tile_alive[g]
                                    && (tile_bottom[g] > HIT_Y + HIT_ZONE);
            assign in_zone[g]     = tile_alive[g]
                                    && (tile_bottom[g] >= HIT_Y)
                                    && (tile_bottom[g] <= HIT_Y + HIT_ZONE);
            assign hittable[g]    = in_zone[g] && btn_pushed[tile_lane[g]];
        end
    endgenerate

    wire any_hit  = |hittable;
    wire any_miss = |miss_vec;

    wire [3:0] lane_has_tile;
    generate
        for (g = 0; g < 4; g = g + 1) begin : lane_pres
            wire [MAX_TILES-1:0] hits_lane;
            for (genvar t = 0; t < MAX_TILES; t = t + 1) begin : per_tile
                assign hits_lane[t] = in_zone[t] && (tile_lane[t] == g[1:0]);
            end
            assign lane_has_tile[g] = |hits_lane;
        end
    endgenerate

    wire [3:0] wrong_press     = btn_pushed & ~lane_has_tile;
    wire       any_wrong_press = |wrong_press;

    wire progress_up   =  any_hit && !any_wrong_press;
    wire progress_down = !any_hit &&  any_wrong_press;

    // ------------------------------------------------------------------
    // spawn slot finder
    // ------------------------------------------------------------------
    reg [IDX_W-1:0] spawn_idx;
    reg             spawn_slot_free;
    always @(*) begin
        integer kk;
        spawn_idx       = {IDX_W{1'b0}};
        spawn_slot_free = 1'b0;
        for (kk = MAX_TILES-1; kk >= 0; kk = kk - 1)
            if (!tile_alive[kk]) begin
                spawn_idx       = kk[IDX_W-1:0];
                spawn_slot_free = 1'b1;
            end
    end

    wire [1:0]  next_lane    = lfsr[1:0];
    wire [10:0] next_lane_x  = 11'd20
                             + {2'd0, next_lane, 7'd0}
                             + {4'd0, next_lane, 5'd0};

    wire spawn_due   = step && !ended
                       && (spawn_count >= interval_cur - 6'd1);
    wire spawn_pulse = spawn_due && spawn_slot_free;

    // ------------------------------------------------------------------
    // per-tile always blocks
    // ------------------------------------------------------------------
    generate
        for (g = 0; g < MAX_TILES; g = g + 1) begin : tile_state
            localparam [IDX_W-1:0] G_IDX = g;
            always @(posedge clk) begin
                if (!rst_n || restart_clear) begin
                    tile_alive[g] <= 1'b0;
                    tile_y[g]     <= 10'd0;
                    tile_lane[g]  <= 2'd0;
                    tile_x[g]     <= 11'd20;
                end else if (spawn_pulse && (spawn_idx == G_IDX)) begin
                    tile_alive[g] <= 1'b1;
                    tile_y[g]     <= 10'd0;
                    tile_lane[g]  <= next_lane;
                    tile_x[g]     <= next_lane_x;
                end else if (hittable[g] || miss_vec[g]) begin
                    tile_alive[g] <= 1'b0;
                end else if (step && !ended && tile_alive[g]) begin
                    tile_y[g] <= tile_y[g] + {4'd0, speed_cur};
                end
            end
        end
    endgenerate

    // ------------------------------------------------------------------
    // LFSR feedback path (combinational)
    // ------------------------------------------------------------------
    wire [7:0] lfsr_feedback = {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};

    // ------------------------------------------------------------------
    // game state machine
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            spawn_count    <= 6'd0;
            level_progress <= 4'd0;
            level          <= 3'd1;
            ended          <= 1'b1;
            is_win         <= 1'b0;
            first_run      <= 1'b1;
            lfsr           <= 8'hA5;
        end else if (restart_clear) begin
            spawn_count    <= 6'd0;
            level_progress <= 4'd0;
            level          <= 3'd1;
            ended          <= 1'b0;
            is_win         <= 1'b0;
            first_run      <= 1'b0;
            // 4-bit btn ^ 4-bit entropy → zero-extend → XOR with 8-bit lfsr
            lfsr           <= (lfsr ^ {4'b0, btn_pushed ^ entropy_ctr}) | 8'h01;
        end else if (!ended) begin
            if (spawn_due) begin
                spawn_count <= 6'd0;
                if (spawn_pulse)
                    lfsr <= lfsr_feedback ^ {4'b0, entropy_ctr};
            end else if (step) begin
                spawn_count <= spawn_count + 6'd1;
            end

            if (any_pushed)
                lfsr <= lfsr ^ {4'b0, entropy_ctr};

            if (progress_up) begin
                if (level_progress == LEVEL_UP_AT) begin
                    level_progress <= 4'd0;
                    if (level < 3'd5)
                        level <= level + 3'd1;
                    else begin
                        ended  <= 1'b1;
                        is_win <= 1'b1;
                    end
                end else begin
                    level_progress <= level_progress + 4'd1;
                end
            end else if (progress_down && level_progress > 4'd0) begin
                level_progress <= level_progress - 4'd1;
            end

            if (any_miss) begin
                if (level == 3'd1) begin
                    ended  <= 1'b1;
                    is_win <= 1'b0;
                end else begin
                    level          <= level - 3'd1;
                    level_progress <= 4'd0;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // tile rendering
    // ------------------------------------------------------------------
    wire [MAX_TILES-1:0] tile_pixel;
    generate
        for (g = 0; g < MAX_TILES; g = g + 1) begin : tile_render
            wire [10:0] x11   = {1'b0, x};
            wire [10:0] y11   = {1'b0, y};
            wire [10:0] tx_lo = tile_x[g];
            wire [10:0] tx_hi = tile_x[g] + TILE_W;
            wire [10:0] ty_lo = {1'b0, tile_y[g]};
            wire [10:0] ty_hi = ty_lo + TILE_H;
            assign tile_pixel[g] = tile_alive[g]
                                   && (x11 >= tx_lo) && (x11 < tx_hi)
                                   && (y11 >= ty_lo) && (y11 < ty_hi);
        end
    endgenerate
    wire any_tile_pixel = |tile_pixel;

    // ==================================================================
    // AUDIO ENGINE — hit / miss / wrong / win / loss
    // ==================================================================
    reg  [7:0] prescaler;
    wire       tone_tick = (prescaler == 8'd249);
    always @(posedge clk) begin
        if (!rst_n)         prescaler <= 8'd0;
        else if (tone_tick) prescaler <= 8'd0;
        else                prescaler <= prescaler + 8'd1;
    end

    reg ended_prev;
    always @(posedge clk) begin
        if (!rst_n) ended_prev <= 1'b0;
        else        ended_prev <= ended;
    end
    wire ended_rise = ended & ~ended_prev;
    wire win_rise   = ended_rise &  is_win & ~first_run;
    wire loss_rise  = ended_rise & ~is_win & ~first_run;

    reg  [2:0] mel_type;
    reg  [2:0] mel_note;
    reg  [4:0] mel_timer;
    reg  [7:0] mel_period;

    wire melody_active = (mel_type != 3'd0);

    always @(posedge clk) begin
        if (!rst_n || restart_clear) begin
            mel_type   <= 3'd0;
            mel_note   <= 3'd0;
            mel_timer  <= 5'd0;
            mel_period <= 8'd50;
        end else if (win_rise) begin
            mel_type   <= 3'd1;
            mel_note   <= 3'd0;
            mel_timer  <= 5'd3;
            mel_period <= 8'd47;
        end else if (loss_rise) begin
            mel_type   <= 3'd2;
            mel_note   <= 3'd0;
            mel_timer  <= 5'd5;
            mel_period <= 8'd214;
        end else if (step && mel_type != 3'd0) begin
            if (mel_timer != 5'd0) begin
                mel_timer <= mel_timer - 5'd1;
            end else begin
                if (mel_type == 3'd1) begin
                    if (mel_note < 3'd3) begin
                        case (mel_note)
                            3'd0: begin mel_period <= 8'd37; mel_timer <= 5'd3;  end
                            3'd1: begin mel_period <= 8'd31; mel_timer <= 5'd3;  end
                            3'd2: begin mel_period <= 8'd23; mel_timer <= 5'd25; end
                            default: begin end
                        endcase
                        mel_note <= mel_note + 3'd1;
                    end else mel_type <= 3'd0;
                end else begin
                    case (mel_note)
                        3'd0: begin mel_period <= 8'd226; mel_timer <= 5'd5;  end
                        3'd1: begin mel_period <= 8'd240; mel_timer <= 5'd5;  end
                        3'd2: begin mel_period <= 8'd254; mel_timer <= 5'd28; end
                        default: mel_type <= 3'd0;
                    endcase
                    if (mel_note < 3'd3)
                        mel_note <= mel_note + 3'd1;
                end
            end
        end
    end

    reg [1:0] hit_lane;
    integer i;
    always @(*) begin
        hit_lane = 2'd0;
        for (i = MAX_TILES-1; i >= 0; i = i - 1)
            if (hittable[i]) hit_lane = tile_lane[i];
    end

    wire [7:0] hit_period = (hit_lane == 2'd0) ? 8'd47 :
                            (hit_lane == 2'd1) ? 8'd37 :
                            (hit_lane == 2'd2) ? 8'd31 :
                                                 8'd23;

    wire snd_hit   = any_hit         && !melody_active && !win_rise  && !restart_clear;
    wire snd_miss  = any_miss        && !any_hit && !melody_active && !loss_rise && !restart_clear;
    wire snd_wrong = any_wrong_press && !any_hit && !any_miss && !melody_active && !restart_clear;

    reg  [2:0] dur_steps;
    reg  [7:0] tone_period;
    always @(posedge clk) begin
        if (!rst_n || restart_clear) begin
            dur_steps   <= 3'd0;
            tone_period <= 8'd50;
        end else if (win_rise || loss_rise) begin
            dur_steps   <= 3'd0;
        end else if (snd_hit) begin
            dur_steps   <= 3'd4;
            tone_period <= hit_period;
        end else if (snd_miss) begin
            dur_steps   <= 3'd6;
            tone_period <= 8'd200;
        end else if (snd_wrong) begin
            dur_steps   <= 3'd3;
            tone_period <= 8'd100;
        end else if (step && dur_steps != 3'd0) begin
            dur_steps   <= dur_steps - 3'd1;
        end
    end

    wire [7:0] active_period = melody_active ? mel_period : tone_period;
    wire       sound_active  = melody_active || (dur_steps != 3'd0);

    reg  [7:0] tone_cnt;
    reg        tone_pol;
    always @(posedge clk) begin
        if (!rst_n) begin
            tone_cnt <= 8'd0;
            tone_pol <= 1'b0;
        end else if (sound_active) begin
            if (tone_tick) begin
                if (tone_cnt >= active_period) begin
                    tone_cnt <= 8'd0;
                    tone_pol <= ~tone_pol;
                end else begin
                    tone_cnt <= tone_cnt + 8'd1;
                end
            end
        end else begin
            tone_cnt <= 8'd0;
            tone_pol <= 1'b0;
        end
    end

    assign audio = sound_active && tone_pol;

    // ==================================================================
    // HUD
    // ==================================================================
    wire [9:0] bar_right = ({7'd0, level} << 7)
                         + ({6'd0, level_progress} << 3)
                         - 10'd120;
    wire bar_pixel = (y < 10'd8) && (x < bar_right);

    wire [2:0] bar_seg   = x[9:7];
    wire [5:0] bar_color = (bar_seg == 3'd0) ? 6'b00_11_00 :
                           (bar_seg == 3'd1) ? 6'b11_11_00 :
                           (bar_seg == 3'd2) ? 6'b11_10_00 :
                           (bar_seg == 3'd3) ? 6'b11_00_00 :
                                               6'b11_00_11;

    wire [10:0] y11_hud = {1'b0, y};
    wire on_hit_line = (y11_hud >= HIT_Y) && (y11_hud < HIT_Y + 11'd2);

    wire [1:0] x_lane = (x < 10'd160) ? 2'd0 :
                        (x < 10'd320) ? 2'd1 :
                        (x < 10'd480) ? 2'd2 : 2'd3;
    wire hit_line_pressed = on_hit_line && lane_active[x_lane];

    wire lane_div = (x == 10'd160) || (x == 10'd320) || (x == 10'd480);

    always @(*) begin
        if (!active)                rgb = 6'b00_00_00;
        else if (ended && is_win)   rgb = 6'b00_11_00;
        else if (ended)             rgb = 6'b11_00_00;
        else if (hit_line_pressed)  rgb = 6'b11_11_00;
        else if (on_hit_line)       rgb = 6'b00_11_11;
        else if (any_tile_pixel)    rgb = 6'b11_11_11;
        else if (bar_pixel)         rgb = bar_color;
        else if (lane_div)          rgb = 6'b01_01_01;
        else                        rgb = 6'b00_00_01;
    end
endmodule
