#!/bin/bash
# PORTMASTER: insaniquarium.zip, Insaniquarium Deluxe.sh

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt

[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

get_controls

GAMEDIR="/$directory/ports/insaniquarium"
BINARY="Insaniquarium"

cd "$GAMEDIR"

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

$ESUDO chmod +x "$GAMEDIR/$BINARY"

export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export LD_LIBRARY_PATH="$GAMEDIR/libs.aarch64:$LD_LIBRARY_PATH"

# There is no PulseAudio server here and both SDL and OpenAL probe it first,
# which is where "Failed to create secure directory (/run/user/.../pulse)" in
# the log comes from. Point them straight at ALSA.
#
# Using :- so the CFW's control.txt keeps priority if it already set these.
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"
export ALSOFT_DRIVERS="${ALSOFT_DRIVERS:-alsa}"

# Larger OpenAL audio buffer, see alsoft.conf. The stock one is small enough
# that any hitch in the game breaks the music up.
export ALSOFT_CONF="$GAMEDIR/alsoft.conf"

# TEMPORARY, while tracking down the freeze some buttons cause: log every key
# event the game receives and how long it takes to handle it. Remove once that
# is resolved.
export POPLIB_LOG_KEYS=1

# The game starts windowed and remembers that choice, but there is no desktop
# here to put a window on, nor a way to reach the options screen beforehand.
export POPLIB_FULLSCREEN=1

# The game draws the pointer itself. There is no desktop cursor here, and under
# KMSDRM the system one depends on the DRM driver exposing a cursor plane, which
# RK3326 does not. Without this the gamepad moves an invisible mouse in a game
# that is entirely pointer driven.
#
# The binary detects this by itself when SDL uses KMSDRM; forced anyway, since
# not every firmware uses that backend and guessing wrong makes the game
# unplayable.
export POPLIB_SOFTWARE_CURSOR=1

# Profiles and high scores inside the port folder rather than /root/.config: on
# several firmwares the system partition is read-only, and this way deleting the
# port removes everything and copying it to another card keeps the saves.
export XDG_CONFIG_HOME="$GAMEDIR/conf"
mkdir -p "$XDG_CONFIG_HOME"

# --------------------------------------------------------------- game files
#
# The port does not ship them: they belong to PopCap and come from the user's
# own copy. Without them there is nothing to run, and a message beats a black
# screen.
if [ ! -f "$GAMEDIR/properties/resources.xml" ] || [ ! -d "$GAMEDIR/images" ]; then
  MSG="Copy the data, images, music, properties, sounds and fishsongs folders from your Insaniquarium Deluxe to $GAMEDIR"
  if type pm_show_error >/dev/null 2>&1; then
    pm_show_error "Game files missing" "$MSG"
  else
    pm_message "$MSG"
    sleep 5
  fi
  pm_finish
  exit 1
fi

# --------------------------------------------------------------- the pointer
#
# The game is entirely pointer driven, so the gamepad acts as a mouse (see the
# .gptk). Speed scales with the screen: the same stick deflection should cover
# the same fraction of the screen at 480p and at 720p, or the pointer crawls on
# the bigger one and bolts on the smaller.
if [ "$DISPLAY_WIDTH" -gt 720 ]; then
  MOUSE_SCALE=4000
  MOUSE_DELAY=8
  DPAD_STEP=5
else
  MOUSE_SCALE=6000
  MOUSE_DELAY=16
  DPAD_STEP=4
fi
sed -i "s/^mouse_scale *= *[0-9]\+/mouse_scale = $MOUSE_SCALE/"       "$GAMEDIR/insaniquarium.gptk"
sed -i "s/^mouse_delay *= *[0-9]\+/mouse_delay = $MOUSE_DELAY/"       "$GAMEDIR/insaniquarium.gptk"
sed -i "s/^dpad_mouse_step *= *[0-9]\+/dpad_mouse_step = $DPAD_STEP/" "$GAMEDIR/insaniquarium.gptk"

# ------------------------------------------------------------------- launch
$GPTOKEYB "$BINARY" -c "$GAMEDIR/insaniquarium.gptk" &

if type pm_platform_helper >/dev/null 2>&1; then
  pm_platform_helper "$GAMEDIR/$BINARY" >/dev/null
fi

./"$BINARY"

pm_finish
