#!/usr/bin/perl -w
#
# Nagios configuration generator (WLCG probe based)
# Copyright (c) 2020 Emir Imamagic
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

package NCG::SiteInfo::EOSC;

use NCG::SiteInfo;
use strict;
use JSON;
use vars qw(@ISA);
use URI::URL;

@ISA=("NCG::SiteSet");

sub new {
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);

    $self;
}

sub getData
{
    my $self = shift;
    my $sitename = shift || $self->{SITENAME};
    my $content;
    my $jsonRef;

    my $fileHndl;
    local $/=undef;
    if (!open ($fileHndl, $self->{FILE_PATH})) {
        $self->error("Cannot open EOSC file!");
        return 0;
    }
    $content = <$fileHndl>;
    close $fileHndl;
    eval {
        $jsonRef = from_json($content);
    };
    if ($@) {
        $self->error("Error parsing JSON response in file feed: ".$@);
        return;
    }

    foreach my $service (@{$jsonRef}) {
        my $url;
        my $hostname;
        my $serviceSiteName = $service->{'SITENAME-SERVICEGROUP'} || next;
        next if ( $serviceSiteName ne $sitename );
        if ( !$service->{'Service Unique ID'} || !$service->{SERVICE_TYPE} ) {
            $self->error("Entry for $serviceSiteName is missing 'Service Unique ID' and/or 'SERVICE_TYPE'");
            next;
        }
        eval {
            $url = url($service->{URL});
        };
        if ($@) {
            $self->error("Error parsing URL ".$service->{URL}." on $serviceSiteName: ".$@);
            next;
        }
        eval {
            $hostname = $url->host;
        };
        if ($@) {
            $self->error("Error parsing hostname from URL ".$service->{URL}." on $serviceSiteName: ".$@);
            next;
        }
        if ($hostname) {
            $self->{SITEDB}->addHost($hostname, $service->{'Service Unique ID'});
            $hostname .= '_'.$service->{'Service Unique ID'};
        } else {
            $self->error("Cannot extract hostname from URL ".$service->{URL}." on $serviceSiteName");
            next;
        }
        $self->{SITEDB}->addService($hostname, $service->{SERVICE_TYPE});
        $self->{SITEDB}->hostAttribute($hostname, 'URL', $service->{URL});
        $self->{SITEDB}->hostAttribute($hostname, 'PORT', $url->port) if ($url->port);
        $self->{SITEDB}->hostAttribute($hostname, 'PATH', $url->path) if ($url->path);
        $self->{SITEDB}->hostAttribute($hostname, 'SSL', 0) if ($url->scheme && $url->scheme eq 'https');
    }
    1;
}

=head1 NAME

NCG::SiteSet::EOSC

=head1 DESCRIPTION

The NCG::SiteSet::EOSC module extends NCG::SiteSet module. Module
extracts list of sites from EOSC json feed.

=head1 SYNOPSIS

  use NCG::SiteSet::EOSC;

  my $siteInfo = NCG::SiteSet::EOSC->new({FILE_PATH=>'/var/nagios/eosc.feed'});

  $siteInfo->getData();

=cut

=head1 METHODS

=over

=item C<new>

  my $siteInfo = NCG::SiteSet::EOSC->new($options);

Creates new NCG::SiteSet::EOSC instance. Argument $options is hash reference that
can contains following elements:
  FILE_PATH - file containing EOSC json feed.

=back

=head1 SEE ALSO

NCG::SiteSet

=cut

1;
