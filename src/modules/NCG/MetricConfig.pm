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

package NCG::MetricConfig;

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

=head1 NAME

NCG::MetricConfig

=head1 DESCRIPTION

The NCG::MetricConfig module is abstract class for extracting
metric configuration.
Each module extending NCG::MetricConfig must implement method
getData.

=head1 SYNOPSIS

  use NCG::MetricConfig;
  $ncg = NCG::MetricConfig->new( $attr );
  $ncg->getData();

=cut

=head1 METHODS

=over

=item C<new>

  $dbh = NCG::LocalMetrics->new( $attr );

Creates new NCG::MetricConfig instance.

=item C<getData>

  $ncg->getData ();

Abstract method for gathering metric configuration.

=back

=head1 SEE ALSO

=cut

1;
