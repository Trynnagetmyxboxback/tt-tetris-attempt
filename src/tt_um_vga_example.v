/*
 * Tiny Tapeout VGA design: a diagonal colour ramp that scrolls one step per
 * frame, a white playfield, and a falling block that locks into a 10 x 20 cell
 * grid inside the well.
 *
 *   ui_in[0]  move the block left
 *   ui_in[1]  move the block right
 *   ui_in[2]  drop the block faster
 *   ui_in[7]  invert the colours
 *
 * uo_out is the TinyVGA PMOD: { hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1] }.
 *
 * hvsync_generator lives in its own file (src/hvsync_generator.v); this flow
 * requires one module per file with the filename matching the module name.
 *
 * TIMING NOTE.  The cell index of the pixel being drawn used to be derived
 * combinationally from hpos and then used to read the 200:1 grid, so the divide
 * and the read sat in series on the path from hpos to uo_out.  The index is now
 * computed one pixel ahead and registered (gcol_q / grow_q).  hpos advances by
 * exactly one per clock, so the registered value is still the index of the
 * *current* pixel: the picture is bit-identical, but the divide and the grid
 * read now occupy separate clock periods.
 */

`default_nettype none

module tt_um_trynnagetmyxboxback_tetris_attempt (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: input path
    output wire [7:0] uio_out,  // IOs: output path
    output wire [7:0] uio_oe,   // IOs: enable path (active high: 0 = input, 1 = output)
    input  wire       ena,      // Always 1 when the design is powered
    input  wire       clk,      // Pixel clock
    input  wire       rst_n     // Reset, active low
);
    wire move_left     = ui_in[0];
    wire move_right    = ui_in[1];
    wire move_downfast = ui_in[2];

    wire       hsync;
    wire       vsync;
    wire       video_active;
    wire [9:0] pix_x;
    wire [9:0] pix_y;

    hvsync_generator hvsync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(video_active),
        .hpos(pix_x),
        .vpos(pix_y)
    );

    // counts frames. one step each time vsync starts.
    reg       vsync_q;
    reg [7:0] frame;
    wire frame_tick = vsync_q & ~vsync;
    always @(posedge clk) begin
        vsync_q <= vsync;
        if (~rst_n)                 frame <= 8'd0;
        else if (vsync_q & ~vsync)  frame <= frame + 8'd1;
    end

    // A diagonal ramp that moves with the frame count, cut into four levels per channel.
    wire [7:0] ramp = pix_x[7:0] + pix_y[7:0] + frame;
    wire [5:0] rgb  = {ramp[7:6], ramp[5:4], ~ramp[7:6]} ^ {6{ui_in[7]}};

    wire [1:0] bg_r = video_active ? rgb[5:4] : 2'b00;
    wire [1:0] bg_g = video_active ? rgb[3:2] : 2'b00;
    wire [1:0] bg_b = video_active ? rgb[1:0] : 2'b00;

// ----------------------------------------------------------------- geometry

    localparam [9:0] BOX_W = 10'd10;
    localparam [9:0] BOX_H = 10'd10;

    // white playfield.
    wire in_box = (pix_x >= 10'd20) && (pix_x < 10'd620) &&
                  (pix_y >= 10'd20) && (pix_y < 10'd460);

    // black well: the outer edge, and the inner area the blocks live in.
    wire in_box3      = (pix_x >= 10'd266) && (pix_x < 10'd374) &&
                        (pix_y >= 10'd36)  && (pix_y < 10'd444);
    wire in_box3inner = (pix_x >= 10'd270) && (pix_x < 10'd370) &&
                        (pix_y >= 10'd40)  && (pix_y < 10'd440);

    localparam [9:0] WELL_X0   = 10'd270;                // left edge of the well
    localparam [9:0] WELL_X1   = WELL_X0 + 10'd100;      // 370, right edge
    localparam [9:0] WELL_Y0   = 10'd40;                 // top of the well
    localparam [9:0] FIELD_Y0  = WELL_Y0 + 10'd200;      // 240, top of the 10 x 20 field
    localparam [9:0] FIELD_Y1  = FIELD_Y0 + 10'd200;     // 440, bottom of the field
    localparam [3:0] SPAWN_COL = 4'd5;                   // column a new block appears in

    // Pixels per movement step.
    localparam [9:0] StepX  = 10'd10;
    localparam [9:0] StepY  = 10'd2;
    localparam [9:0] Step2Y = 10'd5;

//falling block state

    reg [9:0] box_x;    //tracking from top left
    reg [9:0] box_y;

    reg left_q;
    reg right_q;
    wire left_press  = move_left  & ~left_q;
    wire right_press = move_right & ~right_q;

    reg [9:0] grid [0:19];      // the playing field
    integer i;

    // block position expressed as a (column, row) cell index.
    wire [9:0] fcol_w      = (box_x - WELL_X0) / 10'd10;
    wire       above_field = (box_y < FIELD_Y0);
    wire [9:0] field_dy    = above_field ? 10'd0 : (box_y - FIELD_Y0);
    wire [9:0] frow_w      = field_dy / 10'd10;

    // The cell index is registered.  box_x and box_y change at most once per
    // frame, so these settle long before the next frame_tick and the picture is
    // unchanged, but the /10 divide and the 200:1 grid read it feeds now occupy
    // separate clock periods instead of sitting in series on one path.
    reg [3:0] fcol;                     // 0..9
    reg [4:0] frow;                     // 0..19
    always @(posedge clk) begin
        if (~rst_n) begin
            fcol <= 4'd0;
            frow <= 5'd0;
        end else begin
            fcol <= fcol_w[3:0];
            frow <= frow_w[4:0];
        end
    end

    wire [4:0] next_row  = (frow == 5'd19) ? frow : (frow + 5'd1);
    wire [3:0] left_col  = (fcol == 4'd0)  ? fcol : (fcol - 4'd1);
    wire [3:0] right_col = (fcol == 4'd9)  ? fcol : (fcol + 4'd1);

    wire can_fall   = (box_y < 10'd430) && (above_field || ~grid[next_row][fcol]);
    wire can_left   = (fcol != 4'd0) && ~grid[frow][left_col];
    wire can_right  = (fcol != 4'd9) && ~grid[frow][right_col];
    wire spawn_free = ~grid[5'd0][SPAWN_COL];
    wire landed     = ~can_fall;

    // the falling block, drawn as a coloured square.
    wire in_box2 = (pix_x >= box_x) && (pix_x < box_x + BOX_W) &&
                   (pix_y >= box_y) && (pix_y < box_y + BOX_H);

// ------------------------------------ on-screen cell lookup (registered)

    // Index of the cell covering the pixel one to the right of the current one.
    // Registering this makes it the index of the current pixel on the next clock
    // edge, so the picture is unchanged and no divide is left in series with the
    // grid read.
    wire [9:0] next_x      = pix_x + 10'd1;
    wire       next_in_col = (next_x >= WELL_X0) && (next_x < WELL_X1);
    wire [9:0] gcol_next   = next_in_col ? ((next_x - WELL_X0) / 10'd10) : 10'd0;

    // the row does not change along a line, so a plain register is exact here.
    wire       in_row   = (pix_y >= FIELD_Y0) && (pix_y < FIELD_Y1);
    wire [9:0] grow_now = in_row ? ((pix_y - FIELD_Y0) / 10'd10) : 10'd0;

    reg [3:0] gcol_q;
    reg [4:0] grow_q;
    always @(posedge clk) begin
        if (~rst_n) begin
            gcol_q <= 4'd0;
            grow_q <= 5'd0;
        end else begin
            gcol_q <= gcol_next[3:0];
            grow_q <= grow_now[4:0];
        end
    end

    wire in_col       = (pix_x >= WELL_X0) && (pix_x < WELL_X1);
    wire in_field     = in_col && in_row;
    wire cell_settled = grid[grow_q][gcol_q];
    wire cell_on      = in_box2 | (in_field && cell_settled);

// ------------------------------------------------------------ pixel colours

    // black well border, then a settled cell, then the falling block, then the
    // white playfield, then the scrolling background.
    wire [1:0] R = (in_box3 && ~in_box3inner) ? 2'b00 : cell_on ? 2'b11 : in_box ? 2'b11 : bg_r;
    wire [1:0] G = (in_box3 && ~in_box3inner) ? 2'b00 : cell_on ? 2'b00 : in_box ? 2'b11 : bg_g;
    wire [1:0] B = (in_box3 && ~in_box3inner) ? 2'b00 : cell_on ? 2'b00 : in_box ? 2'b11 : bg_b;

    assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

//always block for vertical movement

    always @(posedge clk) begin
        if (!rst_n) begin
            box_y <= WELL_Y0;
            for (i = 0; i < 20; i = i + 1) grid[i] = 10'd0;
        end else if (frame_tick) begin
            if (any_full) begin
                for (i = 19; i >= 0; i = i - 1)
                    if (i >= 1 && i <= {27'd0, clr_row})
                        grid[i] = grid[i-1];
                grid[0] = 10'd0;                       // new top row is empty
            end else if (can_fall) begin
                box_y <= box_y + (move_downfast ? Step2Y : StepY);
            end else if (spawn_free) begin
                grid[frow][fcol] = 1'b1;               // lock this block
                box_y <= WELL_Y0;                      // respawn at the top
            end else begin
                for (i = 0; i < 20; i = i + 1) grid[i] = 10'd0;
                box_y <= WELL_Y0;
            end
        end
    end

//always block for horizontal movement

    always @(posedge clk) begin
        if (!rst_n) begin
            box_x <= 10'd320;
        end else if (frame_tick) begin
            left_q  <= move_left;
            right_q <= move_right;
            if (landed)                              box_x <= 10'd320;
            if (left_press && box_x > 10'd270)       box_x <= box_x - StepX;
            else if (right_press && box_x < 10'd360) box_x <= box_x + StepX;
        end
    end

//row detection

    wire [19:0] full;
    genvar r;
    generate for (r = 0; r < 20; r = r + 1)
        assign full[r] = &grid[r];
    endgenerate

    reg [4:0] clr_row;
    reg       any_full;
    integer   rr;
    always @(*) begin
        clr_row  = 5'd0;
        any_full = 1'b0;
        for (rr = 0; rr <= 19; rr = rr + 1)
            if (full[rr]) begin clr_row = rr[4:0]; any_full = 1'b1; end
    end

    //ai did this
    wire _unused_ok  = &{ena, ui_in, uio_in, can_left, can_right, 1'b0};
    wire _unused2_ok = &{ramp[3:0], fcol_w[9:4], frow_w[9:5],
                         gcol_next[9:4], grow_now[9:5], 1'b0};

endmodule
