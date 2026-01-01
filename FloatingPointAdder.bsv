package FloatingPointAdder;

import Vector::*;

typedef Bit#(32) Float32;

typedef struct {
    Bit#(1) prop;
    Bit#(1) gen;
} CarryBlock deriving (Bits, Eq);

function Bit#(2) fullAdd(Bit#(1) x, Bit#(1) y, Bit#(1) cin);
    Bit#(1) s = x ^ y ^ cin;
    Bit#(1) c = (x & y) | (y & cin) | (x & cin);
    return {c, s};
endfunction

function CarryBlock blackCell(CarryBlock left, CarryBlock right);
    return CarryBlock {
        gen: left.gen | (left.prop & right.gen),
        prop: left.prop & right.prop
    };
endfunction

function Bit#(1) grayCell(CarryBlock left, Bit#(1) rightGen);
    return left.gen | (left.prop & rightGen);
endfunction

// 24-bit Brent-Kung parallel prefix adder
function Bit#(25) adder24bit(Bit#(24) x, Bit#(24) y);
    Vector#(24, CarryBlock) level0;
    
    for (Integer k = 0; k < 24; k = k + 1) begin
        level0[k].gen = x[k] & y[k];
        level0[k].prop = x[k] ^ y[k];
    end
    
    // Forward tree: sparse prefix computation
    Vector#(24, CarryBlock) level1 = level0;
    for (Integer k = 1; k < 24; k = k + 2) begin
        level1[k] = blackCell(level0[k], level0[k-1]);
    end
    
    Vector#(24, CarryBlock) level2 = level1;
    for (Integer k = 3; k < 24; k = k + 4) begin
        level2[k] = blackCell(level1[k], level1[k-2]);
    end
    
    Vector#(24, CarryBlock) level3 = level2;
    for (Integer k = 7; k < 24; k = k + 8) begin
        level3[k] = blackCell(level2[k], level2[k-4]);
    end
    
    Vector#(24, CarryBlock) level4 = level3;
    for (Integer k = 15; k < 24; k = k + 16) begin
        level4[k] = blackCell(level3[k], level3[k-8]);
    end
    
    Vector#(24, CarryBlock) level5 = level4;
    if (23 >= 16) begin
        level5[23] = blackCell(level4[23], level4[23-16]);
    end
    
    // Backward tree: carry distribution
    Vector#(24, Bit#(1)) finalGen;
    
    for (Integer k = 0; k < 24; k = k + 1) begin
        finalGen[k] = level5[k].gen;
    end
    
    for (Integer k = 8; k < 24; k = k + 1) begin
        if ((k % 16) == 7) begin
            finalGen[k] = grayCell(level4[k], finalGen[k-8]);
        end
    end
    
    for (Integer k = 4; k < 24; k = k + 1) begin
        if ((k % 8) == 3) begin
            finalGen[k] = grayCell(level3[k], finalGen[k-4]);
        end
    end
    
    for (Integer k = 2; k < 24; k = k + 1) begin
        if ((k % 4) == 1) begin
            finalGen[k] = grayCell(level2[k], finalGen[k-2]);
        end
    end
    
    for (Integer k = 1; k < 24; k = k + 1) begin
        if ((k % 2) == 0) begin
            finalGen[k] = grayCell(level1[k], finalGen[k-1]);
        end
    end
    
    Bit#(24) sumBits;
    for (Integer k = 0; k < 24; k = k + 1) begin
        Bit#(1) carryIn = (k == 0) ? 1'b0 : finalGen[k-1];
        sumBits[k] = level0[k].prop ^ carryIn;
    end
    
    Bit#(1) carryOut = finalGen[23];
    return {carryOut, sumBits};
endfunction

function Bit#(8) subtract8bit(Bit#(8) x, Bit#(8) y);
    Bit#(8) result = 0;
    Bit#(1) borrow = 1'b1;
    
    for (Integer k = 0; k < 8; k = k + 1) begin
        Bit#(2) temp = fullAdd(x[k], ~y[k], borrow);
        result[k] = temp[0];
        borrow = temp[1];
    end
    return result;
endfunction

function Bit#(8) inc8(Bit#(8) val);
    Bit#(8) out = val;
    Bit#(9) ripple = 0;
    ripple[0] = 1'b1;
    
    for (Integer k = 0; k < 8; k = k + 1) begin
        out[k] = val[k] ^ ripple[k];
        ripple[k+1] = val[k] & ripple[k];
    end
    return out;
endfunction

function Bit#(23) inc23(Bit#(23) val);
    Bit#(23) out = val;
    Bit#(24) ripple = 0;
    ripple[0] = 1'b1;
    
    for (Integer k = 0; k < 23; k = k + 1) begin
        out[k] = val[k] ^ ripple[k];
        ripple[k+1] = val[k] & ripple[k];
    end
    return out;
endfunction

// IEEE 754 single-precision floating-point addition
function Float32 fpAddFunc(Float32 op1, Float32 op2);
    Bit#(1) sign1 = op1[31];
    Bit#(8) exp1 = op1[30:23];
    Bit#(23) frac1 = op1[22:0];
    
    Bit#(1) sign2 = op2[31];
    Bit#(8) exp2 = op2[30:23];
    Bit#(23) frac2 = op2[22:0];
    
    Bool sub1 = (exp1 == 8'h00) && (frac1 != 0);
    Bool sub2 = (exp2 == 8'h00) && (frac2 != 0);
    
    Bit#(24) mant1 = sub1 ? {1'b0, frac1} : {1'b1, frac1};
    Bit#(24) mant2 = sub2 ? {1'b0, frac2} : {1'b1, frac2};
    
    Bit#(8) eff_exp1 = sub1 ? 8'h01 : exp1;
    Bit#(8) eff_exp2 = sub2 ? 8'h01 : exp2;
    
    // Determine larger operand for alignment
    Bool exp1_larger = (eff_exp1 > eff_exp2) || 
                       ((eff_exp1 == eff_exp2) && (mant1 >= mant2));
    Bit#(8) expLarge = exp1_larger ? eff_exp1 : eff_exp2;
    Bit#(8) expDelta = exp1_larger ? (eff_exp1 - eff_exp2) : (eff_exp2 - eff_exp1);
    Bit#(24) mantLarge = exp1_larger ? mant1 : mant2;
    Bit#(24) mantSmall = exp1_larger ? mant2 : mant1;
    Bit#(1) signOut = exp1_larger ? sign1 : sign2;
    
    // Align mantissas
    Bit#(48) extSmall = {mantSmall, 24'b0};
    Bit#(48) shifted = extSmall >> expDelta;
    Bit#(24) aligned = shifted[47:24];
    
    Bit#(1) gBit = shifted[23];
    Bit#(1) sBit = |shifted[22:0];
    
    Bit#(25) addResult = adder24bit(mantLarge, aligned);
    
    // Normalize and round
    Bit#(1) finalSign;
    Bit#(8) finalExp;
    Bit#(23) finalFrac;
    
    if (addResult == 0) begin
        finalSign = 1'b0;
        finalExp = 8'h00;
        finalFrac = 23'h0;
    end
    else if (addResult[24] == 1'b1) begin
        finalSign = signOut;
        finalExp = inc8(expLarge);
        
        Bit#(1) needRound = addResult[0] & (gBit | sBit | addResult[1]);
        if (needRound == 1'b1)
            finalFrac = inc23(addResult[23:1]);
        else
            finalFrac = addResult[23:1];
    end
    else if (addResult[23] == 1'b1) begin
        finalSign = signOut;
        finalExp = expLarge;
        
        if (sub1 && sub2) begin
            finalFrac = addResult[22:0];
        end else begin
            Bit#(1) needRound = gBit & (sBit | addResult[0]);
            if (needRound == 1'b1)
                finalFrac = inc23(addResult[22:0]);
            else
                finalFrac = addResult[22:0];
        end
    end
    else begin
        finalSign = signOut;
        finalExp = 8'h00;
        finalFrac = addResult[22:0];
    end
    
    return {finalSign, finalExp, finalFrac};
endfunction

interface FloatingPointAdder;
    method Float32 add(Float32 a, Float32 b);
endinterface

(* synthesize *)
module mkFloatingPointAdder(FloatingPointAdder);
    method Float32 add(Float32 a, Float32 b);
        return fpAddFunc(a, b);
    endmethod
endmodule

endpackage

