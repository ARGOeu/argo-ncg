#!/bin/sh

ROBOT_CERT=/etc/nagios/globus/robocert.pem
ROBOT_KEY=/etc/nagios/globus/robokey.pem
KEYSTORE_DIR=/etc/nagios/globus
NCG_CONFIG_FILE=/etc/argo-ncg/ncg-localdb.d/java-keystore.conf

if [ ! -f $ROBOT_CERT ]; then 
  echo "Please install robot certificate to $ROBOT_CERT"
  exit -1
fi
if [ ! -f $ROBOT_KEY ]; then
  echo "Please install robot key to $ROBOT_KEY" 
  exit -1
fi

# if parameter is passed, reuse password
if [ "$#" -eq 0 ]; then
  KEYSTORE_PASS=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c20`
else
  KEYSTORE_OLD_PASS=`grep "^GLOBAL_ATTRIBUTE\!KEYSTORE_PASSWORD\!" $NCG_CONFIG_FILE 2>/dev/null`
  if [ $? -ne 0 ]; then
    echo "Cannot find old password in $NCG_CONFIG_FILE"
    exit -1
  else
    KEYSTORE_PASS=${KEYSTORE_OLD_PASS#'GLOBAL_ATTRIBUTE!KEYSTORE_PASSWORD!'}
  fi
fi

# Generate keystore
rm -f $KEYSTORE_DIR/keystore.jks.tmp $KEYSTORE_DIR/tmp.p12
openssl pkcs12 -export -in $ROBOT_CERT -inkey $ROBOT_KEY -name mon_agent -out $KEYSTORE_DIR/tmp.p12 -passout pass:$KEYSTORE_PASS
keytool -importkeystore -srckeystore $KEYSTORE_DIR/tmp.p12 -srcstoretype PKCS12 -deststoretype jks -deststorepass $KEYSTORE_PASS -destkeystore $KEYSTORE_DIR/keystore.jks.tmp -srcstorepass $KEYSTORE_PASS -destalias mon_agent -srcalias mon_agent
rm -f $KEYSTORE_DIR/tmp.p12
chown nagios:nagios $KEYSTORE_DIR/keystore.jks.tmp
chmod 400 $KEYSTORE_DIR/keystore.jks.tmp
mv -f $KEYSTORE_DIR/keystore.jks.tmp $KEYSTORE_DIR/keystore.jks

# Pass keypass to NCG
echo "GLOBAL_ATTRIBUTE!KEYSTORE_PASSWORD!$KEYSTORE_PASS" > $NCG_CONFIG_FILE
