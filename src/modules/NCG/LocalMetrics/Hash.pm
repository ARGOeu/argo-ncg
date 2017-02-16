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

package NCG::LocalMetrics::Hash;

use NCG::LocalMetrics;
use vars qw(@ISA);
use strict;
use warnings;

@ISA = qw(NCG::LocalMetrics);

our $WLCG_SERVICE;
our $WLCG_NODETYPE;
our $WCLG_SERVICE_FULL;

sub new
{
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);

    if (!$self->{PROFILE}) {
        $self->{PROFILE} = 'site';
    } elsif (! exists $WLCG_NODETYPE->{$self->{PROFILE}}) {
        $self->error("Metrics for the profile $self->{PROFILE} are not defined.");
        return;
    }
    
    if (!$self->{METRIC_CONFIG} || ref $self->{METRIC_CONFIG} ne "HASH" ) {
        $self->warning("Metric configuration is not defined. Metric could be skipped in configuration.");
    } elsif (!$WCLG_SERVICE_FULL) {
        my $merged = {};
        while ( my ($k,$v) = each(%$WLCG_SERVICE) ) {
            $merged->{$k} = $v;
        }
        while ( my ($k,$v) = each(%{$self->{METRIC_CONFIG}}) ) {
            $merged->{$k} = $v unless (exists $merged->{$k});
        }
        $WLCG_SERVICE = $merged;
        $WCLG_SERVICE_FULL = 1;
    }

    $self;
}

sub getData {
    my $self = shift;

    foreach my $host ($self->{SITEDB}->getHosts()) {
        foreach my $service ($self->{SITEDB}->getServices($host)) {
            if (exists $WLCG_NODETYPE->{$self->{PROFILE}}->{$service}) {
                foreach my $metric (@{$WLCG_NODETYPE->{$self->{PROFILE}}->{$service}}) {
                    my $metricRef;
                    if (exists $WLCG_SERVICE->{$self->{PROFILE}}->{$service}->{$metric}) {
                        $metricRef = $WLCG_SERVICE->{$self->{PROFILE}}->{$service}->{$metric};
                    } elsif ($WLCG_SERVICE->{$self->{PROFILE}}->{$metric}) {
                        $metricRef = $WLCG_SERVICE->{$self->{PROFILE}}->{$metric};
                    } else {
                        $metricRef = $WLCG_SERVICE->{$metric};
                    }

                    unless($metricRef) {
                        $self->error("Internal metric $metric is not defined, NCG cannot continue. Please check ncg-metric-config.");
                        return;
                    }

                    my $customMetricRef = $metricRef;

                    # hacks
                    if ($service eq 'ARC-CE' && exists $metricRef->{parent} && $metricRef->{parent} eq 'eu.egi.sec.CE-JobState') {
                        $customMetricRef = {%{$metricRef}};
                        $customMetricRef->{parent} = 'eu.egi.sec.ARCCE-Jobsubmit';
                    }

                    $self->_addLocalMetric($customMetricRef, $host, $metric, $service);
                }
            }
        }
    }

    1;
}

########################################################################
########################################################################
#####
#####
#####       Hard coded Probe Description database
#####
#####
########################################################################
########################################################################

our $SERVICE_TEMPL;

$SERVICE_TEMPL->{2}->{path} = $NCG::NCG_PROBES_PATH_GRIDMON;
$SERVICE_TEMPL->{2}->{interval} = 5;
$SERVICE_TEMPL->{2}->{timeout} = 60;
$SERVICE_TEMPL->{2}->{retryInterval} = 2;
$SERVICE_TEMPL->{2}->{maxCheckAttempts} = 2;

$SERVICE_TEMPL->{5}->{path} = $NCG::NCG_PROBES_PATH_GRIDMON;
$SERVICE_TEMPL->{5}->{interval} = 5;
$SERVICE_TEMPL->{5}->{timeout} = 30;
$SERVICE_TEMPL->{5}->{retryInterval} = 3;
$SERVICE_TEMPL->{5}->{maxCheckAttempts} = 3;

$SERVICE_TEMPL->{15}->{path} = $NCG::NCG_PROBES_PATH_GRIDMON;
$SERVICE_TEMPL->{15}->{interval} = 15;
$SERVICE_TEMPL->{15}->{timeout} = 120;
$SERVICE_TEMPL->{15}->{retryInterval} = 5;
$SERVICE_TEMPL->{15}->{maxCheckAttempts} = 4;

$SERVICE_TEMPL->{30}->{path} = $NCG::NCG_PROBES_PATH_GRIDMON;
$SERVICE_TEMPL->{30}->{interval} = 30;
$SERVICE_TEMPL->{30}->{timeout} = 30;
$SERVICE_TEMPL->{30}->{retryInterval} = 5;
$SERVICE_TEMPL->{30}->{maxCheckAttempts} = 3;

$SERVICE_TEMPL->{60}->{path} = $NCG::NCG_PROBES_PATH_GRIDMON;
$SERVICE_TEMPL->{60}->{interval} = 60;
$SERVICE_TEMPL->{60}->{timeout} = 600;
$SERVICE_TEMPL->{60}->{retryInterval} = 15;
$SERVICE_TEMPL->{60}->{maxCheckAttempts} = 4;

$SERVICE_TEMPL->{360}->{path} = $NCG::NCG_PROBES_PATH_GRIDMON;
$SERVICE_TEMPL->{360}->{interval} = 360;
$SERVICE_TEMPL->{360}->{timeout} = 30;
$SERVICE_TEMPL->{360}->{retryInterval} = 15;
$SERVICE_TEMPL->{360}->{maxCheckAttempts} = 3;

$SERVICE_TEMPL->{1440}->{path} = $NCG::NCG_PROBES_PATH_GRIDMON;
$SERVICE_TEMPL->{1440}->{interval} = 1440;
$SERVICE_TEMPL->{1440}->{timeout} = 120;
$SERVICE_TEMPL->{1440}->{retryInterval} = 60;
$SERVICE_TEMPL->{1440}->{maxCheckAttempts} = 4;

$SERVICE_TEMPL->{240}->{path} = $NCG::NCG_PROBES_PATH_GRIDMON;
$SERVICE_TEMPL->{240}->{interval} = 240;
$SERVICE_TEMPL->{240}->{timeout} = 60;
$SERVICE_TEMPL->{240}->{retryInterval} = 30;
$SERVICE_TEMPL->{240}->{maxCheckAttempts} = 4;

$SERVICE_TEMPL->{native_5}->{path} = $NCG::NCG_PROBES_PATH_NAGIOS;
$SERVICE_TEMPL->{native_5}->{interval} = 5;
$SERVICE_TEMPL->{native_5}->{timeout} = 30;
$SERVICE_TEMPL->{native_5}->{retryInterval} = 3;
$SERVICE_TEMPL->{native_5}->{maxCheckAttempts} = 3;

$SERVICE_TEMPL->{native_15}->{path} = $NCG::NCG_PROBES_PATH_NAGIOS;
$SERVICE_TEMPL->{native_15}->{interval} = 15;
$SERVICE_TEMPL->{native_15}->{timeout} = 60;
$SERVICE_TEMPL->{native_15}->{retryInterval} = 5;
$SERVICE_TEMPL->{native_15}->{maxCheckAttempts} = 4;

#
# Nagios internal checks profile
#

# cadist(.nrpe).template
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-GetFiles'}->{config} = {%{$SERVICE_TEMPL->{360}}};
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-GetFiles'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-GetFiles'}->{config}->{path} = '/usr/libexec/argo-monitoring/probes/igtf/';
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-GetFiles'}->{config}->{timeout} = 120;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-GetFiles'}->{probe} = 'download_files';
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-GetFiles'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-GetFiles'}->{docurl} = "http://wiki.cro-ngi.hr/en/index.php/hr.srce.CADist-GetFiles";
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-GetFiles'}->{parameter}->{'--download-list'} = 'http://repository.egi.eu/sw/production/cas/1/current/meta/ca-policy-egi-core.release,http://repository.egi.eu/sw/production/cas/1/current/meta/ca-policy-egi-core.list,http://repository.egi.eu/sw/production/cas/1/current/meta/ca-policy-egi-core.obsoleted,http://repository.egi.eu/sw/production/cas/1/current/meta/ca-policy-egi-core.subjectdn,http://repository.egi.eu/sw/production/cas/1/current/meta/ca-policy-egi-core.obsoleted-subjectdn';

$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-Check'}->{config} = {%{$SERVICE_TEMPL->{1440}}};
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-Check'}->{config}->{maxCheckAttempts} = 2;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-Check'}->{config}->{path} = '/usr/libexec/argo-monitoring/probes/igtf/';
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-Check'}->{probe} = 'check_ca_dist';
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-Check'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-Check'}->{docurl} = "http://wiki.cro-ngi.hr/en/index.php/hr.srce.CADist-Check";
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-Check'}->{parameter}->{'--release-url'} = '/var/spool/nagios/nagios-plugins-igtf/ca-policy-egi-core.release,http://repository.egi.eu/sw/production/cas/1/current/meta/ca-policy-egi-core.release';
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-Check'}->{parameter}->{'--package-list-url'} = '/var/spool/nagios/nagios-plugins-igtf/ca-policy-egi-core.list,http://repository.egi.eu/sw/production/cas/1/current/meta/ca-policy-egi-core.list';
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CADist-Check'}->{parameter}->{'--obsolete-list-url'} = '/var/spool/nagios/nagios-plugins-igtf/ca-policy-egi-core.obsoleted,http://repository.egi.eu/sw/production/cas/1/current/meta/ca-policy-egi-core.obsoleted';

$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CADist-Check'}->{config} = {%{$SERVICE_TEMPL->{1440}}};
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CADist-Check'}->{config}->{maxCheckAttempts} = 2;
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CADist-Check'}->{config}->{path} = '/usr/libexec/argo-monitoring/probes/igtf/';
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CADist-Check'}->{probe} = 'check_ca_dist';
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CADist-Check'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CADist-Check'}->{flags}->{NRPE_SERVICE} = 1;
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CADist-Check'}->{docurl} = "http://wiki.cro-ngi.hr/en/index.php/hr.srce.CADist-Check";
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CADist-Check'}->{parameter}->{'--release-url'} = 'http://repository.egi.eu/sw/production/cas/1/current/meta/ca-policy-egi-core.release';
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CADist-Check'}->{parameter}->{'--package-list-url'} = 'http://repository.egi.eu/sw/production/cas/1/current/meta/ca-policy-egi-core.list';
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CADist-Check'}->{parameter}->{'--obsolete-list-url'} = 'http://repository.egi.eu/sw/production/cas/1/current/meta/ca-policy-egi-core.obsoleted';

$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CertLifetime'}->{probe} = 'CertLifetime-probe';
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CertLifetime'}->{config} = {%{$SERVICE_TEMPL->{240}}};
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CertLifetime'}->{config}->{path} = '/usr/libexec/argo-monitoring/probes/cert';
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CertLifetime'}->{config}->{maxCheckAttempts} = 2;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CertLifetime'}->{attribute}->{NAGIOS_HOST_CERT} = "-f";
$WLCG_SERVICE->{internal}->{NAGIOS}->{'hr.srce.CertLifetime'}->{flags}->{NOHOSTNAME} = 1;

$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CertLifetime'}->{probe} = "CertLifetime-probe";
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CertLifetime'}->{config} = {%{$SERVICE_TEMPL->{240}}};
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CertLifetime'}->{config}->{maxCheckAttempts} = 2;
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CertLifetime'}->{config}->{path} = '/usr/libexec/argo-monitoring/probes/cert';
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CertLifetime'}->{attribute}->{NAGIOS_HOST_CERT} = "-f";
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CertLifetime'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{internal}->{NRPE}->{'hr.srce.CertLifetime'}->{flags}->{NRPE_SERVICE} = 1;

$WLCG_SERVICE->{internal}->{'eu.egi.sec.CRL'}->{probe} = 'eu.egi.sec/probes/CRL';
$WLCG_SERVICE->{internal}->{'eu.egi.sec.CRL'}->{config}->{path} = $NCG::NCG_PROBES_PATH_GRIDMON;
$WLCG_SERVICE->{internal}->{'eu.egi.sec.CRL'}->{config}->{interval} = 1440;
$WLCG_SERVICE->{internal}->{'eu.egi.sec.CRL'}->{config}->{timeout} = 120;
$WLCG_SERVICE->{internal}->{'eu.egi.sec.CRL'}->{config}->{retryInterval} = 60;
$WLCG_SERVICE->{internal}->{'eu.egi.sec.CRL'}->{config}->{maxCheckAttempts} = 2;
$WLCG_SERVICE->{internal}->{'eu.egi.sec.CRL'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{internal}->{'eu.egi.sec.CRL'}->{flags}->{PNP} = 1;
$WLCG_SERVICE->{internal}->{'eu.egi.sec.CRL'}->{flags}->{NOARGS} = 1;

$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.DiskCheck'}->{probe} = 'check_disk';
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.DiskCheck'}->{config}->{path} = $NCG::NCG_PROBES_PATH_NAGIOS;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.DiskCheck'}->{config}->{interval} = 60;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.DiskCheck'}->{config}->{timeout} = 15;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.DiskCheck'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.DiskCheck'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.DiskCheck'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.DiskCheck'}->{flags}->{PNP} = 1;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.DiskCheck'}->{parameter}->{-w} = '10%';
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.DiskCheck'}->{parameter}->{-c} = '5%';

$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.DiskCheck'}->{probe} = 'check_disk';
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.DiskCheck'}->{config}->{path} = $NCG::NCG_PROBES_PATH_NAGIOS;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.DiskCheck'}->{config}->{interval} = 60;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.DiskCheck'}->{config}->{timeout} = 15;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.DiskCheck'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.DiskCheck'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.DiskCheck'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.DiskCheck'}->{flags}->{PNP} = 1;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.DiskCheck'}->{flags}->{NRPE_SERVICE} = 1;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.DiskCheck'}->{parameter}->{-w} = '10%';
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.DiskCheck'}->{parameter}->{-c} = '5%';

$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.ProcessCrond'}->{probe} = 'check_procs';
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.ProcessCrond'}->{config}->{path} = $NCG::NCG_PROBES_PATH_NAGIOS;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.ProcessCrond'}->{config}->{interval} = 15;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.ProcessCrond'}->{config}->{timeout} = 15;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.ProcessCrond'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.ProcessCrond'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.ProcessCrond'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.ProcessCrond'}->{parameter}->{-C} = 'crond';
$WLCG_SERVICE->{internal}->{NAGIOS}->{'org.nagios.ProcessCrond'}->{parameter}->{-c} = '1:10';

$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.ProcessCrond'}->{probe} = 'check_procs';
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.ProcessCrond'}->{config}->{path} = $NCG::NCG_PROBES_PATH_NAGIOS;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.ProcessCrond'}->{config}->{interval} = 15;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.ProcessCrond'}->{config}->{timeout} = 15;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.ProcessCrond'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.ProcessCrond'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.ProcessCrond'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.ProcessCrond'}->{parameter}->{-C} = 'crond';
$WLCG_SERVICE->{internal}->{NRPE}->{'org.nagios.ProcessCrond'}->{parameter}->{-c} = '1:10';

$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNpcd'}->{probe} = 'check_procs';
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNpcd'}->{config}->{path} = $NCG::NCG_PROBES_PATH_NAGIOS;
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNpcd'}->{config}->{interval} = 15;
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNpcd'}->{config}->{timeout} = 15;
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNpcd'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNpcd'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNpcd'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNpcd'}->{parameter}->{-C} = 'npcd';
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNpcd'}->{parameter}->{-c} = '1:10';

$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNSCA'}->{probe} = 'check_procs';
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNSCA'}->{config}->{path} = $NCG::NCG_PROBES_PATH_NAGIOS;
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNSCA'}->{config}->{interval} = 15;
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNSCA'}->{config}->{timeout} = 15;
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNSCA'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNSCA'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNSCA'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNSCA'}->{parameter}->{-C} = 'nsca';
$WLCG_SERVICE->{internal}->{'org.nagios.ProcessNSCA'}->{parameter}->{-c} = '1:10';

# gocdbdowntime.template

$WLCG_SERVICE->{'org.egee.ImportGocdbDowntimes'}->{probe} = "nagios-gocdb-downtime";
$WLCG_SERVICE->{'org.egee.ImportGocdbDowntimes'}->{config}->{path} = '/usr/libexec/argo-monitoring/probes/gocdb';
$WLCG_SERVICE->{'org.egee.ImportGocdbDowntimes'}->{config}->{interval} = 240;
$WLCG_SERVICE->{'org.egee.ImportGocdbDowntimes'}->{config}->{timeout} = 120;
$WLCG_SERVICE->{'org.egee.ImportGocdbDowntimes'}->{config}->{retryInterval} = 10;
$WLCG_SERVICE->{'org.egee.ImportGocdbDowntimes'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{'org.egee.ImportGocdbDowntimes'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'org.egee.ImportGocdbDowntimes'}->{flags}->{PNP} = 1;
$WLCG_SERVICE->{'org.egee.ImportGocdbDowntimes'}->{attribute}->{SITE_LIST} = "--entity";
$WLCG_SERVICE->{'org.egee.ImportGocdbDowntimes'}->{attribute}->{GOCDB_ROOT_URL} = "--gocdb-root-url";

# gridproxy(.nrpe).template
$WLCG_SERVICE->{'org.nagiosexchange.LogFiles'}->{probe} = 'org.nagiosexchange/check_logfiles';
$WLCG_SERVICE->{'org.nagiosexchange.LogFiles'}->{config} = {%{$SERVICE_TEMPL->{30}}};
$WLCG_SERVICE->{'org.nagiosexchange.LogFiles'}->{config}->{maxCheckAttempts} = 1;
$WLCG_SERVICE->{'org.nagiosexchange.LogFiles'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'org.nagiosexchange.LogFiles'}->{flags}->{PNP} = 1;
$WLCG_SERVICE->{'org.nagiosexchange.LogFiles'}->{flags}->{SUDO} = 1;
$WLCG_SERVICE->{'org.nagiosexchange.LogFiles'}->{parameter}->{'-f'} = '/etc/grid-monitoring-org.nagiosexchange/check_logfiles.conf';

$WLCG_SERVICE->{'org.nagiosexchange.NCGLogFiles'}->{probe} = 'org.nagiosexchange/check_logfiles';
$WLCG_SERVICE->{'org.nagiosexchange.NCGLogFiles'}->{config} = {%{$SERVICE_TEMPL->{30}}};
$WLCG_SERVICE->{'org.nagiosexchange.NCGLogFiles'}->{config}->{maxCheckAttempts} = 1;
$WLCG_SERVICE->{'org.nagiosexchange.NCGLogFiles'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'org.nagiosexchange.NCGLogFiles'}->{flags}->{PNP} = 1;
$WLCG_SERVICE->{'org.nagiosexchange.NCGLogFiles'}->{parameter}->{'-f'} = '/etc/argo-ncg/check_logfiles_ncg.conf';

$WLCG_SERVICE->{'hr.srce.GridProxy-Valid'}->{probe} = "GridProxy-probe";
$WLCG_SERVICE->{'hr.srce.GridProxy-Valid'}->{config}->{path} = '/usr/libexec/argo-monitoring/probes/globus';
$WLCG_SERVICE->{'hr.srce.GridProxy-Valid'}->{config}->{timeout} = 30;
$WLCG_SERVICE->{'hr.srce.GridProxy-Valid'}->{config}->{interval} = 15;
$WLCG_SERVICE->{'hr.srce.GridProxy-Valid'}->{config}->{retryInterval} = 3;
$WLCG_SERVICE->{'hr.srce.GridProxy-Valid'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{'hr.srce.GridProxy-Valid'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'hr.srce.GridProxy-Valid'}->{flags}->{VO} = 1;
$WLCG_SERVICE->{'hr.srce.GridProxy-Valid'}->{flags}->{NRPE} = 1;
$WLCG_SERVICE->{'hr.srce.GridProxy-Valid'}->{flags}->{LOCALDEP} = 1;
$WLCG_SERVICE->{'hr.srce.GridProxy-Valid'}->{attribute}->{X509_USER_PROXY} = "-x";
$WLCG_SERVICE->{'hr.srce.GridProxy-Valid'}->{attribute}->{VONAME} = "--vo";
$WLCG_SERVICE->{'hr.srce.GridProxy-Valid'}->{dependency}->{"hr.srce.GridProxy-Get"} = 0;

$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{probe} = "refresh_proxy";
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{config}->{timeout} = 120;
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{config}->{interval} = 240;
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{config}->{path} = '/usr/libexec/argo-monitoring/probes/globus';
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{flags}->{VO} = 1;
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{flags}->{NRPE} = 1;
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{flags}->{LOCALDEP} = 1;
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{attribute}->{X509_USER_PROXY} = "-x";
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{attribute}->{VONAME} = "--vo";
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{attribute}->{VO_FQAN} = "--vo-fqan";
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{attribute}->{MYPROXY_USER} = "--myproxyuser";
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{attribute}->{MYPROXY_NAME} = "--name";
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{attribute}->{MYPROXY_SERVER} = "-H";
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{attribute}->{NAGIOS_HOST_CERT} = "--cert";
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{attribute}->{NAGIOS_HOST_KEY} = "--key";
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{attribute}->{ROBOT_CERT} = "--robot-cert";
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{attribute}->{ROBOT_KEY} = "--robot-key";
$WLCG_SERVICE->{'hr.srce.GridProxy-Get'}->{attribute}->{PROXY_LIFETIME} = "--lifetime";

# myproxy(.nrpe).template

$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{probe} = "MyProxy-probe";
$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{config}->{timeout} = 120;
$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{config}->{interval} = 60;
$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{config}->{path} = '/usr/libexec/argo-monitoring/probes/globus';
$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{flags}->{VO} = 1;
$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{flags}->{NRPE} = 1;
$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{flags}->{LOCALDEP} = 1;
$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{attribute}->{X509_USER_PROXY} = "-x";
$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{attribute}->{MYPROXY_USER} = "--myproxyuser";
$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{attribute}->{MYPROXY_NAME} = "--name";
$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{parameter}->{'-m'} = 'MyProxy-ProxyLifetime';
$WLCG_SERVICE->{'hr.srce.MyProxy-ProxyLifetime'}->{dependency}->{"hr.srce.GridProxy-Valid"} = 0;

$WLCG_SERVICE->{'NRPE'}->{probe} = "check_nrpe";
$WLCG_SERVICE->{'NRPE'}->{config}->{timeout} = 10;
$WLCG_SERVICE->{'NRPE'}->{config}->{interval} = 10;
$WLCG_SERVICE->{'NRPE'}->{config}->{retryInterval} = 2;
$WLCG_SERVICE->{'NRPE'}->{config}->{maxCheckAttempts} = 4;
$WLCG_SERVICE->{'NRPE'}->{config}->{path} = $NCG::NCG_PROBES_PATH_GRIDMON;
$WLCG_SERVICE->{'NRPE'}->{flags}->{NOARGS} = 1;

# sendtomsg.template

$WLCG_SERVICE->{'org.egee.SendToMsg'}->{probe} = "send_to_msg";
$WLCG_SERVICE->{'org.egee.SendToMsg'}->{config}->{timeout} = 120;
$WLCG_SERVICE->{'org.egee.SendToMsg'}->{config}->{interval} = 5;
$WLCG_SERVICE->{'org.egee.SendToMsg'}->{config}->{retryInterval} = 2;
$WLCG_SERVICE->{'org.egee.SendToMsg'}->{config}->{maxCheckAttempts} = 4;
$WLCG_SERVICE->{'org.egee.SendToMsg'}->{config}->{path} = '/usr/libexec/argo-msg-nagios/';
$WLCG_SERVICE->{'org.egee.SendToMsg'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'org.egee.SendToMsg'}->{flags}->{PNP} = 1;
$WLCG_SERVICE->{'org.egee.SendToMsg'}->{parameter}->{'--persistent'} = '';

$WLCG_SERVICE->{'org.egee.RecvFromQueue'}->{probe} = "recv_from_queue";
$WLCG_SERVICE->{'org.egee.RecvFromQueue'}->{config}->{timeout} = 120;
$WLCG_SERVICE->{'org.egee.RecvFromQueue'}->{config}->{interval} = 5;
$WLCG_SERVICE->{'org.egee.RecvFromQueue'}->{config}->{retryInterval} = 2;
$WLCG_SERVICE->{'org.egee.RecvFromQueue'}->{config}->{maxCheckAttempts} = 4;
$WLCG_SERVICE->{'org.egee.RecvFromQueue'}->{config}->{path} = '/usr/libexec/argo-msg-nagios/';
$WLCG_SERVICE->{'org.egee.RecvFromQueue'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'org.egee.RecvFromQueue'}->{flags}->{NOARGS} = 1;
$WLCG_SERVICE->{'org.egee.RecvFromQueue'}->{flags}->{PNP} = 1;

$WLCG_SERVICE->{'org.egee.CheckConfig'}->{probe} = "recv_from_queue";
$WLCG_SERVICE->{'org.egee.CheckConfig'}->{config}->{timeout} = 120;
$WLCG_SERVICE->{'org.egee.CheckConfig'}->{config}->{interval} = 30;
$WLCG_SERVICE->{'org.egee.CheckConfig'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{'org.egee.CheckConfig'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{'org.egee.CheckConfig'}->{config}->{path} = $NCG::NCG_PLUGINS_PATH_GRIDMON;
$WLCG_SERVICE->{'org.egee.CheckConfig'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'org.egee.CheckConfig'}->{flags}->{NOARGS} = 1;
$WLCG_SERVICE->{'org.egee.CheckConfig'}->{flags}->{PNP} = 1;

$WLCG_SERVICE->{'org.nagios.MsgDirSize'}->{probe} = "org.nagiosexchange/check_dirsize.sh";
$WLCG_SERVICE->{'org.nagios.MsgDirSize'}->{config}->{timeout} = 15;
$WLCG_SERVICE->{'org.nagios.MsgDirSize'}->{config}->{interval} = 60;
$WLCG_SERVICE->{'org.nagios.MsgDirSize'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{'org.nagios.MsgDirSize'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{'org.nagios.MsgDirSize'}->{config}->{path} = $NCG::NCG_PROBES_PATH_GRIDMON;
$WLCG_SERVICE->{'org.nagios.MsgDirSize'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'org.nagios.MsgDirSize'}->{flags}->{PNP} = 1;
$WLCG_SERVICE->{'org.nagios.MsgDirSize'}->{parameter}->{'-d'} = '/var/spool/msg-nagios-bridge';
$WLCG_SERVICE->{'org.nagios.MsgDirSize'}->{parameter}->{'-w'} = '10000';
$WLCG_SERVICE->{'org.nagios.MsgDirSize'}->{parameter}->{'-c'} = '100000';
$WLCG_SERVICE->{'org.nagios.MsgDirSize'}->{parameter}->{'-f'} = '';

$WLCG_SERVICE->{'org.nagios.ProcessMsgToHandler'}->{probe} = 'check_procs';
$WLCG_SERVICE->{'org.nagios.ProcessMsgToHandler'}->{config}->{path} = $NCG::NCG_PROBES_PATH_NAGIOS;
$WLCG_SERVICE->{'org.nagios.ProcessMsgToHandler'}->{config}->{interval} = 15;
$WLCG_SERVICE->{'org.nagios.ProcessMsgToHandler'}->{config}->{timeout} = 15;
$WLCG_SERVICE->{'org.nagios.ProcessMsgToHandler'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{'org.nagios.ProcessMsgToHandler'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{'org.nagios.ProcessMsgToHandler'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'org.nagios.ProcessMsgToHandler'}->{parameter}->{-C} = 'msg-to-handler';
$WLCG_SERVICE->{'org.nagios.ProcessMsgToHandler'}->{parameter}->{-c} = '1:10';

$WLCG_SERVICE->{'org.nagios.MsgToHandlerPidFile'}->{probe} = 'check_file_age';
$WLCG_SERVICE->{'org.nagios.MsgToHandlerPidFile'}->{config}->{path} = $NCG::NCG_PROBES_PATH_NAGIOS;
$WLCG_SERVICE->{'org.nagios.MsgToHandlerPidFile'}->{config}->{interval} = 60;
$WLCG_SERVICE->{'org.nagios.MsgToHandlerPidFile'}->{config}->{timeout} = 15;
$WLCG_SERVICE->{'org.nagios.MsgToHandlerPidFile'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{'org.nagios.MsgToHandlerPidFile'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{'org.nagios.MsgToHandlerPidFile'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'org.nagios.MsgToHandlerPidFile'}->{flags}->{NOTIMEOUT} = 1;
$WLCG_SERVICE->{'org.nagios.MsgToHandlerPidFile'}->{parameter}->{-f} = '/var/run/msg-to-handler/pid';
$WLCG_SERVICE->{'org.nagios.MsgToHandlerPidFile'}->{parameter}->{-w} = '300';
$WLCG_SERVICE->{'org.nagios.MsgToHandlerPidFile'}->{parameter}->{-c} = '600';

$WLCG_SERVICE->{'org.nagios.NagiosCmdFile'}->{probe} = 'org.nagiosexchange/check_file';
$WLCG_SERVICE->{'org.nagios.NagiosCmdFile'}->{config}->{path} = $NCG::NCG_PROBES_PATH_GRIDMON;
$WLCG_SERVICE->{'org.nagios.NagiosCmdFile'}->{config}->{interval} = 15;
$WLCG_SERVICE->{'org.nagios.NagiosCmdFile'}->{config}->{timeout} = 10;
$WLCG_SERVICE->{'org.nagios.NagiosCmdFile'}->{config}->{retryInterval} = 3;
$WLCG_SERVICE->{'org.nagios.NagiosCmdFile'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{'org.nagios.NagiosCmdFile'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'org.nagios.NagiosCmdFile'}->{parameter}->{-F} = '/var/nagios/rw/nagios.cmd';
$WLCG_SERVICE->{'org.nagios.NagiosCmdFile'}->{parameter}->{-p} = '';
$WLCG_SERVICE->{'org.nagios.NagiosCmdFile'}->{parameter}->{-r} = '';
$WLCG_SERVICE->{'org.nagios.NagiosCmdFile'}->{parameter}->{-w} = '';
$WLCG_SERVICE->{'org.nagios.NagiosCmdFile'}->{parameter}->{-o} = '';

# GoodCEs for SAM-WMS

$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{probe} = "gather_healthy_nodes";
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{config}->{timeout} = 120;
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{config}->{interval} = 15;
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{config}->{path} = '/usr/libexec/argo-nagios-tools';
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{flags}->{PNP} = 1;
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{flags}->{VO} = 1;
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{flags}->{LOCALDEP} = 1;
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{flags}->{REQUIREMENT} = 'emi.wms.WMS-JobSubmit';
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{attribute}->{VONAME} = "--vo";
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{attribute}->{VO_FQAN} = "--vo-fqan";
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{parameter}->{'--dir'} = '/var/lib/gridprobes';
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{parameter}->{'--file'} = 'GoodCEs';
$WLCG_SERVICE->{'hr.srce.GoodCEs'}->{parameter}->{"--metric"} = 'emi.cream.CREAMCE-JobPurge';

$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{probe} = "gather_healthy_nodes";
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{config}->{timeout} = 120;
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{config}->{interval} = 15;
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{config}->{retryInterval} = 5;
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{config}->{maxCheckAttempts} = 3;
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{config}->{path} = '/usr/libexec/argo-nagios-tools';
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{flags}->{NOHOSTNAME} = 1;
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{flags}->{PNP} = 1;
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{flags}->{VO} = 1;
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{flags}->{LOCALDEP} = 1;
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{attribute}->{VONAME} = "--vo";
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{attribute}->{VO_FQAN} = "--vo-fqan";
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{parameter}->{"--metric"} = 'org.sam.SRM-All';
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{parameter}->{'--dir'} = '/var/lib/gridprobes';
$WLCG_SERVICE->{'hr.srce.GoodSEs'}->{parameter}->{'--file'} = 'GoodSEs';


########################################################################

########################################################################
########################################################################
##
## PROFILES
##
########################################################################
########################################################################

# service must be consistent with GOCDB service naming

# site profile
# table ServiceNodeType
$WLCG_NODETYPE->{site}->{'sBDII'} = ['org.nagios.BDII-Check','org.bdii.Freshness','org.bdii.Entries','org.gstat.SanityCheck','org.nmap.Site-BDII','org.gstat.Site'];
$WLCG_NODETYPE->{site}->{'Top-BDII'} = ['org.nagios.BDII-Check','org.bdii.Freshness','org.bdii.Entries','org.nmap.Top-BDII'];
$WLCG_NODETYPE->{site}->{'Site-BDII'} = ['org.nagios.BDII-Check','org.bdii.Freshness','org.bdii.Entries','org.gstat.SanityCheck','org.nmap.Site-BDII','org.gstat.Site'];
$WLCG_NODETYPE->{site}->{RB} = ['hr.srce.ResourceBroker-CertLifetime','hr.srce.GridFTP-Transfer','org.nagios.GridFTP-Check','org.nagios.LocalLogger-PortCheck','org.nmap.RB'];
$WLCG_NODETYPE->{site}->{SRM} =   ['hr.srce.SRM1-CertLifetime','hr.srce.SRM2-CertLifetime','org.nagios.BDII-Check','hr.srce.DPNS-List','org.sam.SRM-All','org.sam.SRM-GetSURLs','org.sam.SRM-LsDir','org.sam.SRM-Put','org.sam.SRM-Ls','org.sam.SRM-GetTURLs','org.sam.SRM-Get','org.sam.SRM-Del','org.nmap.SRM','org.nmap.SRM1','org.gstat.SE'];
$WLCG_NODETYPE->{site}->{SRMv2} = ['hr.srce.SRM2-CertLifetime','org.nagios.BDII-Check','hr.srce.DPNS-List','org.sam.SRM-All','org.sam.SRM-GetSURLs','org.sam.SRM-LsDir','org.sam.SRM-Put','org.sam.SRM-Ls','org.sam.SRM-GetTURLs','org.sam.SRM-Get','org.sam.SRM-Del','org.nmap.SRM','org.gstat.SE'];
$WLCG_NODETYPE->{site}->{SRMv1} = ['hr.srce.SRM1-CertLifetime','hr.srce.SRM2-CertLifetime','org.nagios.BDII-Check','hr.srce.DPNS-List','org.nmap.SRM1','org.gstat.SE'];
$WLCG_NODETYPE->{site}->{MyProxy} = ['hr.srce.MyProxy-Store','hr.srce.MyProxy-CertLifetime','org.nagios.BDII-Check','org.nmap.MyProxy'];
$WLCG_NODETYPE->{site}->{'Central-LFC'} = ['ch.cern.LFC-Write','ch.cern.LFC-Read','ch.cern.LFC-Readdir','ch.cern.LFC-ReadDli','org.nagios.BDII-Check','org.nmap.Central-LFC','ch.cern.LFC-Ping','org.sam.LFC-CertLifetime'];
$WLCG_NODETYPE->{site}->{'Local-LFC'} = ['org.nmap.Local-LFC','org.nagios.BDII-Check','ch.cern.LFC-Read','ch.cern.LFC-Readdir','ch.cern.LFC-Ping','org.sam.LFC-CertLifetime'];
$WLCG_NODETYPE->{site}->{WMS} = ['org.nagios.BDII-Check', 'hr.srce.GridFTP-Transfer','org.nagios.GridFTP-Check','hr.srce.WMProxy-CertLifetime','org.nagios.LocalLogger-PortCheck','org.nmap.WMS','org.nmap.WMProxy','emi.wms.WMS-JobState','emi.wms.WMS-JobSubmit'];
$WLCG_NODETYPE->{site}->{LB} = ['org.nmap.LB','hr.srce.LB-CertLifetime'];
$WLCG_NODETYPE->{site}->{VOMS} = ['org.nmap.VOMS','hr.srce.VOMS-ServiceStatus','hr.srce.VOMS-CertLifetime'];
$WLCG_NODETYPE->{site}->{FTS} = ['org.nagios.BDII-Check','ch.cern.FTS-ChannelList','org.nmap.FTS','ch.cern.FTS-InfoSites','hr.srce.FTS-CertLifetime'];
$WLCG_NODETYPE->{site}->{'VO-box'} = ['org.nagios.gsissh-Check'];
$WLCG_NODETYPE->{site}->{'CREAM-CE'} = ['hr.srce.GridFTP-Transfer','org.nagios.GridFTP-Check', 'org.nmap.CREAM-CE', 'org.gstat.CE','org.nagios.BDII-Check','emi.cream.CREAMCE-DirectJobState','emi.cream.CREAMCE-DirectJobSubmit','hr.srce.CREAMCE-CertLifetime'];
$WLCG_NODETYPE->{site}->{'SCAS'} = ['org.egee.SCAS-Check'];

$WLCG_NODETYPE->{SITE} = $WLCG_NODETYPE->{site};

# Security monitoring profile
$WLCG_NODETYPE->{security}->{CE} = [
'eu.egi.sec.CREAMCE-JobState',
'eu.egi.sec.CREAMCE-JobSubmit',
'eu.egi.sec.WN-CRL',
'eu.egi.sec.WN-Pakiti',
'eu.egi.sec.WN-Permissions',
'eu.egi.sec.WN-FilePermVulns',
'eu.egi.sec.WN-Torque',
'eu.egi.sec.WN-RDSModuleCheck',
];

$WLCG_NODETYPE->{security}->{"CREAM-CE"} = [
'eu.egi.sec.CREAMCE-JobState',
'eu.egi.sec.CREAMCE-JobSubmit',
'eu.egi.sec.WN-CRL',
'eu.egi.sec.WN-Pakiti',
'eu.egi.sec.WN-Permissions',
'eu.egi.sec.WN-FilePermVulns',
'eu.egi.sec.WN-Torque',
'eu.egi.sec.WN-RDSModuleCheck',
];

$WLCG_NODETYPE->{security}->{"ARC-CE"} = [
'eu.egi.sec.ARCCE-Jobsubmit',
'eu.egi.sec.WN-Pakiti',
'eu.egi.sec.WN-Permissions',
'eu.egi.sec.WN-FilePermVulns',
'eu.egi.sec.WN-Torque',
'eu.egi.sec.WN-RDSModuleCheck',
];

# Nagios internal checks profile
$WLCG_NODETYPE->{internal}->{"NAGIOS"} = [
'hr.srce.CADist-Check',
'hr.srce.CADist-GetFiles',
'hr.srce.CertLifetime',
'org.nagios.DiskCheck',
'org.nagios.ProcessCrond',
'org.nagios.ProcessNpcd',
'org.nagios.ProcessNSCA', # (if NRPE_UI is set)
'org.egee.ImportGocdbDowntimes',
'hr.srce.GridProxy-Valid', # (if INCLUDE_PROXY_CHECKS && local, NRPE)
'hr.srce.GridProxy-Get', # (if INCLUDE_PROXY_CHECKS && local, NRPE)

'org.egee.SendToMsg', # (if INCLUDE_MSG_SEND_CHECKS
'org.egee.RecvFromQueue', # (if INCLUDE_MSG_CHECKS_RECV
#'org.egee.CheckConfig', # (if INCLUDE_MSG_CHECKS_RECV
'org.nagios.MsgDirSize', # (if INCLUDE_MSG_CHECKS_RECV || INCLUDE_MSG_SEND_CHECKS
'org.nagios.ProcessMsgToHandler', # (if INCLUDE_MSG_CHECKS_RECV
'org.nagios.MsgToHandlerPidFile', # (if INCLUDE_MSG_CHECKS_RECV
'hr.srce.GoodCEs',
'hr.srce.GoodSEs',
'org.nagiosexchange.LogFiles',
'org.nagios.NagiosCmdFile',
'org.nagiosexchange.NCGLogFiles',
'emi.wms.WMS-JobMonit',
'org.nordugrid.ARC-CE-monitor',
'org.nordugrid.ARC-CE-clean',
];

$WLCG_NODETYPE->{internal}->{"NRPE"} = [
'hr.srce.CADist-Check',
'hr.srce.CertLifetime',
'org.nagios.DiskCheck',
'org.nagios.ProcessCrond',
#'NRPE'
];
$WLCG_NODETYPE->{internal}->{"MyProxy"} = [
'hr.srce.MyProxy-ProxyLifetime', # (if INCLUDE_PROXY_CHECKS, NRPE)
];

=head1 NAME

NCG::LocalMetrics::Hash

=head1 DESCRIPTION

The NCG::LocalMetrics::Hash module extends NCG::LocalMetrics module.
Module extracts metric information from hard-coded hash.

=head1 SYNOPSIS

  use NCG::LocalMetrics::Hash;

  my $lms = NCG::LocalMetrics::Hash->new( { SITEDB=> $sitedb,
                                    NATIVE => 'Nagios' } );

  $lms->getData();

=cut

=head1 METHODS

=over

=item C<new>

  $siteInfo = NCG::LocalMetrics::Hash->new( $options );

Creates new NCG::LocalMetrics::Hash instance. Argument $options is hash
reference that can contain following elements:
  NATIVE - name of underlying monitoring system; if set this
  variable is used to filter metrics gathered by using native
  probes (e.g. Nagios: check_tcp, check_ftp). If not set,
  all defined metrics will be loaded.

=back

=head1 SEE ALSO

NCG::LocalMetrics

=cut

1;
