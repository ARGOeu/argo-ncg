#!/bin/sh

# Generate truststore
rm -f /etc/nagios/globus/truststore.ts.tmp
for i in /etc/grid-security/certificates/*.pem ; do
	j=$(echo $i | sed -e 's_.*/__g;s/\.pem$//')
	keytool -importcert -keystore /etc/nagios/globus/truststore.ts.tmp -noprompt -deststorepass password -alias $j -file $i 2>/dev/null
done
chmod 444 /etc/nagios/globus/truststore.ts.tmp
chown nagios:nagios /etc/nagios/globus/truststore.ts.tmp
mv -f /etc/nagios/globus/truststore.ts.tmp /etc/nagios/globus/truststore.ts
