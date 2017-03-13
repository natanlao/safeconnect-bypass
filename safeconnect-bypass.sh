#!/bin/bash
# ./safeconnect-bypass.sh
# Script that monitors computer's wifi connection and bypasses SafeConnect
# policies if detected. macOS only. Tested on macOS 10.12.1.

### Constants

# Chrome OS user agent (TODO: Randomly select a 'safe' user agent)
user_agent="Mozilla/5.0 (X11; CrOS x86_64 8872.76.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883.105 Safari/537.46"
user_string="5.0 (X11; CrOS x86_64 8872.76.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883.105 Safari/537.46"


### Functions

# Log to stdout
log() { printf "[$(date)] $1\n"; }

# Ensure script is being run as superuser and preserve privilege escalation.
ensure_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log "Fatal: Root permissions required. Call $0 with \`sudo\`. Exiting."
        exit 1
    fi
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
}

# Generate a random MAC address with a Chromebook prefix. (to $mac)
# Derived from http://superuser.com/a/218372
generate_mac() {
    hexchars="0123456789ABCDEF"
    end=$(for i in {1..6}; do echo -n ${hexchars:$(($RANDOM % 16)):1}; done | sed -e 's/\(..\)/:\1/g')
    mac="CC:3D:82$end"
}

# Reads CruzID and Blue password from user input to $username and $password respectively
get_cruzid() {
    read -p "CruzID: " username
    read -s -p "Blue password: " password
    echo
}

# Sends spoofed login request. Takes $username as first arg and $password as second arg
send_login_request() {
    log "Sending spoofed login request."
    PAYLOAD="{\"username\":\"$1\",\"password\":\"$2\",\"appversion\":\"$user_string\",\"platform\":\"Linux x86_64\"}"
    AUTH_URL="https://resreg.ucsc.edu:9443/api/authRest"
    HEADER="Content-Type: application/json"
    curl --user-agent "$user_agent" -H "$HEADER" -X POST -d "$PAYLOAD" --location "$AUTH_URL" &> /dev/null
}

# Toggle power to wifi.
# TODO: wifi is not en1 on all platforms
toggle_wifi() {
    log "Toggling wifi..."
    networksetup -setairportpower en1 off
    networksetup -setairportpower en1 on
}

wait_http() {
    waiting=0
    while [[ waiting -eq 0 ]]; do
        r=$(curl -s -o /dev/null -w "%{http_code}" "http://www.example.com/")
        if [[ $r == 200 ]]; then
            waiting=1
        else
            sleep 1
        fi
    done
}

get_cruzid
generate_mac

if [[ "$1" == "--login-only" ]]; then
    send_login_request "$username" "$password"
    exit 0
fi

ensure_root

while true; do
    # Does Young Metro trust the internet connection?
    r=$(curl --user-agent '$user_agent' -I --silent --location icanhazip.com)

    # If Young Metro doesn't trust the internet connection, shoot
    if [[ "${r}" != "HTTP/1.1 200 OK"* ]]; then
        log "It looks like SafeConnect is being mean."

        toggle_wifi

        # Wait for wifi to actually turn on before doing anything
        log "Waiting for wifi to turn on..."
        while [[ $(networksetup -getairportpower en1) != "Wi-Fi Power (en1): On" ]]; do
            sleep 1
        done

        # Apply the new MAC address.
        # To restore the true MAC address, restart the computer.
        log "Switching to new MAC address $mac"
        sudo ifconfig en1 ether $mac

        # Wait until a wifi connection is established before continuing
        log "Waiting to connect to a wifi network..."
        while [[ $(ifconfig en1 | tail -n 1 | xargs) != "status: active" ]]; do
            sleep 1
        done

        # Make sure that we're connected to the network and everything is good.
        log "Waiting to see if we're up and running..."
        wait_http

        sleep 10
        # Spoof a request from a Chromebook
        log "Sending spoofed request..."
        curl --user-agent "$user_agent" --location http://example.com &> /dev/null

        log "Attempting to log in..."
        send_login_request "$username" "$password"
        # skrttttttt

        sleep 5
    else
        # If things look okay, check again in 30 seconds.
        log "Everything looks good. Checking again in 30 seconds."
        sleep 30
    fi
done
