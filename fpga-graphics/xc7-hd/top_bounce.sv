// Project F: FPGA Graphics - Top Bounce (Nexys Video)
// (C)2020 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io

`default_nettype none
`timescale 1ns / 1ps

module top_bounce (
    input  wire logic clk_100m,         // 100 MHz clock
    input  wire logic btn_rst,          // reset button (active low)
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

    // size of screen with and without blanking
    localparam H_RES_FULL = 2200;
    localparam V_RES_FULL = 1125;
    localparam H_RES = 1920;
    localparam V_RES = 1080;

    logic animate;  // high for one clock tick at start of blanking
    always_comb animate = (sy == V_RES && sx == 0);

    // squares - origin at top-left
    localparam Q1_SIZE = 300;   // square 1 size in pixels
    localparam Q2_SIZE = 450;   // square 2 size in pixels
    localparam Q3_SIZE = 600;   // square 3 size in pixels
    logic [CORDW-1:0] q1x, q1y; // square 1 position
    logic [CORDW-1:0] q2x, q2y; // square 2 position
    logic [CORDW-1:0] q3x, q3y; // square 3 position
    logic q1dx, q1dy;           // square 1 direction: 0 is right/down
    logic q2dx, q2dy;           // square 2 direction: 0 is right/down
    logic q3dx, q3dy;           // square 3 direction: 0 is right/down
    logic [CORDW-1:0] q1s = 6;  // square 1 speed
    logic [CORDW-1:0] q2s = 4;  // square 2 speed
    logic [CORDW-1:0] q3s = 4;  // square 3 speed

    // update square position once per frame
    always_ff @(posedge clk_pix) begin
        if (animate) begin
            if (q1x >= H_RES - (Q1_SIZE + q1s)) begin  // right edge
                q1dx <= 1;
                q1x <= q1x - q1s;
            end else if (q1x < q1s) begin  // left edge
                q1dx <= 0;
                q1x <= q1x + q1s;
            end else q1x <= (q1dx) ? q1x - q1s : q1x + q1s;

            if (q1y >= V_RES - (Q1_SIZE + q1s)) begin  // bottom edge
                q1dy <= 1;
                q1y <= q1y - q1s;
            end else if (q1y < q1s) begin  // top edge
                q1dy <= 0;
                q1y <= q1y + q1s;
            end else q1y <= (q1dy) ? q1y - q1s : q1y + q1s;

            if (q2x >= H_RES - (Q2_SIZE + q2s)) begin
                q2dx <= 1;
                q2x <= q2x - q2s;
            end else if (q2x < q2s) begin
                q2dx <= 0;
                q2x <= q2x + q2s;
            end else q2x <= (q2dx) ? q2x - q2s : q2x + q2s;

            if (q2y >= V_RES - (Q2_SIZE + q2s)) begin
                q2dy <= 1;
                q2y <= q2y - q2s;
            end else if (q2y < q2s) begin
                q2dy <= 0;
                q2y <= q2y + q2s;
            end else q2y <= (q2dy) ? q2y - q2s : q2y + q2s;

            if (q3x >= H_RES - (Q3_SIZE + q3s)) begin
                q3dx <= 1;
                q3x <= q3x - q3s;
            end else if (q3x < q3s) begin
                q3dx <= 0;
                q3x <= q3x + q3s;
            end else q3x <= (q3dx) ? q3x - q3s : q3x + q3s;

            if (q3y >= V_RES - (Q3_SIZE + q3s)) begin
                q3dy <= 1;
                q3y <= q3y - q3s;
            end else if (q3y < q3s) begin
                q3dy <= 0;
                q3y <= q3y + q3s;
            end else q3y <= (q3dy) ? q3y - q3s : q3y + q3s;
        end
    end

    // are any squares at current screen position?
    logic q1_draw, q2_draw, q3_draw;
    always_comb begin
        q1_draw = (sx >= q1x) && (sx < q1x + Q1_SIZE)
              && (sy >= q1y) && (sy < q1y + Q1_SIZE);
        q2_draw = (sx >= q2x) && (sx < q2x + Q2_SIZE)
              && (sy >= q2y) && (sy < q2y + Q2_SIZE);
        q3_draw = (sx >= q3x) && (sx < q3x + Q3_SIZE)
              && (sy >= q3y) && (sy < q3y + Q3_SIZE);
    end

    // colours
    logic [7:0] red, green, blue;
    always_comb begin
        red   = !de ? 8'h0 : (q1_draw ? 8'hFF : 8'h00);
        green = !de ? 8'h0 : (q2_draw ? 8'hFF : 8'h00);
        blue  = !de ? 8'h0 : (q3_draw ? 8'hFF : 8'h00);
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
