# ====================================================
# Viterbi Decoder Project Makefile (verbose, testdir-friendly)
# ====================================================

TOPFILE      = Testbench_Viterbi.bsv
TOPMODULE    = mkTB_Viterbi
BSVINCDIR    = .:%/Libraries
BSCDEFINES   = RV64
VERILOGDIR   = verilog/
BUILDDIR     = intermediate/

# Test configuration (can pass TESTDIR as a local directory or a path)
TESTDIR      ?= fut
TESTS_ROOT   ?= test_cases

# Helper: base name of TESTDIR (so TESTDIR can be "huge" or "test_cases/huge")
TESTNAME     := $(notdir $(TESTDIR))

# Discovered test directories (names under $(TESTS_ROOT))
DISCOVERED_TESTS := $(patsubst $(TESTS_ROOT)/%,%,$(wildcard $(TESTS_ROOT)/*))

# Input files (resolved relative to TESTDIR)
NFILE        = $(TESTDIR)/N_$(TESTNAME).dat
AFILE        = $(TESTDIR)/A_$(TESTNAME).dat
BFILE        = $(TESTDIR)/B_$(TESTNAME).dat
INPUTFILE    = $(TESTDIR)/input_$(TESTNAME).dat
REFOUTPUT    = $(TESTDIR)/Output_$(TESTNAME).dat

# Target folder used by simulator (where we copy inputs to)
TARGET_DIR   = fut
TARGET_N     = $(TARGET_DIR)/N_$(TARGET_DIR).dat
TARGET_A     = $(TARGET_DIR)/A_$(TARGET_DIR).dat
TARGET_B     = $(TARGET_DIR)/B_$(TARGET_DIR).dat
TARGET_INPUT = $(TARGET_DIR)/input_$(TARGET_DIR).dat

# Outputs
BSVOUTPUT    = output.dat
PYOUTPUT     = output_python.dat

# Python helpers
PYDECODER    = Python_Viterbi.py
PYCOMPARE    = compare.py

# Simulator binary path
BSIM         = $(BUILDDIR)/$(TOPMODULE)_bsim

.PHONY: all generate_verilog b_sim run_bsim run_python compare test clean help \
        test_all test_full quick_test cleanall compare_ref list_tests setup_test_files

all: help

# ----------------------------------------------------
# setup_test_files
# Copies the files from $(TESTDIR) (can be a path) into $(TARGET_DIR)/
# Ensures the simulator always reads from fut/
# ----------------------------------------------------
setup_test_files:
	@echo "=========================================="
	@echo "Preparing test files"
	@echo " Source test dir: $(TESTDIR)"
	@echo " Target test dir: $(TARGET_DIR)"
	@echo "=========================================="
	@if [ "$(TESTDIR)" = "$(TARGET_DIR)" ]; then \
		if [ -f "$(TARGET_N)" ]; then \
			echo "  Using existing $(TARGET_DIR)/ files (no copy needed)"; \
		else \
			echo "❌ Error: Expected files in $(TARGET_DIR) not found"; exit 1; \
		fi; \
	else \
		mkdir -p $(TARGET_DIR); \
		echo "  Copying from: $(TESTDIR) -> $(TARGET_DIR)"; \
		if [ -f "$(NFILE)" ]; then cp -f "$(NFILE)" "$(TARGET_N)"; echo "   ✓ $(TARGET_N)"; else echo "   ❌ $(NFILE) not found"; exit 1; fi; \
		if [ -f "$(AFILE)" ]; then cp -f "$(AFILE)" "$(TARGET_A)"; echo "   ✓ $(TARGET_A)"; else echo "   ❌ $(AFILE) not found"; exit 1; fi; \
		if [ -f "$(BFILE)" ]; then cp -f "$(BFILE)" "$(TARGET_B)"; echo "   ✓ $(TARGET_B)"; else echo "   ❌ $(BFILE) not found"; exit 1; fi; \
		if [ -f "$(INPUTFILE)" ]; then cp -f "$(INPUTFILE)" "$(TARGET_INPUT)"; echo "   ✓ $(TARGET_INPUT)"; else echo "   ❌ $(INPUTFILE) not found"; exit 1; fi; \
		echo ""; \
		echo "  Verification - files in $(TARGET_DIR):"; ls -1 $(TARGET_DIR) || true; \
	fi
	@echo "=========================================="

# ----------------------------------------------------
# list_tests
# Show discovered tests (under $(TESTS_ROOT))
# ----------------------------------------------------
list_tests:
	@echo "======================================"
	@echo "Available test cases (in $(TESTS_ROOT)/)"
	@echo "======================================"
	@if [ -d "$(TESTS_ROOT)" ]; then \
		for test in $(DISCOVERED_TESTS); do \
			if [ -d "$(TESTS_ROOT)/$$test" ]; then \
				echo "  • $(TESTS_ROOT)/$$test"; \
			fi; \
		done; \
	else \
		echo "  (No $(TESTS_ROOT)/ directory found)"; \
	fi
	@echo ""
	@echo "Manual (default/target) test folders: fut, huge, small"
	@echo ""

# ----------------------------------------------------
# generate_verilog
# Verbose verilog generation (no redirection)
# ----------------------------------------------------
generate_verilog:
	@echo "===================================="
	@echo "Generating Verilog from BSV (verilog target)"
	@echo "TOPFILE: $(TOPFILE)"
	@echo "Output verilog dir: $(VERILOGDIR)"
	@echo "Build dir: $(BUILDDIR)"
	@echo "===================================="
	@mkdir -p $(VERILOGDIR) $(BUILDDIR)
	@bsc -u -verilog -elab \
		-vdir $(VERILOGDIR) -bdir $(BUILDDIR) -info-dir $(BUILDDIR) \
		+RTS -K4000M -RTS \
		-check-assert -keep-fires -opt-undetermined-vals \
		-remove-false-rules -remove-empty-rules -remove-starved-rules \
		-remove-dollar -unspecified-to X \
		-show-schedule -show-module-use \
		-suppress-warnings G0010:T0054:G0020:G0024:G0023:G0096:G0036:G0117:G0015 \
		-D $(BSCDEFINES) -p $(BSVINCDIR) $(TOPFILE)
	@echo "✓ Verilog generated in $(VERILOGDIR)"

# ----------------------------------------------------
# b_sim
# Compile BSV for simulation and emit simulator binary
# ----------------------------------------------------
b_sim:
	@echo "===================================="
	@echo "Compiling BSV for simulation..."
	@echo "TOPMODULE: $(TOPMODULE)"
	@echo "Build dir: $(BUILDDIR)"
	@echo "===================================="
	@mkdir -p $(BUILDDIR)
	@bsc -u -sim -elab \
		-simdir $(BUILDDIR) -bdir $(BUILDDIR) -info-dir $(BUILDDIR) \
		-g $(TOPMODULE) $(TOPFILE)
	@bsc -e $(TOPMODULE) -sim \
		-o $(BSIM) \
		-simdir $(BUILDDIR) -bdir $(BUILDDIR) -info-dir $(BUILDDIR)
	@echo "✓ BSV simulation binary created: $(BSIM)"

# ----------------------------------------------------
# run_bsim
# Run compiled simulator, requires setup_test_files
# ----------------------------------------------------
run_bsim: b_sim setup_test_files
	@echo "===================================="
	@echo "Running BSV simulation (reading from $(TARGET_DIR)/)"
	@echo "Test dir: $(TESTDIR) (mapped to $(TARGET_DIR))"
	@echo "Simulator: $(BSIM)"
	@echo "===================================="
	@if [ ! -x $(BSIM) ]; then \
		echo "❌ Error: Simulator $(BSIM) not found or not executable"; \
		ls -la $(BSIM) 2>/dev/null || true; \
		exit 1; \
	fi
	@echo "Simulator will read these files from $(TARGET_DIR):"
	@ls -lh $(TARGET_DIR)/*.dat || true
	@echo ""
	@$(BSIM)
	@if [ -f $(BSVOUTPUT) ]; then \
		bsv_lines=$$(wc -l < $(BSVOUTPUT) 2>/dev/null || echo 0); \
		echo "✓ BSV produced $(BSVOUTPUT) (lines: $$bsv_lines)"; \
	else \
		echo "❌ Error: BSV simulation did not produce $(BSVOUTPUT)"; \
		exit 1; \
	fi

# ----------------------------------------------------
# run_python
# Run Python implementation (uses original TESTDIR inputs)
# ----------------------------------------------------
run_python:
	@echo "===================================="
	@echo "Running Python decoder..."
	@echo "Using input files from: $(TESTDIR)"
	@echo "Command: python3 $(PYDECODER) $(NFILE) $(AFILE) $(BFILE) $(INPUTFILE) $(PYOUTPUT)"
	@echo "===================================="
	@if [ ! -f $(PYDECODER) ]; then \
		echo "❌ Error: $(PYDECODER) not found!"; \
		exit 1; \
	fi
	@python3 $(PYDECODER) $(NFILE) $(AFILE) $(BFILE) $(INPUTFILE) $(PYOUTPUT)
	@if [ -f $(PYOUTPUT) ]; then \
		py_lines=$$(wc -l < $(PYOUTPUT) 2>/dev/null || echo 0); \
		echo "✓ Python produced $(PYOUTPUT) (lines: $$py_lines)"; \
	else \
		echo "❌ Error: Python decoder did not produce $(PYOUTPUT)"; \
		exit 1; \
	fi

# ----------------------------------------------------
# compare
# Compare BSV output with Python output using compare script
# ----------------------------------------------------
compare:
	@echo "===================================="
	@echo "Comparing BSV vs Python outputs..."
	@echo "BSV: $(BSVOUTPUT)"
	@echo "PY : $(PYOUTPUT)"
	@echo "===================================="
	@if [ ! -f $(BSVOUTPUT) ]; then \
		echo "❌ Error: $(BSVOUTPUT) not found!"; \
		exit 1; \
	fi
	@if [ ! -f $(PYOUTPUT) ]; then \
		echo "❌ Error: $(PYOUTPUT) not found!"; \
		exit 1; \
	fi
	@python3 $(PYCOMPARE) $(BSVOUTPUT) $(PYOUTPUT)
	@echo "✓ Comparison finished"

# ----------------------------------------------------
# compare_ref
# Compare BSV output with reference output if present
# ----------------------------------------------------
compare_ref:
	@echo "===================================="
	@echo "Comparing with reference output (if available)..."
	@echo "Reference: $(REFOUTPUT)"
	@echo "===================================="
	@if [ ! -f $(REFOUTPUT) ]; then \
		echo "⚠ Reference $(REFOUTPUT) not found -> skipping reference check"; \
	else \
		python3 $(PYCOMPARE) $(REFOUTPUT) $(BSVOUTPUT); \
	fi

# ----------------------------------------------------
# test
# Full test: compile, simulate, python, compare
# Accepts TESTDIR (path or name). Example:
#   make test TESTDIR=test_cases/minimal
# ----------------------------------------------------
test: run_bsim run_python compare
	@echo "===================================="
	@echo "✅ TEST COMPLETE for: $(TESTDIR)"
	@echo " (Simulator reads from $(TARGET_DIR)/)"
	@echo "===================================="

# Full test with reference comparison
test_full: run_bsim run_python compare compare_ref
	@echo "===================================="
	@echo "✅ FULL TEST COMPLETE for: $(TESTDIR)"
	@echo "===================================="

# quick_test: skip recompilation if binary present
quick_test: setup_test_files
	@if [ ! -x $(BSIM) ]; then \
		$(MAKE) b_sim; \
	fi
	@$(MAKE) run_bsim run_python compare TESTDIR=$(TESTDIR)

# Run tests for every directory under $(TESTS_ROOT)
test_all: b_sim
	@echo "======================================"
	@echo "Running All Tests in: $(TESTS_ROOT)"
	@echo "======================================"
	@if [ ! -d "$(TESTS_ROOT)" ]; then \
		echo "❌ Error: $(TESTS_ROOT)/ directory not found!"; \
		echo "Create test cases first."; \
		exit 1; \
	fi
	@echo ""
	@passed=0; failed=0; total=0; \
	for test in $(DISCOVERED_TESTS); do \
		testdir="$(TESTS_ROOT)/$$test"; \
		if [ -d "$$testdir" ]; then \
			total=$$((total + 1)); \
			echo ""; \
			echo "--------------------------------------"; \
			echo " Test $$total: $$test"; \
			echo "--------------------------------------"; \
			if $(MAKE) --no-print-directory test TESTDIR="$$testdir" 2>&1 | tee /tmp/test_output_$$$$.log | grep -q "TEST COMPLETE"; then \
				passed=$$((passed + 1)); \
				echo "  ✅ $$test PASSED"; \
			else \
				failed=$$((failed + 1)); \
				echo "  ❌ $$test FAILED (see output)"; \
			fi; \
			rm -f /tmp/test_output_$$$$.log; \
		fi; \
	done; \
	echo ""; \
	echo "======================================"; \
	echo "Summary: $$passed/$$total passed, $$failed failed"; \
	echo "======================================"; \
	[ $$failed -eq 0 ]

# ----------------------------------------------------
# clean / cleanall
# ----------------------------------------------------
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILDDIR) $(VERILOGDIR) *.vcd $(BSVOUTPUT) $(PYOUTPUT)
	@echo "✓ Clean complete"

cleanall: clean
	@echo "Cleaning all generated files..."
	@rm -f output*.dat *.vcd
	@rm -rf test_results
	@echo "✓ All files cleaned"

# ----------------------------------------------------
# help
# More detailed help + common examples
# ----------------------------------------------------
help:
	@echo "======================================"
	@echo "Viterbi Decoder Makefile"
	@echo "======================================"
	@echo ""
	@echo "Quick start:"
	@echo "  make test                    # Run test using default TESTDIR=fut (maps to fut/)"
	@echo "  make test TESTDIR=huge      # Use local dir 'huge/'"
	@echo "  make test TESTDIR=test_cases/minimal  # Use a test-case directory path"
	@echo ""
	@echo "Build & generate:"
	@echo "  make generate_verilog        # Generate Verilog files from BSV (verbose)"
	@echo "  make b_sim                   # Compile BSV into a simulator binary"
	@echo "  make run_bsim TESTDIR=...    # Run compiled simulator (reads from fut/ by default)"
	@echo ""
	@echo "Testing:"
	@echo "  make test                    # Compile, run simulator, run Python, compare outputs"
	@echo "  make test_full               # As 'test' + compare with reference output if present"
	@echo "  make quick_test TESTDIR=...  # Skip recompilation if simulator binary exists"
	@echo "  make test_all                # Run all test directories under $(TESTS_ROOT)/"
	@echo "  make list_tests              # Show discovered test directories under $(TESTS_ROOT)/"
	@echo ""
	@echo "Utilities:"
	@echo "  make run_python              # Run Python decoder only"
	@echo "  make compare                 # Compare BSV output vs Python output"
	@echo "  make clean                   # Remove build artifacts"
	@echo "  make cleanall                # Remove all generated files and outputs"
	@echo ""
	@echo "Examples:"
	@echo "  make test TESTDIR=test_cases/minimal"
	@echo "  make test TESTDIR=test_cases/classic_hmm"
	@echo "  make generate_verilog"
	@echo ""

