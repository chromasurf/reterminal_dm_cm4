################################################################################
#
# mipi-dsi 
#
################################################################################

MIPI_DSI_VERSION = 1.1
MIPI_DSI_SITE = $(NERVES_DEFCONFIG_DIR)/package/mipi-dsi/src
MIPI_DSI_SITE_METHOD = local

$(eval $(kernel-module))
$(eval $(generic-package))
