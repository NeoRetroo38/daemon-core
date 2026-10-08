# POSIX build (macOS, Linux). Windows uses build.ps1.
#   make test      build and run the core tests
#   make service   build build/neo-cube-service
#   make smoke     run the service and exercise it end to end (needs curl, openssl)
CXX ?= c++
AR ?= ar
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Wpedantic -O2
BUILD := build
LIB := $(BUILD)/lib
PREFIX ?= $(HOME)/.local
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
SHARED_LIBRARY := $(LIB)/libneo_cube.dylib
SHARED_FLAGS := -dynamiclib -Wl,-install_name,@rpath/libneo_cube.dylib
else
SHARED_LIBRARY := $(LIB)/libneo_cube.so
SHARED_FLAGS := -shared
endif

.PHONY: all tests service library library-test library-consumer-test test smoke install clean

all: tests service library library-test library-consumer-test

$(BUILD):
	mkdir -p $(BUILD)

$(LIB): | $(BUILD)
	mkdir -p $(LIB)

tests: $(BUILD)/neo-cube-tests
service: $(BUILD)/neo-cube-service

$(BUILD)/neo-cube-tests: tests/core-tests.cpp src/core/cube.hpp | $(BUILD)
	$(CXX) $(CXXFLAGS) tests/core-tests.cpp -o $@

$(BUILD)/neo-cube-service: src/api/server.cpp src/core/cube.hpp | $(BUILD)
	$(CXX) $(CXXFLAGS) src/api/server.cpp -o $@

$(BUILD)/neo_cube_c_api.o: src/library/neo_cube_c_api.cpp include/scenarys/neo_cube.h src/core/cube.hpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -fPIC -DSCENARYS_NEO_CUBE_BUILD -Iinclude -c src/library/neo_cube_c_api.cpp -o $@

$(LIB)/libneo_cube.a: $(BUILD)/neo_cube_c_api.o | $(LIB)
	$(AR) rcs $@ $<

$(SHARED_LIBRARY): $(BUILD)/neo_cube_c_api.o | $(LIB)
	$(CXX) $(SHARED_FLAGS) $< -o $@

library: $(LIB)/libneo_cube.a $(SHARED_LIBRARY)

$(BUILD)/neo-cube-library-tests: tests/library-tests.cpp src/library/neo_cube_c_api.cpp include/scenarys/neo_cube.h src/core/cube.hpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -Iinclude tests/library-tests.cpp src/library/neo_cube_c_api.cpp -o $@

library-test: $(BUILD)/neo-cube-library-tests
	./$(BUILD)/neo-cube-library-tests

$(BUILD)/neo-cube-library-consumer-tests: tests/library-tests.cpp $(LIB)/libneo_cube.a include/scenarys/neo_cube.h | $(BUILD)
	$(CXX) $(CXXFLAGS) -Iinclude tests/library-tests.cpp $(LIB)/libneo_cube.a -o $@

library-consumer-test: $(BUILD)/neo-cube-library-consumer-tests
	./$(BUILD)/neo-cube-library-consumer-tests

test: $(BUILD)/neo-cube-tests
	./$(BUILD)/neo-cube-tests

smoke: $(BUILD)/neo-cube-service
	sh tests/smoke-posix.sh

install: library
	mkdir -p $(DESTDIR)$(PREFIX)/include/scenarys $(DESTDIR)$(PREFIX)/lib $(DESTDIR)$(PREFIX)/share/scenarys/neo-cube
	cp include/scenarys/neo_cube.h $(DESTDIR)$(PREFIX)/include/scenarys/
	cp $(LIB)/libneo_cube.a $(SHARED_LIBRARY) $(DESTDIR)$(PREFIX)/lib/
	cp package/manifest.json $(DESTDIR)$(PREFIX)/share/scenarys/neo-cube/

clean:
	rm -rf $(BUILD)
