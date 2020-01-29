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

package NCG::LocalMetrics::WEBAPI;

use strict;
use warnings;
use NCG::LocalMetrics;
use vars qw(@ISA);
use JSON; 
use LWP::UserAgent;

@ISA=("NCG::LocalMetrics");

my $DEFAULT_WEBAPI_ROOT_URL = "https://api.argo.grnet.gr/";
my $DEFAULT_WEBAPI_ROOT_URL_SUFFIX = "/api/v2/metric_profiles";

sub new
{
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);
    # set default values
    if (! $self->{WEBAPI_ROOT_URL}) {
        $self->{WEBAPI_ROOT_URL} = $DEFAULT_WEBAPI_ROOT_URL;
    }
    if (!$self->{METRIC_CONFIG} || ref $self->{METRIC_CONFIG} ne "HASH" ) {
        $self->error("Metric configuration is not defined. Unable to generate configuration.");
        return;
    }

    if ($self->{PROFILES}) {
        foreach my $pt (split (/,/, $self->{PROFILES})) {
            $self->{PROFILES_HASH}->{$pt} = 1;
        }
    }
    if (! $self->{TOKEN}) {
        $self->error("Authentication token must be defined.");
        return;
    }
    if (! $self->{VO}) {
        $self->{VO} = 'ops';
    }

    $self;
}

sub getData {
    my $self = shift;
    my $sitename = shift || $self->{SITENAME};
    my $poemService = {};
    my $url;

    my $ua = LWP::UserAgent->new(timeout=>$self->{TIMEOUT}, env_proxy=>1, ssl_opts => { SSL_ca_path => '/etc/grid-security/certificates' });
    $ua->agent("NCG::LocalMetrics::WEBAPI");
    $url = $self->{WEBAPI_ROOT_URL} . $DEFAULT_WEBAPI_ROOT_URL_SUFFIX;
    my $req = HTTP::Request->new(GET => $url);
    $req->header('x-api-key' => $self->{TOKEN});
    $req->header('Accept' => 'application/json');
    $req->header('Content-Type' => 'application/json');
    my $res = $self->safeHTTPSCall($ua,$req);
    if (!$res->is_success) {
        $self->error("Could not get results from WEBAPI: ".$res->status_line);
        return;
    }

    my $jsonRef;
    eval {
        $jsonRef = from_json($res->content);
    };
    if ($@) {
        $self->error("Error parsing JSON response: ".$@);
        return;
    }
    if ( !$jsonRef ) {
        $self->error("JSON response is empty");
        return;
    }
    if ( ref $jsonRef ne "HASH" ) {
        $self->error("JSON response is not a hash:".$res->content);
        return;
    }    
    if ( ! exists $jsonRef->{status} ) {
        $self->error("JSON response doesn't contain status hash:".$res->content);
        return;
    }
    if ( ! exists $jsonRef->{status}->{code} ) {
        $self->error("JSON response doesn't contain status code:".$res->content);
        return;
    }
    if ( $jsonRef->{status}->{code} ne '200' ) {
        $self->error("Status code is not equal 200:".$res->content);
        return;
    }

    my $vo = $self->{VO};
    my $voFqan = '_ALL_';
    foreach my $profileHash (@{$jsonRef->{data}}) {
        next if ( defined ($self->{PROFILES_HASH}) && ! exists $self->{PROFILES_HASH}->{$profileHash->{name}});
        foreach my $serviceHash (@{$profileHash->{services}}) {
            my $service = $serviceHash->{service};
            foreach my $metric (@{$serviceHash->{metrics}}) {
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
                    if ($service eq 'CREAM-CE' && exists $metricRef->{parent} && $metricRef->{parent} && $metricRef->{parent} eq 'emi.ce.CREAMCE-JobState') {
                        $customMetricRef->{parent} = 'emi.cream.CREAMCE-JobState';
                    }                    

                    foreach my $vo (keys %{$poemService->{$service}->{$metric}}) {
                        foreach my $voFqan (keys %{$poemService->{$service}->{$metric}->{$vo}}) {
                            $customMetricRef->{vo} = $vo;
                            $customMetricRef->{vofqan} = $voFqan;
                            $self->{SITEDB}->addVoFqan($vo, $customMetricRef->{vofqan}) unless ($voFqan eq '_ALL_');
                            $self->_addLocalMetric($customMetricRef, $host, $metric, $service);

                            if (exists $customMetricRef->{parent} && $customMetricRef->{parent}) {
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

    TOKEN - token used for POEM API authentication
    (default: )

=back

=head1 SEE ALSO

NCG::LocalMetrics

=cut

1;
