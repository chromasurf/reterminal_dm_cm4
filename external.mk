include $(sort $(wildcard $(NERVES_DEFCONFIG_DIR)/package/*/*.mk))

# The built-in Goodix driver probes before the rootfs is mounted. CONFIG_EXTRA_FIRMWARE links its
# config into the kernel from $(LINUX_DIR)/firmware.
define RETERMINAL_DM_GOODIX_CFG
	$(INSTALL) -D -m 0644 $(NERVES_DEFCONFIG_DIR)/rootfs_overlay/lib/firmware/goodix_9271_cfg.bin \
		$(LINUX_DIR)/firmware/goodix_9271_cfg.bin
endef
LINUX_PRE_BUILD_HOOKS += RETERMINAL_DM_GOODIX_CFG
