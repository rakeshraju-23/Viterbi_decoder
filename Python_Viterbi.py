import struct
import sys

def read_hex_file(filename):
    """Read hex values from .dat file"""
    data = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                val = int(line, 16)
                data.append(val)
    return data

def bits_to_float(bits):
    """Convert 32-bit hex to IEEE 754 float"""
    return struct.unpack('!f', struct.pack('!I', bits))[0]

def float_to_bits(f):
    """Convert IEEE 754 float to 32-bit hex"""
    return struct.unpack('!I', struct.pack('!f', f))[0]

def float_add_round_to_nearest_even(a_bits, b_bits):
    """
    Custom float addition that tries to match BSV's rounding behavior.
    Uses round-to-nearest-even (banker's rounding) which is IEEE 754 default.
    """
    a_float = bits_to_float(a_bits)
    b_float = bits_to_float(b_bits)
    result = a_float + b_float
    return float_to_bits(result)

def viterbi_decoder(n_file, a_file, b_file, input_file, output_file):
    """
    Viterbi decoder implementation for HMM
    Uses log probabilities (natural logarithm)
    """
    
    # Read input files
    n_data = read_hex_file(n_file)
    a_data = read_hex_file(a_file)
    b_data = read_hex_file(b_file)
    input_data = read_hex_file(input_file)
    
    N = n_data[0]  # Number of states
    M = n_data[1]  # Number of observations
    
    print(f"N (states) = {N}, M (observations) = {M}")
    
    output_values = []
    
    # Process all observation sequences
    ptr = 0
    seq_num = 0
    
    while ptr < len(input_data):
        # Read observation sequence
        observations = []
        while ptr < len(input_data):
            obs = input_data[ptr]
            ptr += 1
            
            if obs == 0xFFFFFFFF:
                # End of current sequence
                break
            elif obs == 0x00000000:
                # End of all sequences
                output_values.append(0x00000000)
                with open(output_file, 'w') as f:
                    for val in output_values:
                        f.write(f"{val:08x}\n")
                print(f"\nWrote {len(output_values)} values to {output_file}")
                return
            else:
                observations.append(obs)
        
        # Handle empty sequence (just 0xFFFFFFFF marker with no observations)
        if not observations:
            print(f"\n=== Empty Sequence ===")
            output_values.append(0xFFFFFFFF)
            continue
        
        seq_num += 1
        print(f"\n=== Sequence {seq_num} ===")
        print(f"Observations: {observations}")
        
        T = len(observations)
        
        # Viterbi algorithm using bit-level operations to match BSV
        V = [[0xFFFFFFFF] * N for _ in range(T)]
        V_float = [[-float('inf')] * N for _ in range(T)]
        backpointer = [[0] * N for _ in range(T)]
        
        # Initialization (t=0)
        for j in range(N):
            obs_idx = observations[0] - 1
            init_prob_bits = a_data[j]
            emission_prob_bits = b_data[j * M + obs_idx]
            
            V[0][j] = float_add_round_to_nearest_even(init_prob_bits, emission_prob_bits)
            V_float[0][j] = bits_to_float(V[0][j])
        
        # Recursion (t=1 to T-1)
        for t in range(1, T):
            obs_idx = observations[t] - 1
            
            for j in range(N):
                max_prob_bits = 0xFF800000  # -inf in IEEE 754
                max_prob_float = -float('inf')
                max_state = 0
                
                for i in range(N):
                    trans_idx = N + i * N + j
                    
                    prob_bits = float_add_round_to_nearest_even(V[t-1][i], a_data[trans_idx])
                    prob_float = bits_to_float(prob_bits)
                    
                    if prob_float > max_prob_float:
                        max_prob_float = prob_float
                        max_prob_bits = prob_bits
                        max_state = i
                
                emission_prob_bits = b_data[j * M + obs_idx]
                V[t][j] = float_add_round_to_nearest_even(max_prob_bits, emission_prob_bits)
                V_float[t][j] = bits_to_float(V[t][j])
                backpointer[t][j] = max_state
        
        # Find best final state
        best_prob_float = -float('inf')
        best_prob_bits = 0xFF800000
        best_state = 0
        
        for j in range(N):
            if V_float[T-1][j] > best_prob_float:
                best_prob_float = V_float[T-1][j]
                best_prob_bits = V[T-1][j]
                best_state = j
        
        # Traceback
        path = [0] * T
        path[T-1] = best_state + 1
        
        for t in range(T-2, -1, -1):
            path[t] = backpointer[t+1][path[t+1]-1] + 1
        
        print(f"Decoded path: {path}")
        print(f"Log probability: {best_prob_float} (0x{best_prob_bits:08x})")
        
        # Write output for this sequence
        for state in path:
            output_values.append(state)
        
        output_values.append(best_prob_bits)
        output_values.append(0xFFFFFFFF)
    
    # If we exit the loop without seeing 0x00000000, write final terminator
    output_values.append(0x00000000)
    
    with open(output_file, 'w') as f:
        for val in output_values:
            f.write(f"{val:08x}\n")
    
    print(f"\nWrote {len(output_values)} values to {output_file}")

if __name__ == "__main__":
    if len(sys.argv) >= 6:
        n_file = sys.argv[1]
        a_file = sys.argv[2]
        b_file = sys.argv[3]
        input_file = sys.argv[4]
        output_file = sys.argv[5]
    else:
        n_file = "fut/N_fut.dat"
        a_file = "fut/A_fut.dat"
        b_file = "fut/B_fut.dat"
        input_file = "fut/input_fut.dat"
        output_file = "output_python.dat"
    
    print(f"Reading from:")
    print(f"  N: {n_file}")
    print(f"  A: {a_file}")
    print(f"  B: {b_file}")
    print(f"  Input: {input_file}")
    print(f"  Output: {output_file}\n")
    
    viterbi_decoder(n_file, a_file, b_file, input_file, output_file)
    print("\nDone!")

