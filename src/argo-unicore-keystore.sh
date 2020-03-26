#!/bin/sh

ROBOT_CERT=/etc/nagios/globus/robocert.pem
ROBOT_KEY=/etc/nagios/globus/robokey.pem

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
  UNICORE_KEYSTORE_PASS=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c20`
else
  UNICORE_OLD_PASS=`grep "^credential.password=" /etc/nagios/unicore/ucc.config 2>/dev/null`
  if [ $? -ne 0 ]; then
    echo "Cannot find credential.password in /etc/nagios/unicore/ucc.config"
    exit -1
  else
    UNICORE_KEYSTORE_PASS=${UNICORE_OLD_PASS#'credential.password='}
  fi
fi

# Generate keystore
rm -f /etc/nagios/unicore/keystore.jks.tmp /etc/nagios/unicore/tmp.p12
openssl pkcs12 -export -in $ROBOT_CERT -inkey $ROBOT_KEY -name mon_agent -out /etc/nagios/unicore/tmp.p12 -passout pass:$UNICORE_KEYSTORE_PASS
keytool -importkeystore -srckeystore /etc/nagios/unicore/tmp.p12 -srcstoretype PKCS12 -deststoretype jks -deststorepass $UNICORE_KEYSTORE_PASS -destkeystore /etc/nagios/unicore/keystore.jks.tmp -srcstorepass $UNICORE_KEYSTORE_PASS -destalias mon_agent -srcalias mon_agent
rm -f /etc/nagios/unicore/tmp.p12
chown nagios:nagios /etc/nagios/unicore/keystore.jks.tmp
chmod 400 /etc/nagios/unicore/keystore.jks.tmp
mv -f /etc/nagios/unicore/keystore.jks.tmp /etc/nagios/unicore/keystore.jks

# Pass keypass to NCG
echo "GLOBAL_ATTRIBUTE!KEYSTORE_PASSWORD!$UNICORE_KEYSTORE_PASS" > /etc/argo-ncg/ncg-localdb.d/java-keystore.conf

# Generate UNICORE config
cat << EOF > /etc/nagios/unicore/ucc.config
credential.path=/etc/nagios/unicore/keystore.jks
credential.password=$UNICORE_KEYSTORE_PASS
credential.keyAlias=mon_agent
truststore.type=keystore
truststore.keystorePath=/etc/nagios/globus/truststore.ts
truststore.keystorePassword=password
output=.
EOF
chmod 400 /etc/nagios/unicore/ucc.config
chown nagios:nagios /etc/nagios/unicore/*

# Generate UNICORE log directory
mkdir -p /var/log/unicore
chmod 750 /var/log/unicore
chown nagios:nagios /var/log/unicore
