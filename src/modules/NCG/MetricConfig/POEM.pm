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

package NCG::MetricConfig::POEM;

use strict;
use warnings;
use NCG::MetricConfig;
use vars qw(@ISA);
use JSON; 
use LWP::UserAgent;

@ISA=("NCG::MetricConfig");

my $DEFAULT_POEM_ROOT_URL = "http://poem.egi.eu";
my $DEFAULT_POEM_ROOT_URL_SUFFIX = "/api/v2/metrics";
sub new
{
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);
    # set default values
    if (! $self->{POEM_ROOT_URL}) {
        $self->{POEM_ROOT_URL} = $DEFAULT_POEM_ROOT_URL;
    }
    if (! $self->{TOKEN}) {
        $self->error("Authentication token must be defined.");
        return;
    }

    $self;
}

sub getDataWWW {
    my $self = shift;
    my $url;

    my $ua = LWP::UserAgent->new(timeout=>$self->{TIMEOUT}, env_proxy=>1);
    $ua->agent("NCG::MetricConfig::POEM");
    $url = $self->{POEM_ROOT_URL} . $DEFAULT_POEM_ROOT_URL_SUFFIX;
    my $req = HTTP::Request->new(GET => $url);
    $req->header('x-api-key' => $self->{TOKEN});
    my $res = $self->safeHTTPSCall($ua,$req);
    if (!$res->is_success) {
        $self->error("Could not get results from POEM $url: ".$res->status_line);
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
    my $content;
    my $jsonRef;

    if ( $self->{POEM_FILE} ) {
        $content = $self->getDataFile();
    } else {
        $content = $self->getDataWWW();
    }
    return unless ($content);

    eval {
        $jsonRef = from_json($content);
    };
    if ($@) {
        $self->error("Error parsing JSON response from POEM: ".$@);
        return;
    }
    foreach my $hashRef ( @{$jsonRef}) {
        foreach my $metric (keys %{$hashRef}) {
            if (exists $self->{METRIC_CONFIG}->{$metric}) {
                foreach my $attr (keys %{$hashRef->{$metric}}) {
                    if ( ref $hashRef->{$metric}->{$attr} eq "HASH" ) {
                        foreach my $attr2 (keys %{$hashRef->{$metric}->{$attr}}) {
                            $self->{METRIC_CONFIG}->{$metric}->{$attr}->{$attr2} = $hashRef->{$metric}->{$attr}->{$attr2};
                        }
                    } else {
                        $self->{METRIC_CONFIG}->{$metric}->{$attr} = $hashRef->{$metric}->{$attr};
                    }
                }
            } else {
                $self->{METRIC_CONFIG}->{$metric} = {%{$hashRef->{$metric}}}
            }
        }
    }

    1;
}


=head1 NAME

NCG::MetricConfig::POEM

=head1 DESCRIPTION

The NCG::MetricConfig::POEM module extends NCG::MetricConfig module.
Module extracts metric configuration from POEM.

=head1 SYNOPSIS

  use NCG::MetricConfig::POEM;

  my $lms = NCG::MetricConfig::POEM->new( { METRIC_CONFIG => $metricConfig } );

  $lms->getData();

=cut

=head1 METHODS

=over

=item C<new>

  $siteInfo = NCG::MetricConfig::POEM->new( $options );

Creates new NCG::MetricConfig::POEM instance. Argument $options is hash
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

NCG

=cut

1;
