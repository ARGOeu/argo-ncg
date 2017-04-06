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

package NCG::SiteInfo::LDAP;

use NCG::SiteInfo;
use strict;
use Net::LDAP;
use vars qw(@ISA);

@ISA=("NCG::SiteInfo");

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

    if (! defined $self->{ADD_HOSTS} ) {
        $self->{ADD_HOSTS} = 1;
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
    my $filter;

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

    # Set site contact address, country & site
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                           filter => "(objectClass=GlueSite)",
                           attrs=> ['GlueSiteLocation', 'GlueSiteOtherInfo'],
                           timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch site info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if (!$self->{SITEDB}->siteCountry()) {
                my $country = $entry->get_value('GlueSiteLocation');
                if ($country =~ /(\S.+?)\,\s*(\S.*\S)\s*/) {
                    my $testString = $2;
                    if ($testString =~ /(\`|\~|\!|\$|\%|\^|\*|\||\'|\"|\<|\>|\?|\,|\(|\))/) {
                        $self->error('Found country entry with illegal character (`~!$%^*|\'"<>?,()): '.$testString);
                    } else {
                        $self->{SITEDB}->siteCountry($testString);
                    }
                }
            }

            foreach my $attr ($entry->get_value('GlueSiteOtherInfo')) {
                if ($attr =~ /GRID=\s*(\S.*\S)\s*/) {
                    my $testString = $1;
                    if ($testString =~ /(\`|\~|\!|\$|\%|\^|\*|\||\'|\"|\<|\>|\?|\,|\(|\))/) {
                        $self->error('Found country entry with illegal character (`~!$%^*|\'"<>?,()): '.$testString);
                    } else {
                        $self->{SITEDB}->addSiteGrid($testString);
                    }
                }
            }
        }
    }

    if ($self->{VO_FILTER}) {
        $filter = "(&(objectClass=GlueCE)(GlueCEAccessControlBaseRule=*".$self->{VO_FILTER}."))";
    } else {
        $filter = "(objectClass=GlueCE)";
    }
    # Get CE information
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => $filter,
                            attrs=> ['GlueCEUniqueID','GlueCEAccessControlBaseRule'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch CE info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            #lxb2006.cern.ch:2119/jobmanager-lcgpbs-dteam
            #lxb2039.cern.ch:2119/blah-pbs-dteam
            if ($entry->get_value('GlueCEUniqueID') && $entry->get_value('GlueCEUniqueID') =~ /([-_.A-Za-z0-9]+):(\d+)\/(jobmanager)-([-_.A-Za-z0-9]+?)-([-_.A-Za-z0-9]+)/) {
                $hostname = $1;
                $self->{SITEDB}->addHost($hostname) if ($self->{ADD_HOSTS});
                $self->{SITEDB}->addService($hostname, "CE");

                foreach my $attr ($entry->get_value('GlueCEAccessControlBaseRule')) {
                    if ($attr =~ /VO:(.*)/) {
                        my $voname = lc($1);
                        $self->{SITEDB}->addVO($hostname, "CE", $voname);
                    }
                }
            } elsif ($entry->get_value('GlueCEUniqueID') && $entry->get_value('GlueCEUniqueID') =~ /([-_.A-Za-z0-9]+):(\d+)\/(cream)-([-_.A-Za-z0-9]+?)-([-_.A-Za-z0-9@]+)/) {
                $hostname = $1;
                $self->{SITEDB}->addHost($hostname) if ($self->{ADD_HOSTS});
                $self->{SITEDB}->addService($hostname, "CREAM-CE");

                foreach my $attr ($entry->get_value('GlueCEAccessControlBaseRule')) {
                    if ($attr =~ /VO:(.*)/) {
                        my $voname = lc($1);
                        $self->{SITEDB}->addVO($hostname, "CREAM-CE", $voname);
                    }
                }
            }
        }
    }

    if ($self->{VO_FILTER}) {
        $filter = "(&(&(objectClass=GlueService)(GlueServiceType=srm))(GlueServiceAccessControlRule=".$self->{VO_FILTER}."))";
    } else {
        $filter = "(&(objectClass=GlueService)(GlueServiceType=srm))";
    }
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => $filter,
                            attrs=> ['GlueServiceEndpoint','GlueServiceAccessControlRule'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch SRM info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /httpg:\/\/([-_.A-Za-z0-9]+):(\d+)\/srm\/managerv(\d+)/) {
                $hostname = $1;
                next if ($3 && $3 eq '1');
                $self->{SITEDB}->addHost($hostname) if ($self->{ADD_HOSTS});
                $self->{SITEDB}->addService($hostname, "SRM");

                foreach my $attr ($entry->get_value('GlueServiceAccessControlRule')) {
                    my $voname = lc($attr);
                    $self->{SITEDB}->addVO($hostname, "SRM", $voname);
                }
            }
        }
    }

    if ($self->{VO_FILTER}) {
        $filter = "(&(&(objectClass=GlueService)(GlueServiceType=org.glite.wms.WMProxy))(GlueServiceAccessControlRule=".$self->{VO_FILTER}."))";
    } else {
        $filter = "(&(objectClass=GlueService)(GlueServiceType=org.glite.wms.WMProxy))";
    }
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => $filter,
                            attrs=> ['GlueServiceEndpoint','GlueServiceAccessControlRule'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch WMS info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /https:\/\/([-_.A-Za-z0-9]+):(\d+)/) {
                $hostname = $1;
                $self->{SITEDB}->addHost($hostname) if ($self->{ADD_HOSTS});
                $self->{SITEDB}->addService($hostname, "WMS");

                foreach my $attr ($entry->get_value('GlueServiceAccessControlRule')) {
                    my $voname = lc($attr);
                    $self->{SITEDB}->addVO($hostname, "WMS", $voname);
                }
            }
        }
    }

    if ($self->{VO_FILTER}) {
        $filter = "(&(&(objectClass=GlueService)(GlueServiceType=VOBOX))(GlueServiceAccessControlRule=".$self->{VO_FILTER}."))";
    } else {
        $filter = "(&(objectClass=GlueService)(GlueServiceType=VOBOX))";
    }
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => $filter,
                            attrs=> ['GlueServiceEndpoint','GlueServiceAccessControlRule'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch VOBOX info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /gsissh:\/\/([-_.A-Za-z0-9]+):(\d+)/) {
                $hostname = $1;
                $self->{SITEDB}->addHost($hostname) if ($self->{ADD_HOSTS});
                $self->{SITEDB}->addService($hostname, "VO-box");

                foreach my $attr ($entry->get_value('GlueServiceAccessControlRule')) {
                    my $voname = lc($attr);
                    $self->{SITEDB}->addVO($hostname, "VO-box", $voname);
                }
            }
        }
    }

    # Get MyProxy information
    if ($self->{VO_FILTER}) {
        $filter = "(&(&(objectClass=GlueService)(GlueServiceType=MyProxy))(GlueServiceAccessControlRule=".$self->{VO_FILTER}."))";
    } else {
        $filter = "(&(objectClass=GlueService)(GlueServiceType=MyProxy))";
    }
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => $filter,
                            attrs=> ['GlueServiceEndpoint'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch PROX info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /([-_.A-Za-z0-9]+):(\d+)/) {
                $hostname = $1;
                $self->{SITEDB}->addHost($hostname) if ($self->{ADD_HOSTS});
                $self->{SITEDB}->addService($hostname, "MyProxy");
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
                $self->{SITEDB}->addHost($hostname) if ($self->{ADD_HOSTS});
                $self->{SITEDB}->addService($hostname, "MON");
            }
        }
    }

    # Get TOP BDII information
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => "(&(objectClass=GlueService)(GlueServiceType=bdii_top))",
                            attrs=> ['GlueServiceEndpoint'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch TOP BDII info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /^ldap:\/\/([-_.A-Za-z0-9]+):(\d+)/) {
                $hostname = $1;
                $self->{SITEDB}->addHost($hostname) if ($self->{ADD_HOSTS});
                $self->{SITEDB}->addService($hostname, "Top-BDII");
            }
        }
    }

    # Get Site BDII information
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => "(&(objectClass=GlueService)(GlueServiceType=bdii_site))",
                            attrs=> ['GlueServiceEndpoint'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch Site BDII info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /^ldap:\/\/([-_.A-Za-z0-9]+):(\d+)/i) {
                $hostname = $1;
                $self->{SITEDB}->addHost($hostname) if ($self->{ADD_HOSTS});
                $self->{SITEDB}->addService($hostname, 'Site-BDII');
            }
        }
    }

    # Get LFC information
    if ($self->{VO_FILTER}) {
        $filter = "(&(&(objectClass=GlueService)(GlueServiceType=lcg-file-catalog))(GlueServiceAccessControlRule=".$self->{VO_FILTER}."))";
    } else {
        $filter = "(&(objectClass=GlueService)(GlueServiceType=lcg-file-catalog))";
    }
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => $filter,
                            attrs=> ['GlueServiceEndpoint','GlueServiceAccessControlRule'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch LFC info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /([-_.A-Za-z0-9]+)/) {
                $hostname = $1;
                $self->{SITEDB}->addHost($hostname) if ($self->{ADD_HOSTS});
                $self->{SITEDB}->addService($hostname, "Central-LFC");

                foreach my $attr ($entry->get_value('GlueServiceAccessControlRule')) {
                    my $voname = lc($attr);
                    $self->{SITEDB}->addVO($hostname, "Central-LFC", $voname);
                }
            }
        }
    }

    if ($self->{VO_FILTER}) {
        $filter = "(&(&(objectClass=GlueService)(GlueServiceType=lcg-local-file-catalog))(GlueServiceAccessControlRule=".$self->{VO_FILTER}."))";
    } else {
        $filter = "(&(objectClass=GlueService)(GlueServiceType=lcg-local-file-catalog))";
    }
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => $filter,
                            attrs=> ['GlueServiceEndpoint','GlueServiceAccessControlRule'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch LFC info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /([-_.A-Za-z0-9]+)/) {
                $hostname = $1;
                $self->{SITEDB}->addHost($hostname) if ($self->{ADD_HOSTS});
                $self->{SITEDB}->addService($hostname, "Local-LFC");

                foreach my $attr ($entry->get_value('GlueServiceAccessControlRule')) {
                    my $voname = lc($attr);
                    $self->{SITEDB}->addVO($hostname, "Local-LFC", $voname);
                }
            }
        }
    }

    # Get VOMS information
    if ($self->{VO_FILTER}) {
        $filter = "(&(&(objectClass=GlueService)(GlueServiceType=org.glite.voms-admin))(GlueServiceAccessControlRule=".$self->{VO_FILTER}."))";
    } else {
        $filter = "(&(objectClass=GlueService)(GlueServiceType=org.glite.voms-admin))";
    }
    $mesg = $ldap->search ( base => $self->{LDAP_BASEDN},
                            filter => $filter,
                            attrs=> ['GlueServiceEndpoint','GlueServiceAccessControlRule'],
                            timelimit => 60 );
    if ($mesg->code) {
        $self->error("Could not fetch PROX info from LDAP: ".$mesg->error);
    } else {
        foreach $entry ($mesg->entries()) {
            if ($entry->get_value('GlueServiceEndpoint') && $entry->get_value('GlueServiceEndpoint') =~ /^https:\/\/([-_.A-Za-z0-9]+):(\d+)/) {
                $hostname = $1;
                $self->{SITEDB}->addHost($hostname) if ($self->{ADD_HOSTS});
                $self->{SITEDB}->addService($hostname, "VOMS");
                
                foreach my $attr ($entry->get_value('GlueServiceAccessControlRule')) {
                    my $voname = lc($attr);
                    $self->{SITEDB}->addVO($hostname, "VOMS", $voname);
                }
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

sub addHosts {
    my $self = shift;
    my $value = shift;
    $self->{ADD_HOSTS} = $value if (defined $value);
    $self->{ADD_HOSTS};
}

sub bdiiLevel {
    my $self = shift;
    my $value = shift;
    $self->{BDII_LEVEL} = $value if (defined $value);
    $self->{BDII_LEVEL};
}

=head1 NAME

NCG::SiteInfo::LDAP

=head1 DESCRIPTION

The NCG::SiteInfo::LDAP module extends NCG::SiteInfo module. Module
extracts site information from LDAP-based information services (e.g.
BDII, Globus MDS).

=head1 SYNOPSIS

  use NCG::SiteInfo::LDAP;

  my $siteInfo = NCG::SiteInfo::LDAP->new({LDAP_ADDRESS=>'ldap.server.com', 
                                           LDAP_PORT=>2170, 
                                           LDAP_BASEDN=>'O=Grid'});

  $siteInfo->getData();

=cut

=head1 METHODS

=over

=item C<new>

  my $siteInfo = NCG::SiteInfo::LDAP->new($options); 

Creates new NCG::SiteInfo::LDAP instance. Argument $options is hash reference that
can contains following elements:
  LDAP_ADDRESS - address of LDAP server (default: localhost)
  LDAP_PORT - port of LDAP server (default: 2170)
  LDAP_BASEDN - basedn used when querying LDAP server
  ADD_HOSTS - if true hosts found in LDAP will be added, otherwise only service on existing hosts are added (default: true)
  BDII_LEVEL - which BDII level is queried, this option will
               define default base DN value
               possible values: site, top
  (default: site)
  LDAP_CONNECT_TIMEOUT - timeout for binding to LDAP server
  (default: 10)  
  VO_FILTER - if set module will only get info for hosts which support given VO

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

=item C<addHosts>

  print $siteInfo->addHosts;
  $siteInfo->addHosts(0);

Accessor method for property ADD_HOSTS.

=back

=head1 SEE ALSO

NCG::SiteInfo

=cut

1;
