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

package NCG::SiteInfo::GOCDB;

use NCG::SiteInfo;
use strict;
use LWP::UserAgent;
use XML::DOM;
use vars qw(@ISA);

@ISA=("NCG::SiteInfo");

my $DEFAULT_GOCDB_ROOT_URL = "https://goc.egi.eu/gocdbpi";
my $GOCDB_GET_METHOD = "/public/?method=get_service_endpoint";

sub new {
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);

    if (! $self->{GOCDB_ROOT_URL}) {
        $self->{GOCDB_ROOT_URL} = $DEFAULT_GOCDB_ROOT_URL;
    }

    if (! exists $self->{NODE_MONITORED}) {
        $self->{NODE_MONITORED} = 'Y';
    }

    if ($self->{SCOPE} && $self->{SCOPE} !~ /Local/) {
        $self->error("Incorrect SCOPE value, acceptable values are: Local.");
        return;
    }

    if (! exists $self->{URL_TYPE}) {
        $self->{URL_TYPE} = 'ROOT';
    }

    $self->{TIMEOUT} = $self->{DEFAULT_HTTP_TIMEOUT} unless ($self->{TIMEOUT});

    if (! exists $self->{VO}) {
        $self->{VO} = 'ops';
    }
    $self;
}

sub getData {
    my $self = shift;
    my $sitename = shift || $self->{SITENAME};
    my $content;

    if ( $self->{URL_TYPE} eq 'FILE' ) {
        my $fileHndl;
        local $/=undef;
        if (!open ($fileHndl, $self->{GOCDB_ROOT_URL})) {
            $self->error("Cannot open GOCDB file!");
            return 0;
        }
        $content = <$fileHndl>;
        close $fileHndl;
    } else {
        my $ua = LWP::UserAgent->new(timeout=>$self->{TIMEOUT}, env_proxy=>1, ssl_opts => { SSL_ca_path => '/etc/grid-security/certificates' });
        $ua->agent("NCG::SiteInfo::GOCDB");

        my $url;
        if ( $self->{URL_TYPE} eq 'ROOT' ) {
            $url = $self->{GOCDB_ROOT_URL} . $GOCDB_GET_METHOD . '&sitename=' . $sitename;
            if ($self->{NODE_MONITORED}) {
                $url .= '&monitored=' . $self->{NODE_MONITORED};
            }
            if ($self->{SCOPE}) {
                $url .= '&scope=' . $self->{SCOPE};
            }
        } else {
            $url = $self->{GOCDB_ROOT_URL};
        }
        my $req = HTTP::Request->new(GET => $url);

        if ( $self->{USERNAME} && $self->{PASSWORD} ) {
            $req->authorization_basic($self->{USERNAME}, $self->{PASSWORD});
        }

        my $res = $self->safeHTTPSCall($ua,$req);
        if (!$res->is_success) {
            $self->error("Could not get results from GOCDB: ".$res->status_line);
            return 0;
        }
        $content = $res->content;
    }
    my $parser = new XML::DOM::Parser(ErrorContext => 2);
    my $doc;
    eval {
        $doc = $parser->parse($content);
    };
    if ($@) {
        $self->error("Error parsing XML response: ".$@);
        return;
    }

    foreach my $site ($doc->getElementsByTagName("SERVICE_ENDPOINT")) {
        my $elem;
        my $hostname;
        my $sesitename;
        my $hostnameReal;

        foreach $elem ($site->getElementsByTagName("SITENAME")) {
            my $value = $elem->getFirstChild->getNodeValue();
            if ($value) {
                $sesitename = $value;
            }
        }
        if ( $sesitename ne $sitename ) {
            next;
        }

        if ($self->{PRODUCTION}) {
            my $prod;
            foreach $elem ($site->getElementsByTagName("IN_PRODUCTION")) {
                my $value = $elem->getFirstChild->getNodeValue();
                if ($value) {
                    $prod = $value;
                }
            }
            if ($prod && $prod ne $self->{PRODUCTION}) {
                next;
            }
        }
      
        if ($self->{NODE_MONITORED}) {
            my $prod;
            foreach $elem ($site->getElementsByTagName("NODE_MONITORED")) {
                my $value = $elem->getFirstChild->getNodeValue();
                if ($value) {
                    $prod = $value;
                }
            }
            if ($prod && $prod ne $self->{NODE_MONITORED}) {
                next;
            }
        }

        foreach $elem ($site->getElementsByTagName("HOSTNAME")) {
            my $value = $elem->getFirstChild->getNodeValue();
            if ($value) {
                $hostname = $value;
                $hostnameReal = $value;
            }
        }

        #foreach $elem ($site->getElementsByTagName("PRIMARY_KEY")) {
        #    my $value = $elem->getFirstChild->getNodeValue();
        #    if ($value) {
        #        $self->{SITEDB}->addHost($hostname, $value);
        #        $hostname .= '_' . $value;
        #    }
        #}

        if ($hostname) {
            my $serviceType;
            foreach $elem ($site->getElementsByTagName("SERVICE_TYPE")) {
                my $value = $elem->getFirstChild->getNodeValue();
                if ($value) {
                    $self->{SITEDB}->addService($hostname, $value);
                    $self->{SITEDB}->addVO($hostname, $value, $self->{VO});
                    $self->{SITEDB}->siteLDAP($hostnameReal) if ($value eq 'Site-BDII');

                    $serviceType = $value;
                }
            }
            if ($serviceType) {
                foreach $elem ($site->getElementsByTagName("HOSTDN")) {
                    my $child = $elem->getFirstChild;
                    if ($child) {
                        my $value = $child->getNodeValue();
                        if ($value) {
                            $self->{SITEDB}->hostAttribute($hostname, $serviceType."_HOSTDN", $value);
                        }
                    }
                }
                foreach $elem ($site->getElementsByTagName("URL")) {
                    my $child = $elem->getFirstChild;
                    if ($child) {
                        my $value = $child->getNodeValue();
                        if ($value) {
                            $self->{SITEDB}->hostAttribute($hostname, $serviceType."_URL", $value);
                        }
                    }
                }
                foreach my $endpoint ($site->getElementsByTagName("ENDPOINT")) {
                    my $monitored = "";
                    foreach $elem ($site->getElementsByTagName("ENDPOINT_MONITORED")) {
                        my $value = $elem->getFirstChild->getNodeValue();
                        if ($value) {
                            $monitored = $value;
                        }
                    }
                    if ( $monitored eq 'Y' ) {
                        foreach $elem ($endpoint->getElementsByTagName("URL")) {
                            my $child = $elem->getFirstChild;
                            if ($child) {
                                my $value = $child->getNodeValue();
                                if ($value) {
                                    $self->{SITEDB}->hostAttribute($hostname, $serviceType."_URL", $value);
                                }
                            }
                        }
                    }
                }
            }
            foreach $elem ($site->getElementsByTagName("EXTENSIONS")) {
                foreach my $ext ($elem->getElementsByTagName("EXTENSION")) {
                    my ($elemInt, $keyInt, $valueInt);
                    foreach $elemInt ($ext->getElementsByTagName("KEY")) {
                        my $value = $elemInt->getFirstChild->getNodeValue();
                        if ($value) {
                            $keyInt = $value;
                        }
                    }
                    foreach $elemInt ($ext->getElementsByTagName("VALUE")) {
                        my $child = $elemInt->getFirstChild;
                        if ($child) {
                            my $value = $child->getNodeValue();
                            if ($value) {
                                $valueInt = $value;
                            }
                        }
                    }
                    if ($keyInt && $valueInt) {
                        $self->{SITEDB}->hostAttribute($hostname, $keyInt, $valueInt);
                    }
                }
            }
        }

        if (!$self->{SITEDB}->siteCountry()) {
            foreach $elem ($site->getElementsByTagName("COUNTRY_NAME")) {
                my $value = $elem->getFirstChild->getNodeValue();
                if ($value) {
                    $self->{SITEDB}->siteCountry($value);
                }
            }
        }
    }

    $doc->dispose;

    1;
}

=head1 NAME

NCG::SiteInfo::GOCDB

=head1 DESCRIPTION

The NCG::SiteInfo::GOCDB module extends NCG::SiteInfo module. Module
extracts site information from GOCDB.

=head1 SYNOPSIS

  use NCG::SiteInfo::GOCDB;

  my $siteInfo = NCG::SiteInfo::GOCDB->new();

  $siteInfo->getData();

=cut

=head1 METHODS

=over

=item C<new>

  my $siteInfo = NCG::SiteInfo::GOCDB->new($options);

Creates new NCG::SiteInfo::GOCDB instance. Argument $options is hash reference that
can contains following elements:
  GOCDB_ROOT_URL - root URL used for GOCDB query interface
                 - only if GOCDB_ACCESS_TYPE is xml
                 - default: https://goc.egi.eu/gocdbpi

  NODE_MONITORED - is node monitored (for possible values see GOCDB documentation)
                 - default: Y

  PRODUCTION - is node in production (for possible values see GOCDB documentation)
             - default: Y

  SCOPE - scope of services (for possible values see GOCDB documentation)
        - default: undefined
             
  TIMEOUT - HTTP timeout
          - default: DEFAULT_HTTP_TIMEOUT inherited from NCG

  USERNAME - username for basic authentication
           - default: undefined

  PASSWORD - password for basic authentication
           - default: undefined

=back

=head1 SEE ALSO

NCG::SiteInfo

=cut

1;
