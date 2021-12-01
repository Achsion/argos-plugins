#!/bin/bash

# some default values
SPOTIFY_DEST="org.mpris.MediaPlayer2.spotify"
SPOTIFY_PATH="/org/mpris/MediaPlayer2"
SPOTIFY_MEMB="org.mpris.MediaPlayer2.Player"

# directories and files
WORKING_DIRECTORY="${0%/*}"
SETTINGS_DIRECTORY="${WORKING_DIRECTORY}/settings"
SETTINGS_FILE="${SETTINGS_DIRECTORY}/$(basename "${0}" | sed -E 's/\..*$//')"

# eval setting variables playceholder
SETTING_PLAYLIST_URI=""
SETTING_START_WINDOW="show"

# eval spotify metadata variables placeholder
SPOTIFY_CURRENT_TRACKNUMBER="---"
SPOTIFY_CURRENT_TRACKID="---"
SPOTIFY_CURRENT_TITLE="---"
SPOTIFY_CURRENT_ARTIST="---"
SPOTIFY_CURRENT_ALBUM="---"
SPOTIFY_CURRENT_ALBUMARTIST="---"


# SETTINGS #############################################################################################################

if [ ! -d "${SETTINGS_DIRECTORY}" ]
then
    mkdir -p "${SETTINGS_DIRECTORY}"
fi
if [ ! -f "${SETTINGS_FILE}" ]
then
    touch "${SETTINGS_FILE}"
fi

function apply-settings() {
    # read settings from file
    #TODO: maybe read setting variables with sed or smth else
    while read -r LINE
    do
        # TODO: do i really want to use the settings file to eval the settings?
        eval "${LINE}"
    done < "${SETTINGS_FILE}"
}

#TODO
#function save-settings() {
#}

apply-settings


# Spotify default window/process functions #############################################################################

function is-spotify-running() {
  if [ "$(pgrep -c "spotify")" -le 1 ]
  then
    return 1
  fi

  return 0
}

# get spotify window id
function spotify-window-id() {
    #TODO: can this search be made case sensitive?
    #TODO: this also doesnt work, i'll just dont use it for now
    xdotool search --name '^Spotify$'
}

function spotify-window-minimize() {
    spotify-window-id | xargs -L1 xdotool windowminimize
}

function spotify-window-hide() {
    spotify-window-id | xargs -L1 xdotool windowunmap
}

function spotify-window-show() {
    spotify-window-id | xargs -L1 xdotool windowmap
}

# start spotify with default playlist
function spotify-start() {
    if ! is-spotify-running
    then
        spotify 1>/dev/null 2>&1 &
        sleep 3

        case "${SETTING_START_WINDOW}" in
            'show' )
                spotify-window-show
                ;;
            'minimize' )
                spotify-window-minimize
                ;;
            'hide' )
                spotify-window-hide
                ;;
            * )
                spotify-window-show
                ;;
        esac
    fi

    dbus-send --session --type=method_call --dest=${SPOTIFY_DEST} ${SPOTIFY_PATH} "${SPOTIFY_MEMB}.OpenUri" "string:${SETTING_PLAYLIST_URI}"
}

function spotify-window-mappedStatus() {
    declare -a IDS

    while read -r line
    do
        IDS+=("$line")
    done <<< "$(xdotool search --name '^Spotify$')"

    for WINDOW_ID in "${IDS[@]}"
    do
        WINDOW_INFO=$(xargs -L1 xwininfo -id "${WINDOW_ID}")

        # use the colormap attribute to determine if its the window i want
        # this is due to a second window being active but not visible at all times, which has no colormap installed
        # another solution would be to only get the wanted window id but for that the search needs to be case sensitive
        if [ "$(grep -c "Colormap: 0x20 (installed)" <<< "${WINDOW_INFO}")" -ge "1" ]
        then
            grep "Map State:" <<< "${WINDOW_INFO}" \
            | sed -E 's/Map State://' \
            | sed -E 's/ *//'

            return 0
        fi
    done
}

function spotify-window-toggleMapping() {
    if [ "$(spotify-window-mappedStatus)" == 'IsViewable' ]
    then
        spotify-window-hide
    else
        spotify-window-show
    fi
}

function spotify-quit() {
    pkill spotify
}


# Spotify dbus functions ###############################################################################################

# prints the currently playing track in a parseable format
function spotify-metadata() {
    dbus-send --print-reply --session --dest=${SPOTIFY_DEST} ${SPOTIFY_PATH} org.freedesktop.DBus.Properties.Get string:"${SPOTIFY_MEMB}" string:'Metadata' \
    | grep -Ev "^method"                            `# Ignore the first line.`      \
    | grep -Eo '("(.*)")|(\b[0-9][a-zA-Z0-9.]*\b)'  `# Filter interesting fields.`  \
    | sed -E '2~2 a|||'                             `# Mark odd fields.`            \
    | tr -d '\n'                                    `# Remove all newlines.`        \
    | sed -E 's/\|\|\|/\n/g'                        `# Restore newlines.`           \
    | sed -E 's/(xesam:)|(mpris:)//'                `# Remove ns prefixes.`         \
    | sed -E 's/^"//'                               `# Strip leading quotes`        \
    | sed -E 's/"$//'                               `# ...and trailing quotes.`     \
    | sed -E 's/"+/|/'                              `# Replace "" with a seperator.`\
    | sed -E 's/"/\\"/g'                            `# Escape remaining quotes`     \
    | sed -E 's/ +/ /g';                            `# Merge consecutive spaces.`
}

# prints the currently playing track as shell variables, ready to be eval'ed
function spotify-eval() {
    spotify-metadata \
    | grep --color=never -E "(title)|(album)|(artist)|(trackid)|(trackNumber)" \
    | sort -r \
    | sed 's/^\([^|]*\)\|/\U\1/' \
    | sed 's/"/\"/g' \
    | sed -E 's/\|/="/' \
    | sed -E 's/$/"/' \
    | sed -E 's/^/SPOTIFY_CURRENT_/'
}

# prints the current playback status
function spotify-playbackStatus() {
    dbus-send --print-reply --session --dest=${SPOTIFY_DEST} ${SPOTIFY_PATH} org.freedesktop.DBus.Properties.Get string:"${SPOTIFY_MEMB}" string:'PlaybackStatus' \
    | grep -Ev "^method"                            `# Ignore the first line.`  \
    | grep -Eo '("(.*)")|(\b[0-9][a-zA-Z0-9.]*\b)'  `# Filter status value.`    \
    | sed -E 's/^"//'                               `# Strip leading quotes`    \
    | sed -E 's/"$//'                               `# ...and trailing quotes.`
}

# prints the current spotify track id
function spotify-current-trackid() {
    TRACKID_FIELD_NAME="trackid\|"

    spotify-metadata \
    | grep --color=never -E "^${TRACKID_FIELD_NAME}" \
    | sed -E "s/^${TRACKID_FIELD_NAME}//"
}

# toggle play and pause
function spotify-playPause() {
    dbus-send --print-reply --dest=${SPOTIFY_DEST} ${SPOTIFY_PATH} "${SPOTIFY_MEMB}.PlayPause" > /dev/null
}

# play next track
function spotify-next() {
    dbus-send --print-reply --dest=${SPOTIFY_DEST} ${SPOTIFY_PATH} "${SPOTIFY_MEMB}.Next" > /dev/null
}

# send "previous" signal to spotify
function spotify-previous() {
    dbus-send --print-reply --dest=${SPOTIFY_DEST} ${SPOTIFY_PATH} "${SPOTIFY_MEMB}.Previous" > /dev/null
}

# play previous track (force it)
function spotify-previous-force() {
    PREV_TRACKID=$(spotify-current-trackid)
    spotify-previous

    sleep 1 #spotify needs a little bit time to update the metadata

    if [ "${PREV_TRACKID}" == "$(spotify-current-trackid)" ]
    then
        spotify-previous
    fi
}


# Plugin functionality #################################################################################################

# check if spotify start button has been clicked
case "${1}" in
    'start' )
        spotify-start
        exit 0
        ;;
esac

# spotify isn't running
if ! is-spotify-running
then
    echo ":radio:"
    echo "---"

    echo "Start Spotify | bash='${0}' terminal=false refresh=true param1=start"

    echo "---"
    echo "Refresh... | refresh=true"

    exit 0
fi

# button actions (spotify is running)
case "${1}" in
    'playpause' )
        spotify-playPause
        exit 0
        ;;
    'next' )
        spotify-next
        exit 0
        ;;
    'previous' )
        spotify-previous-force
        exit 0
        ;;
    'showhide' )
        spotify-window-toggleMapping
        exit 0
        ;;
    'quit' )
        spotify-quit
        exit 0
        ;;
esac


# apply spotify metadata variables to placeholders
eval "$(spotify-eval)"


OUT_PLAYPAUSE="---"
OUT_HEADER_ICON=":exclamation:"
OUT_HEADER_COLOR="#ff0000"
case "$(spotify-playbackStatus)" in
    'Playing' )
        OUT_PLAYPAUSE="Pause"
        OUT_HEADER_ICON=":musical_note:"
        OUT_HEADER_COLOR="#add8e6"
        ;;
    'Paused' )
        OUT_PLAYPAUSE="Play"
        OUT_HEADER_ICON=":zzz:"
        OUT_HEADER_COLOR="#acacac"
        ;;
    * )
        OUT_PLAYPAUSE="Play/Pause"
        OUT_HEADER_ICON=":musical_note:"
        OUT_HEADER_COLOR="#add8e6"
        ;;
esac

OUT_VISIBILITY_CHANGE="---"
case "$(spotify-window-mappedStatus)" in
    'IsViewable' )
        OUT_VISIBILITY_CHANGE="Hide Spotify"
        ;;
    'IsUnMapped' )
        OUT_VISIBILITY_CHANGE="Show Spotify"
        ;;
    * )
        OUT_VISIBILITY_CHANGE="Show/Hide Spotify"
        ;;
esac

# set music title displayed on panel button (max length of 15 chars)
OUT_TITLE="${SPOTIFY_CURRENT_TITLE:0:15}"
if [[ ${#SPOTIFY_CURRENT_TITLE} -gt 15 ]]
then
    OUT_TITLE="${SPOTIFY_CURRENT_TITLE:0:14}&#8230;"
fi


# "Frontend" ###########################################################################################################

echo "${OUT_HEADER_ICON} ${OUT_TITLE} ${OUT_HEADER_ICON} | color=${OUT_HEADER_COLOR}"
echo "---"

echo "${SPOTIFY_CURRENT_TITLE} | length=25"
echo "from \"${SPOTIFY_CURRENT_ARTIST:0:18}\""

echo "---"

echo "${OUT_PLAYPAUSE} | bash='${0}' terminal=false refresh=true param1=playpause"
echo "Next | bash='${0}' terminal=false refresh=true param1=next"
echo "Previous | bash='${0}' terminal=false refresh=true param1=previous"

echo "---"

echo "${OUT_VISIBILITY_CHANGE} | bash='${0}' terminal=false refresh=false param1=showhide"

echo "---"

echo "Quit | bash='${0}' terminal=false refresh=true param1=quit"
echo "Refresh... | refresh=true"
