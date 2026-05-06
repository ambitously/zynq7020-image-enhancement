module AXI_VIP_Frame_Difference(
    input               clk             , // 100MHz FCLK_CLK0
    input               rst_n           , // 低电平复位

    // 【触摸按键与LED接口】
    input               touch_key       , // 物理管脚 F16
    output reg          led             , // 物理管脚 H15 (1:开启Gamma 0.5增强)
    output wire         control_flag    , 

    // AXI_ST Slave 0 (摄像头)
    input [23:0]        s0_axis_tdata   ,
    input               s0_axis_tvalid  ,
    output              s0_axis_tready  ,
    input               s0_axis_tuser   ,
    input               s0_axis_tlast   ,
    
    // AXI_ST Slave 1 (VDMA)
    input [23:0]        s1_axis_tdata   ,
    input               s1_axis_tvalid  ,
    output              s1_axis_tready  ,
    input               s1_axis_tuser   ,
    input               s1_axis_tlast   ,
    
    // AXI_ST Master (输出)
    output reg [23:0]   m_axis_tdata    ,
    output reg          m_axis_tvalid   ,
    input               m_axis_tready   ,
    output reg          m_axis_tuser    ,
    output reg          m_axis_tlast 
    );
    
    //---------------------------------------------------
    // 阈值管理 (关键修改)
    //---------------------------------------------------
    // 普通模式: 75
    // Gamma模式: 100 (因为Gamma把底噪从20放到了70多，必须提高阈值才能压住)
    wire [7:0] diff_threshold;
    assign diff_threshold = (led) ? 8'd100 : 8'd75;

    localparam  [9:0]   IMG_HDISP       = 10'd640;  
    localparam  [9:0]   IMG_VDISP       = 10'd480;  

    //*****************************************************
    //** 按键控制逻辑 + 冷却倒计时 (关键修改)
    //*****************************************************
    reg     touch_key_d0, touch_key_d1;
    wire    touch_en;
    assign  touch_en = (~touch_key_d1) & touch_key_d0;

    // 冷却计数器：切换模式时，VDMA里的背景和当前帧亮度不一致，会导致全屏误判。
    // 所以我们需要"闭眼"大约30帧，等背景更新好。
    reg [5:0] cool_down_cnt; 
    reg       led_last;
    wire      allow_detect; // 是否允许检测

    always @ (posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            touch_key_d0 <= 1'b0; touch_key_d1 <= 1'b0;
        end
        else begin
            touch_key_d0 <= touch_key; touch_key_d1 <= touch_key_d0;
        end 
    end

    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led <= 1'b0;
            cool_down_cnt <= 0;
            led_last <= 0;
        end
        else begin 
            // 1. LED 翻转逻辑
            if (touch_en) led <= ~led;
            
            // 2. 冷却逻辑检测
            led_last <= led;
            if (led != led_last) begin
                // 一旦检测到切换，重置冷却时间 (30帧)
                // 30帧 * (640*480 clocks) 足够VDMA刷新背景
                cool_down_cnt <= 6'd30; 
            end
            else if (s0_axis_tuser && s0_axis_tvalid && s0_axis_tready && (cool_down_cnt > 0)) begin
                // 每过一帧(遇到帧头tuser)，计数器减1
                cool_down_cnt <= cool_down_cnt - 1'b1;
            end
        end
    end
    
    assign control_flag = led;
    // 只有倒计时结束(==0)才允许画框
    assign allow_detect = (cool_down_cnt == 0);

    //*****************************************************
    //** 图像增强模块实例化 (Gamma 0.5)
    //*****************************************************
    wire [23:0] s0_data_enhanced; 
    wire [23:0] s0_final_data;    

    // 实例化 Gamma 0.5 LUT
    Gamma_LUT_0_5_Real u_gamma_lut (
        .data_in    (s0_axis_tdata),
        .data_out   (s0_data_enhanced)
    );

    // LED亮起时使用增强数据，否则直通
    assign s0_final_data = (led) ? s0_data_enhanced : s0_axis_tdata;

    //*****************************************************
    // 原有逻辑保持不变 (输入源已替换为 s0_final_data)
    //*****************************************************

    // VDMA 缓存 FIFO
    reg   [23:0]    fifo_data;
    reg             fifo_wr, fifo_wr_en; 
    wire            fifo_full;
    reg             fifo_rd, fifo_rd_en;
    wire [23:0]     fifo_q;
    reg             fifo_valid;
    wire            fifo_empty;

    assign s1_axis_tready = ~fifo_full;

    always @ (posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            fifo_wr_en <= 1'b0; fifo_wr <= 1'b0; fifo_data <= 24'd0;
        end
        else begin
            if(s1_axis_tvalid & s1_axis_tready & s1_axis_tuser) fifo_wr_en <= 1'b1;
            if(s1_axis_tvalid & s1_axis_tready) begin
                fifo_wr <= 1'b1; fifo_data <= s1_axis_tdata; 
            end  
            else begin
                fifo_wr <= 1'b0; fifo_data <= fifo_data;
            end
        end
    end

    video_fifo u_video_fifo (
      .clk(clk), .srst(~rst_n), .din(fifo_data), .wr_en(fifo_wr & fifo_wr_en),  
      .full(), .rd_en(fifo_rd & fifo_rd_en), .dout(fifo_q), .empty(fifo_empty),
      .almost_full(fifo_full), .almost_empty() 
    );

    always @ (posedge clk or negedge rst_n) begin
        if(!rst_n) begin fifo_rd_en <= 1'b0; fifo_rd <= 1'b0; end
        else begin
            if(s0_axis_tvalid & s0_axis_tready & s0_axis_tuser & fifo_full) fifo_rd_en <= 1'b1;
            if(s0_axis_tvalid & s0_axis_tready) fifo_rd <= 1'b1;
            else fifo_rd <= 1'b0;
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if(!rst_n) fifo_valid <= 1'b0;
        else fifo_valid <= fifo_rd;     
    end

    // 同步延迟
    reg [23:0]  s0_axis_tdata_dly1, s0_axis_tdata_dly2;
    always @ (posedge clk or negedge rst_n) begin
        if(!rst_n) begin s0_axis_tdata_dly1 <= 0; s0_axis_tdata_dly2 <= 0; end
        else begin
            s0_axis_tdata_dly1 <= s0_final_data; // 存入增强后的数据
            s0_axis_tdata_dly2 <= s0_axis_tdata_dly1;
        end
    end 

    // 转灰度
    wire [7:0]  s0_img_y, s1_img_y;
    RGB888_YCbCr444 S0_RGB888_YCbCr444 (
        .clk(clk), .rst_n(rst_n),                 
        .in_img_red(s0_axis_tdata_dly2[23:16]),       
        .in_img_green(s0_axis_tdata_dly2[15: 8]),       
        .in_img_blue(s0_axis_tdata_dly2[ 7: 0]),       
        .out_img_Y(s0_img_y), .out_img_Cb(), .out_img_Cr()                  
    );

    RGB888_YCbCr444 S1_RGB888_YCbCr444 (
        .clk(clk), .rst_n(rst_n),                 
        .in_img_red(fifo_q[23:16]),       
        .in_img_green(fifo_q[15: 8]),       
        .in_img_blue(fifo_q[ 7: 0]),       
        .out_img_Y(s1_img_y), .out_img_Cb(), .out_img_Cr()                  
    );

    // 帧差运算 (使用动态阈值 diff_threshold)
    reg frame_difference_flag;  
    always @ (posedge clk or negedge rst_n) begin
        if(!rst_n) frame_difference_flag <= 1'b0;
        else begin
            if(s0_img_y > s1_img_y) begin
                // 使用 diff_threshold 替代原来的 fixed value
                if(s0_img_y - s1_img_y > diff_threshold) frame_difference_flag <= 1'b1; 
                else frame_difference_flag <= 1'b0;  
            end
            else begin
                if(s1_img_y - s0_img_y > diff_threshold) frame_difference_flag <= 1'b1; 
                else frame_difference_flag <= 1'b0;
            end
        end
    end

    // 延迟控制信号
    wire s0_axis_tuser_dly, s0_axis_tlast_dly, s0_axis_tvalid_dly;
    reg  [5:0] s0_axis_tuser_reg, s0_axis_tlast_reg, s0_axis_tvalid_reg;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin s0_axis_tuser_reg<=0; s0_axis_tlast_reg<=0; s0_axis_tvalid_reg<=0; end
        else begin
            s0_axis_tuser_reg  <= {s0_axis_tuser_reg[4:0], s0_axis_tvalid & s0_axis_tready & s0_axis_tuser}; 
            s0_axis_tlast_reg  <= {s0_axis_tlast_reg[4:0], s0_axis_tvalid & s0_axis_tready & s0_axis_tlast}; 
            s0_axis_tvalid_reg <= {s0_axis_tvalid_reg[4:0],s0_axis_tvalid & s0_axis_tready }; 
        end
    end
    assign s0_axis_tuser_dly = s0_axis_tuser_reg[5];
    assign s0_axis_tlast_dly = s0_axis_tlast_reg[5];
    assign s0_axis_tvalid_dly = s0_axis_tvalid_reg[5];

    // 坐标计算
    reg [9:0] x_cnt, y_cnt;    
    always @ (posedge clk or negedge rst_n) begin
        if(!rst_n) begin x_cnt <= 0; y_cnt <= 0; end
        else if(s0_axis_tvalid_dly) begin
            if(s0_axis_tlast_dly) begin x_cnt <= 0; y_cnt <= y_cnt + 1; end
            else if(s0_axis_tuser_dly) begin x_cnt <= 0; y_cnt <= 0; end
            else x_cnt <= x_cnt + 1;        
        end  
    end

    // 矩形框 (增加 allow_detect 判断)
    reg [9:0] up_reg, down_reg, left_reg, right_reg;
    reg flag_reg;
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin up_reg<=IMG_VDISP; down_reg<=0; left_reg<=IMG_HDISP; right_reg<=0; flag_reg<=0; end
        else if(s0_axis_tuser_dly)begin up_reg<=IMG_VDISP; down_reg<=0; left_reg<=IMG_HDISP; right_reg<=0; flag_reg<=0; end
        // 关键：只有冷却时间结束 (allow_detect=1) 才更新坐标
        else if(s0_axis_tvalid_dly & frame_difference_flag & allow_detect) begin
            flag_reg  <= 1'b1;
            if(x_cnt < left_reg) left_reg <= x_cnt;      
            if(x_cnt > right_reg) right_reg <= x_cnt;     
            if(y_cnt < up_reg) up_reg <= y_cnt;        
            if(y_cnt > down_reg) down_reg <= y_cnt;   
        end
    end

    reg [9:0] rectangular_up, rectangular_down, rectangular_left, rectangular_right;
    reg rectangular_flag;
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin rectangular_up<=0; rectangular_down<=0; rectangular_left<=0; rectangular_right<=0; rectangular_flag<=0; end
        else if((x_cnt == IMG_HDISP - 1) && (y_cnt == IMG_VDISP - 1))begin
            rectangular_up <= up_reg; rectangular_down <= down_reg; rectangular_left <= left_reg; rectangular_right <= right_reg; rectangular_flag <= flag_reg;
        end
    end

    // 绘制输出
    reg [9:0] s0_x_cnt, s0_y_cnt;    
    always @ (posedge clk or negedge rst_n) begin
        if(!rst_n) begin s0_x_cnt <= 0; s0_y_cnt <= 0; end
        else if(s0_axis_tvalid) begin
            if(s0_axis_tlast) begin s0_x_cnt <= 0; s0_y_cnt <= y_cnt + 1; end
            else if(s0_axis_tuser) begin s0_x_cnt <= 0; s0_y_cnt <= 0; end
            else s0_x_cnt <= s0_x_cnt + 1;        
        end  
    end

    reg boarder_flag;   
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) boarder_flag <= 0;             
        else if(rectangular_flag)begin   
            if((s0_x_cnt > rectangular_left) && (s0_x_cnt < rectangular_right) && ((s0_y_cnt == rectangular_up) || (s0_y_cnt == rectangular_down))) 
                boarder_flag <= 1;   
            else if((s0_y_cnt > rectangular_up) && (s0_y_cnt < rectangular_down) && ((s0_x_cnt == rectangular_left) || (s0_x_cnt == rectangular_right))) 
                boarder_flag <= 1;
            else boarder_flag <= 0;
        end else boarder_flag <= 0;
    end

    // 输出赋值 (增加 allow_detect 判断)
    assign s0_axis_tready = m_axis_tready;
        
    always @ (posedge clk or negedge rst_n ) begin
        if(!rst_n) begin m_axis_tvalid<=0; m_axis_tuser<=0; m_axis_tlast<=0; m_axis_tdata<=0; end
        else begin
             m_axis_tvalid  <= s0_axis_tvalid;
             m_axis_tuser   <= s0_axis_tuser ;
             m_axis_tlast   <= s0_axis_tlast ;
             // 关键：只有冷却结束且检测到边框才画红框
             m_axis_tdata   <= (boarder_flag && allow_detect) ? 24'hff_00_00 : s0_final_data;
        end
    end

endmodule


//****************************************************************************
// Gamma 0.5 (开根号) LUT 模块
//****************************************************************************
module Gamma_LUT_0_5_Real(
    input  wire [23:0] data_in,
    output reg  [23:0] data_out
);

    wire [7:0] r = data_in[23:16];
    wire [7:0] g = data_in[15:8];
    wire [7:0] b = data_in[7:0];

    function [7:0] get_gamma_0_5;
        input [7:0] val;
        begin
            case(val)
                // --- 去噪区 (Coring) ---
                8'd0:   get_gamma_0_5 = 8'd0;
                8'd1:   get_gamma_0_5 = 8'd0;
                8'd2:   get_gamma_0_5 = 8'd0;
                8'd3:   get_gamma_0_5 = 8'd0;
                8'd4:   get_gamma_0_5 = 8'd0;
                8'd5:   get_gamma_0_5 = 8'd0;
                8'd6:   get_gamma_0_5 = 8'd0;
                8'd7:   get_gamma_0_5 = 8'd0;
                8'd8:   get_gamma_0_5 = 8'd0;
                8'd9:   get_gamma_0_5 = 8'd0;
                8'd10:  get_gamma_0_5 = 8'd0;
                8'd11:  get_gamma_0_5 = 8'd0;
                8'd12:  get_gamma_0_5 = 8'd0;
                8'd13:  get_gamma_0_5 = 8'd0;
                8'd14:  get_gamma_0_5 = 8'd0;
                8'd15:  get_gamma_0_5 = 8'd0;
                
                // --- Gamma 0.5 增强区 ---
                8'd16:  get_gamma_0_5 = 8'd64; 
                8'd17:  get_gamma_0_5 = 8'd66;
                8'd18:  get_gamma_0_5 = 8'd68;
                8'd19:  get_gamma_0_5 = 8'd69;
                8'd20:  get_gamma_0_5 = 8'd71;
                8'd21:  get_gamma_0_5 = 8'd73;
                8'd22:  get_gamma_0_5 = 8'd75;
                8'd23:  get_gamma_0_5 = 8'd76;
                8'd24:  get_gamma_0_5 = 8'd78;
                8'd25:  get_gamma_0_5 = 8'd80;
                8'd26:  get_gamma_0_5 = 8'd81;
                8'd27:  get_gamma_0_5 = 8'd83;
                8'd28:  get_gamma_0_5 = 8'd84;
                8'd29:  get_gamma_0_5 = 8'd86;
                8'd30:  get_gamma_0_5 = 8'd87;
                8'd31:  get_gamma_0_5 = 8'd89;
                8'd32:  get_gamma_0_5 = 8'd90;
                8'd33:  get_gamma_0_5 = 8'd92;
                8'd34:  get_gamma_0_5 = 8'd93;
                8'd35:  get_gamma_0_5 = 8'd94;
                8'd36:  get_gamma_0_5 = 8'd96;
                8'd37:  get_gamma_0_5 = 8'd97;
                8'd38:  get_gamma_0_5 = 8'd98;
                8'd39:  get_gamma_0_5 = 8'd99;
                8'd40:  get_gamma_0_5 = 8'd101;
                8'd41:  get_gamma_0_5 = 8'd102;
                8'd42:  get_gamma_0_5 = 8'd103;
                8'd43:  get_gamma_0_5 = 8'd104;
                8'd44:  get_gamma_0_5 = 8'd105;
                8'd45:  get_gamma_0_5 = 8'd107;
                8'd46:  get_gamma_0_5 = 8'd108;
                8'd47:  get_gamma_0_5 = 8'd109;
                8'd48:  get_gamma_0_5 = 8'd110;
                8'd49:  get_gamma_0_5 = 8'd111;
                8'd50:  get_gamma_0_5 = 8'd112;
                8'd51:  get_gamma_0_5 = 8'd114;
                8'd52:  get_gamma_0_5 = 8'd115;
                8'd53:  get_gamma_0_5 = 8'd116;
                8'd54:  get_gamma_0_5 = 8'd117;
                8'd55:  get_gamma_0_5 = 8'd118;
                8'd56:  get_gamma_0_5 = 8'd119;
                8'd57:  get_gamma_0_5 = 8'd120;
                8'd58:  get_gamma_0_5 = 8'd121;
                8'd59:  get_gamma_0_5 = 8'd122;
                8'd60:  get_gamma_0_5 = 8'd123;
                8'd61:  get_gamma_0_5 = 8'd124;
                8'd62:  get_gamma_0_5 = 8'd125;
                8'd63:  get_gamma_0_5 = 8'd126;
                8'd64:  get_gamma_0_5 = 8'd127;
                8'd65:  get_gamma_0_5 = 8'd128;
                8'd66:  get_gamma_0_5 = 8'd129;
                8'd67:  get_gamma_0_5 = 8'd130;
                8'd68:  get_gamma_0_5 = 8'd131;
                8'd69:  get_gamma_0_5 = 8'd132;
                8'd70:  get_gamma_0_5 = 8'd133;
                8'd71:  get_gamma_0_5 = 8'd134;
                8'd72:  get_gamma_0_5 = 8'd135;
                8'd73:  get_gamma_0_5 = 8'd136;
                8'd74:  get_gamma_0_5 = 8'd137;
                8'd75:  get_gamma_0_5 = 8'd138;
                8'd76:  get_gamma_0_5 = 8'd139;
                8'd77:  get_gamma_0_5 = 8'd139;
                8'd78:  get_gamma_0_5 = 8'd140;
                8'd79:  get_gamma_0_5 = 8'd141;
                8'd80:  get_gamma_0_5 = 8'd142;
                8'd81:  get_gamma_0_5 = 8'd143;
                8'd82:  get_gamma_0_5 = 8'd144;
                8'd83:  get_gamma_0_5 = 8'd145;
                8'd84:  get_gamma_0_5 = 8'd146;
                8'd85:  get_gamma_0_5 = 8'd146;
                8'd86:  get_gamma_0_5 = 8'd147;
                8'd87:  get_gamma_0_5 = 8'd148;
                8'd88:  get_gamma_0_5 = 8'd149;
                8'd89:  get_gamma_0_5 = 8'd150;
                8'd90:  get_gamma_0_5 = 8'd151;
                8'd91:  get_gamma_0_5 = 8'd151;
                8'd92:  get_gamma_0_5 = 8'd152;
                8'd93:  get_gamma_0_5 = 8'd153;
                8'd94:  get_gamma_0_5 = 8'd154;
                8'd95:  get_gamma_0_5 = 8'd155;
                8'd96:  get_gamma_0_5 = 8'd156;
                8'd97:  get_gamma_0_5 = 8'd156;
                8'd98:  get_gamma_0_5 = 8'd157;
                8'd99:  get_gamma_0_5 = 8'd158;
                8'd100: get_gamma_0_5 = 8'd159;
                8'd101: get_gamma_0_5 = 8'd160;
                8'd102: get_gamma_0_5 = 8'd160;
                8'd103: get_gamma_0_5 = 8'd161;
                8'd104: get_gamma_0_5 = 8'd162;
                8'd105: get_gamma_0_5 = 8'd163;
                8'd106: get_gamma_0_5 = 8'd164;
                8'd107: get_gamma_0_5 = 8'd164;
                8'd108: get_gamma_0_5 = 8'd165;
                8'd109: get_gamma_0_5 = 8'd166;
                8'd110: get_gamma_0_5 = 8'd167;
                8'd111: get_gamma_0_5 = 8'd167;
                8'd112: get_gamma_0_5 = 8'd168;
                8'd113: get_gamma_0_5 = 8'd169;
                8'd114: get_gamma_0_5 = 8'd170;
                8'd115: get_gamma_0_5 = 8'd170;
                8'd116: get_gamma_0_5 = 8'd171;
                8'd117: get_gamma_0_5 = 8'd172;
                8'd118: get_gamma_0_5 = 8'd173;
                8'd119: get_gamma_0_5 = 8'd173;
                8'd120: get_gamma_0_5 = 8'd174;
                8'd121: get_gamma_0_5 = 8'd175;
                8'd122: get_gamma_0_5 = 8'd176;
                8'd123: get_gamma_0_5 = 8'd176;
                8'd124: get_gamma_0_5 = 8'd177;
                8'd125: get_gamma_0_5 = 8'd178;
                8'd126: get_gamma_0_5 = 8'd178;
                8'd127: get_gamma_0_5 = 8'd179;
                8'd128: get_gamma_0_5 = 8'd180;
                8'd129: get_gamma_0_5 = 8'd180;
                8'd130: get_gamma_0_5 = 8'd181;
                8'd131: get_gamma_0_5 = 8'd182;
                8'd132: get_gamma_0_5 = 8'd182;
                8'd133: get_gamma_0_5 = 8'd183;
                8'd134: get_gamma_0_5 = 8'd184;
                8'd135: get_gamma_0_5 = 8'd185;
                8'd136: get_gamma_0_5 = 8'd185;
                8'd137: get_gamma_0_5 = 8'd186;
                8'd138: get_gamma_0_5 = 8'd187;
                8'd139: get_gamma_0_5 = 8'd187;
                8'd140: get_gamma_0_5 = 8'd188;
                8'd141: get_gamma_0_5 = 8'd189;
                8'd142: get_gamma_0_5 = 8'd189;
                8'd143: get_gamma_0_5 = 8'd190;
                8'd144: get_gamma_0_5 = 8'd191;
                8'd145: get_gamma_0_5 = 8'd191;
                8'd146: get_gamma_0_5 = 8'd192;
                8'd147: get_gamma_0_5 = 8'd193;
                8'd148: get_gamma_0_5 = 8'd193;
                8'd149: get_gamma_0_5 = 8'd194;
                8'd150: get_gamma_0_5 = 8'd195;
                8'd151: get_gamma_0_5 = 8'd195;
                8'd152: get_gamma_0_5 = 8'd196;
                8'd153: get_gamma_0_5 = 8'd196;
                8'd154: get_gamma_0_5 = 8'd197;
                8'd155: get_gamma_0_5 = 8'd198;
                8'd156: get_gamma_0_5 = 8'd198;
                8'd157: get_gamma_0_5 = 8'd199;
                8'd158: get_gamma_0_5 = 8'd200;
                8'd159: get_gamma_0_5 = 8'd200;
                8'd160: get_gamma_0_5 = 8'd201;
                8'd161: get_gamma_0_5 = 8'd201;
                8'd162: get_gamma_0_5 = 8'd202;
                8'd163: get_gamma_0_5 = 8'd203;
                8'd164: get_gamma_0_5 = 8'd203;
                8'd165: get_gamma_0_5 = 8'd204;
                8'd166: get_gamma_0_5 = 8'd204;
                8'd167: get_gamma_0_5 = 8'd205;
                8'd168: get_gamma_0_5 = 8'd206;
                8'd169: get_gamma_0_5 = 8'd206;
                8'd170: get_gamma_0_5 = 8'd207;
                8'd171: get_gamma_0_5 = 8'd207;
                8'd172: get_gamma_0_5 = 8'd208;
                8'd173: get_gamma_0_5 = 8'd208;
                8'd174: get_gamma_0_5 = 8'd209;
                8'd175: get_gamma_0_5 = 8'd209;
                8'd176: get_gamma_0_5 = 8'd210;
                8'd177: get_gamma_0_5 = 8'd211;
                8'd178: get_gamma_0_5 = 8'd211;
                8'd179: get_gamma_0_5 = 8'd212;
                8'd180: get_gamma_0_5 = 8'd212;
                8'd181: get_gamma_0_5 = 8'd213;
                8'd182: get_gamma_0_5 = 8'd213;
                8'd183: get_gamma_0_5 = 8'd214;
                8'd184: get_gamma_0_5 = 8'd214;
                8'd185: get_gamma_0_5 = 8'd215;
                8'd186: get_gamma_0_5 = 8'd216;
                8'd187: get_gamma_0_5 = 8'd216;
                8'd188: get_gamma_0_5 = 8'd217;
                8'd189: get_gamma_0_5 = 8'd217;
                8'd190: get_gamma_0_5 = 8'd218;
                8'd191: get_gamma_0_5 = 8'd218;
                8'd192: get_gamma_0_5 = 8'd219;
                8'd193: get_gamma_0_5 = 8'd219;
                8'd194: get_gamma_0_5 = 8'd220;
                8'd195: get_gamma_0_5 = 8'd220;
                8'd196: get_gamma_0_5 = 8'd221;
                8'd197: get_gamma_0_5 = 8'd221;
                8'd198: get_gamma_0_5 = 8'd222;
                8'd199: get_gamma_0_5 = 8'd222;
                8'd200: get_gamma_0_5 = 8'd223;
                8'd201: get_gamma_0_5 = 8'd223;
                8'd202: get_gamma_0_5 = 8'd224;
                8'd203: get_gamma_0_5 = 8'd224;
                8'd204: get_gamma_0_5 = 8'd225;
                8'd205: get_gamma_0_5 = 8'd225;
                8'd206: get_gamma_0_5 = 8'd226;
                8'd207: get_gamma_0_5 = 8'd226;
                8'd208: get_gamma_0_5 = 8'd227;
                8'd209: get_gamma_0_5 = 8'd227;
                8'd210: get_gamma_0_5 = 8'd228;
                8'd211: get_gamma_0_5 = 8'd228;
                8'd212: get_gamma_0_5 = 8'd229;
                8'd213: get_gamma_0_5 = 8'd229;
                8'd214: get_gamma_0_5 = 8'd230;
                8'd215: get_gamma_0_5 = 8'd230;
                8'd216: get_gamma_0_5 = 8'd231;
                8'd217: get_gamma_0_5 = 8'd231;
                8'd218: get_gamma_0_5 = 8'd232;
                8'd219: get_gamma_0_5 = 8'd232;
                8'd220: get_gamma_0_5 = 8'd233;
                8'd221: get_gamma_0_5 = 8'd233;
                8'd222: get_gamma_0_5 = 8'd234;
                8'd223: get_gamma_0_5 = 8'd234;
                8'd224: get_gamma_0_5 = 8'd235;
                8'd225: get_gamma_0_5 = 8'd235;
                8'd226: get_gamma_0_5 = 8'd236;
                8'd227: get_gamma_0_5 = 8'd236;
                8'd228: get_gamma_0_5 = 8'd237;
                8'd229: get_gamma_0_5 = 8'd237;
                8'd230: get_gamma_0_5 = 8'd238;
                8'd231: get_gamma_0_5 = 8'd238;
                8'd232: get_gamma_0_5 = 8'd239;
                8'd233: get_gamma_0_5 = 8'd239;
                8'd234: get_gamma_0_5 = 8'd240;
                8'd235: get_gamma_0_5 = 8'd240;
                8'd236: get_gamma_0_5 = 8'd241;
                8'd237: get_gamma_0_5 = 8'd241;
                8'd238: get_gamma_0_5 = 8'd242;
                8'd239: get_gamma_0_5 = 8'd242;
                8'd240: get_gamma_0_5 = 8'd242;
                8'd241: get_gamma_0_5 = 8'd243;
                8'd242: get_gamma_0_5 = 8'd243;
                8'd243: get_gamma_0_5 = 8'd244;
                8'd244: get_gamma_0_5 = 8'd244;
                8'd245: get_gamma_0_5 = 8'd245;
                8'd246: get_gamma_0_5 = 8'd245;
                8'd247: get_gamma_0_5 = 8'd246;
                8'd248: get_gamma_0_5 = 8'd246;
                8'd249: get_gamma_0_5 = 8'd247;
                8'd250: get_gamma_0_5 = 8'd247;
                8'd251: get_gamma_0_5 = 8'd248;
                8'd252: get_gamma_0_5 = 8'd248;
                8'd253: get_gamma_0_5 = 8'd249;
                8'd254: get_gamma_0_5 = 8'd249;
                8'd255: get_gamma_0_5 = 8'd255;
            endcase
        end
    endfunction

    always @(*) begin
        data_out[23:16] = get_gamma_0_5(r);
        data_out[15:8]  = get_gamma_0_5(g);
        data_out[7:0]   = get_gamma_0_5(b);
    end

endmodule