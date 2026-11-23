################################################################################
#
# ch34x
#
################################################################################

CH34X_VERSION = 1.0
CH34X_SITE = $(NERVES_DEFCONFIG_DIR)/package/ch34x/src
CH34X_SITE_METHOD = local

$(eval $(kernel-module))
$(eval $(generic-package))
