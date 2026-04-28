# SPDX-License-Identifier: GPL-2.0

# Top-level external-module wrapper.
# The extracted kernel sources live under kernel-src/.

LINUXINCLUDE := \
	-I$(src)/kernel-src/include \
	-I$(src)/kernel-src/drivers/gpu/drm/i915 \
	-idirafter $(src)/kernel-src/compat/include \
	$(LINUXINCLUDE) \
	-include $(src)/kernel-src/include/config.h

# Absolute path to this DKMS module source tree (used by MODULE_ABS_PATH()).
subdir-ccflags-y += -DDKMS_MODULE_SOURCE_DIR='$(abspath $(src))/kernel-src'

# Trace event headers (trace/define_trace.h) will re-include the trace header
# using TRACE_INCLUDE_PATH relative to the kernel tree. Ensure the DKMS snapshot
# trace headers are reachable via an include path (see LINUXINCLUDE above).

obj-m += kernel-src/drivers/gpu/drm/i915/
