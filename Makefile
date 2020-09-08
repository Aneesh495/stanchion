# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Root Build Automation Makefile

CC ?= clang
CFLAGS ?= -O2 -Wall -Wextra -Wno-unused-parameter -Iinclude -Ivendor/berry/src -Ivendor/berry/default
LDFLAGS ?= -lm

BERRY_DIR = vendor/berry
BIN_DIR = bin
BUILD_DIR = build

BERRY_BIN = $(BIN_DIR)/berry
STANCHION_BIN = $(BIN_DIR)/stanchion

BERRY_SRCS = $(wildcard $(BERRY_DIR)/src/*.c)
BERRY_DEFAULT_SRCS = $(BERRY_DIR)/default/be_modtab.c $(BERRY_DIR)/default/be_port.c
HOST_SRCS = src/stanchion_host.c

.PHONY: all clean test check run

all: $(BERRY_BIN) $(STANCHION_BIN)

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

$(BERRY_BIN): $(BIN_DIR)
	@echo "[Building Berry interpreter...]"
	@$(MAKE) -C $(BERRY_DIR)
	@cp $(BERRY_DIR)/berry $(BERRY_BIN)
	@echo "[Berry binary built: $(BERRY_BIN)]"

$(STANCHION_BIN): $(BIN_DIR) $(HOST_SRCS) $(BERRY_SRCS) $(BERRY_DEFAULT_SRCS)
	@echo "[Compiling Stanchion native host...]"
	@$(CC) $(CFLAGS) $(HOST_SRCS) $(BERRY_SRCS) $(BERRY_DEFAULT_SRCS) $(LDFLAGS) -o $(STANCHION_BIN)
	@echo "[Stanchion binary built: $(STANCHION_BIN)]"

test: all
	@echo "[Running test suites...]"
	@python3 scripts/run_tests.py

check:
	@echo "[Checking em-dash constraints...]"
	@python3 scripts/verify_no_em_dash.py
	@echo "[Checking lines of code...]"
	@python3 scripts/check_loc.py

run: all
	@./$(STANCHION_BIN) station/main.be

clean:
	@echo "[Cleaning build artifacts...]"
	@rm -rf $(BIN_DIR) $(BUILD_DIR)
	@$(MAKE) -C $(BERRY_DIR) clean
	@echo "[Clean completed]"
