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

package NCG::SiteSet::EOSC;

use NCG::SiteSet;
use strict;
use JSON;
use vars qw(@ISA);

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

    foreach my $site (@{$jsonRef}) {
        my $sitename = $site->{'SITENAME-SERVICEGROUP'};
        my $country = $site->{'COUNTRY_NAME'};
        $self->verbose ("Found site: $sitename");
        if (!exists $self->{SITES}->{$sitename}) {
            $self->{SITES}->{$sitename} = NCG::SiteDB->new ({SITENAME=>$sitename, COUNTRY=>$country});
        } else {
            $self->{SITES}->{$sitename}->siteCountry($country) if ($country);
        }
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
