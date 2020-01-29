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

our $WLCG_NODETYPE;

sub new
{
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);

    if (! exists $WLCG_NODETYPE->{$self->{PROFILE}}) {
        $self->error("Metrics for the profile $self->{PROFILE} are not defined.");
        return;
    }
    
    if (!$self->{METRIC_CONFIG} || ref $self->{METRIC_CONFIG} ne "HASH" ) {
        $self->warning("Metric configuration is not defined. Metric could be skipped in configuration.");
    } 

    $self;
}

sub getData {
    my $self = shift;

    foreach my $host ($self->{SITEDB}->getHosts()) {
        foreach my $service ($self->{SITEDB}->getServices($host)) {
            if (exists $WLCG_NODETYPE->{$self->{PROFILE}}->{$service}) {
                foreach my $metric (@{$WLCG_NODETYPE->{$self->{PROFILE}}->{$service}}) {
                    my $metricRef = $self->{METRIC_CONFIG}->{$metric};
                    unless($metricRef) {
                        $self->error("Internal metric $metric is not defined, NCG cannot continue.");
                        return;
                    }
                    my $customMetricRef = {%{$metricRef}};

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

# Nagios internal checks profile
$WLCG_NODETYPE->{internal}->{"NAGIOS"} = [
'hr.srce.CADist-Check',
'hr.srce.CADist-GetFiles',
'hr.srce.CertLifetime-Local',
'org.nagios.DiskCheck-Local',
'org.nagios.ProcessCrond',
'hr.srce.GridProxy-Valid', # (if INCLUDE_PROXY_CHECKS && local, NRPE)
'hr.srce.GridProxy-Get', # (if INCLUDE_PROXY_CHECKS && local, NRPE)
'org.egee.RecvFromQueue', # (if INCLUDE_MSG_CHECKS_RECV
'org.nagios.MsgDirSize', # (if INCLUDE_MSG_CHECKS_RECV || INCLUDE_MSG_SEND_CHECKS
'org.nagios.AmsDirSize', # (if INCLUDE_MSG_CHECKS_RECV || INCLUDE_MSG_SEND_CHECKS
'org.nagios.ProcessMsgToHandler', # (if INCLUDE_MSG_CHECKS_RECV
'org.nagios.MsgToHandlerPidFile', # (if INCLUDE_MSG_CHECKS_RECV
'hr.srce.GoodSEs',
'org.nagios.NagiosCmdFile',
'org.nordugrid.ARC-CE-monitor',
'org.nordugrid.ARC-CE-clean',
'argo.AMSPublisher-Check',
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
