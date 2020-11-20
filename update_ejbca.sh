#!/bin/bash

EJBCA_VERSION="6_15_2_6"
WILDFLY_HOME="/opt/wildfly"

sudo cp *.properties ejbca_ce_$EJBCA_VERSION/conf/
sudo chown -RH wildfly: ejbca_ce_$EJBCA_VERSION/
sudo -u wildfly -g wildfly ant -f ejbca_ce_$EJBCA_VERSION/build.xml -q clean deployear

