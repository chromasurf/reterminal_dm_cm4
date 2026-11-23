################################################################################
#
# ltr30x
#
################################################################################

LTR30X_VERSION = 1.0
LTR30X_SITE = $(NERVES_DEFCONFIG_DIR)/package/ltr30x/src
LTR30X_SITE_METHOD = local

$(eval $(kernel-module))
$(eval $(generic-package))
