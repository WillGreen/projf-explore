// Project F: FPGA Pong - Top Pong v4 (Nexys Video)
// (C)2020 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io

`default_nettype none
`timescale 1ns / 1ps

module top_pong_v4 (
    input  wire logic clk_100m,         // 100 MHz clock
    input  wire logic btn_rst,          // reset button (active low)
    input  wire logic btn_up,           // up button
    input  wire logic btn_ctrl,         // control button
    input  wire logic btn_dn,           // down button
    output      logic hdmi_tx_ch0_p,    // HDMI source channel 0 diff+
    output      logic hdmi_tx_ch0_n,    // HDMI source channel 0 diff-
    output      logic hdmi_tx_ch1_p,    // HDMI source channel 1 diff+
    output      logic hdmi_tx_ch1_n,    // HDMI source channel 1 diff-
    output      logic hdmi_tx_ch2_p,    // HDMI source channel 2 diff+
    output      logic hdmi_tx_ch2_n,    // HDMI source channel 2 diff-
    output      logic hdmi_tx_clk_p,    // HDMI source clock diff+
    output      logic hdmi_tx_clk_n     // HDMI source clock diff-
    );

    // pixel clocks
    logic clk_pix;                  // pixel clock (148.5 MHz)
    logic clk_pix_5x;               // 5x pixel clock for 10:1 DDR SerDes
    logic clk_pix_locked;           // pixel clocks locked?
    clock_gen_pix clock_pix_inst (
        .clk_100m,
        .rst(!btn_rst),             // reset button is active low
        .clk_pix,
        .clk_pix_5x,
        .clk_pix_locked
    );

    // display timings
    localparam CORDW = 12;  // screen coordinate width in bits
    logic [CORDW-1:0] sx, sy;
    logic hsync, vsync;
    logic de;
    display_timings_1080p timings_1080p (
        .clk_pix,
        .rst(!clk_pix_locked),  // wait for pixel clock lock
        .sx,
        .sy,
        .hsync,
        .vsync,
        .de
    );

    // size of screen (excluding blanking)
    localparam H_RES = 1920;
    localparam V_RES = 1080;

    logic animate;  // high for one clock tick at start of blanking
    always_comb animate = (sy == V_RES && sx == 0);

    // debounce buttons
    logic sig_ctrl, move_up, move_dn;
    /* verilator lint_off PINCONNECTEMPTY */
    debounce deb_btn_ctrl (.clk(clk_pix), .in(btn_ctrl), .out(), .ondn(), .onup(sig_ctrl));
    debounce deb_btn_up (.clk(clk_pix), .in(btn_up), .out(move_up), .ondn(), .onup());
    debounce deb_btn_dn (.clk(clk_pix), .in(btn_dn), .out(move_dn), .ondn(), .onup());
    /* verilator lint_on PINCONNECTEMPTY */

    // ball
    localparam B_SIZE = 24;         // size in pixels
    logic [CORDW-1:0] bx, by;       // position
    logic dx, dy;                   // direction: 0 is right/down
    logic [CORDW-1:0] spx = 12'd16; // horizontal speed
    logic [CORDW-1:0] spy = 12'd8;  // vertical speed
    logic b_draw;                   // draw ball?

    // paddles
    localparam P_HEIGHT = 100;      // height in pixels
    localparam P_WIDTH  = 20;       // width in pixels
    localparam P_SPEED  = 12;       // speed
    localparam P_OFFSET = 96;       // offset from screen edge
    logic [CORDW-1:0] p1y, p2y;     // vertical position of paddles 1 and 2
    logic p1_draw, p2_draw;         // draw paddles?
    logic p1_col, p2_col;           // paddle collision?

    // game state
    enum {IDLE, PLAY} state, state_next;
    always_comb begin
        case(state)
            IDLE: state_next = (sig_ctrl) ? PLAY : IDLE;
            PLAY: state_next = (sig_ctrl) ? IDLE : PLAY;
            default: state_next = IDLE;
        endcase
    end

    always_ff @(posedge clk_pix) begin
        state <= state_next;
    end

    // paddle animation
    always_ff @(posedge clk_pix) begin
        if (animate) begin
            if (state == PLAY) begin  // human paddle 1
                if (move_up) begin
                    if (p1y > P_SPEED) p1y <= p1y - P_SPEED;  // at top?
                end
                if (move_dn) begin
                    if (p1y < V_RES - (P_HEIGHT + P_SPEED)) p1y <= p1y + P_SPEED;  // at bottom?
                end
            end else begin  // "AI" paddle 1
                if ((p1y + P_HEIGHT/2) < by) begin  // top of ball is below
                    if (p1y < V_RES - (P_HEIGHT + P_SPEED)) p1y <= p1y + P_SPEED;  // screen bottom?
                end
                if ((p1y + P_HEIGHT/2) > (by + B_SIZE)) begin  // bottom of ball is above
                    if (p1y > P_SPEED) p1y <= p1y - P_SPEED;  // screen top?
                end
            end

            // "AI" paddle 2
            if ((p2y + P_HEIGHT/2) < by) begin
                if (p2y < V_RES - (P_HEIGHT + P_SPEED)) p2y <= p2y + P_SPEED;
            end
            if ((p2y + P_HEIGHT/2) > (by + B_SIZE)) begin
                if (p2y > P_SPEED) p2y <= p2y - P_SPEED;
            end
        end
    end

    // draw paddles - are paddles at current screen position?
    always_comb begin
        p1_draw = (sx >= P_OFFSET) && (sx < P_OFFSET + P_WIDTH)
               && (sy >= p1y) && (sy < p1y + P_HEIGHT);
        p2_draw = (sx >= H_RES - P_OFFSET - P_WIDTH) && (sx < H_RES - P_OFFSET)
               && (sy >= p2y) && (sy < p2y + P_HEIGHT);
    end

    // paddle collision detection
    always_ff @(posedge clk_pix) begin
        if (animate) begin
            p1_col <= 0;
            p2_col <= 0;
        end else if (b_draw) begin
            if (p1_draw) p1_col <= 1;
            if (p2_draw) p2_col <= 1;
        end
    end

    // ball animation
    always_ff @(posedge clk_pix) begin
        if (animate) begin
            if (p1_col) begin  // left paddle collision
                dx <= 0;
                bx <= bx + spx;
            end else if (p2_col) begin  // right paddle collision
                dx <= 1;
                bx <= bx - spx;
            end else if (bx >= H_RES - (spx + B_SIZE)) begin  // right edge
                dx <= 1;
                bx <= bx - spx;
            end else if (bx < spx) begin  // left edge
                dx <= 0;
                bx <= bx + spx;
            end else bx <= (dx) ? bx - spx : bx + spx;

            if (by >= V_RES - (spy + B_SIZE)) begin  // bottom edge
                dy <= 1;
                by <= by - spy;
            end else if (by < spy) begin  // top edge
                dy <= 0;
                by <= by + spy;
            end else by <= (dy) ? by - spy : by + spy;
        end
    end

    // draw ball - is ball at current screen position?
    always_comb begin
        b_draw = (sx >= bx) && (sx < bx + B_SIZE)
              && (sy >= by) && (sy < by + B_SIZE);
    end

    // colours
    logic [7:0] red, green, blue;
    always_comb begin
        red   = (de && (b_draw | p1_draw | p2_draw)) ? 8'hFF : 8'h00;
        green = (de && (b_draw | p1_draw | p2_draw)) ? 8'hFF : 8'h00;
        blue  = (de && (b_draw | p1_draw | p2_draw)) ? 8'hFF : 8'h00;
    end

    // TMDS encoding and serialization
    logic tmds_ch0_serial, tmds_ch1_serial, tmds_ch2_serial, tmds_clk_serial;
    dvi_generator dvi_out (
        .clk_pix,
        .clk_pix_5x,
        .rst(!clk_pix_locked),
        .de,
        .data_in_ch0(blue),
        .data_in_ch1(green),
        .data_in_ch2(red),
        .ctrl_in_ch0({vsync, hsync}),
        .ctrl_in_ch1(2'b00),
        .ctrl_in_ch2(2'b00),
        .tmds_ch0_serial,
        .tmds_ch1_serial,
        .tmds_ch2_serial,
        .tmds_clk_serial
    );

    // TMDS output pins
    tmds_out tmds_ch0 (.tmds(tmds_ch0_serial), .pin_p(hdmi_tx_ch0_p), .pin_n(hdmi_tx_ch0_n));
    tmds_out tmds_ch1 (.tmds(tmds_ch1_serial), .pin_p(hdmi_tx_ch1_p), .pin_n(hdmi_tx_ch1_n));
    tmds_out tmds_ch2 (.tmds(tmds_ch2_serial), .pin_p(hdmi_tx_ch2_p), .pin_n(hdmi_tx_ch2_n));
    tmds_out tmds_clk (.tmds(tmds_clk_serial), .pin_p(hdmi_tx_clk_p), .pin_n(hdmi_tx_clk_n));
endmodule
