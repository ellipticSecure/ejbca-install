#!/bin/bash
# Author: Kobus Grobler
#

EJBCA_VERSION="6_15_2_1"
SHASUM="74743302559645761481ce17259541f2b0d66c97cea051c8dff511bb037642a7"
WILDFLY_HOME="/opt/wildfly"
DB_VERSION="2.2.6"
DB_SHASUM="4d28fbd8fd4ea239b0ef9482f56ce77e2ef197a60d523a8ee3c84eb984fc76fe"
EHSM_VERSION=2.1
EHSM_SHASUM="0a9547555f804d81aca21ea89a95044ad0f42e494723eef44dee27f73ecd6a57"

sudo apt-get install ant mariadb-server
sudo usermod -a -G plugdev wildfly
sudo mysql -u root < mariadb.sql
sudo mysql -u root < create-tables-ejbca-mysql.sql

if [ ! -f eHSM-pkcs11-${EHSM_VERSION}.deb ]; then
    wget https://ellipticsecure.com/downloads/eHSM-pkcs11-${EHSM_VERSION}.deb
    if [ $? -ne 0 ]; then
     exit 1;
    fi
fi

echo "${EHSM_SHASUM}  eHSM-pkcs11-${EHSM_VERSION}.deb" | shasum -a 256 -c

if [ $? -ne 0 ]; then
 exit 1;
fi

sudo dpkg -i eHSM-pkcs11-${EHSM_VERSION}.deb

if [ ! -f ejbca_ce_$EJBCA_VERSION.zip ]; then
    wget https://sourceforge.net/projects/ejbca/files/ejbca6/ejbca_$EJBCA_VERSION/ejbca_ce_$EJBCA_VERSION.zip/download -O ejbca_ce_$EJBCA_VERSION.zip
    if [ $? -ne 0 ]; then
     exit 1;
    fi
fi

echo "${SHASUM}  ejbca_ce_$EJBCA_VERSION.zip" | shasum -a 256 -c

if [ $? -ne 0 ]; then
 exit 1;
fi

if [ ! -d ejbca_ce_$EJBCA_VERSION ]; then
 unzip ejbca_ce_$EJBCA_VERSION.zip
fi

# prep wildfly
grep -qxF 'JAVA_OPTS="-Xmx2048m"'\
 ${WILDFLY_HOME}/bin/standalone.conf || sudo bash -c 'echo ''JAVA_OPTS=\"-Xmx2048m\"''\
 >> /opt/wildfly/bin/standalone.conf'

if [ ! -f mariadb-java-client.jar ]; then
  wget https://downloads.mariadb.com/Connectors/java/connector-java-${DB_VERSION}/mariadb-java-client-${DB_VERSION}.jar -O mariadb-java-client.jar
fi

echo "${DB_SHASUM}  mariadb-java-client.jar" | shasum -a 256 -c
if [ $? -ne 0 ]; then
 exit 1;
fi

sudo cp mariadb-java-client.jar ${WILDFLY_HOME}/standalone/deployments/
sudo chown -RH wildfly: /opt/wildfly/standalone/deployments/

echo "Installing mysql driver..."

sudo service wildfly restart

wait_for_server() {
COUNTER=1
sleep 2
until [ $(curl --output /dev/null --silent --head --fail http://localhost:8080/) ] || [ $COUNTER -eq 10 ] 
do
    echo "waiting for service to start...." $COUNTER
    sleep 2
    ((COUNTER++))
done
}

wait_for_server

sudo cp *.properties ejbca_ce_$EJBCA_VERSION/conf/
sudo chown -RH wildfly: ejbca_ce_$EJBCA_VERSION/

echo "updating wildfly datasource..."

sudo -u wildfly -g wildfly ${WILDFLY_HOME}/bin/jboss-cli.sh -c 'data-source add --name=EjbcaDS --driver-name="mariadb-java-client.jar" --connection-url="jdbc:mysql://127.0.0.1:3306/ejbca" --jndi-name="java:/EjbcaDS" --use-ccm=true --driver-class="org.mariadb.jdbc.Driver" --user-name="ejbca" --password="ejbca" --validate-on-match=true --background-validation=false --prepared-statements-cache-size=50 --share-prepared-statements=true --min-pool-size=5 --max-pool-size=150 --pool-prefill=true --transaction-isolation=TRANSACTION_READ_COMMITTED --check-valid-connection-sql="select 1;"'
sudo -u wildfly -g wildfly ${WILDFLY_HOME}/bin/jboss-cli.sh -c "/subsystem=remoting/http-connector=http-remoting-connector:write-attribute(name=connector-ref,value=remoting),
/socket-binding-group=standard-sockets/socket-binding=remoting:add(port=4447,interface=management),
/subsystem=undertow/server=default-server/http-listener=remoting:add(socket-binding=remoting,enable-http2=true),
/subsystem=infinispan/cache-container=ejb:remove(),
/subsystem=infinispan/cache-container=server:remove(),
/subsystem=infinispan/cache-container=web:remove(),
/subsystem=ejb3/cache=distributable:remove(),
/subsystem=ejb3/passivation-store=infinispan:remove(),
/subsystem=logging/logger=org.ejbca:add(level=INFO),
/subsystem=logging/logger=org.cesecore:add(level=INFO)"
#sudo -u wildfly -g wildfly ${WILDFLY_HOME}/bin/jboss-cli.sh -c ':reload'

sudo service wildfly restart

wait_for_server

sudo -u wildfly -g wildfly ant -f ejbca_ce_$EJBCA_VERSION/build.xml -q clean deployear

wait_for_ejbca() {
COUNTER=1
sleep 5
until [ $(curl --output /dev/null --silent --head --fail http://localhost:8080/ejbca/) ] || [ $COUNTER -eq 10 ]
do
    echo "waiting for ejbca to start...."
    sleep 2
    ((COUNTER++))
done
}

wait_for_ejbca

sudo -u wildfly -g wildfly ant -f ejbca_ce_$EJBCA_VERSION/build.xml runinstall
sudo -u wildfly -g wildfly ant -f ejbca_ce_$EJBCA_VERSION/build.xml deploy-keystore
sudo cp -i -r ejbca_ce_$EJBCA_VERSION/p12/ .

echo "removing listeners..."

sudo -u wildfly -g wildfly ${WILDFLY_HOME}/bin/jboss-cli.sh -c '/subsystem=undertow/server=default-server/http-listener=default:remove(),
/subsystem=undertow/server=default-server/https-listener=https:remove(),
/socket-binding-group=standard-sockets/socket-binding=http:remove(),
/socket-binding-group=standard-sockets/socket-binding=https:remove(),
:reload'

sleep 6

wait_for_ejbca

echo "installing listeners..."

sudo -u wildfly -g wildfly ${WILDFLY_HOME}/bin/jboss-cli.sh -c '
/interface=http:add(inet-address="0.0.0.0"),
/interface=httpspub:add(inet-address="0.0.0.0"),
/interface=httpspriv:add(inet-address="0.0.0.0"),
/socket-binding-group=standard-sockets/socket-binding=http:add(port="8080",interface="http"),
/socket-binding-group=standard-sockets/socket-binding=httpspub:add(port="8442",interface="httpspub"),
/socket-binding-group=standard-sockets/socket-binding=httpspriv:add(port="8443",interface="httpspriv"),
/subsystem=elytron/key-store=httpsKS:add(path="keystore/keystore.jks",relative-to=jboss.server.config.dir,credential-reference={clear-text="serverpwd"},type=JKS),
/subsystem=elytron/key-store=httpsTS:add(path="keystore/truststore.jks",relative-to=jboss.server.config.dir,credential-reference={clear-text="changeit"},type=JKS),
/subsystem=elytron/key-manager=httpsKM:add(key-store=httpsKS,algorithm="SunX509",credential-reference={clear-text="serverpwd"}),
/subsystem=elytron/trust-manager=httpsTM:add(key-store=httpsTS),
/subsystem=elytron/server-ssl-context=httpspub:add(key-manager=httpsKM,protocols=["TLSv1.2"]),
/subsystem=elytron/server-ssl-context=httpspriv:add(key-manager=httpsKM,protocols=["TLSv1.2"],trust-manager=httpsTM,need-client-auth=true,authentication-optional=false,want-client-auth=true),
/subsystem=undertow/server=default-server/http-listener=http:add(socket-binding="http", redirect-socket="httpspriv"),
/subsystem=undertow/server=default-server/https-listener=httpspub:add(socket-binding="httpspub", ssl-context="httpspub", max-parameters=2048),
/subsystem=undertow/server=default-server/https-listener=httpspriv:add(socket-binding="httpspriv", ssl-context="httpspriv", max-parameters=2048)'

sudo service wildfly restart
wait_for_ejbca

echo "fianl config..."

sudo -u wildfly -g wildfly ${WILDFLY_HOME}/bin/jboss-cli.sh -c '/system-property=org.apache.catalina.connector.URI_ENCODING:add(value="UTF-8"),
/system-property=org.apache.catalina.connector.USE_BODY_ENCODING_FOR_QUERY_STRING:add(value=true),
/system-property=org.apache.tomcat.util.buf.UDecoder.ALLOW_ENCODED_SLASH:add(value=true),
/system-property=org.apache.tomcat.util.http.Parameters.MAX_COUNT:add(value=2048),
/system-property=org.apache.catalina.connector.CoyoteAdapter.ALLOW_BACKSLASH:add(value=true),
/subsystem=webservices:write-attribute(name=wsdl-host, value=jbossws.undefined.host),
/subsystem=webservices:write-attribute(name=modify-wsdl-address, value=true)'

sudo service wildfly restart
wait_for_ejbca
