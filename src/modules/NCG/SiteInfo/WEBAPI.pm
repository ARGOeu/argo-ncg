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

package NCG::SiteInfo::WEBAPI;

use strict;
use warnings;
use NCG::SiteInfo;
use vars qw(@ISA);
use JSON; 
use LWP::UserAgent;
use URI::URL;

@ISA=("NCG::SiteInfo");

my $DEFAULT_WEBAPI_ROOT_URL = "https://api.argo.grnet.gr/";
my $DEFAULT_WEBAPI_ROOT_URL_SUFFIX = "/api/v2/topology/endpoints";

sub new
{
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);
    # set default values
    if (! $self->{WEBAPI_ROOT_URL}) {
        $self->{WEBAPI_ROOT_URL} = $DEFAULT_WEBAPI_ROOT_URL;
    }

    if (! $self->{TOKEN}) {
        $self->error("Authentication token must be defined.");
        return;
    }
    if (! exists $self->{TIMEOUT}) {
        $self->{TIMEOUT} = $self->{DEFAULT_HTTP_TIMEOUT};
    }

    if (! exists $self->{VO}) {
        $self->{VO} = 'ops';
    }

    if (! exists $self->{USE_IDS}) {
        $self->{USE_IDS} = 0;
    }

    $self;
}

sub getData {
    my $self = shift;
    my $sitename = shift || $self->{SITENAME};
    my $poemService = {};
    my $url;

    my $ua = LWP::UserAgent->new( timeout=>$self->{TIMEOUT}, env_proxy=>1 );
    $ua->agent("NCG::SiteInfo::WEBAPI");
    $url = $self->{WEBAPI_ROOT_URL} . $DEFAULT_WEBAPI_ROOT_URL_SUFFIX;

    if ($self->{FILTER}) {
        $url .= '?' . $self->{FILTER} . '&group=' . $sitename;
    } else {
        $url .= '?group='  . $sitename;
    }

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

    foreach my $service (@{$jsonRef->{data}}) {
        my $sitename = $service->{group};
        my $hostname = $service->{hostname};
        my $serviceType = $service->{service};

        if (exists $service->{tags}->{hostname}) {
            $hostname = $service->{tags}->{hostname};
        }

        if ($self->{USE_IDS} && exists $service->{tags}->{info_ID} && $service->{tags}->{info_ID}) {
            $self->{SITEDB}->addHost($hostname, $service->{tags}->{info_ID});
            $hostname .= '_' . $service->{tags}->{info_ID};
        } else {
            $self->{SITEDB}->addHost($hostname);
        }

        $self->{SITEDB}->addService($hostname, $serviceType);
        $self->{SITEDB}->addVO($hostname, $serviceType, $self->{VO});
        $self->{SITEDB}->siteLDAP($hostname) if ($serviceType eq 'Site-BDII');

        foreach my $tag (keys %{$service->{tags}}) {
            if ( $tag =~ /^info_ext_(\S+)$/i ) {
                $self->{SITEDB}->hostAttribute($hostname, $1, $service->{tags}->{$tag});
            } elsif ( $tag =~ /^info_bdii_(\S+)$/i ) {
                $self->{SITEDB}->hostAttribute($hostname, $1, $service->{tags}->{$tag});
            } elsif ( $tag eq 'info_URL' || $tag eq 'info.URL' ) {
                my $url;
                my $value = $service->{tags}->{$tag};
                eval {
                    $url = url($value);
                };
                unless ($@) {
                    eval { $self->{SITEDB}->hostAttribute($hostname, 'PORT', $url->port) if ($url->port); };
                    eval { $self->{SITEDB}->hostAttribute($hostname, 'PATH', $url->path) if ($url->path); };
                    eval { $self->{SITEDB}->hostAttribute($hostname, 'SSL', 0) if ($url->scheme && $url->scheme eq 'https'); };
                }
                $self->{SITEDB}->hostAttribute($hostname, 'URL', $value);
                $self->{SITEDB}->hostAttribute($hostname, $serviceType."_URL", $value);
                $self->{SITEDB}->hostAttribute($hostname, 'GOCDB_SERVICE_URL', $value);
                $self->{SITEDB}->hostAttribute($hostname, $serviceType."_GOCDB_SERVICE_URL", $value);
            } elsif ( $tag eq 'info_service_endpoint_URL' ) {
                foreach my $url ( split (/, /, $service->{tags}->{$tag}) ) {
                    $self->{SITEDB}->hostAttribute($hostname, $serviceType."_URL", $url);
                }
            } elsif ( $tag =~ /^info_(\S+)$/i ) {
                $self->{SITEDB}->hostAttribute($hostname, $1, $service->{tags}->{$tag});
            } elsif ( $tag =~ /^vo_(\S+?)_attr_(\S+)$/ ) {
                $self->{SITEDB}->hostAttributeVO($hostname, $2, $1, $service->{tags}->{$tag});
            }
        }
    }

    1;
}


=head1 NAME

NCG::SiteInfo::WEBAPI

=head1 DESCRIPTION

The NCG::SiteInfo::WEBAPI module extends NCG::SiteInfo module.
Module extracts list of sites from ARGO WEBAPI component.

=head1 SYNOPSIS

  use NCG::SiteInfo::WEBAPI;

  my $lms = NCG::SiteInfo::WEBAPI->new( { SITEDB=> $sitedb} );

  $lms->getData();

=cut

=head1 METHODS

=over

=item C<new>

  $siteInfo = NCG::SiteInfo::WEBAPI->new( $options );

Creates new NCG::SiteInfo::WEBAPI instance. Argument $options is hash
reference that can contain following elements:

    FILTER - filter query that will be forwarded
    (default: )

    TIMEOUT - HTTP timeout
    (default: DEFAULT_HTTP_TIMEOUT inherited from NCG)
    
    TOKEN - token used for WEBAPI API authentication
    (default: )

    USE_IDS - use IDs for Nagios hostnames
    (default: false)

    WEBAPI_ROOT_URL - WEBAPI JSON API root URL
    (default: https://api.argo.grnet.gr)

=back

=head1 SEE ALSO

NCG::SiteInfo

=cut

1;
