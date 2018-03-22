#!/bin/sh

NAGIOS_RUNNING=1
NCG_TIMEOUT=1800
OUTPUT_DIR_TMP=/etc/nagios/argo-ncg.d.tmp.$$
CONFIG_FILE_TMP=/etc/nagios/nagios.cfg.tmp.$$

if [ -f /etc/sysconfig/ncg ] ; then
  . /etc/sysconfig/ncg
fi

NCG_BACKUP_OPTIONS=""
if [ -n "${BACKUP_INSTANCE}" ] && [ ${BACKUP_INSTANCE} == "true" ] ; then
  NCG_BACKUP_OPTIONS="--backup-instance"
fi

revert_config_and_exit () {
  rm -rf $OUTPUT_DIR_TMP
  rm -rf $CONFIG_FILE_TMP
  exit 1
}

# check if nagios is running at all
service nagios status 2>&1 > /dev/null
# status will return 1 if not running
if [ $? -ne 0 ]; then
    NAGIOS_RUNNING=0
fi

/usr/sbin/ncg.pl --timeout $NCG_TIMEOUT --output-dir=$OUTPUT_DIR_TMP --final-output-dir=/etc/nagios/argo-ncg.d $NCG_OPTIONS $NCG_BACKUP_OPTIONS || revert_config_and_exit

sed "s|/etc/nagios/argo-ncg.d|$OUTPUT_DIR_TMP|" /etc/nagios/nagios.cfg > $CONFIG_FILE_TMP
/usr/bin/nagios -v $CONFIG_FILE_TMP || revert_config_and_exit

# remove temp
rm -rf $CONFIG_FILE_TMP

# keep the existing config
rm -rf /etc/nagios/argo-ncg.d.backup
mv /etc/nagios/argo-ncg.d /etc/nagios/argo-ncg.d.backup
mv $OUTPUT_DIR_TMP /etc/nagios/argo-ncg.d

if [ $NAGIOS_RUNNING -eq 1 ]; then
  /sbin/service nagios reload
else
  # here we try to start nagios, continue running even if it fails
  echo "Nagios is not running, attempting to start it"
  /sbin/service nagios start
fi
