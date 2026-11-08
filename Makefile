CXX ?= c++
CPPFLAGS += -IAlphaSync/Driver -IAlphaSync/Library
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Wpedantic -Werror -Wno-unknown-pragmas -g

CORE_SOURCES := $(filter-out AlphaSync/Driver/ASDeviceFactory.cc,$(wildcard AlphaSync/Driver/*.cc))
CORE_HEADERS := $(wildcard AlphaSync/Driver/*.h AlphaSync/Library/*.h)
TEST_SOURCES := $(wildcard tests/*.cc)

.PHONY: test sanitize clean

test: build/core-tests
	./build/core-tests

sanitize: build/core-tests-sanitize
	./build/core-tests-sanitize

build/core-tests: $(CORE_SOURCES) $(CORE_HEADERS) $(TEST_SOURCES) Makefile
	@mkdir -p build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(CORE_SOURCES) $(TEST_SOURCES) -o $@

build/core-tests-sanitize: $(CORE_SOURCES) $(CORE_HEADERS) $(TEST_SOURCES) Makefile
	@mkdir -p build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -O1 -fsanitize=address,undefined -fno-omit-frame-pointer $(CORE_SOURCES) $(TEST_SOURCES) -o $@

clean:
	rm -rf build

ifeq ($(shell uname -s),Darwin)
.PHONY: test-xml test-files test-reports test-queue test-text
test: test-xml test-files test-reports test-queue test-text

test-xml: build/xml-tests
	./build/xml-tests

build/xml-tests: $(CORE_SOURCES) $(CORE_HEADERS) tests/xml-tests.mm Makefile
	@mkdir -p build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(CORE_SOURCES) tests/xml-tests.mm -framework Foundation -o $@
endif

ifeq ($(shell uname -s),Darwin)
test-files: build/file-tests
	./build/file-tests

build/file-tests: tests/file-tests.mm AlphaSync/Library/AQFileUtilities.m AlphaSync/Library/AQFileUtilities.h Makefile
	@mkdir -p build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -fblocks -x objective-c++ tests/file-tests.mm AlphaSync/Library/AQFileUtilities.m -framework Cocoa -o $@
endif

ifeq ($(shell uname -s),Darwin)
test-reports: build/report-tests
	./build/report-tests

build/report-tests: tests/report-tests.mm AlphaSync/Application/ASBackupReport.mm AlphaSync/Application/ASBackupReport.h AlphaSync/Library/AQFileUtilities.m AlphaSync/Library/AQFileUtilities.h Makefile
	@mkdir -p build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -x objective-c++ tests/report-tests.mm AlphaSync/Application/ASBackupReport.mm AlphaSync/Library/AQFileUtilities.m -framework Cocoa -o $@
endif

ifeq ($(shell uname -s),Darwin)
QUEUE_SOURCES := $(addprefix AlphaSync/Application/,ASDeviceController.mm ASDeviceNode.mm ASAppletNode.mm ASFileNode.mm ASNode.mm ASLoadSaveProtocol.mm ASPreferenceController.mm)
test-queue: build/queue-tests
	./build/queue-tests

test-text: build/text-tests
	./build/text-tests

build/device-factory.o: AlphaSync/Driver/ASDeviceFactory.cc $(CORE_HEADERS) Makefile
	@mkdir -p build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

build/queue-tests build/text-tests: build/%: tests/%.mm $(QUEUE_SOURCES) $(wildcard AlphaSync/Application/*.h) $(CORE_SOURCES) $(CORE_HEADERS) build/device-factory.o AlphaSync/Library/AQTreeNode.m AlphaSync/Library/AQFileUtilities.m Makefile
	@mkdir -p build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -fblocks -x objective-c++ $< $(QUEUE_SOURCES) $(CORE_SOURCES) AlphaSync/Library/AQTreeNode.m AlphaSync/Library/AQFileUtilities.m -x none build/device-factory.o -framework Cocoa -framework IOKit -framework ServiceManagement -framework UniformTypeIdentifiers -o $@
endif
