
///////////////////////////////// RTL FOR SPI SUBSYSTEM NOT PURE NATIVE SPI IP  ///////////////////////////////////////////

`timescale 1ns / 1ps
////////////////(addr > 31) when error cs will be stay high -> memory will stay in
/////////////// in idle stay

module spi_intf(
    input wr,clk,rst,ready,op_done,
    input [7:0] addr, din,
    output [7:0] dout,
    output reg cs, mosi,
    input miso,
    output reg done, err
    );
////////////////////////////////
reg [16:0] din_reg;  //// <- data 0:7 -> <- addr 0 : 7 -> <- op: wr / rd ->
reg [7:0] dout_reg;

integer count = 0;

typedef enum bit [2:0] {idle = 0, load = 1, check_op = 2, send_data = 3, send_addr = 4, read_data = 5, error = 6, check_ready = 7} state_type;
state_type state = idle; 
 
/////////////////cs logic   
always@(posedge clk)
begin
  if(rst)
           begin
           state <= idle;
           count <= 0;
           cs <= 1'b1;
           mosi <= 1'b0; 
           err <= 1'b0;
           done <= 1'b0;
           end
 else 
   begin
      case(state)
            idle: begin
            cs    <= 1'b1;
            mosi  <= 1'b0;
            state <= load;
            err   <= 1'b0;
            done  <= 1'b0;
            end
            
            load: begin
            din_reg <= {din, addr, wr};
            state   <= check_op;
            end

            check_op: begin
            if(wr == 1'b1 && addr < 32)                  //WRITE 
             begin
             cs <= 1'b0;            //enable memory
             state <= send_data;    //send addr and data and wait for memory to write both "op_done" 
             end
            else if (wr == 1'b0 && addr < 32)           //READ
             begin
             state <= send_addr;       //send addr and wait for memory to be ready to send data
             cs <= 1'b0;                //enable memory
             end
            else begin
             state <= error;                           //addr out of range
             cs <= 1'b1; 
             end
            end


            send_data :                                //for write part 
            begin
                if(count <= 16)  
                 begin
                 count <= count + 1;
                 mosi  <= din_reg[count];
                 state = send_data;            // He mixed blcoking and non blocking assignment 
                 end
                else
                  begin
                     cs    <= 1'b1;            //used only once in memory code, not effective here 
                     mosi  <= 1'b0;
                     if(op_done)               //signifies mem completed process of writing data to itself
                           begin
                                  count <= 0;
                                  done  <= 1'b1;  //WRITE OPERATION COMPLETED
                                  state <= idle;
                            end
                      else
                              begin
                              state <= send_data;
                              end
                  end
            end

            send_addr: begin            //READ OPERATION START 
            if(count <= 8)
             begin
             count <= count + 1;
             mosi  <= din_reg[count];
             state <= send_addr;
             end
            else
              begin
              count <= 0;
              cs    <= 1'b1;
              state <= check_ready;         //WAIT UNTIL MEMORY IS READY TO TAKE DATA
              end
            end
   
            check_ready : begin             //WHEN MEM SAYS ready is HIGH,  SEND the ADDRESS
                if(ready)
                      state <= read_data;
                else
                      state <= check_ready;
                      
            end

            read_data:begin                 //READ DATA after giving address to memory, now read data from memory and give to controller
                            if(count <= 7)
                                 begin
                                 count <= count + 1;
                                 dout_reg[count]  <=  miso;   //MISO will take data from memory and give to controller
                                 // finally data being read is present in dout_reg 
                                 state = read_data;
                                 end
                            else
                                  begin
                                  count <= 0;
                                  done <= 1'b1;             //read operation completed 
                                  state <= idle; 
                                  end
                      end
            
            error :
            begin

            err   <= 1'b1; 
            state <= idle;
            done  <= 1'b1;     // this done says whole transaction is completed 

            end
            
           default: 
           begin
           state <= idle;
           count <= 0;
           done <= 0;
           end
            
      endcase
   end 
end 

assign dout = dout_reg;                     //final read data is present in dout_reg
endmodule
////////////////////////////////////////////////////
































///////////////////////////     SPI MEMORY   ////////////////////////////////////
module spi_mem(
input clk, rst, cs, miso,
output reg ready, mosi, op_done
);

reg [7:0] mem [31:0] = '{default:0};
integer count = 0;
reg [15:0] datain;
reg [7:0]  dataout;

typedef enum bit [2:0] {idle = 0, detect = 1, store = 2, read_addr = 3, send_data = 4} state_type;
state_type state = idle;

always@(posedge clk)
begin
      if(rst) 
          begin
             state <= idle;
             count <= 0;
             mosi  <= 0;
             ready <= 0;
             op_done <= 0;
             
          end
     else
         begin
                case(state)
                  idle: begin
                    count <= 0;
                    mosi  <= 0;
                    ready <= 0;
                    op_done <= 0;
                    datain <= 0;
                  
                     if(!cs)       //senses start of operation
                       state <= detect;
                     else
                       state <= idle;
                  end
                  
                    
                  detect: begin 
                      if(miso)    // if LSB of din_reg is = 1 then write
                        state <= store; //write 
                      else
                        state <= read_addr;   // else read
                   end
                   
                    
                   store: begin
                      if(count <= 15) begin             //rd and store 16 bit (both DATA and ADDR bits)
                        datain[count]     <= miso;       //store in TEMP reg of memory
                        count             <= count + 1;
                        state             <= store;
                      end
                      else
                        begin                                   //split the ADDR becuase its common for both read and write
                         mem[datain[7:0]]  <= datain[15:8];     //read the address, store it in memory LSB of data_in which is on MSB of SPI controller datain_[15:8]
                         state <= idle;
                         count <= 0;
                         op_done <= 1'b1;
                        end
                    end
                    
                    read_addr: begin                        //while writing, we first read address 
                      if(count <= 7) begin
                       count <= count + 1;
                       datain[count] <= miso;               //update the variable with addr given by SPI controller 
                       state <= read_addr;
                       end
                       else begin
                       count <= 0;
                       state <= send_data;
                       ready <= 1'b1;                       //tell controller that I'm ready with address, read addr from memory which has data requested bu user   
                       dataout <= mem[datain];
                       end
                    end
                       
                    send_data: begin                        //now send data on that address
                       ready <= 1'b0;
                       if(count < 8) 
                       begin
                        count <= count + 1;
                        mosi  <= dataout[count];            //send data via MOSI pin 
                        state <= send_data;
                       end 
                       else
                         begin
                         count <= 0;
                         state <= idle;
                         op_done <= 1'b1;
                         end     
                    end   
                    
                    default : state <= idle;
                    
                 endcase
          end
      end
endmodule

////////////////////////////////////////////////////////////







///////////////////////////// CONNECTION B/W MEM. AND CONTROLLER   ///////////////////////////////////
module top(
    input wr,clk,rst,
    input [7:0] addr, din,
    output [7:0] dout,
    output done, err
);
wire csreg, mosireg, misoreg, readyreg, opdonereg;

spi_intf intf (wr, clk, rst, readyreg, opdonereg, addr, din, dout, csreg, mosireg, misoreg, done, err);
spi_mem  mem_inst (clk, rst, csreg, mosireg, readyreg, misoreg, opdonereg);

endmodule





//////////////////////////////////////////////

interface spi_i;
  
    logic wr,clk,rst;
    logic [7:0] addr, din;
    logic [7:0] dout;
    logic done, err;
  
endinterface