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

package NCG::LocalMetricsAttrs::File;

use NCG::LocalMetricsAttrs;
use strict;
use Text::CSV_XS;
use vars qw(@ISA);

@ISA=("NCG::LocalMetricsAttrs");

sub new
{
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);
    
    if ( defined $self->{DB_FILE} ) {
        if (! -f $self->{DB_FILE})
        {
            $self->error("Can't find static file!");
            undef $self;
            return 0;
        }
        $self->{DB_FILES}->{$self->{DB_FILE}} = 1;
    }

    if ( defined $self->{DB_DIRECTORY} ) {
        if (! -d $self->{DB_DIRECTORY})
        {
            $self->error("Can't find static directory!");
            undef $self;
            return 0;
        }
        my $filelist = [];
        $self->_addRecurseDirs($filelist, $self->{DB_DIRECTORY});
        foreach my $file (@$filelist) {
            $self->{DB_FILES}->{$file} = 1;
        }
    }

    if ( !defined $self->{DB_DIRECTORY} && ! defined $self->{DB_FILE} ) {
        $self->error("File of directory name must be defined!");
        undef $self;
        return 0;
    }

    $self;
}

sub _loadMetricAttrs {
    my $self = shift;
    my $globalAttributes = shift;
    my $attributes = shift;
    my $hosts = shift;
    my $services = shift;
    my $line;
    my $fileHndl;
    my $csv = Text::CSV_XS->new( {sep_char=>'!'} );

    foreach my $file (keys %{$self->{DB_FILES}}) {
        if (!open ($fileHndl, $file)) {
            $self->error("Cannot open static file!");
            return 0;
        }
        while (my $row = $csv->getline ($fileHndl)) {
            my $action = $row->[0];
            if ($action eq "ATTRIBUTE") {
                $attributes->{global}->{$row->[1]} = $row->[2];
            } elsif ($action eq "HOST_ATTRIBUTE") {
                $hosts->{global}->{$row->[1]}->{$row->[2]} = $row->[3];
            } elsif ($action eq "SERVICE_ATTRIBUTE") {
                $services->{global}->{$row->[1]}->{$row->[2]} = $row->[3];
            } elsif ($action eq "VO_ATTRIBUTE") {
                $attributes->{vo}->{$row->[1]}->{$row->[2]} = $row->[3];
            } elsif ($action eq "VO_HOST_ATTRIBUTE") {
                $hosts->{vo}->{$row->[1]}->{$row->[2]}->{$row->[3]} = $row->[4];
            } elsif ($action eq "VO_SERVICE_ATTRIBUTE") {
                $services->{vo}->{$row->[1]}->{$row->[2]}->{$row->[3]} = $row->[4];
            } elsif ($action eq "GLOBAL_ATTRIBUTE") {
                $globalAttributes->{global}->{$row->[1]} = $row->[2];
            } elsif ($action eq "VO_GLOBAL_ATTRIBUTE") {
                $globalAttributes->{vo}->{$row->[1]}->{$row->[2]} = $row->[3];
            } elsif ($action eq "HOST_ARRAY_ATTRIBUTE") {
                $hosts->{array}->{$row->[1]}->{$row->[2]} = $row->[3];
            } elsif ($action eq "VO_HOST_ARRAY_ATTRIBUTE") {
                $hosts->{vo_array}->{$row->[1]}->{$row->[2]}->{$row->[3]} = $row->[4];
            } else {
                $self->debug("Unknown command found: $action");
            }
        }
        close ($fileHndl);
    }

    1;
}

sub getData {
    my $self = shift;
    my $globalAttributes = {};
    my $attributes = {};
    my $hosts = {};
    my $services = {};
    my $attribute;
    
    $self->_loadMetricAttrs ($globalAttributes, $attributes, $hosts, $services) || return 0;

    # add global attributes
    foreach my $attribute (keys %{$globalAttributes->{global}}) {
        $self->{SITEDB}->globalAttribute($attribute, $globalAttributes->{global}->{$attribute});
    }
    foreach my $vo (keys %{$globalAttributes->{vo}}) {
        foreach my $attribute (keys %{$globalAttributes->{vo}->{$vo}}) {
            $self->{SITEDB}->globalAttributeVO($attribute, $vo, $globalAttributes->{vo}->{$vo}->{$attribute});
        }
    }
    
    # add host attributes
    foreach my $hostname ($self->{SITEDB}->getHosts()) {
        # add default attributes
        foreach my $attribute (keys %{$attributes->{global}}) {
            $self->{SITEDB}->hostAttribute($hostname, $attribute, $attributes->{global}->{$attribute});
        }
        foreach my $vo (keys %{$attributes->{vo}}) {
            foreach my $attribute (keys %{$attributes->{vo}->{$vo}}) {
                $self->{SITEDB}->hostAttributeVO($hostname, $attribute, $vo, $attributes->{vo}->{$vo}->{$attribute});
            }
        }

        # add host specific attributes
        if (exists $hosts->{global}->{$hostname}) {
            foreach my $attribute (keys %{$hosts->{global}->{$hostname}}) {
                $self->{SITEDB}->hostAttribute($hostname, $attribute, $hosts->{global}->{$hostname}->{$attribute});
            }
        }
        if (exists $hosts->{vo}->{$hostname}) {
            foreach my $vo (keys %{$hosts->{vo}->{$hostname}}) {
                foreach my $attribute (keys %{$hosts->{vo}->{$hostname}->{$vo}}) {
                    $self->{SITEDB}->hostAttributeVO($hostname, $attribute, $vo, $hosts->{vo}->{$hostname}->{$vo}->{$attribute});
                }
            }
        }
        if (exists $hosts->{array}->{$hostname}) {
            foreach my $attribute (keys %{$hosts->{array}->{$hostname}}) {
                $self->{SITEDB}->addHostAttributeArray($hostname, $attribute, $hosts->{array}->{$hostname}->{$attribute});
            }
        }
        if (exists $hosts->{vo_array}->{$hostname}) {
            foreach my $vo (keys %{$hosts->{vo_array}->{$hostname}}) {
                foreach my $attribute (keys %{$hosts->{vo_array}->{$hostname}->{$vo}}) {
                    $self->{SITEDB}->addHostAttributeArrayVO($hostname, $attribute, $vo, $hosts->{vo_array}->{$hostname}->{$vo}->{$attribute});
                }
            }
        }

        # add service specific attributes
        foreach my $service ($self->{SITEDB}->getServices($hostname)) {
            if (exists $services->{global}->{$service}) {
                foreach my $attribute (keys %{$services->{global}->{$service}}) {
                    $self->{SITEDB}->hostAttribute($hostname, $attribute, $services->{global}->{$service}->{$attribute});
                }
            }
            if (exists $services->{vo}->{$service}) {
                foreach my $vo (keys %{$services->{vo}->{$service}}) {
                    foreach $attribute (keys %{$services->{vo}->{$service}->{$vo}}) {
                        $self->{SITEDB}->hostAttributeVO($hostname, $attribute, $services->{vo}->{$service}->{$vo}->{$attribute});
                    }
                }
            }
        }
    }
    
    1;
}


=head1 NAME

NCG::LocalMetricsAttrs::File

=head1 DESCRIPTION

The NCG::LocalMetricsAttrs::File module extends NCG::LocalMetricsAttrs
module. Module extracts detailed metric information from file with
list of tuples:
  # this is a comment
  # add global attribute
  GLOBAL_ATTRIBUTE!name!value
  # add global attribute
  VO_GLOBAL_ATTRIBUTE!VO!name!value
  # add attribute value to all hosts
  ATTRIBUTE!name!value
  # add attribute value to defined host
  HOST_ATTRIBUTE!host!name!value
  # add attribute to each host which contains defined service
  SERVICE_ATTRIBUTE!service!name!value
  # add VO attribute value to all hosts
  VO_ATTRIBUTE!VO!name!value
  # add VO attribute value to defined host
  VO_HOST_ATTRIBUTE!host!VO!name!value
  # add VO attribute to each host which contains defined service
  VO_SERVICE_ATTRIBUTE!service!VO!name!value


information services (e.g. BDII, Globus MDS).

=head1 SYNOPSIS

  use NCG::LocalMetricsAttrs::File;

  my $lma = NCG::LocalMetricsAttrs::File->new( { SITEDB=> $sitedb,
                                        DB_FILE => '/path/to/metrics' } );

  $lma->getData();

=cut

=head1 METHODS

=over

=item C<new>

  my $lma = NCG::LocalMetricsAttrs::File->new( $options );

Creates new NCG::LocalMetricsAttrs::File instance. Argument $options is hash
reference that can contains following elements:
  DB_FILE - location of file with list of tuples (no default)
  DB_DIRECTORY - directory with files with list of tuples (no default)

=back

=head1 SEE ALSO

NCG::LocalMetricsAttrs

=cut

1;
