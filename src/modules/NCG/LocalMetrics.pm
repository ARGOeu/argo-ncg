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

package NCG::LocalMetrics;

use strict;
use warnings;
use NCG;
use vars qw(@ISA);

@ISA=("NCG");

sub new : method {
    my ($proto, $data) = @_;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new($data);
    $self;
}

sub _addLocalMetric : method {
    my ($self, $metricRef, $host, $metric, $service) = @_;
    my $confRef = {};
    my $depRef = {};
    my $attrRef = {};
    my $paramRef = {};
    my $flagsRef = {};
    my $parent;

    $confRef = {%{$metricRef->{config}}} if (exists $metricRef->{config});
    $attrRef = {%{$metricRef->{attribute}}} if (exists $metricRef->{attribute});
    $paramRef = {%{$metricRef->{parameter}}} if (exists $metricRef->{parameter});
    $depRef = {%{$metricRef->{dependency}}} if (exists $metricRef->{dependency});
    $flagsRef = {%{$metricRef->{flags}}} if (exists $metricRef->{flags});
    $parent = $metricRef->{parent} if (exists $metricRef->{parent});
    
    $self->{SITEDB}->addLocalMetric($host,
                                    $metric,
                                    $service,
                                    $metricRef->{probe},
                                    $confRef,
                                    $attrRef,
                                    $paramRef,
                                    $depRef,
                                    $flagsRef,
                                    $parent,
                                    $metricRef->{docurl},
                                    $metricRef->{vo},
                                    $metricRef->{vofqan});
}

=head1 NAME

NCG::LocalMetrics

=head1 DESCRIPTION

The NCG::LocalMetrics module is abstract class for extracting
information about local metrics which are available for each host.
Each module extending NCG::LocalMetrics must implement method
getMetrics.

=head1 SYNOPSIS

  use NCG::LocalMetrics;
  $ncg = NCG::LocalMetrics->new( $attr );
  $ncg->getData();

=cut

=head1 METHODS

=over

=item C<new>

  $dbh = NCG::LocalMetrics->new( $attr );

Creates new NCG::LocalMetrics instance.

=item C<getData>

  $ncg->getData ();

Abstract method for gathering metric information.

=back

=head1 SEE ALSO

=cut

1;
