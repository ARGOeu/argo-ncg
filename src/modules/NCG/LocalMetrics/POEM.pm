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

package NCG::LocalMetrics::POEM;

use strict;
use warnings;
use NCG::LocalMetrics;
use vars qw(@ISA);
use JSON; 

@ISA=("NCG::LocalMetrics");

my $DEFAULT_POEM_ROOT_URL = "http://mon.egi.eu/poem";
my $DEFAULT_POEM_ROOT_URL_SUFFIX = "/api/0.2/json/profiles";

sub new
{
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);
    # set default values
    if (! $self->{POEM_ROOT_URL}) {
        $self->{POEM_ROOT_URL} = $DEFAULT_POEM_ROOT_URL;
    }
    if (!$self->{METRIC_CONFIG} || ref $self->{METRIC_CONFIG} ne "HASH" ) {
        $self->error("Metric configuration is not defined. Unable to generate configuration.");
        return;
    }

    if ($self->{POEM_PROFILES}) {
        foreach my $pt (split (/,/, $self->{POEM_PROFILES})) {
            $self->{PROFILES_HASH}->{$pt} = 1;
        }
    }


    $self;
}

sub getDataWWW {
    my $self = shift;
    my $url;

    my $ua = LWP::UserAgent->new(timeout=>$self->{TIMEOUT}, env_proxy=>1);
    $ua->agent("NCG::LocalMetrics::POEM");
    $url = $self->{POEM_ROOT_URL} . $DEFAULT_POEM_ROOT_URL_SUFFIX;
    my $req = HTTP::Request->new(GET => $url);
    my $res = $self->safeHTTPSCall($ua,$req);
    if (!$res->is_success) {
        $self->error("Could not get results from POEM: ".$res->status_line);
        return;
    }
    return $res->content;
}

sub getDataFile {
    my $self = shift;
    my $result;
    my $fileHndl;
    
    unless (open ($fileHndl, $self->{POEM_FILE})) {
        $self->error("Cannot open POEM file: $self->{POEM_FILE}");
        return;
    }
    $result = join ("", <$fileHndl>);
    unless (close ($fileHndl)) {
        $self->error("Cannot close POEM file: $self->{POEM_FILE}");
        return $result;
    }
    return $result;
}

sub getData {
    my $self = shift;
    my $sitename = shift || $self->{SITENAME};
    my $content;
    my $poemService = {};

    if ( $self->{POEM_FILE} ) {
        $content = $self->getDataFile();
    } else {
        $content = $self->getDataWWW();
    }
    return unless ($content);

    my $jsonRef;
    eval {
        $jsonRef = from_json($content);
    };
    if ($@) {
        $self->error("Error parsing JSON response: ".$@);
        return;
    }

    # Load (service, metric) tuples
    if ($jsonRef && ref $jsonRef eq "ARRAY") {
        foreach my $profileTuple (@{$jsonRef}) {
            next if ( defined ($self->{PROFILES_HASH}) && ! exists $self->{PROFILES_HASH}->{$profileTuple->{name}});
            foreach my $metricTuple (@{$profileTuple->{metric_instances}}) {
                my $service = $metricTuple->{atp_service_type_flavour};
                my $metric = $metricTuple->{metric};
                my $vo = $metricTuple->{vo};
                my $voFqan = $metricTuple->{fqan} || '_ALL_';
            
                unless (exists $self->{METRIC_CONFIG}->{$metric}) {
                    $self->error("Metric configuration does not contain metric $metric. Metric will be skipped.");
                } else {
                    $poemService->{$service}->{$metric}->{$vo}->{$voFqan} = 1;
                }
            }
        }
    }

    foreach my $host ($self->{SITEDB}->getHosts()) {
        foreach my $service ($self->{SITEDB}->getServices($host)) {
            if (exists $poemService->{$service}) {
                foreach my $metric (keys %{$poemService->{$service}}) {
                    my $metricRef = $self->{METRIC_CONFIG}->{$metric};
                    my $customMetricRef = {%{$metricRef}};

                    # hacks
                    if ($service eq 'CREAM-CE' && exists $metricRef->{parent} && $metricRef->{parent} eq 'emi.ce.CREAMCE-JobState') {
                        $customMetricRef->{parent} = 'emi.cream.CREAMCE-JobState';
                    }                    

                    foreach my $vo (keys %{$poemService->{$service}->{$metric}}) {
                        foreach my $voFqan (keys %{$poemService->{$service}->{$metric}->{$vo}}) {
                            $customMetricRef->{vo} = $vo;
                            $customMetricRef->{vofqan} = $voFqan;
                            $self->{SITEDB}->addVoFqan($vo, $customMetricRef->{vofqan}) unless ($voFqan eq '_ALL_');
                            $self->_addLocalMetric($customMetricRef, $host, $metric, $service);

                            if (exists $customMetricRef->{parent}) {
                                my $parent = $customMetricRef->{parent};
                                if (exists $self->{METRIC_CONFIG}->{$parent}) {
                                    my $customParentMetricRef = {%{$self->{METRIC_CONFIG}->{$parent}}};
                                    $customParentMetricRef->{vo} = $customMetricRef->{vo};
                                    $customParentMetricRef->{vofqan} = $customMetricRef->{vofqan};
                                    $self->_addLocalMetric($customParentMetricRef, $host, $parent, $service);
                                } else {
                                    $self->error("Metric $metric requires parent $parent. ".
                                         "Metric configuration does not contain metric $parent.");
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    1;
}


=head1 NAME

NCG::LocalMetrics::POEM

=head1 DESCRIPTION

The NCG::LocalMetrics::POEM module extends NCG::LocalMetrics module.
Module extracts metric information from hard-coded POEM.

=head1 SYNOPSIS

  use NCG::LocalMetrics::POEM;

  my $lms = NCG::LocalMetrics::POEM->new( { SITEDB=> $sitedb} );

  $lms->getData();

=cut

=head1 METHODS

=over

=item C<new>

  $siteInfo = NCG::LocalMetrics::POEM->new( $options );

Creates new NCG::LocalMetrics::POEM instance. Argument $options is hash
reference that can contain following elements:
    POEM_FILE - file containing JSON definition
    (default: )
    
    POEM_ROOT_URL - POEM JSON API root URL
    (default: http://localhost/poem_sync)
    
    METRIC_CONFIG - metric configuration structure fetched from
    NCG::MetricConfig module

=back

=head1 SEE ALSO

NCG::LocalMetrics

=cut

1;
