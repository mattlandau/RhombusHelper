#!/bin/bash
mkdir ring-mqtt
mkdir ring-mqtt/data
mkdir mosquitto
mkdir mosquitto/data
mkdir mosquitto/config
mkdir mosquitto/log

docker pull tsightler/ring-mqtt
docker pull eclipse-mosquitto

echo "Setting Up Ring-MQTT"
RING_FILE="./ring-mqtt/data/ring-state.json"
if [ ! -f  "$RING_FILE" ]; then
  docker run -it --rm --mount type=bind,source=./ring-mqtt/data,target=/data --entrypoint /app/ring-mqtt/init-ring-mqtt.js tsightler/ring-mqtt
fi


echo "Setting up mosquitto.conf"
MOSQUITTO_CONF="./mosquitto/config/mosquitto.conf"
if [ ! -f "$MOSQUITTO_CONF" ]; then
  touch $MOSQUITTO_CONF
  echo "persistence true" > $MOSQUITTO_CONF
  echo "persistence_location /mosquitto/data/" >> $MOSQUITTO_CONF
  echo "log_dest file /mosquitto/log/mosquitto.log" >> $MOSQUITTO_CONF
  echo "listener 1883 0.0.0.0" >> $MOSQUITTO_CONF
  echo "allow_anonymous false" >> $MOSQUITTO_CONF
  echo "password_file /mosquitto/config/passwd" >> $MOSQUITTO_CONF
fi

echo "Setting up Mosquitto"
echo "MOSQUITTO_USERNAME=$(uuidgen)" > ./creds.env
echo "MOSQUITTO_PASSWORD=$(uuidgen)" >> ./creds.env
source ./creds.env
echo $MOSQUITTO_USERNAME
echo $MOSQUITTO_PASSWORD
touch ./mosquitto/config/passwd
docker run --rm -v ./mosquitto/config:/mosquitto/config eclipse-mosquitto mosquitto_passwd -b /mosquitto/config/passwd $MOSQUITTO_USERNAME $MOSQUITTO_PASSWORD
#chmod 0700 ./mosquitto/config/passwd

echo ""
echo "Create an RTSP username:"
read RTSP_USERNAME
echo "Create an RTSP password:"
read -s RTSP_PASSWORD
RING_CONF="./ring-mqtt/data/config.json"
touch $RING_CONF
echo "{" > $RING_CONF
echo "    \"mqtt_url\": \"mqtt://$MOSQUITTO_USERNAME:$MOSQUITTO_PASSWORD@mosquitto:1883\"," >> $RING_CONF
echo "    \"mqtt_options\": \"\"," >> $RING_CONF
echo "    \"livestream_user\": \"$RTSP_USERNAME\"," >> $RING_CONF
echo "    \"livestream_pass\": \"$RTSP_PASSWORD\"," >> $RING_CONF
echo "    \"disarm_code\": \"\"," >> $RING_CONF
echo "    \"enable_cameras\": true," >> $RING_CONF
echo "    \"enable_modes\": false," >> $RING_CONF
echo "    \"enable_panic\": false," >> $RING_CONF
echo "    \"hass_topic\": \"homeassistant/status\"," >> $RING_CONF
echo "    \"ring_topic\": \"ring\"," >> $RING_CONF
echo "    \"location_ids\": []" >> $RING_CONF
echo "}" >> $RING_CONF


echo "Running docker compose up"
echo "Waiting on RTSP URL(s), stand by..."
docker compose up 2>&1 | grep "rtsp://"
