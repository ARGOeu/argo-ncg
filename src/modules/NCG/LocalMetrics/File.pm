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

package NCG::LocalMetrics::File;

use NCG::LocalMetrics;
use vars qw(@ISA);

@ISA=("NCG::LocalMetrics");

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
    
    if (!$self->{METRIC_CONFIG} || ref $self->{METRIC_CONFIG} ne "HASH" ) {
        $self->{NO_METRIC_CONFIG} = 1;
    }
     
    $self;
}

sub _loadMetrics {
    my $self = shift;
    my $metricSets = shift;
    my $hosts = shift;
    my $line;
    my $fileHndl;
    
    foreach my $file (keys %{$self->{DB_FILES}}) {
        if (!open ($fileHndl, $file)) {
            $self->error("Cannot open static file!");
            next;
        }
    
        while ($line = <$fileHndl>) {
            next if ($line =~ /^\s*#.*$/);
            if ($line =~ /^\s*(\S+?)!(\S+?)(!(\S+?))?(!(\S+?))?(!(.+))?$/) {
                my $action = $1;
                
                # adding metrics to service or profile,service
                if ($action eq "SERVICE_METRIC" || $action eq "ADD_SERVICE_METRIC") {
                    next if (!defined $4);
                    $metricSets->{$2}->{$4}->{all} = 1 unless (exists $metricSets->{$2}->{$4});
                } 
                
                # adding things to hosts
                elsif ($action eq "ADD_HOST_METRIC") {
                    next if (!defined $4);
                    $hosts->{$2}->{metric}->{$4} = 1 unless (exists $hosts->{$2}->{$4});
                } elsif ($action eq "ADD_HOST_SERVICE_METRIC") {
                    next if (!defined $4 || !defined $6);
                    $hosts->{$2}->{service}->{$4}->{$6} = 1;
                }

                # actions for adding/modifying metrics
                # metrics in general (on all hosts)
                elsif ($action eq "MODIFY_METRIC_CONFIG") {
                    next if (!defined $4 || !defined $6);
                    $self->{SITEDB}->metricConfigValue(undef, $2, $4, $6);
                } elsif ($action eq "MODIFY_METRIC_DEPENDENCY") {
                    next if (!defined $4 || !defined $6);
                    $self->{SITEDB}->metricDependency(undef, $2, $4, $6);
                } elsif ($action eq "MODIFY_METRIC_ATTRIBUTE") {
                    next if (!defined $4 || !defined $6);
                    $self->{SITEDB}->metricAttribute(undef, $2, $4, $6);
                } elsif ($action eq "MODIFY_METRIC_PARAMETER") {
                    next if (!defined $4 || !defined $6);
                    $self->{SITEDB}->metricParameter(undef, $2, $4, $6);
                } elsif ($action eq "MODIFY_METRIC_FLAG") {
                    next if (!defined $4 || !defined $6);
                    $self->{SITEDB}->metricFlag(undef, $2, $4, $6);
                }
                # metrics per host
                elsif ($action eq "MODIFY_HOST_METRIC_CONFIG") {
                    next if (!defined $4 || !defined $6 || !defined $8);
                    $self->{SITEDB}->metricConfigValue($2, $4, $6, $8);
                } elsif ($action eq "MODIFY_HOST_METRIC_DEPENDENCY") {
                    next if (!defined $4 || !defined $6 || !defined $8);
                    $self->{SITEDB}->metricDependency($2, $4, $6, $8);
                } elsif ($action eq "MODIFY_HOST_METRIC_ATTRIBUTE") {
                    next if (!defined $4 || !defined $6 || !defined $8);
                    $self->{SITEDB}->metricAttribute($2, $4, $6, $8);
                } elsif ($action eq "MODIFY_HOST_METRIC_PARAMETER") {
                    next if (!defined $4 || !defined $6 || !defined $8);
                    $self->{SITEDB}->metricParameter($2, $4, $6, $8);
                } elsif ($action eq "MODIFY_HOST_METRIC_FLAG") {
                    next if (!defined $4 || !defined $6 || !defined $8);
                    $self->{SITEDB}->metricFlag($2, $4, $6, $8);
                }

                # actions for removing metrics
                elsif ($action eq "REMOVE_SERVICE_METRIC") {
                    next if (!defined $4);
                    $self->{SITEDB}->removeMetric(undef, $2, $4);
                } elsif ($action eq "REMOVE_HOST_SERVICE_METRIC") {
                    next if (!defined $4 || !defined $6);
                    $self->{SITEDB}->removeMetric($2, $4, $6);
                } elsif ($action eq "REMOVE_METRIC") {
                    $self->{SITEDB}->removeMetric(undef, undef, $2);
                } elsif ($action eq "REMOVE_HOST_METRIC") {
                    next if (!defined $4);
                    $self->{SITEDB}->removeMetric($2, undef, $4);
                } else {
                    $self->debug("Unknown command found: $1");
                }
            }
        }
        close ($fileHndl);
    }

    1;
}




sub getData {
    my $self = shift;
    my $metricSets = {};
    my $hosts = {};
    
    $self->_loadMetrics ($metricSets, $hosts) || return 0;

    foreach my $host ($self->{SITEDB}->getHosts()) {
        foreach my $service ($self->{SITEDB}->getServices($host)) {
            # add metrics associated to service
            if (exists $metricSets->{$service}) {
                foreach my $metric (keys %{$metricSets->{$service}}) {
                    if (!$self->{NO_METRIC_CONFIG} && exists $self->{METRIC_CONFIG}->{$metric}) {
                        if (exists $metricSets->{$service}->{$metric}->{all}) {
                            $self->_addLocalMetric($self->{METRIC_CONFIG}->{$metric}, $host, $metric, $service);
                        } 
                    } else {
                        $self->error("Metric configuration does not contain metric $metric. Metric will be skipped.");
                    }
                }
            }
            # add metrics associated to (host, service)
            if (exists $hosts->{$host}->{service}->{$service}) {
                foreach my $metric (keys %{$hosts->{$host}->{service}->{$service}}) {
                    if (!$self->{NO_METRIC_CONFIG} && exists $self->{METRIC_CONFIG}->{$metric}) {
                        $self->_addLocalMetric($self->{METRIC_CONFIG}->{$metric}, $host, $metric, $service);
                    } else {
                        $self->error("Metric configuration does not contain metric $metric. Metric will be skipped.");
                    }
                }
            }
        }
        # add metrics associated to host
        if (exists $hosts->{$host}->{metric}) {
            foreach my $metric (keys %{$hosts->{$host}->{metric}}) {
                if (!$self->{NO_METRIC_CONFIG} && exists $self->{METRIC_CONFIG}->{$metric}) {
                    $self->_addLocalMetric($self->{METRIC_CONFIG}->{$metric}, $host, $metric);
                } else {
                    $self->error("Metric configuration does not contain metric $metric. Metric will be skipped.");
                }
            }
        }
    }
    
    1;
}

=head1 NAME

NCG::LocalMetrics::File

=head1 DESCRIPTION

The NCG::LocalMetrics::File module extends NCG::LocalMetrics module.
Module extracts metric information from file with list of tuples:
  # this is a comment
  # association between metric and service
  ADD_SERVICE_METRIC!service!metric
  # add metric to host
  ADD_HOST_METRIC!host!metric
  # add metric to service on a host
  ADD_HOST_SERVICE_METRIC!host!service!metric

  # remove single metric for defined host and service
  REMOVE_HOST_SERVICE_METRIC!host!service!metric
  # remove single metric for defined service 
  # from all hosts gathered by other SiteInfo modules
  REMOVE_SERVICE_METRIC!service!metric
  # remove single metric for defined host
  REMOVE_HOST_METRIC!host!metric
  # remove single metric from all hosts gathered by other SiteInfo modules
  REMOVE_METRIC!service!metric

  # actions for adding/modifying metrics
  # use undef to remove parameter
  # metrics in general (on all hosts)
  # add/modify configuration parameter
  MODIFY_METRIC_CONFIG!metric!config!value
  # add/modify dependency
  MODIFY_METRIC_DEPENDENCY!metric!dep!value
  # add/modify attribute
  MODIFY_METRIC_ATTRIBUTE!metric!attr!value
  # add/modify parameter
  MODIFY_METRIC_PARAMETER!metric!param!value
  # add/modify flag
  MODIFY_METRIC_FLAG!metric!flag!value

  # metrics per host
  # add/modify configuration parameter
  MODIFY_HOST_METRIC_CONFIG!host!metric!config!value
  # add/modify dependency
  MODIFY_HOST_METRIC_DEPENDENCY!host!metric!dep!value
  # add/modify attribute
  MODIFY_HOST_METRIC_ATTRIBUTE!host!metric!attr!value
  # add/modify parameter
  MODIFY_HOST_METRIC_PARAMETER!host!metric!param!value
  # add/modify flag
  MODIFY_HOST_METRIC_FLAG!host!metric!flag!value

=head1 SYNOPSIS

  use NCG::LocalMetrics::File;

  my $lms = NCG::LocalMetrics::File->new( { SITEDB=> $sitedb,
                                    DB_FILE => '/path/to/metriclist' } );

  $lms->getData();

=cut

=head1 METHODS

=over

=item C<new>

  $siteInfo = NCG::LocalMetrics::File->new( $options );

Creates new NCG::LocalMetrics::File instance. Argument $options is hash
reference that can contains following elements:
  DB_FILE - location of file with list of tuples (no default)
  DB_DIRECTORY - directory with files with list of tuples (no default)

=back

=head1 SEE ALSO

NCG::LocalMetrics

=cut

1;
