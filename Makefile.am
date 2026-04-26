## Copyright (C) 2017  Trevor Woerner <twoerner@gmail.com>

SUBDIRS =
DIST_SUBDIRS = cfg

AM_CPPFLAGS = -Wall -Werror -Wextra -Wreturn-type -fno-strict-aliasing -D_FILE_OFFSET_BITS=64 -D_LARGE_FILE $(LIBUSB1_CFLAGS)

bin_PROGRAMS = rk-flashtool
rk_flashtool_SOURCES = src/main.cpp \
	src/crc.cpp src/DefineHeader.h src/Endian.h src/Property.hpp \
	src/RKBoot.cpp src/RKBoot.h \
	src/RKComm.cpp src/RKComm.h \
	src/RKDevice.cpp src/RKDevice.h \
	src/RKImage.cpp src/RKImage.h \
	src/RKLog.cpp src/RKLog.h \
	src/RKScan.cpp src/RKScan.h \
	src/boot_merger.h src/gpt.h
rk_flashtool_LDADD = $(LIBUSB1_LIBS)

clean-local::
	rm -fr log
