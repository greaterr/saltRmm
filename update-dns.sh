#!/bin/bash
# Updates DNS records in Samba when Mac IP changes
# Run via launchd on network change

DOMAIN="rmm.lan"
DC_CONTAINER="samba-dc"
ADMIN_PASS="Admin1234!"
CACHE_FILE="/tmp/.last_mac_ip"

CURRENT_IP=$(ipconfig getifaddr en0 2>/dev/null)

if [ -z "$CURRENT_IP" ]; then
    echo "No IP on en0, skipping"
    exit 0
fi

LAST_IP=$(cat "$CACHE_FILE" 2>/dev/null)

if [ "$CURRENT_IP" = "$LAST_IP" ]; then
    exit 0
fi

echo "IP changed: $LAST_IP -> $CURRENT_IP, updating DNS..."

update_record() {
    local NAME=$1
    local OLD_IP
    OLD_IP=$(docker exec "$DC_CONTAINER" samba-tool dns query 127.0.0.1 "$DOMAIN" "$NAME" A \
        -U "Administrator%${ADMIN_PASS}" 2>/dev/null \
        | grep -oE 'A: [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    if [ "$OLD_IP" = "$CURRENT_IP" ]; then
        echo "Up to date: $NAME -> $CURRENT_IP"
        return
    fi

    if [ -n "$OLD_IP" ]; then
        docker exec "$DC_CONTAINER" samba-tool dns delete 127.0.0.1 "$DOMAIN" "$NAME" A "$OLD_IP" \
            -U "Administrator%${ADMIN_PASS}" 2>/dev/null
    fi

    docker exec "$DC_CONTAINER" samba-tool dns add 127.0.0.1 "$DOMAIN" "$NAME" A "$CURRENT_IP" \
        -U "Administrator%${ADMIN_PASS}" 2>/dev/null
    echo "Updated: $NAME  ${OLD_IP:-(none)} -> $CURRENT_IP"
}

update_record "macbook-pro-timur"
update_record "dc1"
update_record "@"

echo "$CURRENT_IP" > "$CACHE_FILE"
echo "Done"
