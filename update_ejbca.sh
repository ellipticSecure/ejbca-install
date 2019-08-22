#!/bin/bash

EJBCA_VERSION="6_15_2_1"
SHASUM="74743302559645761481ce17259541f2b0d66c97cea051c8dff511bb037642a7"
WILDFLY_HOME="/opt/wildfly"

sudo cp *.properties ejbca_ce_$EJBCA_VERSION/conf/
sudo chown -RH wildfly: ejbca_ce_$EJBCA_VERSION/
sudo -u wildfly -g wildfly ant -f ejbca_ce_$EJBCA_VERSION/build.xml -q clean deployear

