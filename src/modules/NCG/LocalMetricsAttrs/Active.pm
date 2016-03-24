#!/usr/bin/perl -w
#
# Nagios configuration generator (WLCG probe based)
# Copyright (c) 2007 Emir Imamagic
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package NCG::LocalMetricsAttrs::Active;

use NCG::LocalMetricsAttrs;
use strict;
use Net::LDAP;
use vars qw(@ISA);
use URI::URL;

@ISA=("NCG::LocalMetricsAttrs");

sub new {
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);

    $self->{INCLUDE_MSG_CHECKS_RECV} = 1
        unless (defined $self->{INCLUDE_MSG_CHECKS_RECV});
    $self->{INCLUDE_MSG_CHECKS_SEND} = 1
        unless (defined $self->{INCLUDE_MSG_CHECKS_SEND});
    $self->{INCLUDE_PROXY_CHECKS} = 1
        unless (defined $self->{INCLUDE_PROXY_CHECKS});

    if ($self->{PROBES_TYPE} && $self->{PROBES_TYPE} =~ /native/) {
        $self->{PROBES_TYPE} .= ',local';
    }

    if ($self->{BACKUP_INSTANCE}) {
        $self->{INCLUDE_MSG_CHECKS_SEND} = 0;
    }

    $self;
}

sub getData {
    my $self = shift;
	my $sitename = shift || $self->{SITENAME};

    $self->_setStaticAttrs($sitename);

    if ($sitename eq 'nagios') {
        my $vos;
        foreach my $site (values %{$self->{MULTI_SITE_SITES}}) {
            foreach my $vo (keys %{$site->{VOS}}) {
                foreach my $voFqan (keys %{$site->{VOS}->{$vo}->{FQAN}}) {
                    $vos->{$vo}->{$voFqan} = $site->{VOS}->{$vo}->{FQAN}->{$voFqan}->{DEFAULT_FQAN};
                }
            }
        }
        foreach my $hostname ($self->{SITEDB}->getHosts()) {
    		$self->_removeProxyChecks($hostname) unless ($self->{INCLUDE_PROXY_CHECKS});
            $self->_analyzeNAGIOS($hostname, $vos);
            $self->_analyzeInternalMyProxy($hostname, $vos);
        }
    } else {
        foreach my $hostname ($self->{SITEDB}->getHosts()) {
    		$self->_setStaticHostAttrs($hostname,$sitename);

    		$self->_analyzeBDII($hostname, $sitename);
            $self->_analyzeMDS($hostname, $sitename);

            $self->_analyzeTargetSystemFactory($hostname);

            $self->_analyzeSAM($hostname, $sitename);
            $self->_removeProxyChecks($hostname) unless ($self->{INCLUDE_PROXY_CHECKS});
            
            $self->_analyzeURLs($hostname, $sitename);
        }

        unless ($self->{ENABLE_UNICORE_PROBES}) {
            $self->{SITEDB}->removeMetric(undef, undef, 'emi.unicore.Gateway');
            $self->{SITEDB}->removeMetric(undef, undef, 'emi.unicore.Registry');
            $self->{SITEDB}->removeMetric(undef, undef, 'emi.unicore.ServiceOrchestrator');
            $self->{SITEDB}->removeMetric(undef, undef, 'emi.unicore.UVOS');
            $self->{SITEDB}->removeMetric(undef, undef, 'emi.unicore.TargetSystemFactory');
            $self->{SITEDB}->removeMetric(undef, undef, 'emi.unicore.GlobalStorage');
            $self->{SITEDB}->removeMetric(undef, undef, 'emi.unicore.GlobalStorage-FreeSpace');
            $self->{SITEDB}->removeMetric(undef, undef, 'emi.unicore.WorkflowService');
        }

    }

    1;
}

sub _analyzeNAGIOS {
    my $self = shift;
    my $hostname = shift;
    my $vos = shift;

    if ($self->{SITEDB}->hasService($hostname, "NAGIOS")) {
        # NRPE service
        $self->{SITEDB}->removeMetric($hostname, undef, "org.nagios.ProcessNSCA") if (!$self->{NRPE_UI});
        # let's gather list of sites
        # needed for remote metrics and GOCDB downtimes
        my $siteList = join ( ',', keys %{$self->{MULTI_SITE_SITES}});
        $self->{SITEDB}->hostAttribute($hostname, "SITE_LIST", $siteList);
        # Remote metrics
        if ($self->{PROBES_TYPE} =~ /(remote|all)/) {
            my $remoteServices;
            foreach my $site (values %{$self->{MULTI_SITE_SITES}}) {
                foreach my $remoteService ($site->{SITEDB}->getRemoteServices()) {
                    $remoteServices->{$remoteService} = 1;
                }
            }
            # Nagios checks exist, add MSG receiver checks
            $self->{INCLUDE_MSG_CHECKS_RECV} = 1 if (exists $remoteServices->{"Nagios"});
            # set attributes for remote gatherers
        } 
        # MSG checks
        # this must go after remote checks because of Nagios remote checks
        if (!$self->{INCLUDE_MSG_CHECKS_RECV}) {
            $self->{SITEDB}->removeMetric($hostname, undef, "org.egee.RecvFromQueue");
            $self->{SITEDB}->removeMetric($hostname, undef, "org.nagios.ProcessMsgToHandler");
            $self->{SITEDB}->removeMetric($hostname, undef, "org.nagios.MsgToHandlerPidFile");
            $self->{SITEDB}->removeMetric($hostname, undef, "org.nagios.MsgDirSize") if (!$self->{INCLUDE_MSG_CHECKS_SEND});
        }
        $self->{SITEDB}->removeMetric($hostname, undef, "org.egee.SendToMsg") if (!$self->{INCLUDE_MSG_CHECKS_SEND});
        # local metrics
        if ($self->{PROBES_TYPE} !~ /(local|all)/) {
            foreach my $metric ($self->{SITEDB}->getLocalMetrics($hostname)) {
                $self->{SITEDB}->removeMetric($hostname, undef, $metric) if ($self->{SITEDB}->metricFlag($hostname,$metric, "LOCALDEP"));
            }
        }
        $self->{SITEDB}->hostAttribute($hostname, "MYPROXY_SERVER", $self->{MYPROXY_SERVER}) if $self->{MYPROXY_SERVER};
        my $jobmonits = {};
        foreach my $vo (keys %{$vos}) {
            foreach my $voFqan (keys %{$vos->{$vo}}) {
                foreach my $metric ($self->{SITEDB}->getLocalMetrics($hostname)) {
                    my $req = $self->{SITEDB}->metricFlag($hostname,$metric, "REQUIREMENT");
                    if ($req) {
                        $jobmonits->{$metric} = 0 unless (exists $jobmonits->{$metric});
                        if ( $self->_checkSAMBabysitter($req,$voFqan,$vos->{$vo}->{$voFqan})) {
                            $self->{SITEDB}->addMetricVoFqans($hostname, $metric, $vo, $voFqan);
                            $jobmonits->{$metric}++;
                        } 
                    }
                }
                $self->{SITEDB}->addMetricVoFqans($hostname, 'hr.srce.GridProxy-Valid', $vo, $voFqan);
                $self->{SITEDB}->addMetricVoFqans($hostname, 'hr.srce.GridProxy-Get', $vo, $voFqan);
                $self->{SITEDB}->addVoFqan($vo, $voFqan) if (!$vos->{$vo}->{$voFqan});
            }
        }
        foreach my $metric (keys %{$jobmonits}) {
            $self->{SITEDB}->removeMetric($hostname, undef, $metric)
                unless ($jobmonits->{$metric});
        }
    }
}

sub _analyzeInternalMyProxy {
    my $self = shift;
    my $hostname = shift;
    my $vos = shift;

    if ($self->{SITEDB}->hasService($hostname, "MyProxy")) {
        foreach my $vo (keys %{$vos}) {
            foreach my $voFqan (keys %{$vos->{$vo}}) {
                $self->{SITEDB}->addMetricVoFqans($hostname, 'hr.srce.MyProxy-ProxyLifetime', $vo, $voFqan);
            }
        }
        # local metrics
        if ($self->{PROBES_TYPE} !~ /(local|all)/) {
            foreach my $metric ($self->{SITEDB}->getLocalMetrics($hostname)) {
                $self->{SITEDB}->removeMetric($hostname, undef, $metric) if ($self->{SITEDB}->metricFlag($hostname,$metric, "LOCALDEP"));
            }
        }
    }
}

# remove all metrics which require proxy check
# this method is invoked if proxy checks are disabled
sub _removeProxyChecks {
    my $self = shift;
    my $host = shift;
    foreach my $metric ($self->{SITEDB}->getLocalMetrics($host)) {
        my $attributes = $self->{SITEDB}->metricAttributes($host, $metric);
        $self->{SITEDB}->removeMetric($host, undef, $metric) if exists ($attributes->{X509_USER_PROXY});
    }
}

sub _checkSAMBabysitter {
    my $self = shift;
    my $babysitter = shift;
    my $voFqan = shift;
    my $isDefault = shift;

    foreach my $site (values %{$self->{MULTI_SITE_SITES}}) {
        return 1 if ($site->{SITEDB}->globalAttribute($babysitter) && $isDefault);
        return 1 if $site->{SITEDB}->globalAttributeVO($babysitter, $voFqan);
    }

    return 0;
}

sub _analyzeSAM {
    my $self = shift;
    my $host = shift;

    foreach my $metric ($self->{SITEDB}->getLocalMetrics($host)) {
        if ( ($metric =~ /\S+?\.(WMS|CREAMCE)-(Direct)?JobSubmit/) || 
             ($metric =~ /org.nordugrid.ARC-CE(-\S+?)?-submit/) ||
             ($metric =~ /\S+?\.CONDOR-JobState/)
           ) {
            my $vos = $self->{SITEDB}->metricVoFqans($host,$metric);
            if ($vos) {
                foreach my $vo (keys %{$vos}) {
                    foreach my $voFqan (keys %{$vos->{$vo}}) {
                        if ($voFqan eq '_ALL_') {
                            $self->{SITEDB}->globalAttribute($metric, "1");
                        } else {
                            $self->{SITEDB}->globalAttributeVO($metric, $voFqan, "1");
                        }
                    }
                }
            }
        }
    }
}

sub _analyzeTargetSystemFactory {
	my $self = shift;
	my $hostname = shift;
	my $url;

	if ($self->{SITEDB}->hasService($hostname, "unicore6.TargetSystemFactory")) {
		if ($url = $self->{SITEDB}->hostAttribute($hostname, "unicore6.TargetSystemFactory_URL")) {
            my @addr = split(/\//, $url);
            $self->{SITEDB}->hostAttribute($hostname, "TSF_SITE_NAME", $addr[3]) if ($addr[3]);
		}
	}
}

sub _analyzeBDII {
	my $self = shift;
	my $hostname = shift;
	my $sitename = shift;

	# Set LDAP check parameter for BDII
	if ($self->{SITEDB}->hasService($hostname, "Top-BDII")) {
            $self->{SITEDB}->hostAttribute($hostname, "BDII_DN", "Mds-Vo-Name=local,O=Grid");
            # this is the GlueService type for Top-BDII
            $self->{SITEDB}->hostAttribute($hostname, "BDII_TYPE", "bdii_top");
 	} elsif ($self->{SITEDB}->hasService($hostname, "Site-BDII") || $self->{SITEDB}->hasService($hostname, "sBDII")) {
	    $self->{SITEDB}->hostAttribute($hostname, "BDII_DN", "Mds-Vo-Name=$sitename,O=Grid");
        $self->{SITEDB}->hostAttribute($hostname, "GLUE2_BDII_DN", "GLUE2DomainID=$sitename,o=glue");
            # this is the GlueService type for Site-BDII
            $self->{SITEDB}->hostAttribute($hostname, "BDII_TYPE", "bdii_site");
	} else {
			$self->{SITEDB}->hostAttribute($hostname, "BDII_DN", "Mds-Vo-Name=resource,O=Grid");
	}
}

sub _analyzeMDS {
	my $self = shift;
	my $hostname = shift;
	my $sitename = shift;

    $self->{SITEDB}->hostAttribute($hostname, "MDS_DN", "mds-vo-name=local,o=grid");
}

sub _analyzeURLs {
	my $self = shift;
	my $hostname = shift;
	my $sitename = shift;
	my $attr;

    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "Site-BDII_URL")) {
        if ($attr =~ /(\S+?:\/\/)?([-_.A-Za-z0-9]+):(\d+)/ ) {
            $self->{SITEDB}->hostAttribute($hostname, "BDII_PORT", $3);
            $self->{SITEDB}->globalAttribute("SITE_BDII_PORT", $3);
        }
    }

    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "Top-BDII_URL")) {
        if ($attr =~ /(\S+?:\/\/)?([-_.A-Za-z0-9]+):(\d+)/ ) {
            $self->{SITEDB}->hostAttribute($hostname, "BDII_PORT", $3);
        }
    }
    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "SRMv2_URL")) {
        if ($attr =~ /(\S+?:\/\/)?([-_.A-Za-z0-9]+):(\d+)/ ) {
            $self->{SITEDB}->hostAttribute($hostname, "SRM2_PORT", $3);
        }
    }
    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "CREAM-CE_URL")) {
        if ($attr =~ /(\S+?:\/\/)?([-_.A-Za-z0-9]+):(\d+)/ ) {
            $self->{SITEDB}->hostAttribute($hostname, "CREAM_PORT", $3);
        }
    }   
    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "MyProxy_URL")) {
        if ($attr =~ /(\S+?:\/\/)?([-_.A-Za-z0-9]+):(\d+)/ ) {
            $self->{SITEDB}->hostAttribute($hostname, "MYPROXY_PORT", $3);
        }
    }
    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "dg.CREAM-CE_URL")) {
        $self->{SITEDB}->hostAttribute($hostname, "DG_SERVICE_URL", $attr);
    }
    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "dg.ARC-CE_URL")) {
        $self->{SITEDB}->hostAttribute($hostname, "DG_SERVICE_URL", $attr);
    }
    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "dg.TargetSystemFactory_URL")) {
        $self->{SITEDB}->hostAttribute($hostname, "DG_SERVICE_URL", $attr);
    }
    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "QCG.Broker_URL")) {
        if ($attr =~ /(\S+?:\/\/)?([-_.A-Za-z0-9]+):(\d+)/ ) {
            $self->{SITEDB}->hostAttribute($hostname, "QCG-BROKER_PORT", $3);
        }
    }
    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "QCG.Computing_URL")) {
        if ($attr =~ /(\S+?:\/\/)?([-_.A-Za-z0-9]+):(\d+)/ ) {
            $self->{SITEDB}->hostAttribute($hostname, "QCG-COMPUTING_PORT", $3);
        }
    }
    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "QCG.Notification_URL")) {
        if ($attr =~ /(\S+?:\/\/)?([-_.A-Za-z0-9]+):(\d+)/ ) {
            $self->{SITEDB}->hostAttribute($hostname, "QCG-NOTIFICATION_PORT", $3);
        }
    }   

    my @unicoreServices = ("unicore6.Gateway", "unicore6.ServiceOrchestrator", "unicore6.StorageManagement", "unicore6.TargetSystemFactory", "unicore6.UVOSAssertionQueryService", "unicore6.WorkflowFactory", "unicore6.StorageFactory");
    foreach my $unicoreService (@unicoreServices) {
        if ($attr = $self->{SITEDB}->hostAttribute($hostname, "${unicoreService}_URL")) {
            $attr =~ s#^(.*)/[A-Za-z]+(\?res=[a-z_]+)?$#$1/Registry?res=default_registry#;
            $self->{SITEDB}->hostAttribute($hostname, "LOCAL_${unicoreService}_REGISTRY_URL", $attr);
        }
    }
    
    if ($self->{SITEDB}->hasService($hostname, "egi.SAM")) {
        $self->{SITEDB}->hostAttribute($hostname, "MYEGI_HOST_URL", "http://${hostname}/");
    }

    if ($self->{SITEDB}->hasService($hostname, "egi.MSGBroker")) {
        $self->{SITEDB}->hostAttribute($hostname, "OPENWIRE_URL", "tcp://${hostname}:6166");
        $self->{SITEDB}->hostAttribute($hostname, "OPENWIRE_SSL_URL", "ssl://${hostname}:6167");
    }

    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "eu.egi.cloud.vm-management.occi_URL")) {
        eval {
            my $occiHash = {};
            my $occiurl = url($attr);
            $self->{SITEDB}->hostAttribute($hostname, 'OCCI_PORT', $occiurl->port);
            my @params = $occiurl->query_form;
            for (my $i=0; $i < @params; $i++) {
                my $key = $params[$i++];
                $key =~ s/^amp;//i;
                $key = 'OCCI_' . uc($key);
                my $value = $params[$i];
                $self->{SITEDB}->hostAttribute($hostname, $key, $value);
                $occiHash->{$key} = $value;
            }
            $self->{SITEDB}->hostAttribute($hostname, 'OCCI_SCHEME', $occiurl->scheme);
            $self->{SITEDB}->hostAttribute($hostname, 'OCCI_URL', $occiurl->scheme."://".$occiurl->host.":".$occiurl->port);
            if (!exists $occiHash->{OCCI_PLATFORM}) {
                $self->{SITEDB}->hostAttribute($hostname, 'OCCI_RESOURCE', 'small');
            } else {
                if (!exists $occiHash->{OCCI_RESOURCE}) {
                    $self->{SITEDB}->hostAttribute($hostname, 'OCCI_RESOURCE', 'm1-tiny');
                }
            }
        };
    }
    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "eu.egi.cloud.storage-management.cdmi_URL")) {
        eval {my $cdmiurl = url($attr);
        $self->{SITEDB}->hostAttribute($hostname, 'CDMI_PORT', $cdmiurl->port);};
    }
    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "eu.egi.cloud.broker.vmdirac_URL")) {
        eval {my $cdmiurl = url($attr);
        $self->{SITEDB}->hostAttribute($hostname, 'BROKER_PORT', $cdmiurl->port);};
    }
    if ($attr = $self->{SITEDB}->hostAttribute($hostname, "eu.egi.cloud.broker.compss_URL")) {
        eval {my $cdmiurl = url($attr);
        $self->{SITEDB}->hostAttribute($hostname, 'BROKER_PORT', $cdmiurl->port);};
    }
}

sub _setDefaultPorts {
	my $self = shift;

        $self->{SITEDB}->globalAttribute("SITE_BDII_PORT", 2170);
	$self->{SITEDB}->globalAttribute("BDII_PORT", 2170);
    $self->{SITEDB}->globalAttribute("MDS_PORT", 2135);
    $self->{SITEDB}->globalAttribute("GRIDFTP_PORT", 2811);
	$self->{SITEDB}->globalAttribute("GRAM_PORT", 2119);
	$self->{SITEDB}->globalAttribute("RB_PORT", 7772);
	$self->{SITEDB}->globalAttribute("WMS_PORT", 7772);
	$self->{SITEDB}->globalAttribute("MYPROXY_PORT", 7512);
	$self->{SITEDB}->globalAttribute("RGMA_PORT", 8443);
	$self->{SITEDB}->globalAttribute("TOMCAT_PORT", 8443);
	$self->{SITEDB}->globalAttribute("LL_PORT", 9002);
	$self->{SITEDB}->globalAttribute("LB_PORT", 9000);
	$self->{SITEDB}->globalAttribute("WMPROXY_PORT", 7443);
	$self->{SITEDB}->globalAttribute("SRM1_PORT", 8443);
	$self->{SITEDB}->globalAttribute("SRM2_PORT", 8446);
	$self->{SITEDB}->globalAttribute("VOBOX_PORT", 1975);
	$self->{SITEDB}->globalAttribute("FTS_PORT", 8443);
	$self->{SITEDB}->globalAttribute("GRIDICE_PORT", 2136);
	$self->{SITEDB}->globalAttribute("CREAM_PORT", 8443);
    $self->{SITEDB}->globalAttribute("QCG-COMPUTING_PORT", 19000);
	$self->{SITEDB}->globalAttribute("QCG-NOTIFICATION_PORT", 19001);
	$self->{SITEDB}->globalAttribute("QCG-BROKER_PORT", 8443);
    # ActiveMQ
    $self->{SITEDB}->globalAttribute("STOMP_PORT", 6163);
    $self->{SITEDB}->globalAttribute("STOMP_SSL_PORT", 6162);
    $self->{SITEDB}->globalAttribute("OPENWIRE_PORT", 6166);
    $self->{SITEDB}->globalAttribute("OPENWIRE_SSL_PORT", 6167);
}

# TODO:
#  move these to localdb file
sub _setStaticHostAttrs {
	my $self = shift;
	my $hostname = shift;

    $self->{SITEDB}->hostAttribute($hostname, "HOST_NAME", $hostname);

    if ($self->{ENABLE_UNICORE_PROBES}) {
        my $unicoreLog = "/var/log/unicore/$hostname";
        $self->{SITEDB}->hostAttribute($hostname, "UNICORE_LOGS_DIR", $unicoreLog);
        unless ( -d $unicoreLog ) {
            unless (mkdir $unicoreLog) {
                $self->error("Cannot create UNICORE_LOGS_DIR: $unicoreLog.");
                return;
            }
            my ($login,$pass,$uid,$gid);
            unless ( ($login,$pass,$uid,$gid) = getpwnam("nagios") ) {
                $self->error("User nagios does not exist.");
                return;
            }
            unless ( chown $uid, $gid, $unicoreLog ) {
                $self->error("Failed changing the ownership of UNICORE_LOGS_DIR $unicoreLog to user nagios.");
                return;
            }
        }
    }
}

sub _setStaticAttrs {
	my $self = shift;
	my $hostname = shift;
	my $VDT_LOCATION = "test";

    $self->_setDefaultPorts;

    $self->{SITEDB}->globalAttribute("VDT_LOCATION", $VDT_LOCATION);
    $self->{SITEDB}->globalAttribute("OSG_TEST_FILE", "=/etc/group ");
    $self->{SITEDB}->globalAttribute("SITE_BDII", $self->{SITEDB}->siteLDAP);
    $self->{SITEDB}->globalAttribute("NAGIOS_HOST_CERT", '/etc/nagios/globus/hostcert.pem');
    $self->{SITEDB}->globalAttribute("NAGIOS_HOST_KEY", '/etc/nagios/globus/hostkey.pem');
    $self->{SITEDB}->globalAttribute("SITENAME", $self->{SITENAME});
    $self->{SITEDB}->globalAttribute("GOCDB_ROOT_URL", $self->{GOCDB_ROOT_URL});
    $self->{SITEDB}->globalAttribute("PROXY_LIFETIME", $self->{PROXY_LIFETIME});

    # UNICORE attributes
    $self->{SITEDB}->globalAttribute("UVOS_CLIENT_PATH", '/usr/bin/uvos-clc');
    $self->{SITEDB}->globalAttribute("UCC_PATH", '/usr/bin/ucc');
    $self->{SITEDB}->globalAttribute("JAVA_PATH", 'java');
    $self->{SITEDB}->globalAttribute("UCC_CONFIG", '/etc/nagios/unicore/ucc.config');
    $self->{SITEDB}->globalAttribute("UNICORE_JOB_FILE", '/etc/nagios/unicore/UNICORE_Job.u');
    
    $self->{SITEDB}->globalAttribute("TOP_BDII", $self->{BDII_HOST});
    $self->{SITEDB}->globalAttribute("NAGIOS_HOST_KEYSTORE", '/etc/nagios/globus/hostcert.ks');
    $self->{SITEDB}->globalAttribute("TRUSTSTORE", '/etc/nagios/globus/truststore.ts');
}

=head1 NAME

NCG::SiteInfo::Active

=head1 DESCRIPTION

The NCG::LocalMetricsAttrs::Active module extends NCG::LocalMetricsAttrs
module. Module extracts detailed metric information by using various
heuristics. Heuristics for each service and metricset are placed in
separate method _analyzeXXX.

=head1 SYNOPSIS

  use NCG::LocalMetricsAttrs::LDAP;

  my $metricInfo = NCG::LocalMetricsAttrs::Active->new();

  $metricInfo->getData();

=cut

=head1 METHODS

=over

=item C<new>

  my $siteInfo = NCG::LocalMetricsAttrs::Active->new($options);

Creates new NCG::LocalMetricsAttrs::Active instance. Argument $options is hash
reference that can contain following elements:

  BACKUP_INSTANCE - if set INCLUDE_MSG_CHECKS_SEND will be set to 0. 
                    This variable is used for setting up backup 
                    SAM instance (SAM-1127)
  (default: unset)


  INCLUDE_MSG_CHECKS_RECV - if true configuration for checks receiving results
  via MSG will be generated. Set this option to 0 if you don't want to
  receive results from the other Nagioses or SAM CE WN tests over MSG.
  (default: true)

  INCLUDE_MSG_CHECKS_SEND - if true configuration for checks sending results
  via MSG will be generated. Set this option to 0 if you don't want to
  send results to the rest of the world over MSG.
  (default: true)

  INCLUDE_PROXY_CHECKS - if true configuration for proxy generation
  will be generated. Set this option to 0 if there are no probes which
  require valid proxy certificate.
  (default: true)

  MYPROXY_SERVER - MyProxy server where user credentials are stored.
  (default: )

  NRPE_UI - set to address of remote UI server which is used to run
  local probes.
  (default: )
  
  PROBES_TYPE - which probes to include in configuration.
                Possible values:
                    local  - only locally executed probes are included.
                             Nagios won't pull results from external
                             monitoring systems (SAM).
                    remote - only remotely executed probes are included.
                             Nagios won't run any active probes. MyProxy
                             settings are not required in this case.
                    all    - all probe types are included.
  (default: all)

=back

=head1 SEE ALSO

NCG::LocalMetricsAttrs

=cut

1;
