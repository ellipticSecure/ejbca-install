#!/bin/bash
# Author: Kobus Grobler

# Download and install Wildfly application server to /opt/wildfly
# Note: this will overwrite the wildfly installation at /opt/wildfly-VERSION

sudo apt install openjdk-8-jdk

sudo groupadd -r wildfly
sudo useradd -r -g wildfly -d /opt/wildfly -s /sbin/nologin wildfly

WILDFLY_VERSION="14.0.1.Final"
SHASUM="e12092ec6a6e048bf696d5a23c3674928b41ddc3f810016ef3e7354ad79fc746"

if [ ! -f wildfly-$WILDFLY_VERSION.tar.gz ]; then
    wget https://download.jboss.org/wildfly/$WILDFLY_VERSION/wildfly-$WILDFLY_VERSION.tar.gz

    if [ $? -ne 0 ]; then
     exit 1;
    fi
fi

echo "${SHASUM}  wildfly-${WILDFLY_VERSION}.tar.gz" | shasum -a 256 -c

if [ $? -ne 0 ]; then
 exit 1;
fi


sudo tar xf wildfly-${WILDFLY_VERSION}.tar.gz -C /opt/
sudo ln -s /opt/wildfly-${WILDFLY_VERSION} /opt/wildfly
sudo chown -RH wildfly: /opt/wildfly
sudo mkdir -p /etc/wildfly
sudo cp -i /opt/wildfly/docs/contrib/scripts/systemd/wildfly.conf /etc/wildfly/

sudo cp -i /opt/wildfly/docs/contrib/scripts/systemd/launch.sh /opt/wildfly/bin/
sudo sh -c 'chmod +x /opt/wildfly/bin/*.sh'
sudo cp -i /opt/wildfly/docs/contrib/scripts/systemd/wildfly.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable wildfly
