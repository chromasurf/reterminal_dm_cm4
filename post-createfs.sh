#!/bin/sh

set -e

FWUP_CONFIG=$NERVES_DEFCONFIG_DIR/fwup.conf

# The Pi firmware unpacks a gzip kernel itself and reads less from the eMMC.
gzip -9 -n -c "$BINARIES_DIR/Image" > "$BINARIES_DIR/kernel8.img.gz"

# Run the common post-image processing for nerves
$BR2_EXTERNAL_NERVES_PATH/board/nerves-common/post-createfs.sh $TARGET_DIR $FWUP_CONFIG
