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

package NCG::SiteSet::GOCDB;

use NCG::SiteSet;
use strict;
use LWP::UserAgent;
use XML::DOM;
use vars qw(@ISA);

@ISA=("NCG::SiteSet");

my $DEFAULT_GOCDB_ROOT_URL = "https://goc.egi.eu/gocdbpi";
my $GOCDB_GET_METHOD = "/public/?method=get_site_list";

sub new {
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);

    # set default values
    if (! $self->{GOCDB_ROOT_URL}) {
        $self->{GOCDB_ROOT_URL} = $DEFAULT_GOCDB_ROOT_URL;
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
    $self->{TIMEOUT} = $self->{DEFAULT_HTTP_TIMEOUT} unless ($self->{TIMEOUT});

    $self;
}

sub getData
{
    my $self = shift;
    my %subgrid_inc = ();
    if ($self->{SUBGRID_INCLUDE}) {
        for my $sg (split /\s*,\s*/, $self->{SUBGRID_INCLUDE}) {
             $subgrid_inc{$sg} = 1 if $sg;
        }
    }
    if ($self->{SUBGRID_EXCLUDE}) {
        for my $sg (split /\s*,\s*/, $self->{SUBGRID_EXCLUDE}) {
             $subgrid_inc{$sg} = 0 if $sg;
        }
    }

    my $ua = LWP::UserAgent->new(timeout=>$self->{TIMEOUT}, env_proxy=>1);
    $ua->agent("NCG::SiteSet::GOCDB");

    my $url = $self->{GOCDB_ROOT_URL} . $GOCDB_GET_METHOD;
    if ($self->{ROC}) {
        $url .= '&roc=' . $self->{ROC};
    }
    if ($self->{COUNTRY}) {
        $url .= '&country=' . $self->{COUNTRY};
    }
    if ($self->{CERT_STATUS}) {
        $url .= '&certification_status=' . $self->{CERT_STATUS};
    }
    if ($self->{PROD_STATUS}) {
        $url .= '&production_status=' . $self->{PROD_STATUS};
    }
    if ($self->{SCOPE}) {
        $url .= '&scope=' . $self->{SCOPE};
    }

    my $req = HTTP::Request->new(GET => $url);
    my $res = $self->safeHTTPSCall($ua,$req);
    if (!$res->is_success) {
        $self->error("Could not get results from GOCDB: ".$res->status_line);
        return 0;
    }

    my $parser = new XML::DOM::Parser(ErrorContext => 2);
    my $doc;
    eval {
        $doc = $parser->parse($res->content);
    };
    if ($@) {
        $self->error("Error parsing XML response: ".$@);
        return;
    }

    foreach my $site ($doc->getElementsByTagName("SITE")) {
        my $sitename = $site->getAttribute("NAME");
        my $giisUrl = $site->getAttribute("GIIS_URL");
        my $country = $site->getAttribute("COUNTRY");
        my $roc = $site->getAttribute("ROC");
        my $subgrid = $site->getAttribute("SUBGRID");
        next if (%subgrid_inc && $subgrid && ! $subgrid_inc{$subgrid});

        my $giis = "";
        if ($giisUrl && $giisUrl =~ /^ldap:\/\/([-_.A-Za-z0-9]+):(\d+)/) {
            $giis = $1;
        }
        $self->verbose ("Found site: $sitename (site BDII: $giis).");

        if (!exists $self->{SITES}->{$sitename}) {
            $self->{SITES}->{$sitename} = NCG::SiteDB->new ({SITENAME=>$sitename, LDAP_ADDRESS=>$giis, COUNTRY=>$country, ROC=>$roc});
        } else {
            $self->{SITES}->{$sitename}->siteLDAP($giis) if ($giis);
            $self->{SITES}->{$sitename}->siteCountry($country) if ($country);
            $self->{SITES}->{$sitename}->siteROC($roc) if ($roc);
        }
    }

    $doc->dispose;

    1;
}

=head1 NAME

NCG::SiteSet::GOCDB

=head1 DESCRIPTION

The NCG::SiteSet::GOCDB module extends NCG::SiteSet module. Module
extracts list of sites from GOCDB. It sets site BDII and site contact
for each site.

=head1 SYNOPSIS

  use NCG::SiteSet::GOCDB;

  my $siteInfo = NCG::SiteSet::GOCDB->new({ROC=>'CentralEurope'});

  $siteInfo->getData();

=cut

=head1 METHODS

=over

=item C<new>

  my $siteInfo = NCG::SiteSet::GOCDB->new($options);

Creates new NCG::SiteSet::GOCDB instance. Argument $options is hash reference that
can contains following elements:
  GOCDB_ROOT_URL - root URL used for GOCDB query interface
                 - only if GOCDB_ACCESS_TYPE is xml
                 - default: https://goc.egi.eu/gocdbpi

  ROC - name of the federation (for possible values see GOCDB documentation)
      - if not defined module will fetch all sites.

  COUNTRY - country where site is placed

  SITE_MONITORED - is site monitored (for possible values see GOCDB documentation)
                 - default: Y

  PROD_STATUS - production status of site (for possible values see GOCDB documentation)
              - default: Production

  CERT_STATUS - certification status of site (for possible values see GOCDB documentation)
              - default: Certified
              
  SUBGRID_INCLUDE - comma separated list of Subgrids to include.

  SUBGRID_EXCLUDE - comma separated list of Subgrids to exclude.
              
  TIMEOUT - HTTP timeout,
  (default: DEFAULT_HTTP_TIMEOUT inherited from NCG)

=back

=head1 SEE ALSO

NCG::SiteSet

=cut

1;
