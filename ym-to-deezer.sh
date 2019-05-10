#!/bin/bash

set -x

cleanup="true"
function add_cleanup_action
{
    cleanup="$@
$cleanup"
}

function cleanup
{
    local action
    echo "$cleanup" | while read action ; do eval $action ; done
}

function ym_request
{
    local ym_url="$1"
    local json_match="$2"
    echo `curl -sb -H "Accept: application/json" https://music.yandex.ru/$ym_url | grep -Po '(?<=var Mu=){.*};' | jq -r "${json_match}" 2>/dev/null`
}

function ym_get_playlist_name
{
    local ym_playlist_id="$1"
    echo `ym_request "users/$USER/playlists/$ym_playlist_id" ".pageData.playlist.title"`
}

function ym_get_track_name
{
    local ym_track_id="$1"
    echo `ym_request "track/$ym_track_id" ".pageData.volumes[][] | select(.id == \"$ym_track_id\") | .title"`
}

function ym_get_track_artist
{
    local ym_track_id="$1"
    echo `ym_request "track/$ym_track_id" ".pageData.volumes[][] | select(.id == \"$ym_track_id\") | .artists[0].name"`
}

function ym_get_track_album
{
    local ym_track_id="$1"
    echo `ym_request "track/$ym_track_id" ".pageData.title"`
}

function ym_get_playlists
{
   rm -f "${playlists_queue}"
   for playlist_id in $@ ; do
       local playlist_title=`ym_get_playlist_name $playlist_id`
       echo "Found '${playlist_title}'"
       echo "$playlist_id \"${playlist_title}\"" >> "${playlists_queue}"
   done
}

function ym_tracks_list
{
    local ym_playlist_id="$1"
    echo `ym_request "users/$USER/playlists/$ym_playlist_id" ".pageData.playlist.tracks[].id"` 
}

function dz_create_playlist
{
    local playlist_title="$1"
    echo `curl -s --data-urlencode "title=$playlist_title" http://api.deezer.com/user/me/playlists?access_token=${TOKEN} | jq -r .id`
}

function dz_add_track_to_playlist
{ 
    local dz_track_id="$1"
    local dz_playlist_id="$2"
    echo `curl -s --data "songs=$dz_track_id" http://api.deezer.com/playlist/$dz_playlist_id/tracks?access_token=${TOKEN}`
}

function dz_find_track
{
    local track_title="$1"
    local track_artist="$2"
    local track_album="$3"

    echo `curl -G -s 'https://api.deezer.com/search' -XGET --data-urlencode "q=artist:\"$track_artist\" track:\"$track_title\" album:\"$track_album\"" | jq -r '.[][0].id' 2>/dev/null`  
}

function run_oauth2_server
{
    echo "To start local OAuth2 server i need permissions..."
    sudo ./deezer-auth > $1
}

tmp=`mktemp`
add_cleanup_action rm -f "$tmp"
function dz_update_token
{ 
    run_oauth2_server $tmp &
    oauth2_pid="$!"
    xdg-open "https://connect.deezer.com/oauth/auth.php?app_id=${APP_ID}&redirect_uri=http://localhost&perms=basic_access,manage_library"
    wait $oauth2_pid
    TOKEN=`cat $tmp`   
}

function do_migrate
{
    while read playlist ; do
        read ym_pl_id ym_pl_title <<<"${playlist}"
        ym_pl_title=`sed -e 's/^"//' -e 's/"$//' <<<"$ym_pl_title"`

        echo "Creating playlist '$ym_pl_title'"
        local dz_playlist_id=`dz_create_playlist "$ym_pl_title"`
        [ -z "${dz_playlist_id}" ] && {
            echo "Need to update token!"
            dz_update_token
            dz_playlist_id=`dz_create_playlist "$ym_pl_title"`
            [ -z "${dz_playlist_id}" ] && {
                echo "Failed to create playlist '$ym_pl_title'"
                continue
            }
        } || echo "Done"

        for ym_track_id in `ym_tracks_list $ym_pl_id` ; do
            
            local track_title=`ym_get_track_name $ym_track_id`
            local track_artist=`ym_get_track_artist $ym_track_id`
            local track_album=`ym_get_track_album $ym_track_id`

            echo "$ym_track_id: $track_artist - $track_title, $track_album" 
            local dz_track_id=`dz_find_track "$track_title" "$track_artist" "$track_album"`
            
            [ `dz_add_track_to_playlist $dz_track_id $dz_playlist_id` != true ] && {
                echo "Need to update token!"
                dz_update_token
                [ `dz_add_track_to_playlist $dz_track_id $dz_playlist_id` != true ] && {
                    echo "Failed to add track!"
                    continue 
                }
                    
            } || echo "Done"
        done
    done < "${playlists_queue}"
}

trap cleanup EXIT

cat <<EOF
You need to create auth file:
${PWD}/auth
<ym_login> <app_id> <secret>
    ym_login   - Your Yandex Music user login
    app_id     - 'Application ID' of created Deezer App
    secret     - 'Secret Key' of created Deezer App

Example:
echo "andrew.ozhegov 123456 x0234t0wer324wq0xweqr5034wer2x503240x50" > ./auth
EOF
read USER APP_ID SECRET_KEY <<<`cat ./auth`

playlists_queue="${PWD}/playlists"
add_cleanup_action rm -f "$playlists_queue"

echo "Read $USER's playlists..."
ym_get_playlists `ym_request "users/$USER/playlists" ".pageData.playlists[].kind"`

echo "Now VIM will be opened with your YM playlists queue."
echo "Remove playlists that you dont want to backup... <Enter>" ; read
vim "${playlists_queue}"

echo "Prepearing local OAuth2 server..."
CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags "-s -w -X main.APP_ID=${APP_ID} -X main.SECRET_KEY=${SECRET_KEY}" -o deezer-auth

echo "Accept authentication..."
dz_update_token

echo "Prepearing done. Let's mirate!"
do_migrate

