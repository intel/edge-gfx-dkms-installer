/* Compatibility shim for out-of-tree i915 builds.
 *
 * Some kernel header trees (especially older ones) don't ship
 * <drm/drm_client_event.h>, but newer i915 snapshots include it.
 *
 * When building against newer kernels, the drm core provides these helpers;
 * when building against older kernels, treat them as no-ops.
 */

#ifndef _DRM_CLIENT_EVENT_H_
#define _DRM_CLIENT_EVENT_H_

#include <linux/version.h>
#include <linux/types.h>

#include <drm/drm_client.h>

struct drm_device;

/*
 * Newer i915 sources include <drm/drm_client_event.h> unconditionally, but not
 * all kernel header packages ship that header.
 *
 * Provide prototypes for the helpers i915 uses.
 *
 * Note: do not provide inline no-op implementations here; some kernels already
 * declare these helpers in <drm/drm_client.h>, and inline stubs would conflict.
 */
void drm_client_dev_unregister(struct drm_device *dev);
void drm_client_dev_hotplug(struct drm_device *dev);
void drm_client_dev_restore(struct drm_device *dev);

/*
 * These helpers were introduced after v6.12; when building against older DRM
 * cores, treat them as no-ops.
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 13, 0)
static inline void drm_client_dev_suspend(struct drm_device *dev, bool holds_console_lock) { }
static inline void drm_client_dev_resume(struct drm_device *dev, bool holds_console_lock) { }
#else
void drm_client_dev_suspend(struct drm_device *dev, bool holds_console_lock);
void drm_client_dev_resume(struct drm_device *dev, bool holds_console_lock);
#endif

#endif /* _DRM_CLIENT_EVENT_H_ */
