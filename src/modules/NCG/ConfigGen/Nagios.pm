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

package NCG::ConfigGen::Nagios;

use strict;
use NCG::ConfigGen;
use Socket;
use Date::Format;
use Archive::Tar;
use File::Path;

use vars qw(@ISA);

@ISA=("NCG::ConfigGen");

my $DEFAULT_TEMPLATES_DIR = '/usr/share/argo-ncg/templates';
my $DEFAULT_OUTPUT_DIR = '/etc/nagios/argo-ncg.d';
my $DEFAULT_NRPE_OUTPUT_DIR = '/etc/nagios';

my $DEFAULT_WLCG_PLUGINS_DIR = '/usr/libexec/grid-monitoring/plugins/nagios';
my $DEFAULT_WLCG_PROBES_DIR = '/usr/libexec/grid-monitoring/probes';
my $DEFAULT_PROXY_FILE = '/etc/nagios/globus/userproxy.pem';
my $DEFAULT_MYPROXY_NAME = 'NagiosRetrieve';
my $DEFAULT_MYPROXY_USER = 'nagios';
my $DEFAULT_NAGIOS_USER = 'nagios';
my $DEFAULT_VO = 'dteam';
my $DEFAULT_NOTIFICATION_HEADER = 'SAM Nagios';

my $PNP_ACTION_URL = '/nagios/html/pnp4nagios/index.php?host=$HOSTNAME$&srv=$SERVICEDESC$';

my $DEFAULT_CHECK_PING = 1;
my $DEFAULT_ENABLE_FLAP_DETECTION = 0;
my $DEFAULT_VO_HOST_FILTER = 1;

my $CONFIGURATION_TEMPLATES =
   {
       CONTACTS                 => 'contacts.template',
       HOST_TEMPLATES           => 'hosts.template',
       SERVICE_TEMPLATES        => 'services.template',
       COMMANDS                 => 'commands.template',
       CONTACTS_CONTACT         => 'contacts/contact.template',
       CONTACTS_CONTACTGROUP    => 'contacts/contactgroup.template',
       HOSTS_HOST               => 'hosts/host.template',
       HOSTS_HOSTGROUP          => 'hosts/hostgroup.template',
       SERVICES_SERVICEGROUP    => 'services/servicegroup.template',
       SERVICES_SERVICEDEP      => 'services/servicedependency.template',
       SERVICES_NATIVE          => 'services/native.template',
       SERVICES_WLCGNRPE        => 'services/wlcg.nrpe.template',
       SERVICES_WLCGPASSIVE     => 'services/wlcg.passive.template',
       SERVICES_NAGIOS          => 'services/nagios.template',
       NRPE_NRPE                => 'wlcg.nagios/nrpe.template',
       NRPE_NATIVECOMMANDS      => 'wlcg.nrpe/native.commands.template',
   };

my $CONFIGURATION_OUTPUT =
   {
       USERS                    => 'users.cfg',
       CONTACTS                 => 'contacts.cfg',
       HOST_TEMPLATES           => 'host.templates.cfg',
       HOST_GROUPS              => 'host.groups.cfg',
       HOSTS                    => 'hosts.cfg',
       SERVICE_GROUPS           => 'service.groups.cfg',
       SERVICE_TEMPLATES        => 'service.templates.cfg',
       SERVICES                 => 'services.cfg',
       COMMANDS                 => 'commands.cfg',
   };

my $NRPE_CONFIGURATION_OUTPUT =
   {
       NRPE                     => 'services.nrpe.cfg',
       NRPE_ADMIN               => 'wlcg.nrpe.cfg'
   };

sub new
{
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);

    # set default values
    $self->{TEMPLATES_DIR} = $DEFAULT_TEMPLATES_DIR 
        unless (defined $self->{TEMPLATES_DIR});
    $self->{OUTPUT_DIR} = $DEFAULT_OUTPUT_DIR
        unless (defined $self->{OUTPUT_DIR});
    $self->{FINAL_OUTPUT_DIR} = $self->{OUTPUT_DIR}
        unless (defined $self->{FINAL_OUTPUT_DIR});
    $self->{NRPE_OUTPUT_DIR} = $DEFAULT_NRPE_OUTPUT_DIR
        unless (defined $self->{NRPE_OUTPUT_DIR});
    $self->{GLITE_VERSION} = "UNKNOWN"
        unless (defined $self->{GLITE_VERSION});
    $self->{NAGIOS_ROLE} = 'site'
        unless (defined $self->{NAGIOS_ROLE});
    $self->{INCLUDE_HOSTS} = 1
        unless (defined $self->{INCLUDE_HOSTS});
    $self->{INCLUDE_EMPTY_HOSTS} = 1
        unless (defined $self->{INCLUDE_EMPTY_HOSTS});
    $self->{WLCG_PLUGINS_DIR} = $DEFAULT_WLCG_PLUGINS_DIR
        unless (defined $self->{WLCG_PLUGINS_DIR});
    $self->{WLCG_PROBES_DIR} = $DEFAULT_WLCG_PROBES_DIR
        unless (defined $self->{WLCG_PROBES_DIR});
    $self->{CHECK_HOSTS} = 1
        unless (defined $self->{CHECK_HOSTS});
    $self->{NOTIFICATION_HEADER} = $DEFAULT_NOTIFICATION_HEADER
        unless (defined $self->{NOTIFICATION_HEADER});
    $self->{ENABLE_NOTIFICATIONS} = 0
        if (!defined $self->{ENABLE_NOTIFICATIONS} && ! defined $self->{SEND_TO_EMAIL});
    $self->{ENABLE_FLAP_DETECTION} = $DEFAULT_ENABLE_FLAP_DETECTION
        unless (defined $self->{ENABLE_FLAP_DETECTION});
    $self->{LOCAL_METRIC_STORE} = 0
        unless (defined $self->{LOCAL_METRIC_STORE});
    $self->{SEND_TO_MSG} = 1
        unless (defined $self->{SEND_TO_MSG});
    $self->{HOST_NOTIFICATIONS_OPTIONS} = "d,r"
        unless (defined $self->{HOST_NOTIFICATIONS_OPTIONS});
    $self->{SERVICE_NOTIFICATIONS_OPTIONS} = "w,u,c,r"
        unless (defined $self->{SERVICE_NOTIFICATIONS_OPTIONS});
    $self->{VO_HOST_FILTER} = $DEFAULT_VO_HOST_FILTER
        unless (defined $self->{VO_HOST_FILTER});

    if ($self->{MULTI_SITE_GLOBAL}) {
        if (! defined $self->{MULTI_SITE_SITES}) {
            undef $self;
            return;
        }
    }

    if ($self->{MULTI_SITE_SITE}) {
        if (! defined $self->{SITEDB} ) {
            undef $self;
            return;
        }
        my $sitename = $self->{SITEDB}->siteName();
        if ($sitename) {
            $self->{OUTPUT_DIR} .= "/$sitename";
            $self->{FINAL_OUTPUT_DIR} .= "/$sitename";
            #$self->{NRPE_OUTPUT_DIR} .= "/$sitename";
        }
    }

    if (! defined $self->{MULTI_SITE_HOSTS}) {
        $self->{MULTI_SITE_HOSTS} = {};
    }

    unless (defined $self->{INCLUDE_LB_NODE}) {
        $self->{INCLUDE_LB_NODE} = 0;
    }

    if (! $self->_checkProbesType) {
        undef $self;
        return;
    }

    $self->_checkVo();
    $self->_checkProxyFile();

    if ($self->{USE_ROBOT_CERT}) {
        $self->_checkRobotCredentials();
    } else {
        $self->_checkMyProxyUser();
        $self->_checkMyProxyName();
    }
    $self->{PNP_ACTION_URL} = "https://".$self->{NAGIOS_SERVER}.$PNP_ACTION_URL;

    if (! $self->_checkFiles ) {
        undef $self;
        return;
    }

    if ($self->{BACKUP_INSTANCE}) {
        $self->{SEND_TO_MSG} = 0;
        $self->{ENABLE_NOTIFICATIONS} = 0;
        $self->{SEND_TO_DASHBOARD} = 0;
    }

    $self;
}                            

#############################
##
##  Constructor helpers
##
#############################

sub _checkProbesType {
    my $self = shift;

    if (! defined $self->{PROBES_TYPE}) {
        $self->{PROBES_TYPE} = 'all';
    } else {
        foreach my $pt (split (/,/, $self->{PROBES_TYPE})) {
            if ($pt eq 'all') {
                $self->{PROBES_TYPE} = 'all';
                last;
            } elsif (   $pt eq 'remote' ||
                        $pt eq 'local')
            {
                $self->{PROBES_TYPE_FLAG}->{$pt} = 1;
            } elsif ($pt eq 'native') {
                $self->{PROBES_TYPE_FLAG}->{local} = 1;
            } else {
                $self->error("Incorrect PROBES_TYPE value. Parameter PROBES_TYPE can be: all, local or remote.");
                return;
            }
        }
    }

    if ($self->{PROBES_TYPE} eq 'all') {
        $self->{PROBES_TYPE_FLAG}->{local} = 1;
        $self->{PROBES_TYPE_FLAG}->{remote} = 1;
    }

    return 1;
}

sub _checkDirectoryFiles {
    my $self = shift;
    my $dir = shift;
    my $confHash = shift;
    my $confName = shift;

    if ( ! -d $dir ) {
        $self->debug("Output directory $dir does not exist. Creating output directory ...");
        my $res = `/bin/mkdir -p $dir 2>&1`;
        if ($?) {
            $self->error("Error creating directory $dir: $res.");
            return;
        }
    }
    foreach my $output (keys %$confHash) {
        $self->{$confName}->{$output} = $dir . "/" . $confHash->{$output};
    }
}

# if hostname is not set, generate config for NRPE_UI
sub _checkNRPEDirectoryFiles {
    my $self = shift;
    my $hostname = shift;
    my $dir = $self->{NRPE_OUTPUT_DIR};

    if (!$hostname || $hostname eq $self->{NRPE_UI}) {
        $hostname = $self->{NRPE_UI};
        $dir .= "/$hostname";
        if ($self->{MULTI_SITE_SITE}) {
            my $sitename = $self->{SITEDB}->siteName();
            if ($sitename) {
                $dir .= "/$sitename";
            }
        }
    } else {
        $dir .= "/$hostname";
    }
    if ( ! -d $dir ) {
        $self->warning("Output directory $dir does not exist. Creating output directory ...");
        my $res = `/bin/mkdir -p $dir 2>&1`;
        if ($?) {
            $self->error("Error creating directory $dir: $res.");
            return;
        }
    }
    foreach my $output (keys %$NRPE_CONFIGURATION_OUTPUT) {
        $self->{NRPE_CONFIGURATION_OUTPUT}->{$hostname}->{$output} = $dir . "/" . $NRPE_CONFIGURATION_OUTPUT->{$output};
    }
}

sub _checkFiles {
    my $self = shift;

    if ( ! -d $self->{TEMPLATES_DIR} ) {
        $self->error("Templates directory ". $self->{TEMPLATES_DIR} ." does not exist.");
        return;
    }

    foreach my $config (keys %$CONFIGURATION_TEMPLATES) {
        $self->{CONFIGURATION_TEMPLATES}->{$config} = $self->{TEMPLATES_DIR} . "/" . $CONFIGURATION_TEMPLATES->{$config};
        if (! -f $self->{CONFIGURATION_TEMPLATES}->{$config}) {
            $self->error("Template ". $self->{CONFIGURATION_TEMPLATES}->{$config} ." does not exist.");
            return;
        }

        if (! -r $self->{CONFIGURATION_TEMPLATES}->{$config}) {
            $self->error("Template ". $self->{CONFIGURATION_TEMPLATES}->{$config} ." is not readable.");
            return;
        }
    }

    $self->_checkDirectoryFiles($self->{OUTPUT_DIR}, $CONFIGURATION_OUTPUT, "CONFIGURATION_OUTPUT");

    1;
}

sub _getVoFqanTidy {
    my $voFqanTidy = shift;
    $voFqanTidy =~ s/\//\-/g;
    $voFqanTidy =~ s/=/_/g;
    return $voFqanTidy;
}

sub _checkSiteVoFqans {
    my $self = shift;
    my $site = shift;

    foreach my $vo (keys %{$self->{VOS}}) { 
        foreach my $voFqan ($site->getVoFqans($vo)) {
            if (!exists $self->{VOS}->{$vo}->{FQAN}->{$voFqan}) {
                $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{FAKE_FQAN} = 1 if ( $voFqan eq $vo );
                $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{VO_FQAN_TIDY} = _getVoFqanTidy($voFqan);
                $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{DEFAULT_FQAN} = 0;
            }
        }
    }
}

# checks if VO is defined and loads VOS hash
sub _checkVo {
    my $self = shift;

    if (! defined $self->{VO}) {
        $self->{VO} = $DEFAULT_VO;
    }
    $self->{VO} =~ s/^\s+//;
	$self->{VO} =~ s/\s+$//;
    foreach my $vo ( split (/\s*,\s*/, $self->{VO}) ) {
        $self->{VOS}->{$vo} = {};
    }

    foreach my $vo (keys %{$self->{VOS}}) {
        my $attrName = "VO_".uc($vo)."_DEFAULT_VO_FQAN";
        # if we have FQANs create them
        if (defined $self->{$attrName}) {
            foreach my $voFqan ( split (/\s*,\s*/, $self->{$attrName}) ) {
                $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{FAKE_FQAN} = 1 if ( $voFqan eq $vo );
                $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{VO_FQAN_TIDY} = _getVoFqanTidy($voFqan);
                $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{DEFAULT_FQAN} = 1;
            }
        }
        # otherwise create fake fqan entry for vo
        # this makes later processing easier
        else {
            $self->{VOS}->{$vo}->{FQAN}->{$vo} = { FAKE_FQAN => 1, VO_FQAN_TIDY => $vo, DEFAULT_FQAN => 1 };
        }
    }
    
    if ($self->{MULTI_SITE_GLOBAL}) {
        foreach my $site (values %{$self->{MULTI_SITE_SITES}}) {
            $self->_checkSiteVoFqans($site->{SITEDB});
        }
    } else {
        $self->_checkSiteVoFqans($self->{SITEDB});
    }
}

sub _setVoAttributes {
    my $self = shift;
    my $attribute = shift;
    my $default = shift || '';
    my $defaultHash = {};

    foreach my $vo (keys %{$self->{VOS}}) {
        foreach my $voFqan (keys %{$self->{VOS}->{$vo}->{FQAN}}) {
            my $fqanHash = $self->{VOS}->{$vo}->{FQAN}->{$voFqan};
            my $attributeNameVo = $attribute . "_" . uc($vo);
            my $attributeNameVoFqan = $attribute . "_" . uc($fqanHash->{VO_FQAN_TIDY});

            $defaultHash->{VO} = $vo;
            $defaultHash->{VO_FQAN} = $fqanHash->{VO_FQAN_TIDY};
            if (defined $self->{$attributeNameVoFqan}) {
                $fqanHash->{$attribute} = $self->{$attributeNameVoFqan};
            } elsif (defined $self->{$attributeNameVo}) {
                $fqanHash->{$attribute} = $self->{$attributeNameVo};
            } else {
                $fqanHash->{$attribute} = $self->{$attribute};
                $fqanHash->{$attribute} = $fqanHash->{$attribute} . '-' .
                    $defaultHash->{$default}
                    if ($defaultHash->{$default});
            }
        }
    }
}

# default value:
#  $DEFAULT_MYPROXY_USER

sub _checkMyProxyUser {
    my $self = shift;

    if (! defined $self->{MYPROXY_USER}) {
        $self->{MYPROXY_USER} = $DEFAULT_MYPROXY_USER;
    }
    $self->_setVoAttributes('MYPROXY_USER');
}

# default value:
#  $DEFAULT_PROXY_FILE-VO_FQAN

sub _checkProxyFile {
    my $self = shift;

    if (! defined $self->{PROXY_FILE}) {
        $self->{PROXY_FILE} = $DEFAULT_PROXY_FILE;
    }
    $self->_setVoAttributes('PROXY_FILE','VO_FQAN');
}

# default value:
#  $DEFAULT_MYPROXY_NAME-($self->{NRPE_UI}|$self->{NAGIOS_SERVER})-VO

sub _checkMyProxyName {
    my $self = shift;

    if (! defined $self->{MYPROXY_NAME}) {
        $self->{MYPROXY_NAME} = $DEFAULT_MYPROXY_NAME;
        # if NRPE is used, set default name to NRPE hostname
        if ($self->{NRPE_UI}) {
            $self->{MYPROXY_NAME} .= "-" . $self->{NRPE_UI};
        } else {
            $self->{MYPROXY_NAME} .= "-" . $self->{NAGIOS_SERVER};
        }
    }

    $self->_setVoAttributes('MYPROXY_NAME','VO');
}

sub _checkRobotCredentials {
    my $self = shift;

    $self->_setVoAttributes('ROBOT_CERT');
    $self->_setVoAttributes('ROBOT_KEY');
}

#############################
##
##  Commands (commands.cfg)
##
#############################

sub _genCommands {
	my $self = shift;
    my $CONFIG;
    my $TEMPL;
    my $line;

    if (!open ($CONFIG, ">" . $self->{CONFIGURATION_OUTPUT}->{COMMANDS})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_OUTPUT}->{COMMANDS}."!");
        return;
    }

    print $CONFIG $self->{OUTPUT_HEADER};

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{COMMANDS})) {
        $self->error("Cannot open template file ".$self->{CONFIGURATION_TEMPLATES}->{COMMANDS}."!");
        close ($CONFIG);
        return;
    }

    my $sendToDashboard='';
    my $ggusServerFqdn='';

    if ($self->{GGUS_SERVER_FQDN}) {
        $ggusServerFqdn = "--ggus-server $self->{GGUS_SERVER_FQDN}";
    }
    if ($self->{SEND_TO_DASHBOARD}) {
        $sendToDashboard = "--send-to-dashboard";
    }

    while ($line = <$TEMPL>){
        $line =~ s/<WLCG_PLUGINS_DIR>/$self->{WLCG_PLUGINS_DIR}/g;
        $line =~ s/<WLCG_PROBES_DIR>/$self->{WLCG_PROBES_DIR}/g;
        $line =~ s/<NAGIOS_ROLE>/$self->{NAGIOS_ROLE}/g;
        $line =~ s/<NOTIFICATION_HEADER>/$self->{NOTIFICATION_HEADER}/g;
        $line =~ s/<NAGIOS_SERVER>/$self->{NAGIOS_SERVER}/g;
        $line =~ s/<LOCAL_METRIC_STORE>/$self->{LOCAL_METRIC_STORE}/g;
        $line =~ s/<SEND_TO_DASHBOARD>/$sendToDashboard/g;
        $line =~ s/<GGUS_SERVER_FQDN>/$ggusServerFqdn/g;
        $line =~ s/<SEND_TO_MSG>/$self->{SEND_TO_MSG}/g;
        print $CONFIG $line;
    }

    close ($TEMPL);
    close ($CONFIG);

    1;
}

#############################
##
##  Contacts (contacts.cfg)
##
#############################

sub _genAdminContact {
    my $self = shift;
    my $CONFIG;
    my $TEMPL;
    my $line;

    if (!open ($CONFIG, ">" . $self->{CONFIGURATION_OUTPUT}->{CONTACTS})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_OUTPUT}->{CONTACTS}."!");
        return;
    }

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{CONTACTS})) {
        $self->error("Cannot open template file ".$self->{CONFIGURATION_TEMPLATES}->{CONTACTS}."!");
        close ($CONFIG);
        return;
    }

    $line = join ("", <$TEMPL>);
    close ($TEMPL);
    print $CONFIG $line;

    close ($CONFIG);

    1;
}

sub _genContactGroup {
    my $self = shift;
    my $CONFIG = shift;
    my $group = shift;
    my $TEMPL;
    my $line;

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{CONTACTS_CONTACTGROUP})) {
        $self->error("Cannot open template file ".$self->{CONFIGURATION_TEMPLATES}->{CONTACTS_CONTACTGROUP}."!");
        return;
    }
    $line = join ("", <$TEMPL>);
    close ($TEMPL);
    $line =~ s/<groupname>/$group/mg;
    print $CONFIG $line;

    1;
}

sub _genContact {
    my $self = shift;
    my $CONFIG = shift;
    my $contact = shift;
    my $email = shift;
    my $group = shift;
    my $enabled = shift;
    my $TEMPL;
    my $line;
    my ($hostNotify, $serviceNotify);

    if ($self->{ENABLE_NOTIFICATIONS}) {
        $hostNotify = $self->{HOST_NOTIFICATIONS_OPTIONS};
        $serviceNotify = $self->{SERVICE_NOTIFICATIONS_OPTIONS};
    } else {
        if ($enabled) {
            $hostNotify = $self->{HOST_NOTIFICATIONS_OPTIONS};
            $serviceNotify = $self->{SERVICE_NOTIFICATIONS_OPTIONS};
        } else {
            $hostNotify = "n";
            $serviceNotify = "n";
        }
    }

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{CONTACTS_CONTACT})) {
        $self->error("Cannot open template file ".$self->{CONFIGURATION_TEMPLATES}->{CONTACTS_CONTACT}."!");
        return;
    }
    $line = join ("", <$TEMPL>);
    close ($TEMPL);
    $line =~ s/<contactemail>/$email/mg;
    $line =~ s/<contactname>/$contact/mg;
    $line =~ s/<contactrealname>/$email administrator/mg;
    $line =~ s/<contactgroup>/$group/mg;
    $line =~ s/<servicenotify>/$serviceNotify/mg;
    $line =~ s/<hostnotify>/$hostNotify/mg;
    print $CONFIG $line;

    1;
}

sub _genContacts {
	my $self = shift;
	# my $vo = shift;
    my $CONFIG;
    my $TEMPL;
    my $line;
    my $contact;
    my $group;
    my $contacts;
    my $sitename = $self->{SITEDB}->siteName();

    if (!open ($CONFIG, ">" . $self->{CONFIGURATION_OUTPUT}->{CONTACTS})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_OUTPUT}->{CONTACTS}."!");
        return;
    }

    print $CONFIG $self->{OUTPUT_HEADER};

    # generate site level contact group
    $group = "$sitename-site";
    if (!$self->_genContactGroup($CONFIG, $group)) {
        close ($CONFIG);
        return;
    }

    my $check;
    foreach $contact ($self->{SITEDB}->getContacts)
    {
        if (!$self->_genContact($CONFIG, "$sitename-$contact", $contact, $group, $self->{SITEDB}->isContactEnabled($contact))) {
            close ($CONFIG);
            return;
        }
        $check = 1;
    }
    if (!$check) {
        $contact = 'root@localhost';
        if (!$self->_genContact($CONFIG, "$sitename-$contact", $contact, $group)) {
            close ($CONFIG);
            return;
        }
    }

    # generate host level contact group
    foreach my $host ($self->{SITEDB}->getHosts) {
        next if ($self->{VO_HOST_FILTER} && !$self->_hostHasAnyVO($host));
        if ( $self->{SITEDB}->hasContacts($host) ) {
            $group = "$sitename-$host";
            if (!$self->_genContactGroup($CONFIG, $group)) {
                close ($CONFIG);
                return;
            }

            foreach $contact ($self->{SITEDB}->getHostContacts($host)) {
                if (!exists $contacts->{$contact}) {
                    $contacts->{$contact}->{group} = $group;
                    $contacts->{$contact}->{enabled} = $self->{SITEDB}->isHostContactEnabled($host, $contact);
                } else {
                    $contacts->{$contact}->{group} .= ",$group";
                    $contacts->{$contact}->{enabled} ||= $self->{SITEDB}->isHostContactEnabled($host, $contact);
                }
            }
        }
    }

    foreach my $host ($self->{SITEDB}->getHosts) {
        next if ($self->{VO_HOST_FILTER} && !$self->_hostHasAnyVO($host));
        foreach my $service ( $self->{SITEDB}->getServiceContactsServices($host) ) {
            $group = "$sitename-$host-$service";
            if (!$self->_genContactGroup($CONFIG, $group)) {
                close ($CONFIG);
                return;
            }
            foreach $contact ($self->{SITEDB}->getServiceContacts($host, $service) ) {
                if (!exists $contacts->{$contact}) {
                    $contacts->{$contact}->{group} = $group;
                } else {
                    $contacts->{$contact}->{group} .= ",$group";
                }
            }
        }
        foreach my $service ( $self->{SITEDB}->getServiceFlavourContactsServiceFlavours($host) ) {
            $group = "$sitename-$host-flavour-$service";
            if (!$self->_genContactGroup($CONFIG, $group)) {
                close ($CONFIG);
                return;
            }
            foreach $contact ($self->{SITEDB}->getServiceFlavourContacts($host, $service) ) {
                if (!exists $contacts->{$contact}) {
                    $contacts->{$contact}->{group} = $group;
                    $contacts->{$contact}->{enabled} = $self->{SITEDB}->isServiceFlavourContactEnabled($host, $service, $contact);
                } else {
                    $contacts->{$contact}->{group} .= ",$group";
                    $contacts->{$contact}->{enabled} ||= $self->{SITEDB}->isServiceFlavourContactEnabled($host, $service, $contact);
                }
            }
        }
    }

    # generate all contacts
    foreach $contact (keys %$contacts) {
        if (!$self->_genContact($CONFIG, "$sitename-$contact", $contact, $contacts->{$contact}->{group}, $contacts->{$contact}->{enabled})) {
            close ($CONFIG);
            return;
        }
    }

    close ($CONFIG);

    1;
}

#############################
##
##  USERS
##
#############################

sub _fillUsers {
	my $self = shift;
	my $users = shift;
	my $sitename;

    if ($self->{MULTI_SITE_GLOBAL} && $self->{MULTI_SITE_SITES}) {
        foreach my $site (values %{$self->{MULTI_SITE_SITES}}) {
            $sitename = $site->{SITEDB}->siteName();
            foreach my $contact ($site->{SITEDB}->getUsers) {
                $users->{$contact} = {
                    EMAIL => $site->{SITEDB}->userEmail($contact),
                    NAME => $site->{SITEDB}->userName($contact),
                    } unless (exists $users->{$contact});
                $users->{$contact}->{GROUPS}->{"$sitename-site"} = 1;
            }
        }
    } else {
        $sitename = $self->{SITEDB}->siteName();
        foreach my $contact ($self->{SITEDB}->getUsers) {
            $users->{$contact} = {
                EMAIL => $self->{SITEDB}->userEmail($contact),
                NAME => $self->{SITEDB}->userName($contact),
                };
            $users->{$contact}->{GROUPS}->{"$sitename-site"} = 1;
        }
    }

    1;
}

sub _genUsers {
	my $self = shift;
	my $users = {};
    my $CONFIG;
    my $TEMPL;
    my $line;
    my $contact;

    $self->_fillUsers($users);

    if (!open ($CONFIG, ">" . $self->{CONFIGURATION_OUTPUT}->{USERS})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_OUTPUT}->{USERS}."!");
        return;
    }

    print $CONFIG $self->{OUTPUT_HEADER};

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{CONTACTS_CONTACT})) {
        $self->error("Cannot open template file ".$self->{CONFIGURATION_TEMPLATES}->{CONTACTS_CONTACT}."!");
        return;
    }
    $line = join ("", <$TEMPL>);
    close ($TEMPL);
    
    foreach $contact (keys %$users)
    {
        my $groups = join (',', keys %{$users->{$contact}->{GROUPS}});
        my $tmpLine = $line;
        $tmpLine =~ s/<contactemail>/$users->{$contact}->{EMAIL}/mg;
        $tmpLine =~ s/<contactname>/$contact/mg;
        $tmpLine =~ s/<contactrealname>/$users->{$contact}->{NAME}/mg;
        $tmpLine =~ s/<contactgroup>/$groups/mg;
        $tmpLine =~ s/<servicenotify>/n/mg;
        $tmpLine =~ s/<hostnotify>/n/mg;
        print $CONFIG $tmpLine;
    }

    close ($CONFIG);

    1;
}

#############################
##
##  NRPE (wlcg_nrpe.cfg)
##    - configuration file for NRPE UI
##
#############################

sub _genNrpe {
	my $self = shift;
    my $CONFIG = shift;
    my $host = shift || $self->{NRPE_UI};
    my $TEMPL;
    my $line;

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{NRPE_NRPE})) {
        $self->error("Cannot open template file ".$self->{CONFIGURATION_TEMPLATES}->{NRPE_NRPE}."!");
        return;
    }

    $line = join ("", <$TEMPL>);
    close ($TEMPL);
    $line =~ s/<NRPE_UI>/$host/mg;
    print $CONFIG $line;

    1;
}

sub _genNrpeHeader {
    my $self = shift;
    my $hostname = shift || $self->{NRPE_UI};
    my $CONFIG;
    my $line;

    $self->_checkNRPEDirectoryFiles($hostname);

    if (!open ($CONFIG, ">" . $self->{NRPE_CONFIGURATION_OUTPUT}->{$hostname}->{NRPE})) {
        $self->error("Cannot open configuration file ".$self->{NRPE_CONFIGURATION_OUTPUT}->{$hostname}->{NRPE}."!");
        return;
    }

    print $CONFIG $self->{OUTPUT_HEADER};

    return $CONFIG;
}

# Pack NRPE stuff
sub _packNrpeFiles {
    my $self = shift;
    my $dir = shift;
    my $hosts = {};
    chdir $self->{NRPE_OUTPUT_DIR};

    foreach my $site (values %{$self->{MULTI_SITE_SITES}}) {
    foreach my $hostname (keys %{$site->{NRPE_CONFIGURATION_OUTPUT}}) {
        next if (exists $hosts->{$hostname});
        $hosts->{$hostname} = 1;
        chdir $self->{NRPE_OUTPUT_DIR}."/".$hostname;
        my $filelist = [];
        my $tar = Archive::Tar->new;
        $self->_addRecurseDirs($filelist, ".");
        if (!$tar->add_files(@$filelist)) {
            $self->error("Error adding list of files to NRPE tarball: ".$tar->error);
            return;
        }
        if (!$tar->write($self->{NRPE_OUTPUT_DIR}."/".$hostname.'.tgz', "COMPRESS_GZIP")) {
            $self->error("Error creating NRPE tarball: ".$tar->error);
            return;
        }
        rmtree($self->{NRPE_OUTPUT_DIR}."/".$hostname);
    }
    }

    1;
}

#############################
##
##  Hosts (hosts.cfg)
##
#############################

sub _genHostTemplates {
	my $self = shift;
    my $CONFIG;
    my $TEMPL;
    my $line;

    if (!open ($CONFIG, ">" . $self->{CONFIGURATION_OUTPUT}->{HOST_TEMPLATES})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_OUTPUT}->{HOST_TEMPLATES}."!");
        return;
    }

    print $CONFIG $self->{OUTPUT_HEADER};

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{HOST_TEMPLATES})) {
        $self->error("Cannot open template file ".$self->{CONFIGURATION_TEMPLATES}->{HOST_TEMPLATES}."!");
        close ($CONFIG);
        return;
    }
    $line = join ("", <$TEMPL>);
    close ($TEMPL);
    print $CONFIG $line;

    close $CONFIG;

    1;
}

sub _getHostCheckType {
	my $self = shift;
	my $hostname = shift || return;
	my $checkType;

    if ( $self->{CHECK_HOSTS} ) {
        $checkType = "ncg_check_host_alive";
    } else {
        $checkType = "ncg_check_host_dummy";
    }

	return $checkType;
}

sub _getLBHostCheckType {
	my $self = shift;
	my $hostname = shift || return;
	my $lbaddress = shift || return;
	my $checkType;

    if ( $self->{CHECK_HOSTS} ) {
        $checkType = "ncg_check_host_alive";
    } else {
        $checkType = "ncg_check_host_dummy";
    }

	return $checkType;
}

sub _genHostGroup {
    my $self = shift;
    my $CONFIG = shift;
    my $name = shift;
    my $fullname = shift;
    my $members = shift;
    my $memberStr = "";
    my $TEMPL;
    my $line;

    if (! $self->{INCLUDE_HOSTS}) {
        $memberStr = join(',', keys %$members);
        $memberStr = "members $memberStr\n";
    }

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{HOSTS_HOSTGROUP})) {
        $self->error("Cannot open template file ".$self->{CONFIGURATION_TEMPLATES}->{HOSTS_HOSTGROUP}."!");
        return;
    }
    $line = join ("", <$TEMPL>);
    close ($TEMPL);
    $line =~ s/<name>/$name/mg;
    $line =~ s/<fullname>/$fullname/mg;
    $line =~ s/<members>/$memberStr/mg;
    print $CONFIG $line;
    1;
}

sub _genHostGroups {
    my $self = shift;
    my $hostgroups = shift;
    my $CONFIG;

    if (!open ($CONFIG, ">" . $self->{CONFIGURATION_OUTPUT}->{HOST_GROUPS})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_OUTPUT}->{HOST_GROUPS}."!");
        return;
    }

    print $CONFIG $self->{OUTPUT_HEADER};

    foreach my $group (keys %$hostgroups) {
        if (! $self->_genHostGroup ($CONFIG, $group, $hostgroups->{$group}->{fullname}, $hostgroups->{$group}->{members}) ) {
            close ($CONFIG);
            return;
        }
    }

    close $CONFIG;

    1;
}

# ($hostname, $address, $checkType, $contactList, $hostgroup, $alias);
sub _genHost {
    my $self = shift;
    my $CONFIG = shift;
    my $hostname = shift;
    my $address = shift;
    my $checkType = shift;
    my $contactList = shift;
    my $hostgroup = shift;
    my $alias = shift;
    my $parent = shift;
    my $parentStr = "";
    my $TEMPL;
    my $line;

    my $customVarsStr = "_site_name                      ".$self->{SITEDB}->siteName();

    if ($hostgroup) {
        $hostgroup = "hostgroups                      $hostgroup";
    }

    if ($parent) {
        $parentStr = "parents                  $parent\n";
    }

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{HOSTS_HOST})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_TEMPLATES}->{HOSTS_HOST}."!");
        return;
    }
    $line = join ("", <$TEMPL>);
    close ($TEMPL);
    $line =~ s/<alias>/$alias/mg;
    $line =~ s/<parent>/$parentStr/mg;
    $line =~ s/<hostgroup>/$hostgroup/mg;
    $line =~ s/<hostname>/$hostname/mg;
    $line =~ s/<address>/$address/mg;
    $line =~ s/<checktype>/$checkType/mg;
    $line =~ s/<contactlist>/$contactList/mg;
    $line =~ s/<customVars>/$customVarsStr/mg;
    print $CONFIG $line;

    1;
}

sub _genHostsHeader {
	my $self = shift;
    my $CONFIG;
    my $TEMPL;
    my $line;
    my $hosts = {};

    if (!open ($CONFIG, ">" . $self->{CONFIGURATION_OUTPUT}->{HOSTS})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_OUTPUT}->{HOSTS}."!");
        return;
    }

    print $CONFIG $self->{OUTPUT_HEADER};

    return $CONFIG;
}

#############################
##
##  Services (service.cfg)
##
#############################

sub _genServiceTemplates {
	my $self = shift;
    my $CONFIG;
    my $TEMPL;
    my $line;

    if (!open ($CONFIG, ">" . $self->{CONFIGURATION_OUTPUT}->{SERVICE_TEMPLATES})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_OUTPUT}->{SERVICE_TEMPLATES}."!");
        return;
    }

    print $CONFIG $self->{OUTPUT_HEADER};

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{SERVICE_TEMPLATES})) {
        $self->error("Cannot open template file ".$self->{CONFIGURATION_TEMPLATES}->{SERVICE_TEMPLATES}."!");
        close ($CONFIG);
        return;
    }
    $line = join ("", <$TEMPL>);
    close ($TEMPL);
    $line =~ s/<ENABLE_FLAP_DETECTION>/$self->{ENABLE_FLAP_DETECTION}/mg;
    print $CONFIG $line;

    close $CONFIG;

    1;
}

sub _getAttributeValue {
    my $self = shift;
    my $host = shift;
    my $attr = shift;
    my $vo = shift;
    my $voFqan = shift;

    my $value = $self->{SITEDB}->hostAttribute($host, $attr);
    my $voValue = $self->{SITEDB}->hostAttributeVO($host, $attr, $voFqan);
    $voValue = $self->{SITEDB}->hostAttributeVO($host, $attr, $vo) if (!$voValue && !$self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{FAKE_FQAN});
    $value = $voValue if ($voValue);
    $value = $vo if ($attr eq 'VONAME');
    $value = $voFqan if ($attr eq 'VO_FQAN' && !$self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{FAKE_FQAN});
    $value = $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{PROXY_FILE} if ($attr eq 'X509_USER_PROXY');
    $value = $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{MYPROXY_USER} if ($attr eq 'MYPROXY_USER' && $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{MYPROXY_USER});
    $value = $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{MYPROXY_NAME} if ($attr eq 'MYPROXY_NAME' && $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{MYPROXY_NAME});
    $value = $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{ROBOT_CERT} if ($attr eq 'ROBOT_CERT' && $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{ROBOT_CERT});
    $value = $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{ROBOT_KEY} if ($attr eq 'ROBOT_KEY' && $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{ROBOT_KEY});

    # ARC hacks, ask them to enable definition without -O key=value
    if ($attr eq 'ARC_GOOD_SES') {
        my $seFile = '/var/lib/gridprobes/';
        my $seFileAttr = 'GoodSEs';
        if (!$self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{FAKE_FQAN}) {
            my $voFqanNeat = $voFqan;
            $voFqanNeat =~ s/^.(.*)$/$1/;
            $voFqanNeat =~ s/\//./g;
            $seFile .= $voFqanNeat . '/' . $seFileAttr;
        } else {
            $seFile .= $vo . '/' . $seFileAttr;
        }       
        $value = 'good_ses_file=' . $seFile;
    }

    $value;
}

sub _getMetricOptionString {
    my $self = shift;
    my $host = shift;
    my $metric = shift;
    my $vo = shift;
    my $voFqan = shift;
    my $nrpe = shift;
    my $attributes = $self->{SITEDB}->metricAttributes($host, $metric);
    my $parameters = $self->{SITEDB}->metricParameters($host, $metric);
    my $fileAttributes = $self->{SITEDB}->metricFileAttributes($host, $metric);
    my $fileParameters = $self->{SITEDB}->metricFileParameters($host, $metric);
    my $options = "";
    my $fileName = "";
    my $finalFileName = "";

    # file attrs/params exist, need to create the file
    if ($fileAttributes && %$fileAttributes || $fileParameters && %$fileParameters) {
        my $CONFIG;
        $fileName = $self->{OUTPUT_DIR} . "/" . $host . "_" . $metric . ".config";
        $finalFileName = $self->{FINAL_OUTPUT_DIR} . "/" . $host . "_" . $metric . ".config";
        if (!open ($CONFIG, ">" . $fileName)) {
            $self->error("Cannot open configuration file ".$fileName."!");
            return;
        }
        foreach my $attr (keys %$fileAttributes) {
            my $value = $self->_getAttributeValue($host, $attr, $vo, $voFqan);
            next unless($value);

            print $CONFIG $fileAttributes->{$attr} . '="' . $value . "\"\n";
        }
        foreach my $param (keys %$fileParameters) {
            print $CONFIG $param . '="' . $fileParameters->{$param} . "\"\n";
        }
        close $CONFIG;
    }

    if (exists $attributes->{METRIC_CONFIG_FILE}) {
        $options .= $attributes->{METRIC_CONFIG_FILE} . ' '  . $finalFileName . ' ';
    }
    
    foreach my $attr (keys %$attributes) {
        next if ($attr eq 'METRIC_CONFIG_FILE');
        my $value = $self->_getAttributeValue($host, $attr, $vo, $voFqan);
        next unless($value);

        $options .= $attributes->{$attr} . ' '  . $value . ' ';
    }

    foreach my $param (keys %$parameters) {
        $options .= $param . ' ';
        if ($parameters->{$param}) {
            $options .= $parameters->{$param} . ' ';
        }
    }

    return $options;
}

sub _genServiceGroup {
    my $self = shift;
    my $CONFIG = shift;
    my $name = shift;
    my $TEMPL;
    my $line;

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{SERVICES_SERVICEGROUP})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_TEMPLATES}->{SERVICES_SERVICEGROUP}."!");
        return;
    }
    $line = join ("", <$TEMPL>);
    close ($TEMPL);
    $line =~ s/<service>/$name/mg;
    print $CONFIG $line;

    1;
}

sub _genServiceGroups {
    my $self = shift;
    my $servicegroups = shift;
    my $CONFIG;

    if (!open ($CONFIG, ">" . $self->{CONFIGURATION_OUTPUT}->{SERVICE_GROUPS})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_OUTPUT}->{SERVICE_GROUPS}."!");
        return;
    }

    print $CONFIG $self->{OUTPUT_HEADER};

    foreach my $sgroup (keys %$servicegroups) {
        if (! $self->_genServiceGroup ($CONFIG, $sgroup) ) {
            close ($CONFIG);
            return;
        }
    }

    close $CONFIG;

    1;
}

sub _genServiceDependency {
    my $self = shift;
    my $CONFIG = shift;
    my $hostname1 = shift;
    my $servicename1 = shift;
    my $hostname2 = shift;
    my $servicename2 = shift;
    my $TEMPL;
    my $line;

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{SERVICES_SERVICEDEP})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_TEMPLATES}->{SERVICES_SERVICEDEP}."!");
        return;
    }
    $line = join ("", <$TEMPL>);
    close ($TEMPL);
    $line =~ s/<servicename1>/$servicename1/mg;
    $line =~ s/<servicename2>/$servicename2/mg;
    $line =~ s/<hostname1>/$hostname1/mg;
    $line =~ s/<hostname2>/$hostname2/mg;

    print $CONFIG $line;

    1;
}

sub _genWlcgServicePassive {
    my $self = shift;
    my $CONFIG = shift;
    my $line = shift;
    my $hostname = shift;
    my $metricName = shift;
    my $parent = shift;
    my $contactlist = shift;
    my $servicegroup = shift;
    my $config = shift;
    my $notes = shift || "-";
    my $obsess = shift;
    my $customVars = shift;
    my $docUrl = shift || "";
    my $pnp = shift || "";
    my $customVarsStr = "";

    if ($docUrl) {
        $docUrl = "notes_url                      $docUrl";
    }
    if ($pnp) {
        $pnp = "action_url                      $self->{PNP_ACTION_URL}";
    }
    if ($customVars) {
        foreach my $key (keys %$customVars) {
            $customVarsStr .= "        $key     $customVars->{$key}\n";
        }
    }

    $line =~ s/<hostname>/$hostname/mg;
    $line =~ s/<servicegroup>/$servicegroup/mg;
    $line =~ s/<contactlist>/$contactlist/mg;
    $line =~ s/<metricName>/$metricName/mg;
    $line =~ s/<parent>/$parent/mg;
    $line =~ s/<docurl>/$docUrl/mg;
    $line =~ s/<url>/$pnp/mg;
    $line =~ s/<notes>/$notes/mg;
    $line =~ s/<obsess>/$obsess/mg;
    $line =~ s/<customVars>/$customVarsStr/mg;

    foreach my $configVar (keys %$config) {
        $line =~ s/<$configVar>/$config->{$configVar}/mg;
    }

    print $CONFIG $line;

    1;
}

sub _substPathVariable {
    my $self = shift;
    my $path = shift;
    my $nrpe = shift;
    my $retVal = $path;

    if ($path eq $NCG::NCG_PROBES_PATH_GRIDMON) {
        $retVal = $self->{WLCG_PROBES_DIR};
    } elsif ($path eq $NCG::NCG_PLUGINS_PATH_GRIDMON) {
        $retVal = $self->{WLCG_PLUGINS_DIR};
    } elsif ($path eq $NCG::NCG_PROBES_PATH_NAGIOS) {
        if ($nrpe) {
            $retVal = '@NAGIOS_PROBES_DIR@';
        } else {
            $retVal = '$USER1$';
        }
    }
    $retVal;
}

sub _genNativeService {
    my $self = shift;
    my $CONFIG = shift;
    my $line = shift;
    my $hostname = shift;
    my $metric = shift;
    my $metricName = shift;
    my $probe = shift;
    my $contactlist = shift;
    my $servicegroup = shift;
    my $config = shift;
    my $options = shift;
    my $notes = shift || "-";
    my $obsess = shift;
    my $customVars = shift;
    my $docUrl = shift || "";
    my $pnp = shift || "";
    my $command = shift;
    my $customVarsStr = "";

    if ($docUrl) {
        $docUrl = "notes_url                      $docUrl";
    }
    if ($pnp) {
        $pnp = "action_url                      $self->{PNP_ACTION_URL}";
    }
    if ($customVars) {
        foreach my $key (keys %$customVars) {
            $customVarsStr .= "        $key     $customVars->{$key}\n";
        }
    }
    
    if (exists $config->{path}) {
        $config->{path} = $self->_substPathVariable($config->{path});
    }

    $line =~ s/<hostname>/$hostname/mg;
    $line =~ s/<servicegroup>/$servicegroup/mg;
    $line =~ s/<metric>/$metric/mg;
    $line =~ s/<metricName>/$metricName/mg;
    $line =~ s/<contactlist>/$contactlist/mg;
    $line =~ s/<probe>/$probe/mg;
    $line =~ s/<options>/$options/mg;
    $line =~ s/<docurl>/$docUrl/mg;
    $line =~ s/<url>/$pnp/mg;
    $line =~ s/<notes>/$notes/mg;
    $line =~ s/<obsess>/$obsess/mg;
    $line =~ s/<commandName>/$command/mg;
    $line =~ s/<customVars>/$customVarsStr/mg;
    foreach my $configVar (keys %$config) {
        $line =~ s/<$configVar>/$config->{$configVar}/mg;
    }
    print $CONFIG $line;

    1;
}

sub _genNativeServiceNrpe {
    my $self = shift;
    my $CONFIG = shift;
    my $NRPE_CONFIG = shift;
    my $line = shift;
    my $nrpeLine = shift;

    my $hostname = shift;
    my $metric = shift;
    my $metricName = shift;
    my $nrpecommand = shift;
    my $contactlist = shift;
    my $servicegroup = shift;
    my $config = shift;
    my $options = shift;
    my $notes = shift || "-";
    my $obsess = shift;
    my $customVars = shift;
    my $docUrl = shift || "";
    my $pnp = shift || "";
    my $command = shift;
    my $nrpeHost = shift;
    my $customVarsStr = "";

    if ($docUrl) {
        $docUrl = "notes_url                      $docUrl";
    }
    if ($pnp) {
        $pnp = "action_url                      $self->{PNP_ACTION_URL}";
    }

    if ($customVars) {
        foreach my $key (keys %$customVars) {
            $customVarsStr .= "        $key     $customVars->{$key}\n";
        }
    }

    my $timeout = $config->{timeout} + 20;

    $line =~ s/<hostname>/$hostname/mg;
    $line =~ s/<servicegroup>/$servicegroup/mg;
    $line =~ s/<metric>/$metric/mg;
    $line =~ s/<metricName>/$metricName/mg;
    $line =~ s/<contactlist>/$contactlist/mg;
    $line =~ s/<nrpecommand>/$nrpecommand/mg;
    $line =~ s/<docurl>/$docUrl/mg;
    $line =~ s/<url>/$pnp/mg;
    $line =~ s/<notes>/$notes/mg;
    $line =~ s/<obsess>/$obsess/mg;
    $line =~ s/<customVars>/$customVarsStr/mg;
    $line =~ s/<NRPE_UI>/$nrpeHost/mg;
    $line =~ s/<timeout>/$timeout/mg;
    foreach my $configVar (keys %$config) {
        $line =~ s/<$configVar>/$config->{$configVar}/mg;
    }
    print $CONFIG $line;

    $nrpeLine =~ s/<nrpecommand>/$nrpecommand/mg;
    $nrpeLine =~ s/<command>/$command/mg;
    $nrpeLine =~ s/<timeout>/$config->{timeout}/mg;
    $nrpeLine =~ s/<options>/$options/mg;
    print $NRPE_CONFIG $nrpeLine;

    1;
}

# ($host, $servicename, $remoteService, $contactgroup, $servicegroup, $url)
sub _genRemoteService {
    my $self = shift;
    my $CONFIG = shift;
    my $line = shift;
    my $host = shift;
    my $servicename = shift;
    my $remoteService = shift;
    my $contactgroup = shift;
    my $servicegroup = shift;
    my $url = shift || "";
    my $docurl = shift || "";
    my $config = shift;

    if ($url) {
        $url = "action_url                       $url";
    }

    if ($docurl) {
        $docurl = "notes_url                      $docurl";
    }

    $line =~ s/<hostname>/$host/mg;
    $line =~ s/<servicename>/$servicename/mg;
    $line =~ s/<servicegroup>/$servicegroup/mg;
    $line =~ s/<contactlist>/$contactgroup/mg;
    $line =~ s/<url>/$url/mg;
    $line =~ s/<docurl>/$docurl/mg;
    $line =~ s/<NAGIOS_SERVER>/$self->{NAGIOS_SERVER}/mg;
    if ($config) {
        foreach my $configVar (keys %$config) {
            $line =~ s/<$configVar>/$config->{$configVar}/mg;
        }
    }
    print $CONFIG $line;

    1;
}

sub _getNativeServiceTemplates {
    my $self = shift;
    my $templates = shift;
    my $TEMPL;

    #if ($self->{NRPE_UI}) {
        if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{SERVICES_WLCGNRPE})) {
            $self->error("Cannot open template file ".$self->{CONFIGURATION_TEMPLATES}->{SERVICES_WLCGNRPE}."!");
            return;
        }
        $templates->{NATIVENRPE} = join ("", <$TEMPL>);
        close ($TEMPL);
        if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{NRPE_NATIVECOMMANDS})) {
            $self->error("Cannot open template file ".$self->{CONFIGURATION_TEMPLATES}->{NRPE_NATIVECOMMANDS}."!");
            return;
        }
        $templates->{NRPE_NATIVECOMMANDS} = join ("", <$TEMPL>);
        close ($TEMPL);
    #}

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{SERVICES_NATIVE})) {
        $self->error("Cannot open template file ".$self->{CONFIGURATION_TEMPLATES}->{SERVICES_NATIVE}."!");
        return;
    }
    $templates->{NATIVE} = join ("", <$TEMPL>);
    close ($TEMPL);

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{SERVICES_WLCGPASSIVE})) {
        $self->error("Cannot open template file ".$self->{CONFIGURATION_TEMPLATES}->{SERVICES_WLCGPASSIVE}."!");
        return;
    }
    $templates->{WLCGPASSIVE} = join ("", <$TEMPL>);
    close ($TEMPL);

    1;
}

sub _getRemoteServiceTemplates {
    my $self = shift;
    my $templates = shift;
    my $TEMPL;

    if (!open ($TEMPL, $self->{CONFIGURATION_TEMPLATES}->{SERVICES_NAGIOS})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_TEMPLATES}->{SERVICES_NAGIOS}."!");
        return;
    }
    $templates->{Nagios} = join ("", <$TEMPL>);
    close ($TEMPL);

    1;
}

sub _genNativeServices {
    my $self = shift;
    my $CONFIG = shift;
    my $NRPE_CONFIG = shift;
    my $HOST_NRPE_CONFIG = shift;
    my $host = shift;
    my $templates = shift;
    my $metric = shift;
    my $probe = shift;
    my $contactgroup = shift;
    my $metricSgroup = shift;
    my $isNRPE = shift;
    my $passive = shift;
    my $parent = shift;
    my $obsess = shift;
    my $custom = shift;
    my $config = shift;
    my $options = shift;
    my $notes = shift;
    my $metricDocUrl = shift;
    my $metricVo = shift;
    my $metricPNP = shift;
    my $vo = shift;
    my $voFqan = shift;
    my $voRemovedMetrics = shift;
    my $gridProxyServer = shift;
    my $lbnode = shift;
    my $metricName = $metric;
    my $nrpecommand = $host . "_" . $metric;
    my $hostActual;
    my $sitename = $self->{SITEDB}->siteName();
    
    if ($lbnode) {
        $hostActual = $lbnode;
    } else {
        $hostActual = $host;
    }

    if ($metricVo) {
        $metricName .= "-$voFqan";
        $nrpecommand .= "_".$self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{VO_FQAN_TIDY};
    }
    
    if ($self->{SITEDB}->hasServiceContacts($host, $metricName)) {
        $contactgroup .= ", $sitename-$host-$metricName";
    }
    if ($self->{SITEDB}->hasServiceContacts($host, $metric)) {
        $contactgroup .= ", $sitename-$host-$metric";
    }
    foreach my $serviceFlavour ($self->{SITEDB}->metricServices($host, $metric)) {
        if ($self->{SITEDB}->hasServiceFlavourContacts($host, $serviceFlavour)) {
            $contactgroup .= ", $sitename-$host-flavour-$serviceFlavour";
        }    
    }

    if ($passive) {
        if (! $self->_genWlcgServicePassive($CONFIG,
                                $templates->{WLCGPASSIVE},
                                $hostActual,
                                $metricName,
                                $parent,
                                $contactgroup,
                                $metricSgroup,
                                $config,
                                $notes,
                                $obsess,
                                $custom,
                                $metricDocUrl,
                                $metricPNP) ) {
            return;
        }
    } else {
        if ($isNRPE || $self->{SITEDB}->metricFlag($host,$metric, "NRPE_SERVICE")) {
            my $nrpeHost;
            my $nrpeConfig;
            if (exists $config->{path}) {
                $config->{path} = $self->_substPathVariable($config->{path}, 1);
            }

            my $command = "$config->{path}/$probe";
            my $sudo = $self->{SITEDB}->metricFlag($host,$metric, "SUDO");
            if ($sudo) {
                $sudo = 'root' if ($sudo eq '1');
                $command = "sudo -u $sudo " . $command;
            }
            if (!$self->{SITEDB}->metricFlag($host,$metric, "NOHOSTNAME")) {
                $command .= " -H $hostActual";
            }
            if ($isNRPE) {
                $nrpeHost = $self->{NRPE_UI};
                $nrpeConfig = $NRPE_CONFIG;
            } else {
                $nrpeHost = $hostActual;
                if (!$HOST_NRPE_CONFIG) {
                    $nrpeConfig = $NRPE_CONFIG;
                } else {
                    $nrpeConfig = $HOST_NRPE_CONFIG;
                }
            }

            if (! $self->_genNativeServiceNrpe($CONFIG,
                                        $nrpeConfig,
                                        $templates->{NATIVENRPE},
                                        $templates->{NRPE_NATIVECOMMANDS},
                                        $hostActual,
                                        $metric,
                                        $metricName,
                                        $nrpecommand,
                                        $contactgroup,
                                        $metricSgroup,
                                        $config,
                                        $options,
                                        $notes,
                                        $obsess,
                                        $custom,
                                        $metricDocUrl,
                                        $metricPNP,
                                        $command,
                                        $nrpeHost) ) {
                return;
            }
        } else {
            my $command = "ncg_check_native";
            my $sudo = $self->{SITEDB}->metricFlag($host,$metric, "SUDO");
            if ($sudo) {
                $command .= "_sudo";
                $sudo = 'root' if ($sudo eq '1');
                $custom->{"_sudouser"} = $sudo if ($custom && ref $custom eq "HASH");
            }
            if ($self->{SITEDB}->metricFlag($host,$metric, "NOHOSTNAME")) {
                $command .= "_local";
            }
            if ($self->{SITEDB}->metricFlag($host,$metric, "NOARGS")) {
                $command .= "_noargs";
            }
            if ($self->{SITEDB}->metricFlag($host,$metric, "NOTIMEOUT")) {
                $command .= "_notimeout";
            }
            if (! $self->_genNativeService($CONFIG,
                                        $templates->{NATIVE},
                                        $hostActual,
                                        $metric,
                                        $metricName,
                                        $probe,
                                        $contactgroup,
                                        $metricSgroup,
                                        $config,
                                        $options,
                                        $notes,
                                        $obsess,
                                        $custom,
                                        $metricDocUrl,
                                        $metricPNP,
                                        $command) ) {
                return;
            }
        }
    }

    # generate dependencies
    my $deps = $self->{SITEDB}->metricDependencies($host, $metric);
    my $host2;

    foreach my $dep (keys %$deps) {
        if ($dep eq "hr.srce.GridProxy-Valid") {
            $host2 = $gridProxyServer;
            $dep = "hr.srce.GridProxy-Valid-$voFqan";
        } else {
            # SiteDB might have inconsistent dependencies list
            # TODO: clean dependencies in SiteDB
            if (!$self->{SITEDB}->hasMetric($host, $dep, $self->{PROBES_TYPE_FLAG})) {
                next;
            }
            next if (exists $voRemovedMetrics->{VO}->{$vo}->{$dep} ||
                     exists $voRemovedMetrics->{VO_FQAN}->{$voFqan}->{$dep});
            if ($self->{SITEDB}->metricFlag($host, $dep, "VO")) {
                $dep .= "-$voFqan";
            }
            $host2 = $hostActual;
        }

        if (! $self->_genServiceDependency($CONFIG, $hostActual, $metricName, $host2, $dep) ) {
            return;
        }
    }
    1;
}

sub _getLocalServiceGroups {
	my $self = shift;
    my $host = shift || return;
    my $metric = shift || return;
    my $servicegroups = shift;
    my $lbnode = shift;
    my $metricSgroup;
    my $sitename = $self->{SITEDB}->siteName();

    $metricSgroup = "local";
    $servicegroups->{local} = 1;

    foreach my $service ($self->{SITEDB}->metricServices($host, $metric)) {
        $metricSgroup .= ", SITE_${sitename}_${service}";
        $servicegroups->{"SITE_${sitename}_${service}"} = 1;
        $metricSgroup .= ", SERVICE_${service}";
        $servicegroups->{"SERVICE_${service}"} = 1;
    }

    if ($self->{SITEDB}->metricFlag($host, $metric, "PASSIVE")) {
        my $parent = $self->{SITEDB}->metricParent($host, $metric) || 'no';
        my $address = $host;
        $address = $lbnode if ($lbnode);

        $metricSgroup .= ", ${parent}_${address}";
        $servicegroups->{"${parent}_${address}"} = 1;
    }

    $metricSgroup;
}

sub _genServices {
    my $self = shift;
    my $CONFIG = shift;
    my $host = shift;
    my $contactgroup = shift;
    my $servicegroups = shift;
    my $NRPE_CONFIG = shift;
    my $HOST_NRPE_CONFIG = shift;
    my $sitename = $self->{SITEDB}->siteName();
    my $servicegroup;
    my $metricCount = 0;
    my $gridProxyServer;
    #if ($self->{NRPE_UI}) {
    #    $gridProxyServer = $self->{NRPE_UI};
    #} else {
        $gridProxyServer = $self->{NAGIOS_SERVER};
    #}

    my $grids = join (',', $self->{SITEDB}->getGrids);

    if ($self->{PROBES_TYPE_FLAG}->{local} || $sitename eq 'nagios') {
        my $templates = {};
        if (!$self->_getNativeServiceTemplates ($templates)) {
            return;
        }

        # first run, let's throw out metrics which don't support VO
        my $voRemovedMetrics = {};
        foreach my $metric ($self->{SITEDB}->getLocalMetrics($host)) {
            if ($self->{SITEDB}->metricFlag($host, $metric, "VO")) {
                foreach my $vo (keys %{$self->{VOS}}) {
                    if (!$self->{SITEDB}->hasVO($host, $vo, $metric)) {
                        $voRemovedMetrics->{VO}->{$vo}->{$metric} = 1;
                        next;
                    }
                    foreach my $voFqan (keys %{$self->{VOS}->{$vo}->{FQAN}}) {
                        if (!$self->{SITEDB}->hasMetricVoFqan($host, $metric, $vo, $voFqan, $self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{DEFAULT_FQAN})) {
                            $voRemovedMetrics->{VO_FQAN}->{$voFqan}->{$metric} = 1;
                        }
                    }
                }
            }
        }

        foreach my $metric ($self->{SITEDB}->getLocalMetrics($host)) {
            my $config;
            my $parent;
            my $probe;
            my $metricDocUrl = $self->{SITEDB}->metricDocUrl($host, $metric);
            my $metricSgroup = "";
            my $metricServiceURI = $host;
            my $passive = $self->{SITEDB}->metricFlag($host, $metric, "PASSIVE");
            my $isNrpe = $self->{NRPE_UI} && $self->{SITEDB}->metricFlag($host, $metric, "NRPE");
            my $serviceType = join (',', $self->{SITEDB}->metricServices($host, $metric));
            my $obsess = $self->{SITEDB}->metricFlag($host, $metric, "OBSESS") || 0;
            my $contactgroupLocal = $contactgroup;
            my $roc = $self->{SITEDB}->siteROC || $self->{ROC};
            my $metricVo = $self->{SITEDB}->metricFlag($host, $metric, "VO");

            my $custom = {};
            $custom->{"_site_name"} = $sitename;
            $custom->{"_metric_name"} = $metric;
            $custom->{"_service_uri"} = $metricServiceURI;
            $custom->{"_service_flavour"} = $serviceType;
            $custom->{"_grid"} = $grids if ($grids);
            $custom->{"_server"} = $self->{NAGIOS_SERVER};
            $custom->{"_last_notification_type"} = "";
            $custom->{"_dashboard_notification_status"} = "";
            $custom->{"_dashboard_notification_status_last_update"} = "";
            if ($self->{GGUS_SERVER_FQDN}) {
                $custom->{"_GGUS"} = "";
            }
            if ($roc) {
                $custom->{"_roc"} = $roc;
            }

            if ($obsess && ( $self->{GGUS_SERVER_FQDN} || $self->{SEND_TO_DASHBOARD} )) {
                $contactgroupLocal .= ", msg-contacts";
            }

            $metricSgroup = $self->_getLocalServiceGroups($host, $metric, $servicegroups);

            if ($passive) {
                $parent = $self->{SITEDB}->metricParent($host, $metric);
                if ($parent) {
                    $config = $self->{SITEDB}->metricConfig($host, $parent);
                    next unless ($self->{SITEDB}->hasMetric($host, $parent));
                } else {
                    $config = $self->{SITEDB}->defaultConfig();
                    $parent = 'no';
                }
            } else {
                $config = $self->{SITEDB}->metricConfig($host, $metric);
                $probe = $self->{SITEDB}->metricProbe($host, $metric)
            }

            foreach my $vo (keys %{$self->{VOS}}) {
                foreach my $voFqan (keys %{$self->{VOS}->{$vo}->{FQAN}}) {

                    next if (exists $voRemovedMetrics->{VO}->{$vo}->{$metric} ||
                             exists $voRemovedMetrics->{VO_FQAN}->{$voFqan}->{$metric});
    
                    my $options = $self->_getMetricOptionString($host, $metric, $vo, $voFqan, $self->{NRPE_UI});
                    my $metricSgroupLocal = $metricSgroup;
                    if ($metricVo) {
                        $self->verbose ("    metric: $metric-$voFqan");
                        $metricSgroupLocal .= ", VO_" . $vo . ", " . $voFqan;
                        $servicegroups->{$voFqan} = 1;
                        $servicegroups->{"VO_$vo"} = 1;
                        $custom->{"_vo"} = $vo;
                        $custom->{"_vo_fqan"} = $voFqan;
                    } else {
                        $self->verbose ("    metric: $metric");
                    }
                    if ($self->_genNativeServices (
                                    $CONFIG,
                                    $NRPE_CONFIG,
                                    $HOST_NRPE_CONFIG,
                                    $host,
                                    $templates,
                                    $metric,
                                    $probe,
                                    $contactgroupLocal,
                                    $metricSgroupLocal,
                                    $isNrpe,
                                    $passive,
                                    $parent,
                                    $obsess,
                                    $custom,
                                    $config,
                                    $options,
                                    "",
                                    $metricDocUrl,
                                    $metricVo,
                                    $self->{SITEDB}->metricFlag($host, $metric, "PNP") || '',
                                    $vo,
                                    $voFqan,
                                    $voRemovedMetrics,
                                    $gridProxyServer) ) {
                        $metricCount++;
                        # if this is not VO-dependent metric get out after first pass
                        last unless ($metricVo);
                    } else {
                        return;
                    }

                }
                last unless ($metricVo);
            }
        }
    }


    if ($self->{PROBES_TYPE_FLAG}->{remote}) {
        my $templates = {};
        if (!$self->_getRemoteServiceTemplates ($templates)) {
            return;
        }

        foreach my $metric ($self->{SITEDB}->getRemoteMetrics($host)) {
            $self->verbose ("    metric: $metric");
            my $remoteService = $self->{SITEDB}->metricRemoteService($host, $metric);
            my $metricVo = $self->{SITEDB}->metricVo($host, $metric);
            my $metricSgroup = "remote, $remoteService";
            my $config = $self->{SITEDB}->metricConfig($host, $metric);

            $servicegroups->{remote} = 1;
            $servicegroups->{$remoteService} = 1;
            if ($metricVo) {
                $metricSgroup .= ", $metricVo";
                $servicegroups->{$metricVo} = 1;
            }

            # ($host, $servicename, $remoteService, $contactgroup, $servicegroup, $url)
            if (! $self->_genRemoteService($CONFIG,
                                         $templates->{$remoteService},
                                         $host,
                                         $metric,
                                         $remoteService,
                                         $contactgroup,
                                         $metricSgroup,
                                         $self->{SITEDB}->metricUrl($host, $metric),
                                         $self->{SITEDB}->metricDocUrl($host, $metric),
                                         $config) ) {
                return;
            }

            $metricCount++;

            # generate dependencies
            my $deps = $self->{SITEDB}->metricDependencies($host, $metric);

            if ($deps) {
                foreach my $dep (keys %$deps) {
                    if (!$self->{SITEDB}->hasMetric($host, $dep)) {
                        next;
                    }

                    if (! $self->_genServiceDependency($CONFIG, $host, $metric, $host, $dep) ) {
                        return;
                    }
                }
            }
        }
    }

    $metricCount;
}

sub _genLBServices {
    my $self = shift;
    my $CONFIG = shift;
    my $lbnode = shift;
    my $host = shift;
    my $contactgroup = shift;
    my $servicegroups = shift;
    my $NRPE_CONFIG = shift;
    my $HOST_NRPE_CONFIG = shift;
    my $sitename = $self->{SITEDB}->siteName();
    my $servicegroup;
    my $metricCount = 0;
    my $gridProxyServer;
    #if ($self->{NRPE_UI}) {
    #    $gridProxyServer = $self->{NRPE_UI};
    #} else {
        $gridProxyServer = $self->{NAGIOS_SERVER};
    #}

    if ($self->{PROBES_TYPE_FLAG}->{local} || $sitename eq 'nagios') {
        my $templates = {};
        if (!$self->_getNativeServiceTemplates ($templates)) {
            return;
        }

        # first run, let's throw out metrics which don't support VO
        my $voRemovedMetrics = {};
        foreach my $metric ($self->{SITEDB}->getRealLocalMetrics($host)) {
            if ($self->{SITEDB}->metricFlag($host, $metric, "VO")) {
                foreach my $vo (keys %{$self->{VOS}}) {
                    if (!$self->{SITEDB}->hasVO($host, $vo, $metric)) {
                        $voRemovedMetrics->{VO}->{$vo}->{$metric} = 1;
                        next;
                    }
                    foreach my $voFqan (keys %{$self->{VOS}->{$vo}->{FQAN}}) {
                        if (!$self->{SITEDB}->hasMetricVoFqan($host, $metric, $vo, $voFqan,$self->{VOS}->{$vo}->{FQAN}->{$voFqan}->{DEFAULT_FQAN})) {
                            $voRemovedMetrics->{VO_FQAN}->{$voFqan}->{$metric} = 1;
                        }
                    }
                }

            }
        }

        foreach my $metric ($self->{SITEDB}->getRealLocalMetrics($host)) {
            my $config;
            my $parent;
            my $probe;
            my $passive = $self->{SITEDB}->metricFlag($host, $metric, "PASSIVE");
            my $metricVo = $self->{SITEDB}->metricFlag($host, $metric, "VO");

            # let's first check if we need to do anything with this metric on LB node
            if ($passive) {
                $parent = $self->{SITEDB}->metricParent($host, $metric);
                if ($parent) {
                    if ($self->{SITEDB}->metricFlag($host, $parent, "NOLBNODE")) {
                        next;
                    }
                    $config = $self->{SITEDB}->metricConfig($host, $parent);
                    next unless ($self->{SITEDB}->hasMetric($host, $metric));
                } else {
                    $config = $self->{SITEDB}->defaultConfig();
                    $parent = 'no';
                }                
            } else {
                if ($self->{SITEDB}->metricFlag($host, $metric, "NOLBNODE")) {
                    next;
                }
                $config = $self->{SITEDB}->metricConfig($host, $metric);
                $probe = $self->{SITEDB}->metricProbe($host, $metric)
            }

            my $metricDocUrl = $self->{SITEDB}->metricDocUrl($host, $metric);
            my $metricSgroup = "";
            my $isNrpe = $self->{NRPE_UI} && $self->{SITEDB}->metricFlag($host, $metric, "NRPE");

            $metricSgroup = $self->_getLocalServiceGroups($host, $metric, $servicegroups, $lbnode);

            foreach my $vo (keys %{$self->{VOS}}) {
                foreach my $voFqan (keys %{$self->{VOS}->{$vo}->{FQAN}}) {

                    next if (exists $voRemovedMetrics->{VO}->{$vo}->{$metric} ||
                         exists $voRemovedMetrics->{VO_FQAN}->{$voFqan}->{$metric});

                    my $options = $self->_getMetricOptionString($host, $metric, $vo, $voFqan, $self->{NRPE_UI});
                    my $metricSgroupLocal = $metricSgroup;
                    if ($metricVo) {
                        $self->verbose ("    metric: $metric-$voFqan");
                        $metricSgroupLocal .= ", VO_" . $vo . ", " . $voFqan;
                        $servicegroups->{$voFqan} = 1;
                        $servicegroups->{"VO_$vo"} = 1;
                    } else {
                        $self->verbose ("    metric: $metric");
                    }
                    if ($self->_genNativeServices (
                                    $CONFIG,
                                    $NRPE_CONFIG,
                                    $HOST_NRPE_CONFIG,
                                    $host,
                                    $templates,
                                    $metric,
                                    $probe,
                                    $contactgroup,
                                    $metricSgroupLocal,
                                    $isNrpe,
                                    $passive,
                                    $parent,
                                    0,
                                    "",
                                    $config,
                                    $options,
                                    "",
                                    $metricDocUrl,
                                    $metricVo,
                                    $self->{SITEDB}->metricFlag($host, $metric, "PNP") || '',
                                    $vo,
                                    $voFqan,
                                    $voRemovedMetrics,
                                    $gridProxyServer,
                                    $lbnode) ) {
                        $metricCount++;
                        # if this is not VO-dependent metric get out after first pass
                        last unless ($metricVo);
                    } else {
                        return;
                    }
                }
                last unless ($metricVo);
            }
        }
    }

    $metricCount;
}


sub _genServicesHeader {
	my $self = shift;
    my $CONFIG;
    my $TEMPL;
    my $line;

    if (!open ($CONFIG, ">" . $self->{CONFIGURATION_OUTPUT}->{SERVICES})) {
        $self->error("Cannot open configuration file ".$self->{CONFIGURATION_OUTPUT}->{SERVICES}."!");
        return;
    }

    print $CONFIG $self->{OUTPUT_HEADER};

    return $CONFIG;
}

#############################
##
##  ConfigGen getConfig implementation
##
#############################

sub _loadHeaderText
{
    my $self = shift;
    my $username = getlogin() || "unknown";
    my $time = time2str("%Y-%m-%dT%H:%M:%SZ",time(),"UTC");
    my $settings = "";

    foreach my $attr (keys %$self) {
        $settings .= "#     ".$attr.": ".$self->{$attr}."\n" if (!ref($self->{$attr}) && $self->{$attr});
    }
    chop $settings;

    $self->{OUTPUT_HEADER} =
"#
# Automatically generated by NCG::ConfigGen::Nagios.pm by $username at $time
#
# Settings:
$settings
#

";
}

sub _getContactGroups {
    my $self = shift;
    my $host = shift;
    my $sitename = $self->{SITEDB}->siteName();
    my $contactgroup = "$sitename-site";

    if (!$host) {
        return $contactgroup;
    }

    if ($self->{SITEDB}->hasContacts($host)) {
        $contactgroup .= ", $sitename-$host";
    }

    $contactgroup;
}

sub _getHostGroups {
	my $self = shift;
    my $host = shift || return;
    my $hostgroups = shift;
    my $hostgroup;
    my $sitename = $self->{SITEDB}->siteName();
    my $country = $self->{SITEDB}->siteCountry();
    my $roc = $self->{SITEDB}->siteROC();

    # each host belongs to site hostgroup
    # (this hostgroup is useful on regional level Nagios)
    $hostgroup = "site-$sitename";
    $hostgroups->{"site-$sitename"}->{fullname} = "Site $sitename";
    $hostgroups->{"site-$sitename"}->{members}->{$host} = 1;

    if ($roc) {
        $hostgroup .= ", $roc";
        $hostgroups->{"$roc"}->{fullname} = "$roc";
        $hostgroups->{"$roc"}->{members}->{$host} = 1;
    }

    if ($country) {
        $hostgroup .= ", $country";
        $hostgroups->{"$country"}->{fullname} = "$country";
        $hostgroups->{"$country"}->{members}->{$host} = 1;
    }

    foreach my $grid ($self->{SITEDB}->getGrids) {
        $hostgroup .= ", $grid";
        $hostgroups->{"$grid"}->{fullname} = "$grid";
        $hostgroups->{"$grid"}->{members}->{$host} = 1;
    }

    # for each service group is generated
    foreach my $service ($self->{SITEDB}->getServices($host)) {
        $hostgroup .= ", node-$service";
        $hostgroups->{"node-$service"}->{fullname} = "$service nodes";
        $hostgroups->{"node-$service"}->{members}->{$host} = 1;
    }

    # if host is an alias, generate group of aliases
    my $alias;
    if ($alias = $self->{SITEDB}->hostAlias($host)) {
        $hostgroup .= ", alias-$alias";
        $hostgroups->{"alias-$alias"}->{fullname} = "Aliases of host $alias";
        $hostgroups->{"alias-$alias"}->{members}->{$host} = 1;
    }

    $hostgroup;
}

# difference between _getHostGroups:
#  - getRealServices is used for node-* groups
#  - lbnode-* is used instead of alias-*
sub _getLBHostGroups {
	my $self = shift;
    my $host = shift || return;
    my $hostgroups = shift;
    my $hostgroup;
    my $sitename = $self->{SITEDB}->siteName();
    my $country = $self->{SITEDB}->siteCountry();

    # each host belongs to site hostgroup
    # (this hostgroup is useful on regional level Nagios)
    $hostgroup = "site-$sitename";
    $hostgroups->{"site-$sitename"}->{fullname} = "Site $sitename";
    $hostgroups->{"site-$sitename"}->{members}->{$host} = 1;

    if ($country) {
        $hostgroup .= ", $country";
        $hostgroups->{"$country"}->{fullname} = "$country";
        $hostgroups->{"$country"}->{members}->{$host} = 1;
    }

    foreach my $grid ($self->{SITEDB}->getGrids) {
        $hostgroup .= ", $grid";
        $hostgroups->{"$grid"}->{fullname} = "$grid";
        $hostgroups->{"$grid"}->{members}->{$host} = 1;
    }

    # for each service group is generated
    foreach my $service ($self->{SITEDB}->getRealServices($host)) {
        $hostgroup .= ", node-$service";
        $hostgroups->{"node-$service"}->{fullname} = "$service nodes";
        $hostgroups->{"node-$service"}->{members}->{$host} = 1;
    }

    $hostgroup .= ", lbnode-$host";
    $hostgroups->{"lbnode-$host"}->{fullname} = "Load balanced nodes of host $host";
    $hostgroups->{"lbnode-$host"}->{members}->{$host} = 1;

    $hostgroup;
}

sub _closeFDs {
	my $self = shift;
    my $HOST_CONFIG = shift;
    my $SERVICE_CONFIG = shift;
    my $NRPE_CONFIG = shift;

    close($HOST_CONFIG) if ($self->{INCLUDE_HOSTS});
    close($SERVICE_CONFIG);
    close($NRPE_CONFIG) if ($self->{NRPE_UI});
}

sub _hostHasAnyVO {
	my $self = shift;
    my $host = shift;
    
    foreach my $vo (keys %{$self->{VOS}}) {
        return 1 if ($self->{SITEDB}->hasVO($host, $vo));
    }
    
    return 0;
}

sub getData {
	my $self = shift;
    my $HOST_CONFIG;
    my $SERVICE_CONFIG;
    my $NRPE_CONFIG;
    my $sitename;
    my $servicegroups = {};
    my $hostgroups = {};

    $hostgroups->{nagios}->{fullname} = "Nagios internal servers";

    $sitename = $self->{SITEDB}->siteName() if ($self->{SITEDB});

    $self->verbose("Generating configuration:");
    # Load header text which is added to all output files
    $self->_loadHeaderText();

    # generate global configuration for all sites
    if ($self->{MULTI_SITE_GLOBAL}) {
        # Generate commands
        $self->_genCommands() or return;

        $self->_genAdminContact() or return;

        # Generate host templates
        $self->_genHostTemplates() or return;

        # Generate service templates
        $self->_genServiceTemplates() or return;

        # Collect all host and service groups
        foreach my $site (keys %{$self->{MULTI_SITE_SITES}}) {
            foreach my $hgroup (keys %{$self->{MULTI_SITE_SITES}->{$site}->{HOST_GROUPS}}) {
                $hostgroups->{$hgroup} = $self->{MULTI_SITE_SITES}->{$site}->{HOST_GROUPS}->{$hgroup};
            }
            foreach my $sgroup (keys %{$self->{MULTI_SITE_SITES}->{$site}->{SERVICE_GROUPS}}) {
                $servicegroups->{$sgroup} = $self->{MULTI_SITE_SITES}->{$site}->{SERVICE_GROUPS}->{$sgroup};
            }
        }

        # Generate hostgroups
        $self->_genHostGroups ($hostgroups) or return;

        # Generate servicegroups
        $self->_genServiceGroups ($servicegroups) or return;

        # Generate users
        $self->_genUsers() or return;

        $self->_packNrpeFiles() or return;

        $self->verbose("DONE!");

    # generate configuration for a single site in multisite instance
    } elsif ($self->{MULTI_SITE_SITE}) {
        # In case of remote UI generate NRPE config
        if ($self->{NRPE_UI}) {
            $NRPE_CONFIG = $self->_genNrpeHeader();
            if (!$NRPE_CONFIG) {
                return;
            }
        }

        # Open hosts.cfg file descriptor
        if ($self->{INCLUDE_HOSTS}) {
            $HOST_CONFIG = $self->_genHostsHeader();
            if (!$HOST_CONFIG) {
                return;
            }
        }

        # Open services.cfg file descriptor
        $SERVICE_CONFIG = $self->_genServicesHeader();
        if (!$SERVICE_CONFIG) {
            close ($HOST_CONFIG) if ($self->{INCLUDE_HOSTS});
            close ($NRPE_CONFIG) if ($self->{NRPE_UI});
            return;
        }

        # find parent name
        my $parentName;
        if ($self->{INCLUDE_HOSTS}) {
            my $parent = $self->{SITEDB}->parent;
            if ($parent && ref $parent eq 'HASH' && exists $parent->{HOSTNAME} && $parent->{ADDRESS}) {
                $parentName = $parent->{HOSTNAME};
            }
        }
        
        my $hostNo = 0;

        # Iterate through hosts
        foreach my $host ($self->{SITEDB}->getHosts) {
            my $HOST_NRPE_CONFIG;
            
            next if ($self->{VO_HOST_FILTER} && !$self->_hostHasAnyVO($host));

            $self->verbose("  host: $host");

            if ($self->{SITEDB}->hasMetricNRPEService($host)) {
                if ($host ne $self->{NRPE_UI}) {
                    $HOST_NRPE_CONFIG = $self->_genNrpeHeader($host);
                    if (!$HOST_NRPE_CONFIG) {
                        return;
                    }
                }
                $self->_genNrpe($SERVICE_CONFIG, $host);
            } 

            my $contactgroup = $self->_getContactGroups ($host);

            my $serviceNo = $self->_genServices($SERVICE_CONFIG, $host, $contactgroup, $servicegroups, $NRPE_CONFIG, $HOST_NRPE_CONFIG);
            if (! defined $serviceNo ) {
                $self->_closeFDs($HOST_CONFIG, $SERVICE_CONFIG, $NRPE_CONFIG);
                close($HOST_NRPE_CONFIG) if ($HOST_NRPE_CONFIG);
                return;
            } else {
                # Generate host even if it doesn't have services
                if ($self->{INCLUDE_EMPTY_HOSTS} || $serviceNo gt 0) {
                    next if (exists $self->{MULTI_SITE_HOSTS}->{$host});
                    $self->{MULTI_SITE_HOSTS}->{$host} = $sitename;
                    my $hostgroup = $self->_getHostGroups ($host, $hostgroups);
                    if ($self->{INCLUDE_HOSTS}) {
                        my $checktype = $self->_getHostCheckType($host) || next;
                        if (! $self->_genHost ($HOST_CONFIG,
                                         $host,
                                         $self->{SITEDB}->hostAddress($host),
                                         $checktype,
                                         $contactgroup,
                                         $hostgroup,
                                         $host,
                                         $parentName) ) {
                            $self->_closeFDs($HOST_CONFIG, $SERVICE_CONFIG, $NRPE_CONFIG);
                            close($HOST_NRPE_CONFIG) if ($HOST_NRPE_CONFIG);
                            return;
                        }
                        $hostNo++;
                    }
                }
            }
            close($HOST_NRPE_CONFIG) if ($HOST_NRPE_CONFIG);
        }

        # Iterate through hosts which have LB nodes
        if ($self->{INCLUDE_LB_NODE}) {
            foreach my $host ($self->{SITEDB}->getRealHosts) {
                next if ($self->{VO_HOST_FILTER} && !$self->_hostHasAnyVO($host));
                
                if ($self->{SITEDB}->hasLBNodes($host)) {
                    my $contactgroup = $self->_getContactGroups ($host);
                    my $hasMetricNRPEService = $self->{SITEDB}->hasMetricNRPEService($host);

                    # Iterate through LB nodes
                    foreach my $lbnode ($self->{SITEDB}->getLBNodes($host)) {
                        my $HOST_NRPE_CONFIG;
                        if (exists $self->{MULTI_SITE_HOSTS}->{$lbnode}) {
                            $self->verbose("  LB node $lbnode is already generated for site " . $self->{MULTI_SITE_HOSTS}->{$lbnode});
                            next;
                        }
                        $self->verbose("  LB node: $lbnode");

                        if ($hasMetricNRPEService) {
                            $HOST_NRPE_CONFIG = $self->_genNrpeHeader($lbnode);
                            if (!$HOST_NRPE_CONFIG) {
                                return;
                            }
                            $self->_genNrpe($SERVICE_CONFIG, $lbnode);
                        }

                        my $serviceNo = $self->_genLBServices ($SERVICE_CONFIG, $lbnode, $host, $contactgroup, $servicegroups, $NRPE_CONFIG, $HOST_NRPE_CONFIG);
                        if (! defined $serviceNo ) {
                            $self->_closeFDs($HOST_CONFIG, $SERVICE_CONFIG, $NRPE_CONFIG);
                            close($HOST_NRPE_CONFIG) if ($hasMetricNRPEService);
                            return;
                        } else {
                            if ($self->{INCLUDE_EMPTY_HOSTS} || $serviceNo gt 0) {
                                $self->{MULTI_SITE_HOSTS}->{$lbnode} = $sitename;
                                my $hostgroup = $self->_getLBHostGroups ($host, $hostgroups);
                                if ($self->{INCLUDE_HOSTS}) {
                                    my $lbaddress = $self->{SITEDB}->LBNodeAddress($host, $lbnode);
                                    my $checktype = $self->_getLBHostCheckType($host,$lbaddress) || next;
                                    if (! $self->_genHost ($HOST_CONFIG,
                                                     $lbnode,
                                                     $lbaddress,
                                                     $checktype,
                                                     $contactgroup,
                                                     $hostgroup,
                                                     $lbnode,
                                                     $parentName) ) {
                                        $self->_closeFDs($HOST_CONFIG, $SERVICE_CONFIG, $NRPE_CONFIG);
                                        close($HOST_NRPE_CONFIG) if ($hasMetricNRPEService);
                                        return;
                                    }
                                    $hostNo++;
                                }
                            }
                        }
                        close($HOST_NRPE_CONFIG) if ($hasMetricNRPEService);
                    }
                }
            }
        }

        # generate parent if any host was generated
        if ($self->{INCLUDE_HOSTS}) {
            my $parent = $self->{SITEDB}->parent;
            if ($parentName) {
                if (!exists $self->{MULTI_SITE_HOSTS}->{$parentName} && $hostNo gt 0) {
                    $hostgroups->{routers}->{fullname} = "Routers";
                    $hostgroups->{routers}->{members}->{$parentName} = 1;
                    my $contactgroup = $self->_getContactGroups();
                    if (! $self->_genHost ($HOST_CONFIG,
                                 $parentName,
                                 $parent->{ADDRESS},
                                 'ncg_check_host_alive',
                                 $contactgroup,
                                 'routers',
                                 $parent->{HOSTNAME}) ) {
                        $self->_closeFDs($HOST_CONFIG, $SERVICE_CONFIG, $NRPE_CONFIG);
                        return;
                    }
                    $self->{MULTI_SITE_HOSTS}->{$parentName} = $sitename;
                }
            }
        }

        # store gathered host and service groups for global configuration
        $self->{HOST_GROUPS} = $hostgroups;
        $self->{SERVICE_GROUPS} = $servicegroups;

        # Generate contacts
        if (! $self->_genContacts() ) {
            $self->_closeFDs($HOST_CONFIG, $SERVICE_CONFIG, $NRPE_CONFIG);
            return;
        }

        $self->_closeFDs($HOST_CONFIG, $SERVICE_CONFIG, $NRPE_CONFIG);

    }

    1;
}

=head1 NAME

NCG::ConfigGen::Nagios

=head1 DESCRIPTION

The NCG::ConfigGen::Nagios module extends NCG::ConfigGen module.
Module generates configuration for Nagios monitoring system.

Module has following requirements on native Nagios configuration:
- resource variable $USER1$ should point to location of
Nagios plugins. If this is not the case, please modify
template commands.template.
- following Nagios plugins are used:
  - check_ping
  - native plugins included in NCG::LocalMetrics modules
  (currently: check_tcp, check_ftp, check_ldap)

Generated configuration should not interfere with the existing
Nagios configuration. Following properties can be used to tune
configuration in case when existing Nagios server is used:
- INCLUDE_HOSTS - defines if hosts configuration is generated

=head1 SYNOPSIS

  use NCG::ConfigGen::Nagios;

  my $ncg = NCG::ConfigGen::Nagios->new( { SITEDB=> $sitedb,
                                           OUTPUT_DIR=>'/etc/nagios/argo-ncg.d' } );

  $ncg->getData();

=cut

=head1 METHODS

=over

=item C<new>

  $ncg = NCG::ConfigGen::Nagios->new( $options );

Creates new NCG::ConfigGen::Nagios instance. Argument $options is hash
reference that can contain following elements:
  BACKUP_INSTANCE - if set SEND_TO_MSG, SEND_TO_DASHBOARD and 
                    ENABLE_NOTIFICATIONS will be set to 0. This variable is
                    used for setting up backup SAM instance (SAM-1127)
  (default: unset)

  CHECK_HOSTS - if set to false NCG will generate configuration without host
  checks. For checking hosts dummy check (ncg_check_host_dummy) that always
  returns OK will be used.
  Warning: Using Nagios without host check will disable host/service dependency,
  meaning that in case of host failure admin will receive notifications
  for all services on host. Set this option to false only if you don't
  care about notifications or if you have different dependencies in place.
  (default: true)

  CHECK_PING - if set to false NCG will not check if host is pingable,
  all hosts will be checked via check_tcp check
  OBSOLETED: check_tcp is not used anymore
  (default: true)

  FORCE_CHECK_PING - if set to true NCG will not check if host is pingable,
  all hosts will be checked via check_ping check
  OBSOLETED: this is controlled only with CHECK_HOSTS, if CHECK_HOSTS is set
  hosts will be checked via check_ping
  (default: false)

  ENABLE_NOTIFICATIONS - if set to true notifications to contact will
  be enabled
  (default: false)

  ENABLE_FLAP_DETECTION - if set to 1 flap detection will be switched on
  (default: 0)
  
  FINAL_OUTPUT_DIR - final output dir where the configuration will be stored
                     this option is used in case that OUTPUT_DIR is just 
                     a temporary location (e.g. ncg.reload.sh). final location
                     is needed for metrics with parameters stored in file
  (default: OUTPUT_DIR)

  GGUS_SERVER_FQDN - if set to valid GGUS server handle_service_change will
                    send notifications to GGUS
                   - furthremore services which publish notifications will
                   have _GGUS custom var added

  GLITE_VERSION - which version of Glite UI the tests will run on.
  (default: UNKNOWN)

  INCLUDE_HOSTS - if true hosts definitions (hosts.cfg) will be
  generated.
  (default: true)

  INCLUDE_EMPTY_HOSTS - if true configuration for hosts without any
  associated services will be generated.
  (default: true)

  INCLUDE_LB_NODE - if true configuration for load balancing nodes
  will be generated.
  (default: false)

  LOCAL_METRIC_STORE - if true configuration for storing results to
  local metric store.
  (default: false)

  MULTI_SITE_GLOBAL - if true only global configuration for multisite
  will be generated. Global configuration consists of:
    - commands definitions (commands.cfg)
    - generic contact nagios-admin and timeperiod (contacts.cfg)
    - Nagios internal checks (wlcg.nagios.cfg)
    - host templates (ncg-generic-host)
    - service templates ncg-generic-service and ncg-passive-service
      (services.cfg)
    - host and service groups
  NOTICE: This is an internal option used only by multisite
  configuration generator. This option shouldn't be set manually,
  otherwise incorrect configuration will be generated.
  (default: false)

  MULTI_SITE_HOSTS - list of hosts which have been included in 
  config generation up to the current step.
  NOTICE: This is an internal option used only by multisite
  configuration generator. This option shouldn't be set manually.
  (default: )

  MULTI_SITE_SITE - if true only single site configuration for
  multisite configuration will be generated. Site level configuration
  consists of:
    - hosts definitions (hosts.cfg)
    - services definitions (services.cfg)
    - site level contacts (contacts.cfg)
  NOTICE: This is an internal option used only by multisite
  configuration generator. This option shouldn't be set manually,
  otherwise incorrect configuration will be generated.
  (default: false)

  MULTI_SITE_SITES - list of sites which will be passed to
  remote gatherers (SAM, NPM). Option contains hash with references
  to previously created Nagios.pm objects with option MULTI_SITE_SITE.
  NOTICE: This is an internal option used only by multisite
  configuration generator. This option shouldn't be set manually.
  (default: )

  MYPROXY_NAME - global name of MyProxy credential which is used to
  regenerate proxy.  This value will be used for all VOs, unless
  MYPROXY_NAME_<VONAME> is set.
  In case when NRPE_UI is set it will be added to MYPROXY_NAME to
  ensure uniqueness. In case when NRPE_UI is not set, NAGIOS_SERVER
  will be used instead.
  Since MYPROXY_NAME must be unique for each credential used, NCG
  will add suffix in the form of "-VONAME" for individual VO.
  (default: NagiosRetrieve-(NAGIOS_SERVER|NRPE_UI)-<VONAME>)

  MYPROXY_NAME_<VONAME> - name of MyProxy credential which is used to
  regenerate proxy VO <VONAME>. VONAME must be defined in upper case, e.g.
  MYPROXY_USER_OPS or MYPROXY_USER_DTEAM.
  (default: see MYPROXY_NAME)

  MYPROXY_USER - Global name of MyProxy account under which the
  credential was stored. This value will be used for all VOs, unless
  MYPROXY_USER_<VONAME> is set.
  (default: nagios)

  MYPROXY_USER_<VONAME> - Name of MyProxy account under which the credential
  for VO VONAME was stored. VONAME must be defined in upper case, e.g.
  MYPROXY_USER_OPS or MYPROXY_USER_DTEAM.
  (default: see MYPROXY_USER)

  NAGIOS_ROLE - defines if this is site-level or multisite-level instance.
              - valid values: site, ROC
  (default: site)

  NAGIOS_SERVER - name of the Nagios server, set this variable if server
  is using name different from hostname()
  (default: hostname()

  NOTIFICATION_HEADER - header which will be set in subject of notification
  emails (e.g. [SAM Nagios] ....)
  (default: SAM Nagios)

  NRPE_UI - set to address of remote UI server which is used to run
  local probes.
  (default: )

  NRPE_OUTPUT_DIR - path where to write NRPE configuration for remote UI.
  This should not be the same as OUTPUT_DIR because Nagios will report
  error when parsing NRPE configuration file. If these are the same,
  generated wlcg.nrpe.cfg should be manually removed before starting
  Nagios.
  WARNING: generated file wlcg.nrpe.cfg must be installed to remote UI
  manually.
  (default: /etc/nagios)

  OUTPUT_DIR - path where to write configuration.
  (default: /etc/nagios/argo-ncg.d)

  PROBES_TYPE - which probes to include in configuration.
                Possible values:
                    local  - only locally executed probes are included.
                             Nagios won't pull results from external
                             monitoring systems (SAM).
                    remote - only remotely executed probes are included.
                             Nagios won't run any active probes. MyProxy
                             settings are not required in this case.
                    all    - all probe types are included.
  (default: all)

  PROXY_FILE - global location where generated proxy credential will be
  stored. This value will be used for all VOs, unless
  PROXY_FILE_<VONAME> is set.
  Since PROXY_FILE must be unique for each VO, NCG will add suffix
  in the for of "-VONAME" for individual VO.
  (default: /etc/nagios/globus/userproxy.pem-<VONAME>)

  PROXY_FILE_<VONAME> - location where generated proxy credential for
  VO <VONAME> will be stored. VONAME must be defined in upper case, e.g.
  MYPROXY_USER_OPS or MYPROXY_USER_DTEAM.
  (default: see PROXY_FILE)

  ROBOT_CERT[_<VONAME>] - Location of robot certificate for VO VONAME is
  stored. VONAME must be defined in upper case, e.g. MYPROXY_USER_OPS or
  MYPROXY_USER_DTEAM.

  ROBOT_KEY[_<VONAME>] - Location of robot certificate key for VO VONAME is
  stored. VONAME must be defined in upper case, e.g. MYPROXY_USER_OPS or
  MYPROXY_USER_DTEAM.

  ROC - name of the region which is being monitored. It will be overwritten
        from the value from SiteInfo module.
  (default: )

  SEND_TO_DASHBOARD - if set handle_service_change will send
                    notifications to dashboard

  SEND_TO_EMAIL - see ENABLE_NOTIFICATIONS
  
  SEND_TO_MSG - if set to 0 obsess handler will not store results to directory
                queue for sending to message bus.
  (default: 1)

  TEMPLATES_DIR - path to templates directory.
  (default: /usr/share/grid-monitoring-config-gen/nagios)

  USE_ROBOT_CERT - configures Nagios to use robot certificates instead of
  MyProxy credentials.
  (default: false)

  VO - which VO credentials should be used for local probes. It is possible
  to define multiple VOs with comma separated list:
    VO = vo1,vo2,vo3,...
  (default: dteam)

  VO_<VO>_DEFAULT_VO_FQAN - if defined NCG will generate all checks for
  listed FQANs on profiles which are not tied to FQANs. In case of
  profiles tied to FQAN NCG will generate checks only for the defined
  FQAN.
  In case when <VO> is not listed in VO parameter it will be ignored.
  (default: none)
  
  VO_HOST_FILTER - if defined NCG will generate configuration only for hosts 
  that support defined VOs.
  (default: 1)

  WLCG_PLUGINS_DIR - location of check_wlcg Nagios plugin which
  is used for running WLCG probes.
  (default: /usr/libexec/grid-monitoring/plugins/nagios)

  WLCG_PROBES_DIR - location of WLCG probes.
  (default: /usr/libexec/grid-monitoring/probes)

Constructor checks if all templates are present and if output directory
is writeable.

=back

=head1 SEE ALSO

NCG::ConfigGen

=cut

1;
