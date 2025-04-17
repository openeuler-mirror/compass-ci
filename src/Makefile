SOURCES := $(wildcard *.cr */*.cr)
TARGET_DIR := ../sbin
TARGET := $(TARGET_DIR)/scheduler

# Build options
STATIC ?= false
STATIC_FLAG := $(if $(filter true 1,$(STATIC)),--static,)

# Phony targets
.PHONY: all debug debug-trace release clean cscope

all: debug

release: $(TARGET)
debug: $(TARGET)-debug
debug-trace: $(TARGET)-debug-trace

# Rule for building the release target
$(TARGET): $(SOURCES)
	@mkdir -p $(TARGET_DIR)
	crystal build -o $@ scheduler.cr --release $(STATIC_FLAG)

# Rule for building the debug target
$(TARGET)-debug: $(SOURCES)
	@mkdir -p $(TARGET_DIR)
	crystal build -o $@ scheduler.cr $(STATIC_FLAG)

# Rule for building the debug-trace target
$(TARGET)-debug-trace: $(SOURCES)
	@mkdir -p $(TARGET_DIR)
	crystal build -o $@ scheduler.cr --error-trace $(STATIC_FLAG)

# Rule for generating cscope files
cscope:
	@echo "$(SOURCES)" > cscope.files
	cscope -b -q -k

# Rule for cleaning up build artifacts
clean:
	rm -f $(TARGET) $(TARGET)-debug $(TARGET)-debug-trace
