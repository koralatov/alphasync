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
.PHONY: test-xml
test: test-xml

test-xml: build/xml-tests
	./build/xml-tests

build/xml-tests: $(CORE_SOURCES) $(CORE_HEADERS) tests/xml-tests.mm Makefile
	@mkdir -p build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(CORE_SOURCES) tests/xml-tests.mm -framework Foundation -o $@
endif
