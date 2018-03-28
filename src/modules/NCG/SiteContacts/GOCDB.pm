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

package NCG::SiteContacts::GOCDB;

use NCG::SiteContacts;
use strict;
use LWP::UserAgent;
use XML::DOM;
use vars qw(@ISA);

@ISA=("NCG::SiteContacts");

my $DEFAULT_GOCDB_ROOT_URL = "https://goc.egi.eu/gocdbpi";
my $DEFAULT_X509_CERT = '/etc/grid-security/hostcert.pem';
my $DEFAULT_X509_KEY = '/etc/grid-security/hostkey.pem';
my $GOCDB_GET_METHOD = "/private/?method=get_site_contacts";
my $GOCDB_ROC_GET_METHOD = "/private/?method=get_roc_contacts";
my $GOCDB_ALARM_GET_METHOD = "/private/?method=get_site";

sub new {
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);

    # set default values
    if (! $self->{GOCDB_ROOT_URL}) {
        $self->{GOCDB_ROOT_URL} = $DEFAULT_GOCDB_ROOT_URL;
    }

    if (! $self->{X509_CERT}) {
        $self->{X509_CERT} = $DEFAULT_X509_CERT;
    }

    if (! $self->{X509_KEY}) {
        $self->{X509_KEY} = $DEFAULT_X509_KEY;
    }

    if (! -f $self->{X509_KEY} || ! -r $self->{X509_KEY} ) {
        $self->error("X509 key ($self->{X509_KEY}) does not exist or it is not readable!");
        undef $self;
        return;
    }

    if (! -f $self->{X509_CERT} || ! -r $self->{X509_CERT} ) {
        $self->error("X509 certificate ($self->{X509_CERT}) does not exist or it is not readable!");
        undef $self;
        return;
    }
    $self->{TIMEOUT} = $self->{DEFAULT_HTTP_TIMEOUT} unless ($self->{TIMEOUT});

    $self->{CONTACT_TYPE} = 'site' unless ($self->{CONTACT_TYPE});
    if ($self->{CONTACT_TYPE} =~ /roc/) {
        $self->{CONTACT_TYPE} = 'roc';
        $self->{GOCDB_GET_METHOD} = $GOCDB_ROC_GET_METHOD;
    } elsif ($self->{CONTACT_TYPE} =~ /alarm/) {
        $self->{CONTACT_TYPE} = 'alarm';
        $self->{GOCDB_GET_METHOD} = $GOCDB_ALARM_GET_METHOD;
    } elsif ($self->{CONTACT_TYPE} =~ /site/) {
        $self->{CONTACT_TYPE} = 'site';
        $self->{GOCDB_GET_METHOD} = $GOCDB_GET_METHOD;
    } else {
        $self->error("Unsupported CONTACT_TYPE defined: ".$self->{CONTACT_TYPE});
        undef $self;
        return;
    }

    $self;
}

sub _getUsers : method {
    my ($self, $doc) = @_;
    foreach my $site ($doc->getElementsByTagName("CONTACT")) {
        my $elem;
        my $tuple = {FORENAME=>"", SURNAME=>"", EMAIL=>"", CERTDN=>""};

        foreach my $attr (keys %$tuple) {
            foreach $elem ($site->getElementsByTagName($attr)) {
                my $value = $elem->getFirstChild->getNodeValue() if ($elem->getFirstChild);
                if ($value) {
                    $tuple->{$attr} = $value;
                }
            }
        }

        next if ($tuple->{CERTDN} =~ /,/);
        $self->{SITEDB}->addUser($tuple->{CERTDN},$tuple->{FORENAME} . " " . $tuple->{SURNAME},$tuple->{EMAIL});
    }
}

sub _getContacts : method {
    my ($self, $doc) = @_;
    my $email;
    foreach my $site ($doc->getElementsByTagName("CONTACT_EMAIL")) {
        $email = $site->getFirstChild->getNodeValue();
    }

    if ($email) {
        foreach my $emailAddr (split(/(;|,)/,$email)) {
            $self->{SITEDB}->addContact($emailAddr) if ($emailAddr=~ /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4}$/i);
        }
    }
}

sub getData {
    my $self = shift;
    my $sitename = shift || $self->{SITENAME};
    local %ENV = %ENV;

    $ENV{HTTPS_KEY_FILE} = $self->{X509_KEY};
    $ENV{HTTPS_CERT_FILE} = $self->{X509_CERT};
    $ENV{HTTPS_CA_DIR} = '/etc/grid-security/certificates';

    my $ua = LWP::UserAgent->new(timeout=>$self->{TIMEOUT}, env_proxy => 1, ssl_opts => { SSL_key_file => $self->{X509_KEY}, SSL_cert_file => $self->{X509_CERT}, SSL_ca_path => '/etc/grid-security/certificates' });
    $ua->agent('NCG::SiteContacts::GOCDB');

    my $url = $self->{GOCDB_ROOT_URL} . $self->{GOCDB_GET_METHOD};
    if ($self->{CONTACT_TYPE} eq 'site' || $self->{CONTACT_TYPE} eq 'alarm') {
        $url .= '&sitename=' . $sitename;
    } elsif ($self->{CONTACT_TYPE} eq 'roc') {
        my $roc = $self->{SITEDB}->siteROC || $self->{ROC};
        $url .= '&roc=' . $roc if ($roc);
    }

    if ($self->{NODE_MONITORED}) {
        $url .= '&monitored=' . $self->{NODE_MONITORED};
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

    my $parser = new XML::DOM::Parser(ErrorContext => 2);
    my $doc;
    eval {
        $doc = $parser->parse($res->content);
    };
    if ($@) {
        $self->error("Error parsing XML response: ".$@);
        return;
    }

    if ($self->{CONTACT_TYPE} eq 'alarm') {
        $self->_getContacts($doc);
    } else {
        $self->_getUsers($doc);
    }

    $doc->dispose;

    1;
}

=head1 NAME

NCG::SiteContacts::GOCDB

=head1 DESCRIPTION

The NCG::SiteContacts::GOCDB module extends NCG::SiteContacts module. Module
extracts list of contacts for site from GOCDB.

=head1 SYNOPSIS

  use NCG::SiteContacts::GOCDB;

  my $siteInfo = NCG::SiteContacts::GOCDB->new();

  $siteInfo->getData();

=cut

=head1 METHODS

=over

=item C<new>

  my $siteInfo = NCG::SiteContacts::GOCDB->new($options);

Creates new NCG::SiteContacts::GOCDB instance. Argument $options is hash reference that
can contains following elements:
  CONTACT_TYPE - which type of contacts to retrieve. Currently supported
                 options are:
                    - site (default): get site contacts
                    - roc: get roc contacts
                    - alarm: get contacts which should receive emails

  GOCDB_ROOT_URL - root URL used for GOCDB query interface
                 - only if GOCDB_ACCESS_TYPE is xml
                 - default: https://goc.egi.eu/gocdbpi

  ROC - roc name must be set in case when CONTACT_TYPE is set to 'roc'.
  
  TIMEOUT - HTTP timeout
          - default: DEFAULT_HTTP_TIMEOUT inherited from NCG

  USERNAME - username for basic authentication
           - default: undefined

  PASSWORD - password for basic authentication
           - default: undefined

=item C<getData>

  my $siteInfo = $gocdb->getData();

Retrieves defined data.

=item C<_getUsers>

  my $siteInfo = $gocdb->_getUsers();

Retrieves users in case when CONTACT_TYPE is 'site' or 'roc'.

=item C<_getContacts>

  my $siteInfo = $gocdb->_getContacts

Retrieves contacts for alarms in case when CONTACT_TYPE is 'alarm'

=back

=head1 SEE ALSO

NCG::SiteContacts

=cut

1;
