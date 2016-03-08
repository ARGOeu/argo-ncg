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

package NCG::LocalMetricsAttrs::LDAP;

use NCG::LocalMetricsAttrs;
use strict;
use Net::LDAP;
use vars qw(@ISA);

@ISA=("NCG::LocalMetricsAttrs");

my $DEFAULT_LDAP_CONNECT_TIMEOUT = 10;

sub new
{
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);
    
    # set default values
    if (! $self->{LDAP_ADDRESS}) {
        if ( ! ($self->{LDAP_ADDRESS} = $self->{SITEDB}->siteLDAP)) {
            $self->error("LDAP_ADDRESS must be defined!");
            undef $self;
            return;
        }
    }
    # default LDAP port is BDII
    if (! defined $self->{LDAP_PORT} ) {
        $self->{LDAP_PORT} = 2170;
    }
    
    # default BDII level is site
    if (! $self->{BDII_LEVEL} ) {
        $self->{BDII_LEVEL} = "site";
    } else {
        if ($self->{BDII_LEVEL} ne "site" && $self->{BDII_LEVEL} ne "top") {
            $self->error("BDII_LEVEL value unknown: $self->{BDII_LEVEL}. BDII_LEVEL can be: site, top.!");
            undef $self;
            return;
        }
    }

    if (! defined $self->{LDAP_CONNECT_TIMEOUT}) {
        $self->{LDAP_CONNECT_TIMEOUT} = $DEFAULT_LDAP_CONNECT_TIMEOUT;
    }

    $self;
}

sub getData {
    my $self = shift;
    my $sitename = shift || $self->{SITENAME} || "";

    #if ($sitename) {
    #    $self->error("Sitename must be defined!");
    #    return 0;
    #}

    my $basedn;
    my $mesg;
    my $hostname;
    my $port;
    my $entry;
    my $voEntry;
    
    if (! $self->{LDAP_BASEDN} ) {
        if ($self->{LDAP_PORT} == 2135) {
            $self->{LDAP_BASEDN} = "Mds-Vo-Name=local, O=Grid";
        } elsif ($self->{LDAP_PORT} == 2170) {
            if ($self->{BDII_LEVEL} eq "site") {
                $self->{LDAP_BASEDN} = "Mds-Vo-Name=$sitename, O=Grid";
            } elsif ($self->{BDII_LEVEL} eq "top") {
                $self->{LDAP_BASEDN} = "Mds-Vo-Name=$sitename, Mds-Vo-Name=local, O=Grid";
            }
        } else {
            $self->warning("Base DN not defined, port ". $self->{LDAP_PORT} ." is not BDII or MDS. Assuming 'O=Grid'");
            $self->{LDAP_BASEDN} = "O=Grid";
        }
    }

    $self->verbose("Getting info from LDAP: " . $self->{LDAP_ADDRESS} . ":" . $self->{LDAP_PORT} . "/" . $self->{LDAP_BASEDN});

    my $ldap = Net::LDAP->new( $self->{LDAP_ADDRESS}, port => $self->{LDAP_PORT}, timeout => $self->{LDAP_CONNECT_TIMEOUT}, async => 1 );
    if (! defined $ldap ) {
        $self->error("Cannot connect to $self->{LDAP_ADDRESS}:$self->{LDAP_PORT}");
        return 0;
    }    
    $mesg = $ldap->bind( anonymous => 1 );
    if ($mesg->code) {
        $self->error("Could not bind to LDAP: ".$mesg->error);
        return 0;
    }

    # Get SE information
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => "(objectClass=GlueSE)",
                            attrs=> ['GlueSEUniqueID'],
                            timelimit => 60 );
    
    if ($mesg->code) {
        $self->error("Could not fetch SE info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            $hostname = $entry->get_value('GlueSEUniqueID') or next;
            my $path;

            # Get remote path that selected VO can use
            my $mesg1 = $ldap->search ( base => $self->{LDAP_BASEDN},
                                        filter => "(&(objectClass=GlueSATop)(GlueChunkKey=GlueSEUniqueID=$hostname))",
                                        attrs => ['GlueVOInfoAccessControlBaseRule','GlueVOInfoPath'],
                                        timelimit => 60 );
            if ($mesg1->code) {
                $self->error("Could not fetch SE VO info from LDAP: ".$mesg->error);    
            } else {
                foreach my $voEntry ($mesg1->entries()) {
                    my $voname = $voEntry->get_value('GlueVOInfoAccessControlBaseRule') or next;
                    $voname = lc($voname);
                    $voname =~ s/^vo://;
                    my $path = $voEntry->get_value('GlueVOInfoPath') or next;
                    $self->{SITEDB}->hostAttributeVO($hostname, "SE_PATH", $voname, $path);
                }
            }

            # GridFTP specific parameter
            $mesg1 = $ldap->search ( base => $self->{LDAP_BASEDN},
                                    filter => "(&(&(objectClass=GlueSEAccessProtocol)(GlueChunkKey=GlueSEUniqueID=$hostname))(GlueSEAccessProtocolType=gsiftp))",
                                    attrs => ['GlueSEAccessProtocolPort'],
                                    timelimit => 60 );
		
            next if ($mesg1->code);
            if ($mesg1->count != 0) {
                my $port = $mesg1->entry(0)->get_value('GlueSEAccessProtocolPort');
                if ($port) {
                    $self->{SITEDB}->hostAttribute($hostname, "GRIDFTP_PORT", $port);
                }
            } 
        }
    }

    # Get CE information
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => "(objectClass=GlueCE)",
                            attrs=> ['GlueCEUniqueID'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch CE info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueCEUniqueID') && $entry->get_value('GlueCEUniqueID') =~ /([-_.A-Za-z0-9]+):(\d+)\/(jobmanager|blahp)-([-_.A-Za-z0-9]+)-([-_.A-Za-z0-9]+)/) {
                $hostname = $1;
                $port = $2;
                $self->{SITEDB}->hostAttribute($hostname, "GRAM_PORT", $port);
            }
        }
    }
    
    # Get CREAM CE information
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => "(&(objectClass=GlueCE)(GlueCEImplementationName=CREAM))",
                            attrs=> ['GlueCEAccessControlBaseRule','GlueCEUniqueID'],
                            timelimit => 60 );
    
    if ($mesg->code) {
        $self->error("Could not fetch CREAM CE info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueCEUniqueID') && $entry->get_value('GlueCEUniqueID') =~ /([-_.A-Za-z0-9]+):(\d+)\/(cream-([-_.A-Za-z0-9]+?)-([-_.A-Za-z0-9]+))$/) {
                $hostname = $1;
                $port = $2;
                my $cream_lrms = $4;
                my $cream_queue = $5;
                $self->{SITEDB}->hostAttribute($hostname, "CREAM_PORT", $port);
                
                foreach my $attr ($entry->get_value('GlueCEAccessControlBaseRule')) {
                    if ($attr =~ /VO:(.*)/) {
                        my $voname = lc($1);
                        $self->{SITEDB}->hostAttributeVO($hostname, "CREAM_LRMS", $voname, $cream_lrms);
                        $self->{SITEDB}->hostAttributeVO($hostname, "CREAM_QUEUE", $voname, $cream_queue);
                    }
                }
            }
        }
    }

    # Get SRM information
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => "(&(objectClass=GlueService)(|(GlueServiceType=srm_v1)(GlueServiceType=srm)))",
                            attrs=> ['GlueServiceEndpoint','GlueServiceVersion'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch SRM info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /httpg:\/\/([-_.A-Za-z0-9]+):(\d+)\/srm/) {
                $hostname = $1;
                $port = $2;

                if($entry->get_value('GlueServiceVersion') && $entry->get_value('GlueServiceVersion') eq '2.2.0') {
                    # SRMv2
                    $self->{SITEDB}->hostAttribute($hostname, "SRM2_PORT", $port);
                } else { # Allow anything else to be SRMv1 to deal with bad information providers
                    $self->{SITEDB}->hostAttribute($hostname, "SRM1_PORT", $port);
                }

            }
        }
    }

    # https://egee.srce.hr:7443/glite_wms_wmproxy_server
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => "(&(objectClass=GlueService)(GlueServiceType=org.glite.wms.WMProxy))",
                            attrs=> ['GlueServiceEndpoint'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch WMS info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /^(https:\/\/([-_.A-Za-z0-9]+):(\d+)\/[-_.A-Za-z0-9]+)$/) {
                $hostname = $2;
                $port = $3;
                $self->{SITEDB}->hostAttribute($hostname, "WMPROXY_PORT", $port);
            }
        }
    }
    
    # Get VOBOX information
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => "(&(objectClass=GlueService)(GlueServiceType=VOBOX))",
                            attrs=> ['GlueServiceEndpoint'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch VOBOX info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /gsissh:\/\/([-_.A-Za-z0-9]+):(\d+)/) {
                $hostname = $1;
                $port = $2;
                $self->{SITEDB}->hostAttribute($hostname, "VOBOX_PORT", $port);
            }
        }
    }

    # Get MyProxy information
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => "(&(objectClass=GlueService)(GlueServiceType=MyProxy))",
                            attrs=> ['GlueServiceEndpoint'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch PROX info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /([-_.A-Za-z0-9]+):(\d+)/) {
                $hostname = $1;
                $port = $2;
                $self->{SITEDB}->hostAttribute($hostname, "MYPROXY_PORT", $port);
            }
        }
    }

    # Get MON boxes information
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => "(&(objectClass=GlueService)(GlueServiceType=org.glite.rgma.PrimaryProducer))",
                            attrs=> ['GlueServiceEndpoint'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch MON info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /^https:\/\/([-_.A-Za-z0-9]+):(\d+)/) {
                $hostname = $1;
                $port = $2;
                $self->{SITEDB}->hostAttribute($hostname, "RGMA_PORT", $port);
            }
        }
    }

    # Get top & site BDII information
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => "(&(objectClass=GlueService)(|(GlueServiceType=bdii_top)(GlueServiceType=bdii_site)))",
                            attrs=> ['GlueServiceEndpoint'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch TOP BDII info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /([-_.A-Za-z0-9]+):(\d+)\/bdii\-(top|site)/) {
                $hostname = $1;
                $port = $2;
                $self->{SITEDB}->hostAttribute($hostname, "BDII_PORT", $port);
            }
        }
    }

    1;
}



sub baseDN {
    my $self = shift;
    my $value = shift;
    $self->{LDAP_BASEDN} = $value if (defined $value);
    $self->{LDAP_BASEDN};
}

sub address {
    my $self = shift;
    my $value = shift;
    $self->{LDAP_ADDRESS} = $value if (defined $value);
    $self->{LDAP_ADDRESS};
}

sub port {
    my $self = shift;
    my $value = shift;
    $self->{LDAP_PORT} = $value if (defined $value);
    $self->{LDAP_PORT};
}

sub bdiiLevel {
    my $self = shift;
    my $value = shift;
    $self->{BDII_LEVEL} = $value if (defined $value);
    $self->{BDII_LEVEL};
}

=head1 NAME

NCG::LocalMetricsAttrs::LDAP

=head1 DESCRIPTION

The NCG::LocalMetricsAttrs::LDAP module extends NCG::LocalMetricsAttrs
module. Module extracts detailed metric information from LDAP-based 
information services (e.g. BDII, Globus MDS).

=head1 SYNOPSIS

  use NCG::LocalMetricsAttrs::LDAP;

  my $metricInfo = NCG::LocalMetricsAttrs::LDAP->new({LDAP_ADDRESS=>'ldap.server.com',
                                           LDAP_PORT=>2170,
                                           LDAP_BASEDN=>'O=Grid', SITEDB=>$siteDb});

  $siteInfo->getData();

=cut

=head1 METHODS

=over

=item C<new>

  my $siteInfo = NCG::LocalMetricsAttrs::LDAP->new($options);

Creates new NCG::LocalMetricsAttrs::LDAP instance. Argument $options is 
hash reference that can contains following elements:
  LDAP_ADDRESS - address of LDAP server (default: localhost)
  LDAP_PORT - port of LDAP server (default: 2170)
  LDAP_BASEDN - basedn used when querying LDAP server
  BDII_LEVEL - which BDII level is queried, this option will
               define default base DN value
               possible values: site, top
  (default: site)
  LDAP_CONNECT_TIMEOUT - timeout for binding to LDAP server
  (default: 10)

=item C<address>

  print $siteInfo->address;
  $siteInfo->address('ldap.server.com');

Accessor method for property address.

=item C<port>

  print $siteInfo->port;
  $siteInfo->port(2135);

Accessor method for property port.

=item C<baseDN>

  print $siteInfo->baseDN;
  $siteInfo->baseDN('Mds-Vo-Name=myegeesite,O=Grid');

Accessor method for property baseDN.

=item C<bdiiLevel>

  print $siteInfo->bdiiLevel;
  $siteInfo->bdiiLevel('top');

Accessor method for property BDII_LEVEL.

=back

=head1 SEE ALSO

NCG::LocalMetricsAttrs

=cut

1;
