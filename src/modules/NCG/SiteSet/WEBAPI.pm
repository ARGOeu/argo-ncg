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

package NCG::SiteSet::WEBAPI;

use strict;
use warnings;
use NCG::SiteSet;
use vars qw(@ISA);
use JSON; 
use LWP::UserAgent;

@ISA=("NCG::SiteSet");

my $DEFAULT_WEBAPI_ROOT_URL = "https://api.argo.grnet.gr/";
my $DEFAULT_WEBAPI_ROOT_URL_SUFFIX = "/api/v2/topology/groups";

sub new
{
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);
    # set default values
    if (! $self->{WEBAPI_ROOT_URL}) {
        $self->{WEBAPI_ROOT_URL} = $DEFAULT_WEBAPI_ROOT_URL;
    }

    if (! exists $self->{SITE_MONITORED}) {
        $self->{SITE_MONITORED} = 'Y';
    }

    if (! exists $self->{PROD_STATUS}) {
        $self->{PROD_STATUS} = 'Production';
    }

    if (! exists $self->{CERT_STATUS}) {
        $self->{CERT_STATUS} = 'Certified';
    }

    if (! $self->{TOKEN}) {
        $self->error("Authentication token must be defined.");
        return;
    }
    if (! exists $self->{TIMEOUT}) {
        $self->{TIMEOUT} = $self->{DEFAULT_HTTP_TIMEOUT};
    }

    $self;
}

sub getData {
    my $self = shift;
    my $sitename = shift || $self->{SITENAME};
    my $poemService = {};
    my $url;

    my $ua = LWP::UserAgent->new( timeout=>$self->{TIMEOUT}, env_proxy=>1 );
    $ua->agent("NCG::SiteSet::WEBAPI");
    $url = $self->{WEBAPI_ROOT_URL} . $DEFAULT_WEBAPI_ROOT_URL_SUFFIX;
    $url .= '?type=NGI';
    my @tags;
    if ($self->{CERT_STATUS}) {
        push @tags, 'certification:' . $self->{CERT_STATUS};
    }
    if ($self->{PROD_STATUS}) {
        push @tags, 'infrastructure:' . $self->{PROD_STATUS};
    }
    if ($self->{SCOPE}) {
        push @tags, 'scope:' . $self->{SCOPE};
    }
    if (@tags) {
        $url .= '&tags='.join(',',@tags);
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

    foreach my $site (@{$jsonRef->{data}}) {
        my $sitename = $site->{subgroup};
        my $roc = $site->{group};

        $self->verbose ("Found site: $sitename.");

        if (!exists $self->{SITES}->{$sitename}) {
            $self->{SITES}->{$sitename} = NCG::SiteDB->new ({SITENAME=>$sitename, ROC=>$roc});
        } else {
            $self->{SITES}->{$sitename}->siteROC($roc) if ($roc);
        }
    }

    1;
}


=head1 NAME

NCG::SiteSet::WEBAPI

=head1 DESCRIPTION

The NCG::SiteSet::WEBAPI module extends NCG::SiteSet module.
Module extracts list of sites from ARGO WEBAPI component.

=head1 SYNOPSIS

  use NCG::SiteSet::WEBAPI;

  my $lms = NCG::SiteSet::WEBAPI->new( { SITEDB=> $sitedb} );

  $lms->getData();

=cut

=head1 METHODS

=over

=item C<new>

  $siteInfo = NCG::SiteSet::WEBAPI->new( $options );

Creates new NCG::SiteSet::WEBAPI instance. Argument $options is hash
reference that can contain following elements:
    WEBAPI_ROOT_URL - WEBAPI JSON API root URL
    (default: https://api.argo.grnet.gr)

    PROD_STATUS - production status of site
    (default: Production)

    CERT_STATUS - certification status of site
    (default: Certified)

    SCOPE - scope of sites
    (default: )

    TIMEOUT - HTTP timeout
    (default: DEFAULT_HTTP_TIMEOUT inherited from NCG)
    
    TOKEN - token used for WEBAPI API authentication
    (default: )

=back

=head1 SEE ALSO

NCG::SiteSet

=cut

1;
