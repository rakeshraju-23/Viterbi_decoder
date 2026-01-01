# Viterbi Decoder - BSV Implementation


## Project Structure

```
viterbi-decoder/
├── Makefile                    # Build and test automation
├── Testbench_Viterbi.bsv      # Top-level testbench
├── ViterbiDecoder.bsv     # Viterbi decoder implementation             
├── FloatingPointAdder.bsv     # Floating-point adder
├── Python_Viterbi.py           # Python reference decoder
├── compare.py                  # Output comparison script
├── fut/                        # Default test directory (BSV reads from here)
│   ├── N_fut.dat
│   ├── A_fut.dat
│   ├── B_fut.dat
│   └── input_fut.dat
├── huge/, small/               # Optional test datasets
└── test_cases/                 # Automated test cases
    ├── minimal/
    ├── classic_hmm/
    └── large_seq/
```

##  Prerequisites

- **Python 3**: Version 3.7+ 


```bash
bsc -version
python3 --version 
make --version
```


##  Quick Start

### 1. Setup Test Data

```bash
mkdir -p fut
cp your_data/N_*.dat fut/N_fut.dat
cp your_data/A_*.dat fut/A_fut.dat
cp your_data/B_*.dat fut/B_fut.dat
cp your_data/input_*.dat fut/input_fut.dat
```

### 2. Run Test

```bash
make test
```

**Output:**
```
Compiling BSV...
✓ Compilation done
Running BSV simulation (fut)...
SUCCESS! Total cycles: 12345
✓ BSV generated 10 outputs
Running Python decoder...
✓ Python generated 10 outputs
Comparing outputs...
 All 10/10 outputs matched!
```

##  Testing Commands

### Single Test
```bash
make test                           # Test with fut/
make test TESTDIR=huge              # Test with huge/
make test TESTDIR=test_cases/minimal # Test specific case
```

### All Tests
```bash
make test_all                       # Run all tests in test_cases/
```

**Output:**
```
======================================
Running All Tests from test_cases/
======================================

[Test 1] minimal
✓ BSV generated 4 outputs
✓ Python generated 4 outputs
All 4/4 outputs matched!
  PASSED

[Test 2] classic_hmm
✓ BSV generated 10 outputs
✓ Python generated 10 outputs
All 10/10 outputs matched!
  PASSED

======================================
Final Results: 2/2 tests passed
All tests successful!
======================================
```

### Other Commands
```bash
make list_tests     # Show available tests
make quick_test     # Skip recompilation
make clean          # Remove build files
make help           # Show all commands
```

## Adding New Test Cases

### 1. Create Directory
```bash
mkdir -p test_cases/my_test
```

### 2. Add Files (names must match directory)
```bash
cp data/N.dat test_cases/my_test/N_my_test.dat
cp data/A.dat test_cases/my_test/A_my_test.dat
cp data/B.dat test_cases/my_test/B_my_test.dat
cp data/input.dat test_cases/my_test/input_my_test.dat
```

### 3. Run Test
```bash
make test TESTDIR=test_cases/my_test
# Or include in automated testing
make test_all
```

## File Naming Rules

**Pattern:** `<dir>/<type>_<dir>.dat`

**Correct:**
- `fut/N_fut.dat`
- `huge/A_huge.dat`
- `test_cases/minimal/input_minimal.dat`

 **Wrong:**
- `test_cases/my_test/N_mytest.dat` (should be `N_my_test.dat`)

##  Directory Roles

### fut/ (Working Directory)
- BSV testbench reads from here
- Files must be named: `N_fut.dat`, `A_fut.dat`, `B_fut.dat`, `input_fut.dat`
- Default test location

### test_cases/ (Automated Tests)
- Store multiple test cases
- Each subdirectory = one test case
- Used by `make test_all`

##  Makefile Targets

| Command | Description |
|---------|-------------|
| `make test` | Run full test with default dataset |
| `make test TESTDIR=<dir>` | Test specific directory |
| `make test_all` | Run all tests in test_cases/ |
| `make quick_test` | Skip recompilation |
| `make list_tests` | Show available test cases |
| `make b_sim` | Compile BSV only |
| `make generate_verilog` | Generate Verilog |
| `make clean` | Remove build artifacts |
| `make help` | Show all commands |

## Output Files

| File | Description |
|------|-------------|
| `output.dat` | BSV decoder output |
| `output_python.dat` | Python reference output |
| `verilog/*.v` | Generated Verilog |
| `intermediate/` | Build artifacts |

## Troubleshooting

### "N_fut.dat not found"
```bash
# Check fut/ directory
ls fut/

# If testing another directory, Makefile auto-copies
make test TESTDIR=your_directory
```


### Compilation Failed
```bash
# Clean and retry
make cleanall
make test
```

##  How It Works

1. **File Setup**: When you run `make test TESTDIR=xyz`, files from `xyz/` are copied to `fut/` with correct names
2. **BSV Reads**: Testbench always reads from `fut/N_fut.dat`, etc.
3. **Python Reads**: Python decoder reads from original `TESTDIR`
4. **Compare**: Both outputs are compared line-by-line
5. **Result**: Pass/fail status with matched count (e.g., "10/10 matched")

---





