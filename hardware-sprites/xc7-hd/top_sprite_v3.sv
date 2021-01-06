// Project F: Hardware Sprites - Top Sprite v3 (Nexys Video)
// (C)2021 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io

`default_nettype none
`timescale 1ns / 1ps

module top_sprite_v3 (
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

    // sprite
    localparam SPR_WIDTH   = 8;   // width in pixels
    localparam SPR_HEIGHT  = 8;   // number of lines
    localparam SPR_SCALE_X = 30;  // width scale-factor
    localparam SPR_SCALE_Y = 30;  // height scale-factor
    localparam SPR_FILE = "letter_f.mem";
    logic spr_start;
    logic spr_pix;

    // draw sprite at position
    localparam DRAW_X = 840;
    localparam DRAW_Y = 420;

    // start sprite in blanking of line before first line drawn
    logic [CORDW-1:0] draw_y_cor;  // corrected for wrapping
    always_comb begin
        draw_y_cor = (DRAW_Y == 0) ? V_RES_FULL - 1 : DRAW_Y - 1;
        spr_start = (sy == draw_y_cor && sx == H_RES);
    end

    sprite_v3 #(
        .WIDTH(SPR_WIDTH),
        .HEIGHT(SPR_HEIGHT),
        .SPR_FILE(SPR_FILE),
        .SCALE_X(SPR_SCALE_X),
        .SCALE_Y(SPR_SCALE_Y),
        .CORDW(CORDW),
        .H_RES_FULL(H_RES_FULL)
    ) spr_instance (
        .clk(clk_pix),
        .rst(!clk_pix_locked),
        .start(spr_start),
        .sx,
        .sprx(DRAW_X),
        .pix(spr_pix)
    );

    // colours
    logic [7:0] red, green, blue;
    always_comb begin
        red   = (de && spr_pix) ? 8'hFF: 8'h00;
        green = (de && spr_pix) ? 8'hCC: 8'h00;
        blue  = (de && spr_pix) ? 8'h00: 8'h00;
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
