package ViterbiDecoder;

import FIFO::*;
import FloatingPointAdder::*;

typedef Bit#(32) Float32;
typedef Bit#(32) State;
typedef Bit#(32) Observation;
typedef Bit#(32) LogProb;
typedef Bit#(32) Address;

typedef enum {
    READ_N, READ_M, READ_A, READ_B, READ_INPUT
} MemReqType deriving (Bits, Eq, FShow);

typedef enum {
    READ_R1, WRITE_R1, READ_R2, WRITE_R2,
    READ_TB, WRITE_TB, READ_OB, WRITE_OB
} BufferReqType deriving (Bits, Eq, FShow);

typedef struct {
    MemReqType reqType;
    Address addr;
} MemRequest deriving (Bits, FShow);

typedef struct {
    Bit#(32) data;
} MemResponse deriving (Bits, FShow);

typedef struct {
    BufferReqType reqType;
    Bit#(16) addr;
    Bit#(8) data;
    Bit#(32) data32;
} BufferRequest deriving (Bits, FShow);

typedef struct {
    Bit#(8) data;
    Bit#(32) data32;
} BufferResponse deriving (Bits, FShow);

typedef enum {
    IDLE, REQ_NM, WAIT_NM,
    INIT_OBS_WAIT,
    INIT_AB_REQ, INIT_ADD_PROB, INIT_WRITE_R1,
    VITERBI_OBS_REQ, VITERBI_OBS_WAIT,
    VITERBI_COMPUTE_INIT, VITERBI_INNER_LOOP,
    VITERBI_READ_R1, VITERBI_ADD_TRANSITION, VITERBI_ADD_EMISSION, VITERBI_WRITE_TB,
    VITERBI_SWAP, VITERBI_SWAP_READ,
    FIND_BEST_LOOP, FIND_BEST_READ,
    TRACEBACK_LOOP, TRACEBACK_READ_OB, TRACEBACK_READ_TB,
    OUTPUT_STATES, OUTPUT_READ, OUTPUT_MARKER,
    NEXT_SEQ_CHECK, NEXT_SEQ_WAIT,
    DONE
} DecoderState deriving (Bits, Eq, FShow);

interface ViterbiDecoder;
    method Action start();
    method Bool isDone();
    method ActionValue#(MemRequest) getMemReq0();
    method ActionValue#(MemRequest) getMemReq1();
    method Action putMemResp0(MemResponse resp);
    method Action putMemResp1(MemResponse resp);
    method ActionValue#(BufferRequest) getBufferReq();
    method Action putBufferResp(BufferResponse resp);
    method ActionValue#(State) getOutput();
    method Bool hasOutput();
endinterface

(* synthesize *)
module mkViterbiDecoder(ViterbiDecoder);
    
    FIFO#(MemRequest) memReqFifo0 <- mkFIFO1();
    FIFO#(MemRequest) memReqFifo1 <- mkFIFO1();
    FIFO#(MemResponse) memRespFifo0 <- mkFIFO1();
    FIFO#(MemResponse) memRespFifo1 <- mkFIFO1();
    FIFO#(BufferRequest) bufferReqFifo <- mkFIFO1();
    FIFO#(BufferResponse) bufferRespFifo <- mkFIFO1();
    FIFO#(State) outputFifo <- mkFIFO1();
    
    FloatingPointAdder fpAdder <- mkFloatingPointAdder();
    
    Reg#(DecoderState) state <- mkReg(IDLE);
    
    Reg#(Bit#(7)) numStates <- mkReg(0);
    Reg#(Bit#(10)) numObservations <- mkReg(0);
    
    Reg#(Bit#(7)) iCounter <- mkReg(0);
    Reg#(Bit#(7)) jCounter <- mkReg(0);
    Reg#(Bit#(14)) ptr <- mkReg(0);
    Reg#(Bit#(7)) timeStep <- mkReg(0);
    
    Reg#(Observation) currentObs <- mkReg(0);
    Reg#(LogProb) localMax <- mkReg(0);
    Reg#(State) localState <- mkReg(0);
    Reg#(LogProb) bestProb <- mkReg(0);
    Reg#(State) bestState <- mkReg(0);
    Reg#(Bit#(16)) tempTbIdx <- mkReg(0);
    
    Reg#(Float32) tempA <- mkReg(0);
    Reg#(Float32) tempB <- mkReg(0);
    Reg#(Float32) tempResult <- mkReg(0);
    
    function Bool floatGreater(LogProb a, LogProb b);
        return a < b;
    endfunction
    
    // Request number of states (N) and observations (M)
    rule rlReqNM (state == REQ_NM);
        memReqFifo0.enq(MemRequest { reqType: READ_N, addr: 0 });
        memReqFifo1.enq(MemRequest { reqType: READ_M, addr: 1 });
        ptr <= 0;
        state <= WAIT_NM;
    endrule
    
    // Receive N and M, then request first observation
    rule rlRcvNM (state == WAIT_NM);
        let respN = memRespFifo0.first();
        let respM = memRespFifo1.first();
        memRespFifo0.deq();
        memRespFifo1.deq();
        memReqFifo0.enq(MemRequest { reqType: READ_INPUT, addr: zeroExtend(ptr) });
        numStates <= truncate(respN.data);
        numObservations <= truncate(respM.data);
        state <= INIT_OBS_WAIT;
    endrule
    
    // Wait for first observation; handle termination or sequence markers
    rule rlInitObsWait (state == INIT_OBS_WAIT);
        let resp = memRespFifo0.first();
        memRespFifo0.deq();
        if (resp.data == 32'h00000000) begin
            state <= DONE;
            outputFifo.enq(32'h00000000);
        end
        else if (resp.data == 32'hFFFFFFFF) begin
            outputFifo.enq(32'hFFFFFFFF);
            ptr <= ptr + 1;
            memReqFifo0.enq(MemRequest { reqType: READ_INPUT, addr: zeroExtend(ptr + 1) });
            state <= INIT_OBS_WAIT;
        end else begin
            currentObs <= resp.data;
            state <= INIT_AB_REQ;
            iCounter <= 0;
            timeStep <= 0;
        end
    endrule
    
    // Initialize: request initial probabilities (A[i] + B[i][obs])
    rule rlInitAB (state == INIT_AB_REQ && iCounter < numStates);
        Bit#(32) bIdx = zeroExtend(iCounter) * zeroExtend(numObservations) + currentObs - 1;
        memReqFifo0.enq(MemRequest { reqType: READ_A, addr: zeroExtend(iCounter) });
        memReqFifo1.enq(MemRequest { reqType: READ_B, addr: bIdx });
        state <= INIT_ADD_PROB;
    endrule
    
    // Add initial probabilities using FP adder
    rule rlInitAddProb (state == INIT_ADD_PROB);
        let respA = memRespFifo0.first();
        memRespFifo0.deq();
        let respB = memRespFifo1.first();
        memRespFifo1.deq();
        
        let result = fpAdder.add(respA.data, respB.data);
        tempResult <= result;
        state <= INIT_WRITE_R1;
    endrule
    
    // Write initial probability to R1 buffer
    rule rlInitWrite (state == INIT_WRITE_R1);
        bufferReqFifo.enq(BufferRequest { 
            reqType: WRITE_R1, 
            addr: zeroExtend(iCounter[5:0]), 
            data: 0,
            data32: tempResult 
        });
        
        if (iCounter + 1 >= numStates) begin
            ptr <= ptr + 1;
            timeStep <= 1;
            state <= VITERBI_OBS_REQ;
        end else begin
            iCounter <= iCounter + 1;
            state <= INIT_AB_REQ;
        end
    endrule
    
    // Request next observation for Viterbi processing
    rule rlViterbiObsReq (state == VITERBI_OBS_REQ);
        memReqFifo0.enq(MemRequest { reqType: READ_INPUT, addr: zeroExtend(ptr) });
        state <= VITERBI_OBS_WAIT;
    endrule
    
    // Wait for observation; if sequence end marker, start finding best path
    rule rlViterbiObsWait (state == VITERBI_OBS_WAIT);
        let resp = memRespFifo0.first();
        memRespFifo0.deq();
        if (resp.data == 32'hFFFFFFFF) begin
            state <= FIND_BEST_LOOP;
            iCounter <= 0;
            bestProb <= 32'hFF800000;
        end else begin
            currentObs <= resp.data;
            state <= VITERBI_COMPUTE_INIT;
            iCounter <= 0;
        end
    endrule
    
    // Initialize counters for computing Viterbi step for current state
    rule rlViterbiComputeInit (state == VITERBI_COMPUTE_INIT);
        if (iCounter < numStates) begin
            jCounter <= 0;
            localMax <= 32'hFF800000;
            localState <= 0;
            state <= VITERBI_INNER_LOOP;
        end else begin
            iCounter <= 0;
            state <= VITERBI_SWAP;
        end
    endrule
    
    // Inner loop: request transition prob A[j][i] and previous state prob R1[j]
    rule rlViterbiInnerLoop (state == VITERBI_INNER_LOOP);
        if (jCounter < numStates) begin
            Bit#(32) aIdx = (zeroExtend(jCounter) + 1) * zeroExtend(numStates) + zeroExtend(iCounter);
            memReqFifo0.enq(MemRequest { reqType: READ_A, addr: aIdx });
            
            bufferReqFifo.enq(BufferRequest { 
                reqType: READ_R1, 
                addr: zeroExtend(jCounter[5:0]), 
                data: 0,
                data32: 0
            });
            
            state <= VITERBI_READ_R1;
        end else begin
            Bit#(32) bIdx = zeroExtend(iCounter) * zeroExtend(numObservations) + currentObs - 1;
            memReqFifo1.enq(MemRequest { reqType: READ_B, addr: bIdx });
            state <= VITERBI_ADD_EMISSION;
        end
    endrule
    
    // Read transition and previous state probabilities
    rule rlViterbiReadR1 (state == VITERBI_READ_R1);
        let respA = memRespFifo0.first();
        memRespFifo0.deq();
        let r1Resp = bufferRespFifo.first();
        bufferRespFifo.deq();
        
        tempA <= r1Resp.data32;
        tempB <= respA.data;
        state <= VITERBI_ADD_TRANSITION;
    endrule
    
    // Add transition probability and track maximum
    rule rlViterbiAddTransition (state == VITERBI_ADD_TRANSITION);
        let result = fpAdder.add(tempA, tempB);
        
        if (jCounter == 0 || floatGreater(result, localMax)) begin
            localMax <= result;
            localState <= zeroExtend(jCounter) + 1;
        end
        
        jCounter <= jCounter + 1;
        state <= VITERBI_INNER_LOOP;
    endrule
    
    // Add emission probability and write result to R2
    rule rlViterbiAddEmission (state == VITERBI_ADD_EMISSION);
        let respB = memRespFifo1.first();
        memRespFifo1.deq();
        
        let result = fpAdder.add(localMax, respB.data);
        Bit#(32) tbIdx32 = (zeroExtend(timeStep) - 1) * zeroExtend(numStates) + zeroExtend(iCounter);
        tempTbIdx <= truncate(tbIdx32);
        
        bufferReqFifo.enq(BufferRequest { 
            reqType: WRITE_R2, 
            addr: zeroExtend(iCounter[5:0]), 
            data: 0,
            data32: result 
        });
        state <= VITERBI_WRITE_TB;
    endrule
    
    // Write traceback pointer (best previous state)
    rule rlViterbiWriteTB (state == VITERBI_WRITE_TB);
        bufferReqFifo.enq(BufferRequest { 
            reqType: WRITE_TB, 
            addr: tempTbIdx, 
            data: truncate(localState),
            data32: 0
        });
    
        iCounter <= iCounter + 1;
        state <= VITERBI_COMPUTE_INIT;
    endrule
    
    // Swap R1 and R2 buffers: read from R2
    rule rlViterbiSwap (state == VITERBI_SWAP);
        if (iCounter < numStates) begin
            bufferReqFifo.enq(BufferRequest { 
                reqType: READ_R2, 
                addr: zeroExtend(iCounter[5:0]), 
                data: 0,
                data32: 0
            });
            state <= VITERBI_SWAP_READ;
        end else begin
            ptr <= ptr + 1;
            timeStep <= timeStep + 1;
            state <= VITERBI_OBS_REQ;
        end
    endrule
    
    // Swap R1 and R2 buffers: write to R1
    rule rlViterbiSwapRead (state == VITERBI_SWAP_READ);
        let resp = bufferRespFifo.first();
        bufferRespFifo.deq();
        
        bufferReqFifo.enq(BufferRequest { 
            reqType: WRITE_R1, 
            addr: zeroExtend(iCounter[5:0]), 
            data: 0,
            data32: resp.data32 
        });
        
        iCounter <= iCounter + 1;
        state <= VITERBI_SWAP;
    endrule
    
    // Find best final state: read all final probabilities
    rule rlFindBestLoop (state == FIND_BEST_LOOP);
        if (iCounter < numStates) begin
            bufferReqFifo.enq(BufferRequest { 
                reqType: READ_R1, 
                addr: zeroExtend(iCounter[5:0]), 
                data: 0,
                data32: 0
            });
            state <= FIND_BEST_READ;
        end else begin
            bufferReqFifo.enq(BufferRequest { 
                reqType: WRITE_OB, 
                addr: 0, 
                data: 0,
                data32: bestState 
            });
            iCounter <= 1;
            state <= TRACEBACK_LOOP;
        end
    endrule
    
    // Find best final state: compare probabilities
    rule rlFindBestRead (state == FIND_BEST_READ);
        let resp = bufferRespFifo.first();
        bufferRespFifo.deq();
        
        if (iCounter == 0 || floatGreater(resp.data32, bestProb)) begin
            bestProb <= resp.data32;
            bestState <= zeroExtend(iCounter) + 1;
        end
        
        iCounter <= iCounter + 1;
        state <= FIND_BEST_LOOP;
    endrule
    
    // Traceback: read current state from output buffer
    rule rlTracebackLoop (state == TRACEBACK_LOOP);
        if (iCounter < timeStep) begin
            bufferReqFifo.enq(BufferRequest { 
                reqType: READ_OB, 
                addr: zeroExtend((iCounter - 1)[6:0]), 
                data: 0,
                data32: 0
            });
            state <= TRACEBACK_READ_OB;
        end else begin
            iCounter <= 0;
            state <= OUTPUT_STATES;
        end
    endrule
    
    // Traceback: compute traceback buffer index
    rule rlTracebackReadOB (state == TRACEBACK_READ_OB);
        let resp = bufferRespFifo.first();
        bufferRespFifo.deq();
        
        Bit#(32) tempIdx = zeroExtend(timeStep - 1) - zeroExtend(iCounter);
        Bit#(32) tbIdx32 = (tempIdx * zeroExtend(numStates)) + (resp.data32 - 1);
        Bit#(16) tbIdx = truncate(tbIdx32);
        
        bufferReqFifo.enq(BufferRequest { 
            reqType: READ_TB, 
            addr: tbIdx, 
            data: 0,
            data32: 0
        });
        
        state <= TRACEBACK_READ_TB;
    endrule
    
    // Traceback: read previous state and write to output buffer
    rule rlTracebackReadTB (state == TRACEBACK_READ_TB);
        let resp = bufferRespFifo.first();
        bufferRespFifo.deq();
    
        bufferReqFifo.enq(BufferRequest { 
            reqType: WRITE_OB, 
            addr: zeroExtend(iCounter[6:0]), 
            data: 0,
            data32: zeroExtend(resp.data)
        });
    
        iCounter <= iCounter + 1;
        state <= TRACEBACK_LOOP;
    endrule
    
    // Output decoded states in correct order
    rule rlOutputStates (state == OUTPUT_STATES);
        if (iCounter < timeStep) begin
            Bit#(7) tempOutputIdx = (timeStep - 1) - iCounter;
            bufferReqFifo.enq(BufferRequest { 
                reqType: READ_OB, 
                addr: zeroExtend(tempOutputIdx[6:0]), 
                data: 0,
                data32: 0
            });
            state <= OUTPUT_READ;
        end else begin
            outputFifo.enq(bestProb);
            state <= OUTPUT_MARKER;
        end
    endrule
    
    // Read and output state
    rule rlOutputRead (state == OUTPUT_READ);
        let resp = bufferRespFifo.first();
        bufferRespFifo.deq();
        
        outputFifo.enq(resp.data32);
        iCounter <= iCounter + 1;
        state <= OUTPUT_STATES;
    endrule
    
    // Output sequence end marker
    rule rlOutputMarker (state == OUTPUT_MARKER);
        outputFifo.enq(32'hFFFFFFFF);
        ptr <= ptr + 1;
        state <= NEXT_SEQ_CHECK;
    endrule
    
    // Check if another sequence exists
    rule rlNextSeqCheck (state == NEXT_SEQ_CHECK);
        memReqFifo0.enq(MemRequest { reqType: READ_INPUT, addr: zeroExtend(ptr) });
        state <= NEXT_SEQ_WAIT;
    endrule
    
    // Wait for next sequence marker or termination signal
    rule rlNextSeqWait (state == NEXT_SEQ_WAIT);
        let resp = memRespFifo0.first();
        memRespFifo0.deq();
        
        if (resp.data == 32'h00000000) begin
            outputFifo.enq(32'h00000000);
            state <= DONE;
        end 
        else if(resp.data == 32'hFFFFFFFF) begin
             outputFifo.enq(32'hFFFFFFFF);
             ptr <= ptr + 1;
             memReqFifo0.enq(MemRequest { reqType: READ_INPUT, addr: zeroExtend(ptr+1) });
             state <= NEXT_SEQ_WAIT;
        end
        else begin
            currentObs <= resp.data;
            state <= INIT_AB_REQ;
            iCounter <= 0;
            timeStep <= 0;
        end
    endrule
    
    method Action start() if (state == IDLE);
        state <= REQ_NM;
    endmethod
    
    method Bool isDone() = (state == DONE);
    
    method ActionValue#(MemRequest) getMemReq0();
        let req = memReqFifo0.first();
        memReqFifo0.deq();
        return req;
    endmethod
    
    method ActionValue#(MemRequest) getMemReq1();
        let req = memReqFifo1.first();
        memReqFifo1.deq();
        return req;
    endmethod
    
    method Action putMemResp0(MemResponse resp);
        memRespFifo0.enq(resp);
    endmethod
    
    method Action putMemResp1(MemResponse resp);
        memRespFifo1.enq(resp);
    endmethod
    
    method ActionValue#(BufferRequest) getBufferReq();
        let req = bufferReqFifo.first();
        bufferReqFifo.deq();
        return req;
    endmethod
    
    method Action putBufferResp(BufferResponse resp);
        bufferRespFifo.enq(resp);
    endmethod
    
    method ActionValue#(State) getOutput();
        let val = outputFifo.first();
        outputFifo.deq();
        return val;
    endmethod
    
    method Bool hasOutput();
        return True;
    endmethod
    
endmodule

endpackage

