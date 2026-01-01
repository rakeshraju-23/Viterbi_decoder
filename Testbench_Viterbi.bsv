package Testbench_Viterbi;

import ViterbiDecoder::*;
import RegFile::*;

function Bit#(16) to16(Bit#(32) x);
    return truncate(x);
endfunction

(* synthesize *)
module mkTB_Viterbi(Empty);
    // Load memory images (A, B, N, input) as regfiles
    RegFile#(Bit#(32), Bit#(32)) nFile      <- mkRegFileLoad("fut/N_fut.dat",     0, 1);
    RegFile#(Bit#(32), Bit#(32)) aFile      <- mkRegFileLoad("fut/A_fut.dat",     0, 1023);
    RegFile#(Bit#(32), Bit#(32)) bFile      <- mkRegFileLoad("fut/B_fut.dat",     0, 1023);
    RegFile#(Bit#(32), Bit#(32)) inputFile  <- mkRegFileLoad("fut/input_fut.dat", 0, 8191);

    // External buffer
    RegFile#(Bit#(16), Bit#(32)) uniBuffer <- mkRegFile(0, 1023);

    ViterbiDecoder dut <- mkViterbiDecoder();

    Reg#(Bit#(32)) cycleCount <- mkReg(0);
    Reg#(Bit#(2))  state      <- mkReg(0);

    Reg#(MemRequest)    bufferedReq0  <- mkReg(unpack(0));
    Reg#(Bool)          hasReq0       <- mkReg(False);

    Reg#(MemRequest)    bufferedReq1  <- mkReg(unpack(0));
    Reg#(Bool)          hasReq1       <- mkReg(False);

    Reg#(BufferRequest) bufferedBufReq <- mkReg(unpack(0));
    Reg#(Bool)          hasBufReq      <- mkReg(False);

    Reg#(File)          outFile       <- mkReg(InvalidFile);
    Reg#(Bit#(32))      outputCount   <- mkReg(0);

    Bit#(32) maxCycles = 7000000;

    // Buffer region base addresses
    let r1_base  = 16'd0;     
    let r2_base  = 16'd32;   
    let out_base = 16'd64;    
    let tb_base  = 16'd192;   

    function Bit#(16) mapR1(Bit#(16) idx);
        return r1_base + (idx & 16'h001F);
    endfunction

    function Bit#(16) mapR2(Bit#(16) idx);
        return r2_base + (idx & 16'h001F);
    endfunction

    function Bit#(16) mapOUT(Bit#(16) idx);
        return out_base + (idx & 16'h007F);
    endfunction

    // Traceback packing: 4 bytes per 32-bit word
    function Bit#(16) mapTB_word(Bit#(16) idx);
        return tb_base + (idx >> 2);
    endfunction

    function Bit#(2) mapTB_byte(Bit#(16) idx);
        return truncate(idx & 16'h0003);
    endfunction

    // Increment cycle counter and check for timeout
    rule rlCycle;
        cycleCount <= cycleCount + 1;
        if (cycleCount >= maxCycles) begin
            $display("ERROR: Timeout at cycle %0d", cycleCount);
            $finish(1);
        end
    endrule

    // Start the decoder on first cycle
    rule rlInit0 (state == 0);
        dut.start();
        state <= 1;
        $display("[Cycle %0d] TB: Decoder started", cycleCount);
    endrule

    // Open output file for writing decoded results
    rule rlInit1 (state == 1 && cycleCount == 1);
        File fh <- $fopen("output.dat", "w");
        outFile <= fh;
    endrule

    // Get memory request from DUT port 0
    rule rlGetMemReq0 (state == 1 && !hasReq0);
        let req <- dut.getMemReq0();
        bufferedReq0 <= req;
        hasReq0 <= True;
    endrule

    // Process memory request for port 0 (N, M, A, input)
    rule rlProcessReq0 (state == 1 && hasReq0);
        let req = bufferedReq0;
        hasReq0 <= False;
        Bit#(32) data = ?;
        if (req.reqType == READ_N)           data = nFile.sub(0);
        else if (req.reqType == READ_M)      data = nFile.sub(1);
        else if (req.reqType == READ_A)      data = aFile.sub(req.addr);
        else if (req.reqType == READ_INPUT)  data = inputFile.sub(req.addr);
        dut.putMemResp0(MemResponse { data: data });
    endrule

    // Get memory request from DUT port 1
    rule rlGetMemReq1 (state == 1 && !hasReq1);
        let req <- dut.getMemReq1();
        bufferedReq1 <= req;
        hasReq1 <= True;
    endrule

    // Process memory request for port 1 (N, M, B, input)
    rule rlProcessReq1 (state == 1 && hasReq1);
        let req = bufferedReq1;
        hasReq1 <= False;
        Bit#(32) data = ?;
        if (req.reqType == READ_N)           data = nFile.sub(0);
        else if (req.reqType == READ_M)      data = nFile.sub(1);
        else if (req.reqType == READ_B)      data = bFile.sub(req.addr);
        else if (req.reqType == READ_INPUT)  data = inputFile.sub(req.addr);
        dut.putMemResp1(MemResponse { data: data });
    endrule

    // Get buffer request from DUT
    rule rlGetBufferReq (state == 1 && !hasBufReq);
        let req <- dut.getBufferReq();
        bufferedBufReq <= req;
        hasBufReq <= True;
    endrule

    // Process buffer request with byte packing for traceback
    rule rlProcessBufferReq (state == 1 && hasBufReq);
        let req = bufferedBufReq;
        hasBufReq <= False;

        Bit#(16) phys = 0;
        Bool doRead  = False;
        Bool doWrite = False;

        if (req.reqType == READ_R1) begin
            phys = mapR1(truncate(req.addr));
            doRead = True;
        end else if (req.reqType == WRITE_R1) begin
            phys = mapR1(truncate(req.addr));
            doWrite = True;
        end else if (req.reqType == READ_R2) begin
            phys = mapR2(truncate(req.addr));
            doRead = True;
        end else if (req.reqType == WRITE_R2) begin
            phys = mapR2(truncate(req.addr));
            doWrite = True;
        end else if (req.reqType == READ_TB) begin
            // Extract 8-bit traceback value from packed 32-bit word
            Bit#(16) word_addr = mapTB_word(truncate(req.addr));
            Bit#(2) byte_pos = mapTB_byte(truncate(req.addr));
            Bit#(32) word_data = uniBuffer.sub(word_addr);
            
            Bit#(8) byte_data = case (byte_pos)
                2'd0: word_data[7:0];
                2'd1: word_data[15:8];
                2'd2: word_data[23:16];
                2'd3: word_data[31:24];
            endcase;
            
            dut.putBufferResp(BufferResponse { 
                data: byte_data,
                data32: 0
            });
        end else if (req.reqType == WRITE_TB) begin
            // Pack 8-bit traceback value into 32-bit word
            Bit#(16) word_addr = mapTB_word(truncate(req.addr));
            Bit#(2) byte_pos = mapTB_byte(truncate(req.addr));
            Bit#(32) old_word = uniBuffer.sub(word_addr);
            
            Bit#(32) new_word = case (byte_pos)
                2'd0: {old_word[31:8], req.data};
                2'd1: {old_word[31:16], req.data, old_word[7:0]};
                2'd2: {old_word[31:24], req.data, old_word[15:0]};
                2'd3: {req.data, old_word[23:0]};
            endcase;
            
            uniBuffer.upd(word_addr, new_word);
        end else if (req.reqType == READ_OB) begin
            phys = mapOUT(truncate(req.addr));
            doRead = True;
        end else if (req.reqType == WRITE_OB) begin
            phys = mapOUT(truncate(req.addr));
            doWrite = True;
        end

        if (doRead) begin
            Bit#(32) data = uniBuffer.sub(phys);
            dut.putBufferResp(BufferResponse { 
                data: 0,
                data32: data
            });
        end else if (doWrite) begin
            uniBuffer.upd(phys, req.data32);
        end
    endrule

    // Retrieve output from DUT and write to file
    rule rlGetOutput (state == 1 && dut.hasOutput());
        let val <- dut.getOutput();
        outputCount <= outputCount + 1;
        File fh = outFile;
        $fwrite(fh, "%08x\n", val);
        $display("[Cycle %0d] OUTPUT: 0x%h", cycleCount, val);
    endrule

    // Close file and report success when decoding completes
    rule rlDone (state == 1 && dut.isDone());
        File fh = outFile;
        $fclose(fh);
        $display("SUCCESS! Total cycles: %d", cycleCount);
        $finish(0);
    endrule

endmodule

endpackage

