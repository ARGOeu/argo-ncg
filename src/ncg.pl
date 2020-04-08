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

use strict;
use warnings;
use Config::General;
use Getopt::Long;
use NCG::SiteDB;
use File::Copy;
use File::Path;
use Sys::Hostname;
use Fcntl 'LOCK_EX', 'LOCK_NB';

my $DEFAULT_CONFIG_FILE = "/etc/argo-ncg/ncg.conf";
my $DEFAULT_PID_FILE = "/var/run/argo-ncg.pid";
my $DEFAULT_TIMEOUT = 900;
my $VERBOSE;
my $DEBUG;
my $BACKUP_INSTANCE;

# trick taken from http://www.perlmonks.org/?node_id=518209
unless ( flock DATA, LOCK_EX | LOCK_NB ) {
    die("Found active ncg.pl instance. Please stop all ncg.pl instances and try again.");
}

sub verbose {
    my $msg = shift;
    print $msg if $VERBOSE;
}

# single site config functions

sub _invokeNCGObject {
    my $confRef = shift || return;
    my $parent = shift || return;
    my $child = shift || return;
    my $options = shift;
    my $crit = shift;
    my $notifications;
    my @confArr;
    my $objName = $parent . "::" . $child;
    my $obj;

    $notifications = 1 if (
        $options->{SITEDB} && 
        $parent eq 'NCG::ConfigGen' &&
        $options->{SITEDB}->siteName() eq 'nagios');

    eval "use $objName;";
    if ($@) {
        verbose "ERROR: cannot use module $objName, error: $@\n";
        return;
    }

    if(ref($confRef) eq "ARRAY") {
        @confArr = @{$confRef};
    } else {
        @confArr = ($confRef);
    }

    foreach my $instance (@confArr) {
        verbose("Invoking $objName.\n");

        foreach my $opt (keys %$options) {
            $instance->{$opt} = $options->{$opt} unless defined ($instance->{$opt});
        }

        $instance->{VERBOSE} = $VERBOSE;
        $instance->{DEBUG} = $DEBUG;
        $instance->{BACKUP_INSTANCE} = 1 if ($BACKUP_INSTANCE);
        $instance->{OUTPUT_DIR} = $options->{OUTPUT_DIR}
            if exists $options->{OUTPUT_DIR};
        $instance->{FINAL_OUTPUT_DIR} = $options->{FINAL_OUTPUT_DIR}
            if exists $options->{FINAL_OUTPUT_DIR};
        $instance->{ENABLE_NOTIFICATIONS} = 1 if ($notifications);
        $obj = new $objName ($instance);
        next if (!$obj);

        #return if (!$obj->getData() && $crit);
        # Exit program in case of module failure
        # We assume
        if (!$obj->getData() && $crit) {
            alarm(0);
            verbose "Module $objName hit critical error, stopping NCG\n";
            exit 2;
        }
    }

    return $obj;
}

sub invokeNCGObjectExact {
    my $parent = shift || return;
    my $child = shift || return;
    my $options = shift;
    my $crit = shift;

    my $objName = $parent . "::" . $child;
    my $obj;
    my $res;

    eval "use $objName;";
    if ($@) {
        verbose "ERROR: cannot use module $objName, error: $@\n";
        return;
    }

    verbose("Invoking $objName.\n");
    $options->{VERBOSE} = $VERBOSE;
    $options->{DEBUG} = $DEBUG;
    $options->{BACKUP_INSTANCE} = 1 if ($BACKUP_INSTANCE);
    $obj = new $objName ($options);
    $res = $obj->getData() if ($obj);
    if (!$res && $crit) {
        alarm(0);
        verbose "Module $objName hit critical error, stopping NCG\n";
        exit 2;
    }
}

sub invokeNCGObjects {
    my $conf = shift || return;
    my $parent = shift || return;
    my $options = shift;
    my $crit = shift;
    my $sites = shift;
    my $sitename;
    my $confRef;

    if (exists $options->{SITEDB}) {
        $sitename = $options->{SITEDB}->siteName();
    }

    return if (! exists $conf->{$parent});

    if ($sitename && exists $conf->{$parent}->{$sitename}) {
        $confRef = $conf->{$parent}->{$sitename};
    } else {
        $confRef = $conf->{$parent};
    }

    foreach my $confKey ( keys %{$confRef} ) {
        # Skip File modules, they should always be executed the last
        next if ($confKey eq "File" || $confKey eq "JSON");

        # Skip if this is a site config block
        next if ($sites && exists $sites->{$confKey});

        return if (!_invokeNCGObject($confRef->{$confKey}, $parent, $confKey, $options, $crit) && $crit);
    }
    
    invokeNCGObject ($conf, $parent, "File", $options);
    invokeNCGObject ($conf, $parent, "JSON", $options);
    
    1;
}

sub invokeNCGObject {
    my $conf = shift || return;
    my $parent = shift || return;
    my $child = shift || return;
    my $options = shift;
    my $crit = shift;
    my $sitename;
    my $obj;
    my $confRef;

    if (exists $options->{SITEDB}) {
        $sitename = $options->{SITEDB}->siteName();
    }

    return if (! exists $conf->{$parent});

    if ($sitename && exists $conf->{$parent}->{$sitename}) {
        $confRef = $conf->{$parent}->{$sitename};
    } else {
        $confRef = $conf->{$parent};
    }

    if (exists $confRef->{$child}) {
        $obj = _invokeNCGObject($confRef->{$child}, $parent, $child, $options, $crit);
        delete $confRef->{$child};
    }

    return $obj;
}

sub analyzeSite {
    my $conf = shift;
    my $siteDB = shift;
    my $sites = shift;
    my $ncgMetricConfigHash = shift;
    my $options = {SITEDB=>$siteDB};
    $options->{METRIC_CONFIG} = $ncgMetricConfigHash;

    $siteDB->{VERBOSE} = $VERBOSE;
    $siteDB->{DEBUG} = $DEBUG;

    # invoke SAM and GOCDB first in order to get BDII if not defined
    if (!$siteDB->siteLDAP) {
        invokeNCGObject ($conf, "NCG::SiteInfo", "GOCDB", $options, 1);
    }

    # invoke others...
    invokeNCGObjects ($conf, "NCG::SiteInfo", $options, 1, $sites);

    invokeNCGObjects ($conf, "NCG::LocalMetrics", $options, 1, $sites);

    # skip site
    unless ($siteDB->hasMetrics()) {
        print "Site ".$siteDB->siteName()." has no services, skipping configuration.\n";
        return;
    }
    
    # invoke LDAP first otherwise Active will erase SRMs because of
    # missing SE_PATH
    invokeNCGObject ($conf, "NCG::LocalMetricsAttrs", "LDAP", $options, 1 );

    # invoke others...
    invokeNCGObjects ($conf, "NCG::LocalMetricsAttrs", $options, 1, $sites);

    invokeNCGObjects ($conf, "NCG::SiteContacts", $options, 1, $sites);

    1;
}

sub getConfig {
    my $CONFIG_FILE = shift;
    my %options = (-ConfigFile => $CONFIG_FILE, -AllowMultiOptions => 1,
                   -InterPolateVars => 1, -InterPolateEnv => 1,
                   -IncludeGlob => 1, -UseApacheInclude => 1, 
                   -IncludeRelative => 1, -IncludeDirectories => 1);
    my $config = new Config::General(%options);
    if (!$config) {
        alarm(0);
        print "Error reading configuration file!\n";
        exit 2;
    }
    my %conf = $config->getall;

    # set default values
    $conf{NAGIOS_SERVER} = hostname() unless ($conf{NAGIOS_SERVER});
    $conf{VO} = 'dteam' unless ($conf{VO});
    $conf{NAGIOS_ADMIN} = 'root@localhost' unless ($conf{NAGIOS_ADMIN});
    $conf{PROBES_TYPE} = 'all' unless ($conf{PROBES_TYPE});

    $BACKUP_INSTANCE = $conf{BACKUP_INSTANCE} unless ($BACKUP_INSTANCE);

    \%conf;
}

sub analyzeSites {
    my $conf = shift;
    my $confFile = shift;
    my $siteOnly = shift;
    my $outputDir = shift;
    my $finalOutputDir = shift;
    my $ncgMetricConfigHash = shift;
    my $sites = {};
    my $ncgs = {};
    my $siteCount = 0;
    my $hosts = {};

    if (exists $conf->{"NCG::SiteSet"}) {
        invokeNCGObjects ($conf, "NCG::SiteSet", {SITES=>$sites}, 1);
    } else {
        if ($conf->{SITENAME}) {
            $sites->{$conf->{SITENAME}} = new NCG::SiteDB({SITENAME=>$conf->{SITENAME},VERBOSE=>$VERBOSE,DEBUG=>$DEBUG,LDAP_ADDRESS=>$conf->{BDII}});
            if (!$sites->{$conf->{SITENAME}}) {
                alarm(0);
                print "Error creating SiteDB structure!\n";
                exit 2;
            }
        }
    }

    if ($siteOnly) {
        if (!exists $sites->{$siteOnly}) {
            alarm(0);
            print "Site $siteOnly is not in the list of configured sites.\n";
            exit 2;
        }
        my $confLocal = getConfig($confFile);
        $confLocal->{SITENAME} = $sites->{$siteOnly}->siteName;
        $confLocal->{BDII} = $sites->{$siteOnly}->siteLDAP;
        return unless(analyzeSite($confLocal, $sites->{$siteOnly}, $sites, $ncgMetricConfigHash));

        unless ($ncgs->{$siteOnly} = invokeNCGObject ($confLocal, "NCG::ConfigGen", "Nagios",
                                                        {SITEDB=>$sites->{$siteOnly}, MULTI_SITE_SITE=>1,
                                                        NRPE_UI=>$confLocal->{NRPE_UI}, NAGIOS_SERVER=>$confLocal->{NAGIOS_SERVER},
                                                        VO=>$confLocal->{VO}, PROBES_TYPE=>$confLocal->{PROBES_TYPE}, 
                                                        BACKUP_INSTANCE=>$BACKUP_INSTANCE, OUTPUT_DIR=>$outputDir, 
                                                        FINAL_OUTPUT_DIR=>$finalOutputDir}, 1)) {
            alarm(0);
            print "Error generating configuration for site $confLocal->{SITENAME}\n";
            exit 2;
        }
    } else {
        foreach my $site (keys %$sites) {
            my $confLocal = getConfig($confFile);
            $confLocal->{SITENAME} = $sites->{$site}->siteName;
            $confLocal->{BDII} = $sites->{$site}->siteLDAP;
            $siteCount++;
            
            next unless(analyzeSite($confLocal, $sites->{$site}, $sites, $ncgMetricConfigHash));

            unless ($ncgs->{$site} = invokeNCGObject ($confLocal, "NCG::ConfigGen", "Nagios",
                                                    {SITEDB=>$sites->{$site}, MULTI_SITE_SITE=>1,
                                                    MULTI_SITE_HOSTS=>$hosts,NRPE_UI=>$confLocal->{NRPE_UI},
                                                    NAGIOS_SERVER=>$confLocal->{NAGIOS_SERVER},
                                                    VO=>$confLocal->{VO}, PROBES_TYPE=>$confLocal->{PROBES_TYPE},
                                                    BACKUP_INSTANCE=>$BACKUP_INSTANCE, OUTPUT_DIR=>$outputDir,
                                                    FINAL_OUTPUT_DIR=>$finalOutputDir}, 1)) {
                alarm(0);
                print "Error generating configuration for site $confLocal->{SITENAME}\n";
                exit 2;
            }
        }
        if ( $siteCount == 0 ) {
            print "WARNING: NCG::SiteSet modules didn't find any sites.\n";
        }

        my $confLocal = getConfig($confFile);

        createNagiosSite($confLocal, $ncgs, $hosts, $outputDir, $finalOutputDir, $ncgMetricConfigHash);

        invokeNCGObject ($conf, "NCG::ConfigGen", "Nagios",
                                            {MULTI_SITE_GLOBAL=>1, MULTI_SITE_SITES=>$ncgs,
                                            MULTI_SITE_HOSTS=>$hosts,NRPE_UI=>$confLocal->{NRPE_UI},
                                            NAGIOS_SERVER=>$confLocal->{NAGIOS_SERVER},
                                            VO=>$confLocal->{VO}, PROBES_TYPE=>$confLocal->{PROBES_TYPE}, 
                                            BACKUP_INSTANCE=>$BACKUP_INSTANCE, OUTPUT_DIR=>$outputDir,
                                            FINAL_OUTPUT_DIR=>$finalOutputDir}, 1);

    }
}

sub createNagiosSite {
    my $confLocal = shift;
    my $ncgs = shift;
    my $hosts = shift;
    my $outputDir = shift;
    my $finalOutputDir = shift;
    my $ncgMetricConfigHash = shift;
    my $siteDB;

    $siteDB = new NCG::SiteDB({SITENAME=>'nagios',VERBOSE=>$VERBOSE,DEBUG=>$DEBUG});
    if (!$siteDB) {
        alarm(0);
        print "Error creating SiteDB structure!\n";
        exit 2;
    }

    # SiteInfo mimic
    $siteDB->addHost($confLocal->{NAGIOS_SERVER});
    $siteDB->addHost($confLocal->{MYPROXY_SERVER}) if ($confLocal->{MYPROXY_SERVER});
    $siteDB->addService($confLocal->{NAGIOS_SERVER}, 'NAGIOS');
    $siteDB->addService($confLocal->{MYPROXY_SERVER}, 'MyProxy') if ($confLocal->{MYPROXY_SERVER});
    if (exists $confLocal->{NRPE_UI}) {
        $siteDB->addHost($confLocal->{NRPE_UI});
        $siteDB->addService($confLocal->{NRPE_UI}, 'NRPE');
    }
    $confLocal->{VO} =~ s/^\s+//;
	$confLocal->{VO} =~ s/\s+$//;
    foreach my $vo ( split (/\s*,\s*/, $confLocal->{VO}) ) {
        $siteDB->addVO($confLocal->{NAGIOS_SERVER}, 'NAGIOS', $vo);
        $siteDB->addVO($confLocal->{MYPROXY_SERVER}, 'MyProxy', $vo) if ($confLocal->{MYPROXY_SERVER});
    }

    # SiteContact mimic
    $siteDB->addContact($confLocal->{NAGIOS_ADMIN});

    invokeNCGObject ($confLocal, "NCG::SiteContacts", "File", {SITEDB=>$siteDB}, 1);

    # LocalMetrics
    invokeNCGObjectExact ("NCG::LocalMetrics", "Hash",
                          {  PROFILE=>'internal',
                             SITEDB=>$siteDB,
                             METRIC_CONFIG=>$ncgMetricConfigHash,
                             INCLUDE_PROXY_CHECKS=>$confLocal->{INCLUDE_PROXY_CHECKS},
                             INCLUDE_EGI_CHECKS=>$confLocal->{INCLUDE_EGI_CHECKS},
                             INCLUDE_IGTF_CHECKS=>$confLocal->{INCLUDE_IGTF_CHECKS}},
                          1);
    invokeNCGObject ($confLocal, "NCG::LocalMetrics", "File", {SITEDB=>$siteDB, METRIC_CONFIG=>$ncgMetricConfigHash}, 1);

    invokeNCGObject ($confLocal,
                                 "NCG::LocalMetricsAttrs",
                                 "Active",
                                 {  SITEDB => $siteDB,
                                    NRPE_UI => $confLocal->{NRPE_UI},
                                    MYPROXY_SERVER => $confLocal->{MYPROXY_SERVER},
                                    PROBES_TYPE=>$confLocal->{PROBES_TYPE},
                                    MULTI_SITE_SITES=>$ncgs},
                                 1);
    invokeNCGObject ($confLocal, "NCG::LocalMetricsAttrs", "File", {SITEDB=>$siteDB}, 1);

    # LocalMetricsAttrs
    unless ($ncgs->{'nagios'}= invokeNCGObject ($confLocal, "NCG::ConfigGen", "Nagios",
                                        {SITEDB=>$siteDB, MULTI_SITE_SITE=>1, MULTI_SITE_HOSTS=>$hosts,
                                        NRPE_UI=>$confLocal->{NRPE_UI}, NAGIOS_SERVER=>$confLocal->{NAGIOS_SERVER},
                                        VO=>$confLocal->{VO}, PROBES_TYPE=>$confLocal->{PROBES_TYPE},
                                        OUTPUT_DIR=>$outputDir, FINAL_OUTPUT_DIR=>$finalOutputDir}, 1)) {
        alarm(0);
        print "Error generating configuration for nagios site.\n";
        exit 2;
    }

}

#################################
#   Main program
#################################

my $help;
my $siteName;
my $CONFIG_FILE;
my $PID_FILE;
my $timeout;
my ($outputDir,$finalOutputDir,$outputDirBackup);
my $options;

local $SIG{ALRM} = sub {
    print "Timeout occured ($timeout)\n";
    exit 2;
};

if (!GetOptions (
    'h' => \$help, 'help' => \$help,
    'v' => \$VERBOSE, 'verbose' => \$VERBOSE,
    'd' => \$DEBUG, 'debug' => \$DEBUG,
    't=i' => \$timeout, 'timeout=i' => \$timeout,
    'site=s' => \$siteName,
    'config=s' => \$CONFIG_FILE,
    'pid=s' => \$PID_FILE,
    'output-dir=s' => \$outputDir,
    'final-output-dir=s' => \$finalOutputDir,
    'backup-instance' => \$BACKUP_INSTANCE) ) {
    exit 0;
}

if ($help) {
    print "
Nagios configuration generator (WLCG probe based)

    Options:
        --config STRING
            Path to generated configuration file.
            For detailed description of options for
            individual modules see perldoc.
            (default: $DEFAULT_CONFIG_FILE)
        --pid STRING
            Path to pid file. Pid file is touched
            after successful ncg run.
            (default: $DEFAULT_PID_FILE)
        --site STRING
            Generate config only for a single site.
            Option is used only in case of multsite
            Nagios instance.
            In case of single site configuration
            existing output directory will not be
            cleaned.
            (default: )

        -t, --timeout INT
            Timeout period after which ncg.pl will
            exit. Timeout is expressed in seconds.
            (default: $DEFAULT_TIMEOUT)

        --backup-instance
            If set variable BACKUP_INSTANCE will
            be set on all NCG modules. See SAM-1127.
            Argument overrides global value in
            configuration file.
            (default: )

        --output-dir STRING
            If set configuration will be generated
            to output dir instead of OUTPUT_DIR in
            block NCG::ConfigGen::Nagios.
            (default: )
            
        --final-output-dir STRING
            If set configuration will be generated
            to output dir instead of FINAL_OUTPUT_DIR in
            block NCG::ConfigGen::Nagios.
            (default: output-dir)

        -h, --help
            Basic program description

        -v, --verbose
            Print verbose logging information

        -d, --debug
            Print detailed program execution flow

NCG will create backup directory of generated output directory.
Backup directory will have suffix .ncg.backup.

";
    exit 0;
}

if (!defined $CONFIG_FILE) {
    $CONFIG_FILE = $DEFAULT_CONFIG_FILE;
}
if (!defined $PID_FILE) {
    $PID_FILE = $DEFAULT_PID_FILE;
}
if (!defined $timeout) {
    $timeout = $DEFAULT_TIMEOUT;
}

alarm($timeout);

my $conf = getConfig($CONFIG_FILE);

# Backup output directory
unless ($outputDir) {
    if (exists $conf->{"NCG::ConfigGen"} &&
        exists $conf->{"NCG::ConfigGen"}->{Nagios} &&
        $conf->{"NCG::ConfigGen"}->{"Nagios"}->{OUTPUT_DIR}
        ) {
        $outputDir = $conf->{"NCG::ConfigGen"}->{"Nagios"}->{OUTPUT_DIR};
        $outputDir =~ s/\/\s*$//;
    } else {
        $outputDir = "/etc/nagios/argo-ncg.d";
    }
}
unless($finalOutputDir) {
    $finalOutputDir = $outputDir;
}

$outputDirBackup = "$outputDir.ncg.backup";
if ( -d $outputDir && -d $outputDirBackup ) {
    rmtree($outputDirBackup);
}
if ( -d $outputDir ) {
    move($outputDir, $outputDirBackup);
}

$options->{METRIC_CONFIG} = {};
invokeNCGObjects ($conf, "NCG::MetricConfig", $options, 1);

# here we're dealing with multisite configuration
analyzeSites($conf, $CONFIG_FILE, $siteName, $outputDir, $finalOutputDir, $options->{METRIC_CONFIG});

unless ( -f $PID_FILE ) {
    die("Could not open pid file $PID_FILE.\n") unless (open(PID_FILE_HNDL, ">$PID_FILE"));
    die("Could not close pid file $PID_FILE.\n") unless (close(PID_FILE_HNDL));
} else {
    my $mtime = time;
    die("Touching pid file $PID_FILE failed.\n") unless (utime ($mtime, $mtime, $PID_FILE));
}

alarm(0);

### DO NOT REMOVE THE FOLLOWING LINES ###
__DATA__
Locking section
DO NOT REMOVE THESE LINES!
