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

package NCG::SiteInfo::File;

use NCG::SiteInfo;
use strict;
use vars qw(@ISA);

@ISA=("NCG::SiteInfo");

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

sub getData
{
    my $self = shift;
    my $line;
    my $fileHndl;
    
    foreach my $file (keys %{$self->{DB_FILES}}) {
        if (!open ($fileHndl, $file)) {
            $self->error("Cannot open static file!");
            return 0;
        }
        while ($line = <$fileHndl>) {
            next if ($line =~ /^\s*#.*$/);
            if ($line =~ /^\s*(\S+?)!(\S.+?)(!(\S+?))?(!(\S+))?\s*$/) {
                my $action = $1;
                if ($action eq "HOST_SERVICE_VO" || $action eq "ADD_HOST_SERVICE_VO") {
                    next if (!defined $6);
                    $self->{SITEDB}->addHost($2);
                    $self->{SITEDB}->addService($2, $4);
                    $self->{SITEDB}->addVO($2, $4, lc($6));
                } elsif ($action eq "HOST_SERVICE" || $action eq "ADD_HOST_SERVICE") {
                    $self->{SITEDB}->addHost($2);
                    $self->{SITEDB}->addService($2, $4);
                } elsif ($action eq "REMOVE_HOST") {
                    $self->{SITEDB}->removeHost($2);
                } elsif ($action eq "REMOVE_SERVICE") {
                    $self->{SITEDB}->removeService(undef, $2);
                } elsif ($action eq "REMOVE_HOST_SERVICE") {
                    $self->{SITEDB}->removeService($2, $4);
                } elsif ($action eq "SITE_COUNTRY") {
                    $self->{SITEDB}->siteCountry($2);
                } elsif ($action eq "SITE_GRID") {
                    $self->{SITEDB}->addSiteGrid($2);
                } elsif ($action eq "SITE_PARENT") {
                    $self->{SITEDB}->addParent($2, $4);
                } else {
                    $self->debug("Unknown command found: $1");
                }
            }
        }
        close ($fileHndl);
    }

    1;
}

=head1 NAME

NCG::SiteInfo::File

=head1 DESCRIPTION

The NCG::SiteInfo::File module extends NCG::SiteInfo module. Module
extracts site information from file with list of tuples:
  # this is a comment
  # adds service for defined VO to host
  ADD_HOST_SERVICE_VO!host!service!VO
  # adds non-VO-dependent service to host
  ADD_HOST_SERVICE!host!service
  # remove the host
  REMOVE_HOST!host
  # removes service from all hosts gathered by other SiteInfo modules
  REMOVE_SERVICE!service
  # removes service from defined host
  REMOVE_HOST_SERVICE!host!service
  # defines site's country
  SITE_COUNTRY!country
  # defines to which grid does site belong
  SITE_GRID!grid
  # define site's border router 
  SITE_PARENT!router.fqdn
  SITE_PARENT!router.fqdn!router.ip

=head1 SYNOPSIS

  use NCG::SiteInfo::File;

  my $siteInfo = NCG::SiteInfo::File->new( { DB_FILE => '/path/to/tuplelist' } );
  
  $siteInfo->getData();

=cut

=head1 METHODS

=over

=item C<new>

  $siteInfo = NCG::SiteInfo::File->new( $attr );

Creates new NCG::SiteInfo::File instance. Argument $attr is hash
reference that can contains following elements:
  DB_FILE - location of file with list of tuples (no default)
  DB_DIRECTORY - directory with files with list of tuples (no default)

=back

=head1 SEE ALSO

NCG::Site

=cut

1;
