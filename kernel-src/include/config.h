#pragma once

/*
 * DKMS helper config.
 *
 * For out-of-tree builds, tracepoint generation re-includes trace headers using
 * TRACE_INCLUDE_PATH. Kernel header-only build trees (/lib/modules/<kver>/build)
 * typically don't contain drivers/, so we provide an absolute-path helper.
 *
 * Keep this header minimal to avoid colliding with defines provided by the
 * vendored i915 snapshot.
 */

#ifndef DKMS_MODULE_SOURCE_DIR
#define DKMS_MODULE_SOURCE_DIR .
#endif

#define MODULE_ABS_PATH(path) DKMS_MODULE_SOURCE_DIR/path

/*
 * Compat helpers for building newer i915 snapshots on older kernels.
 * Keep these guarded to avoid clashing with definitions provided by the
 * target kernel headers when they exist.
 */

#include <linux/types.h>
#include <linux/version.h>
#include <linux/overflow.h>
#include <linux/errno.h>
#include <linux/iopoll.h>

/* ratelimit_state_get_miss() landed in v6.18; older kernels expose rs->missed directly. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
#include <linux/ratelimit.h>
#ifndef ratelimit_state_get_miss
static inline int ratelimit_state_get_miss(struct ratelimit_state *rs)
{
	return rs->missed;
}
#endif
#endif

#ifndef poll_timeout_us_atomic
#define poll_timeout_us_atomic(op, cond, delay_us, timeout_us, delay_before_op) \
	poll_timeout_us((op), (cond), (delay_us), (timeout_us), (delay_before_op))
#endif

/* Some older kernels only provide rdmsrl_safe(). */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
#ifndef rdmsrq_safe
#define rdmsrq_safe(msr, val) rdmsrl_safe((msr), (val))
#endif
#endif

#ifndef range_overflows_t
#define range_overflows_t(type, start, size, limit) \
({ \
	type __start = (type)(start); \
	type __size = (type)(size); \
	type __limit = (type)(limit); \
	type __end; \
	bool __overflow = check_add_overflow(__start, __size, &__end); \
	__overflow || __end > __limit; \
})
#endif

#ifndef range_end_overflows
#define range_end_overflows(start, size, max) ({ \
	typeof(start) start__ = (start); \
	typeof(size) size__ = (size); \
	typeof(max) max__ = (max); \
	(void)(&start__ == &size__); \
	(void)(&start__ == &max__); \
	start__ > max__ || size__ > max__ - start__; \
})
#endif

#ifndef range_end_overflows_t
#define range_end_overflows_t(type, start, size, max) \
	range_end_overflows((type)(start), (type)(size), (type)(max))
#endif

#ifndef BIT_U32
#define BIT_U32(nr) ((u32)1U << (nr))
#endif

#ifndef BIT_U16
#define BIT_U16(nr) ((u16)1U << (nr))
#endif

#ifndef BIT_U8
#define BIT_U8(nr) ((u8)1U << (nr))
#endif

#ifndef GENMASK_U32
#include <linux/bits.h>
#define GENMASK_U32(h, l) ((u32)GENMASK(h, l))
#endif

#ifndef GENMASK_U16
#include <linux/bits.h>
#define GENMASK_U16(h, l) ((u16)GENMASK(h, l))
#endif

#ifndef GENMASK_U8
#include <linux/bits.h>
#define GENMASK_U8(h, l) ((u8)GENMASK(h, l))
#endif

#ifndef GENMASK_U64
#include <linux/bits.h>
#define GENMASK_U64(h, l) ((u64)GENMASK_ULL(h, l))
#endif

/* Some trees expose range_overflows as a macro; keep ours as an inline helper. */
#ifndef range_overflows
static inline bool range_overflows(u64 start, u64 size, u64 limit)
{
	return range_overflows_t(u64, start, size, limit);
}
#endif

#include <linux/hrtimer.h>
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
#ifndef hrtimer_setup
#define hrtimer_setup(timer, callback, clock_id, mode) \
do { \
	hrtimer_init((timer), (clock_id), (mode)); \
	(timer)->function = (callback); \
} while (0)
#endif
#endif

#include <linux/timer.h>
#ifndef timer_container_of
#define timer_container_of(var, timer, timer_fieldname) \
	container_of(timer, typeof(*var), timer_fieldname)
#endif

#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
#ifndef timer_destroy_on_stack
#define timer_destroy_on_stack(timer) destroy_timer_on_stack(timer)
#endif
#endif

#include <linux/dma-fence.h>
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
#ifndef dma_fence_driver_name
static inline const char *dma_fence_driver_name(struct dma_fence *fence)
{
	if (!fence || !fence->ops || !fence->ops->get_driver_name)
		return "unknown";
	return fence->ops->get_driver_name(fence);
}
#endif
#endif

#include <linux/kthread.h>
#ifndef kthread_run_worker
#define kthread_run_worker(flags, namefmt, ...) \
	kthread_create_worker((flags), (namefmt), ## __VA_ARGS__)
#endif

#include <linux/fs.h>
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
#ifndef vfs_mmap
static inline int vfs_mmap(struct file *file, struct vm_area_struct *vma)
{
	return file->f_op->mmap(file, vma);
}
#endif
#endif

#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
#ifndef dma_fence_timeline_name
static inline const char *dma_fence_timeline_name(struct dma_fence *fence)
{
	if (!fence || !fence->ops || !fence->ops->get_timeline_name)
		return "unknown";
	return fence->ops->get_timeline_name(fence);
}
#endif
#endif

/* drm_client_dev_* helpers evolved over time and moved to drm_client_event.h. */
#include <drm/drm_client.h>
#include <drm/drm_drv.h>
#include <drm/drm_print.h>

#if defined(__has_include)
#if __has_include(<drm/drm_client_event.h>)
#include <drm/drm_client_event.h>
#define I915_DKMS_HAVE_DRM_CLIENT_EVENT_H 1
#endif
#endif

#ifndef I915_DKMS_HAVE_DRM_CLIENT_EVENT_H
static inline void drm_client_dev_unregister(struct drm_device *dev)
{
	(void)dev;
}

static inline void drm_client_dev_suspend(struct drm_device *dev, bool holds_console_lock)
{
	(void)dev;
	(void)holds_console_lock;
}

static inline void drm_client_dev_resume(struct drm_device *dev, bool holds_console_lock)
{
	(void)dev;
	(void)holds_console_lock;
}
#endif

/* drm_gem.h status flags evolve; older kernels don't have ACTIVE. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
#ifndef DRM_GEM_OBJECT_ACTIVE
#define DRM_GEM_OBJECT_ACTIVE 0
#endif
#endif

/* Newer <drm/intel/pciids.h> provides these ID list macros; 6.12 may not. */
#ifndef INTEL_MTL_U_IDS
#define INTEL_MTL_U_IDS(MACRO__, ...) \
	MACRO__(0x7D40, ## __VA_ARGS__), \
	MACRO__(0x7D45, ## __VA_ARGS__)
#endif

#ifndef INTEL_PTL_IDS
#define INTEL_PTL_IDS(MACRO__, ...) \
	MACRO__(0xB080, ## __VA_ARGS__), \
	MACRO__(0xB081, ## __VA_ARGS__), \
	MACRO__(0xB082, ## __VA_ARGS__), \
	MACRO__(0xB083, ## __VA_ARGS__), \
	MACRO__(0xB084, ## __VA_ARGS__), \
	MACRO__(0xB085, ## __VA_ARGS__), \
	MACRO__(0xB086, ## __VA_ARGS__), \
	MACRO__(0xB087, ## __VA_ARGS__), \
	MACRO__(0xB08F, ## __VA_ARGS__), \
	MACRO__(0xB090, ## __VA_ARGS__), \
	MACRO__(0xB0A0, ## __VA_ARGS__), \
	MACRO__(0xB0B0, ## __VA_ARGS__)
#endif

#ifndef INTEL_WCL_IDS
#define INTEL_WCL_IDS(MACRO__, ...) \
	MACRO__(0xFD80, ## __VA_ARGS__), \
	MACRO__(0xFD81, ## __VA_ARGS__)
#endif

/* DisplayPort constants: newer kernels provide these in drm_dp.h. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
/* DP Replay cap size constant exists in newer drm_dp.h. */
#ifndef DP_PANEL_REPLAY_CAP_SIZE
#define DP_PANEL_REPLAY_CAP_SIZE 7
#endif

/* eDP version/caps constants (missing from older drm_dp.h). */
#ifndef DP_EDP_15
#define DP_EDP_15 0x06 /* eDP 1.5 */
#endif

#ifndef DP_EDP_SMOOTH_BRIGHTNESS_CAPABLE
#define DP_EDP_SMOOTH_BRIGHTNESS_CAPABLE (1 << 6) /* eDP 2.0 */
#endif

/* DP Panel Replay DPCD registers/bits (missing from older drm_dp.h). */
#ifndef DP_PANEL_REPLAY_CAP_SUPPORT
#define DP_PANEL_REPLAY_CAP_SUPPORT 0x0b0
#endif

#ifndef DP_PANEL_REPLAY_CAP_CAPABILITY
#define DP_PANEL_REPLAY_CAP_CAPABILITY 0x0b1
#endif

#ifndef DP_PANEL_REPLAY_ASYNC_VIDEO_TIMING_NOT_SUPPORTED_IN_PR
#define DP_PANEL_REPLAY_ASYNC_VIDEO_TIMING_NOT_SUPPORTED_IN_PR (1 << 3)
#endif

#ifndef DP_PANEL_REPLAY_LINK_OFF_SUPPORTED_IN_PR_AFTER_ADAPTIVE_SYNC_SDP
#define DP_PANEL_REPLAY_LINK_OFF_SUPPORTED_IN_PR_AFTER_ADAPTIVE_SYNC_SDP (1 << 7)
#endif

#ifndef DP_PANEL_REPLAY_CAP_X_GRANULARITY
#define DP_PANEL_REPLAY_CAP_X_GRANULARITY 0x0b2
#endif

#ifndef DP_PANEL_REPLAY_CAP_Y_GRANULARITY
#define DP_PANEL_REPLAY_CAP_Y_GRANULARITY 0x0b4
#endif
#endif

/* drm_dp_dpcd_read_data()/read_byte() helpers were introduced after 6.12. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
#include <drm/display/drm_dp_helper.h>
static inline int drm_dp_dpcd_read_data(struct drm_dp_aux *aux,
					unsigned int offset,
					void *buffer, size_t size)
{
	int ret;

	ret = drm_dp_dpcd_read(aux, offset, buffer, size);
	if (ret < 0)
		return ret;
	if (ret < size)
		return -EPROTO;

	return 0;
}

static inline int drm_dp_dpcd_read_byte(struct drm_dp_aux *aux,
					unsigned int offset, u8 *valuep)
{
	return drm_dp_dpcd_read_data(aux, offset, valuep, 1);
}
#endif

/* DP helpers introduced after 6.12. Provide build-time fallbacks. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 14, 0)
struct drm_dp_aux;
static inline int drm_dp_dpcd_write_payload(struct drm_dp_aux *aux,
					   int vcpid,
					   u8 start_time_slot,
					   u8 time_slot_count)
{
	(void)aux;
	(void)vcpid;
	(void)start_time_slot;
	(void)time_slot_count;
	return 0;
}

static inline int drm_dp_dpcd_poll_act_handled(struct drm_dp_aux *aux,
					 int timeout_ms)
{
	(void)aux;
	(void)timeout_ms;
	return 0;
}
#endif

#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 15, 0)
struct drm_dp_aux;
static inline int drm_dp_lttpr_init(struct drm_dp_aux *aux, int lttpr_count)
{
	(void)aux;
	(void)lttpr_count;
	return 0;
}

static inline void drm_dp_lttpr_wake_timeout_setup(struct drm_dp_aux *aux,
					   bool transparent_mode)
{
	(void)aux;
	(void)transparent_mode;
}
#endif

/* drm_dp_link_symbol_cycles() was introduced after older LTS kernels. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
#include <linux/kernel.h>
static inline int drm_dp_link_data_symbol_cycles(int lane_count, int pixels,
					 int bpp_x16, int symbol_size,
					 bool is_mst)
{
	int cycles = DIV_ROUND_UP(pixels * bpp_x16, 16 * symbol_size * lane_count);
	int align = is_mst ? 4 / lane_count : 1;

	return ALIGN(cycles, align);
}

static inline int drm_dp_link_symbol_cycles(int lane_count, int pixels,
					    int dsc_slice_count,
					    int bpp_x16, int symbol_size,
					    bool is_mst)
{
	int slice_count = dsc_slice_count ? dsc_slice_count : 1;
	int slice_pixels = DIV_ROUND_UP(pixels, slice_count);
	int slice_data_cycles = drm_dp_link_data_symbol_cycles(lane_count,
							       slice_pixels,
							       bpp_x16,
							       symbol_size,
							       is_mst);
	int slice_eoc_cycles = 0;

	if (dsc_slice_count)
		slice_eoc_cycles = is_mst ? 4 / lane_count : 1;

	return slice_count * (slice_data_cycles + slice_eoc_cycles);
}
#endif

/* DPCD probe quirk helpers were introduced in v6.17. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 17, 0)
struct drm_dp_aux;
static inline void drm_dp_dpcd_set_probe(struct drm_dp_aux *aux, bool enable)
{
	(void)aux;
	(void)enable;
}

struct drm_connector;

#ifndef DRM_EDID_QUIRK_DP_DPCD_PROBE
#define DRM_EDID_QUIRK_DP_DPCD_PROBE 0
#endif

static inline bool drm_edid_has_quirk(const struct drm_connector *connector,
				     u32 quirk)
{
	(void)connector;
	(void)quirk;
	return false;
}
#endif

/* drm_print_hex_dump() exists in newer DRM core; only provide a fallback on older kernels. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
static inline void drm_print_hex_dump(struct drm_printer *p, const char *prefix,
			      const void *buf, size_t len)
{
	const u8 *data = buf;
	size_t i;

	if (!p || !data)
		return;

	for (i = 0; i < len; i++) {
		if (!(i % 16))
			drm_printf(p, "%s", prefix);
		drm_printf(p, "%02x%s", data[i], (i % 16) == 15 || i == len - 1 ? "\n" : " ");
	}
}
#endif

#include <linux/iopoll.h>
#ifndef poll_timeout_us
#define poll_timeout_us(op, cond, sleep_us, timeout_us, sleep_before_read) \
({ \
	u64 __timeout_us = (timeout_us); \
	unsigned long __sleep_us = (sleep_us); \
	ktime_t __timeout = ktime_add_us(ktime_get(), __timeout_us); \
	int __ret = 0; \
	might_sleep_if((__sleep_us) != 0); \
	if ((sleep_before_read) && __sleep_us) \
		usleep_range((__sleep_us >> 2) + 1, __sleep_us); \
	for (;;) { \
		op; \
		if (cond) { \
			__ret = 0; \
			break; \
		} \
		if (__timeout_us && ktime_compare(ktime_get(), __timeout) > 0) { \
			op; \
			__ret = (cond) ? 0 : -ETIMEDOUT; \
			break; \
		} \
		if (__sleep_us) \
			usleep_range((__sleep_us >> 2) + 1, __sleep_us); \
		cpu_relax(); \
	} \
	__ret; \
})
#endif

/* DRM "wedged" notification helpers arrived in newer DRM core. */
#ifndef DRM_WEDGE_RECOVERY_NONE
#define DRM_WEDGE_RECOVERY_NONE BIT(0)
#endif
#ifndef DRM_WEDGE_RECOVERY_REBIND
#define DRM_WEDGE_RECOVERY_REBIND BIT(1)
#endif
#ifndef DRM_WEDGE_RECOVERY_BUS_RESET
#define DRM_WEDGE_RECOVERY_BUS_RESET BIT(2)
#endif
#ifndef DRM_WEDGE_RECOVERY_VENDOR
#define DRM_WEDGE_RECOVERY_VENDOR BIT(3)
#endif

struct drm_wedge_task_info;
/* drm_dev_wedged_event() exists in newer DRM core; only provide a fallback on older kernels. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
static inline int drm_dev_wedged_event(struct drm_device *dev, unsigned long method,
			       struct drm_wedge_task_info *info)
{
	(void)dev;
	(void)method;
	(void)info;
	return 0;
}
#endif
