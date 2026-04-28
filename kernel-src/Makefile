# SPDX-License-Identifier: GPL-2.0

# External-module wrapper for DKMS.
# The actual driver lives at drivers/gpu/drm/i915/

LINUXINCLUDE := \
	-I$(src)/include \
	-idirafter $(src)/compat/include \
	$(LINUXINCLUDE) \
	-include $(src)/include/config.h

# Absolute path to this DKMS module source tree (used by MODULE_ABS_PATH()).
subdir-ccflags-y += -DDKMS_MODULE_SOURCE_DIR='$(abspath $(src))'

obj-m += drivers/gpu/drm/i915/
