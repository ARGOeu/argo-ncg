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
                                                                                 
package NCG::RemoteMetrics::Nagios;

use strict;
use NCG::RemoteMetrics;
use GridMon::ConfigCache;
use JSON;

use vars qw(@ISA);

@ISA=("NCG::RemoteMetrics");

my $DEFAULT_CACHE_FILE = "/var/cache/msg/config-cache/config.db";
my $DEFAULT_CACHE_TABLE = "config_incoming";

sub new {
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);
    
    # set default values
    unless ($self->{CACHE_FILE}) {
        $self->{CACHE_FILE} = $DEFAULT_CACHE_FILE;
    }
    if (! $self->{CACHE_TABLE}) {
        $self->{CACHE_TABLE} = $DEFAULT_CACHE_TABLE;
    }
    if (! $self->{CACHE}) {
        $self->{CACHE} = GridMon::ConfigCache->new({ CACHE_FILE => $self->{CACHE_FILE},
                                                     CACHE_TABLE => $self->{CACHE_TABLE} });
    }
    $self;
}

sub addRemoteMetrics
{
    my $self = shift;
    my $gatheredAt = shift;
    my $role = shift;
    my $config = shift;
    
    my $objRef = from_json($config) or return;

    foreach my $host (@{$objRef->{host}}) {
        my $hostname = $host->{hostName};
        foreach my $metric (@{$host->{metric}}) {
            my $metricName = $metric->{nagiosName} . "-$role";
            my $deps = {};
            if (exists $metric->{dependency} && ref $metric->{dependency} eq "ARRAY" ) {
                foreach my $dep (@{$metric->{dependency}}) {
                    my $depName = $dep->{nagiosName} . "-$role";
                    $deps->{$depName} = 1;
                }
            }
            $self->{SITEDB}->addRemoteMetricLong($hostname, $metricName, "Nagios", $metric->{config}, $metric->{url}, $metric->{docUrl}, $metric->{vo}, $deps );
        }
    }

    1;
}

sub getData {
    my $self = shift;

    my ($retVal, $arrRef) = $self->{CACHE}->getAll($self->{SITEDB}->siteName(),$self->{HOSTNAME});
    if (!$retVal) {
        $self->error($arrRef);
        return;
    } else {
        if (ref $arrRef eq "ARRAY") {
            foreach my $tuple (@$arrRef) {
                $self->addRemoteMetrics ($tuple->{hostname},$tuple->{role},$tuple->{config});
                $self->{CACHE}->updateProcessed($tuple->{sitename},$tuple->{hostname});
            }
        }
        return 1;
    }
}

=head1 NAME

NCG::RemoteMetrics::Nagios

=head1 DESCRIPTION

The NCG::RemoteMetrics::Nagios module extends NCG::RemoteMetrics module.
Module extracts list of remote metric from Nagios.

=head1 SYNOPSIS

  use NCG::RemoteMetrics::Nagios;

  my $ncg = NCG::RemoteMetrics::Nagios->new( {  SITEDB=> $sitedb,
                                                CACHE_FILE => '/var/alternative/path/config.db',
                                                CACHE_TABLE => 'config_incoming' } );

  $ncg->getData();

=cut

=head1 METHODS

=over

=item C<new>

  $ncg = NCG::RemoteMetrics::Nagios->new( $options );

Creates new NCG::RemoteMetrics::Nagios instance. Argument $options is hash
reference that can contain following elements:
  CACHE_FILE - file where cache is stored. This option is forwarded to
               GridMon::ConfigCache module.
  CACHE_TABLE - table in which cache is stored.This option is forwarded to
                GridMon::ConfigCache module.
  HOSTNAME - get config coming from the defined remote Nagios server
  VO - get config only for a given VO (TODO)

=back

=head1 SEE ALSO

NCG::RemoteMetrics

=cut

1;
