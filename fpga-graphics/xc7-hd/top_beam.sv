// Project F: FPGA Graphics - Top Beam (Nexys Video)
// (C)2020 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io

`default_nettype none
`timescale 1ns / 1ps

module top_beam (
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

    // square 'Q' - origin at top-left
    localparam Q_SIZE = 96;    // square size in pixels
    localparam Q_SPEED = 12;   // pixels moved per frame
    logic [CORDW-1:0] qx, qy;  // square position

    // update square position once per frame
    always_ff @(posedge clk_pix) begin
        if (animate) begin
            if (qx >= H_RES_FULL - Q_SIZE) begin
                qx <= 0;
                qy <= (qy >= V_RES_FULL - Q_SIZE) ? 0 : qy + Q_SIZE;
            end else begin
                qx <= qx + Q_SPEED;
            end
        end
    end

    // is square at current screen position?
    logic q_draw;
    always_comb begin
        q_draw = (sx >= qx) && (sx < qx + Q_SIZE)
              && (sy >= qy) && (sy < qy + Q_SIZE);
    end

    // colours
    logic [7:0] red, green, blue;
    always_comb begin
        red   = !de ? 8'h0 : (q_draw ? 8'hFF : 8'h00);
        green = !de ? 8'h0 : (q_draw ? 8'h88 : 8'h88);
        blue  = !de ? 8'h0 : (q_draw ? 8'h00 : 8'hFF);
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
