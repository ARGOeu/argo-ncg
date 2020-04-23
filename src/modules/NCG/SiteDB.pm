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

package NCG::SiteDB;
use strict;
use Socket;
use NCG;
use vars qw(@ISA);

@ISA=("NCG");

sub new
{
    my $proto  = shift;
    my $class  = ref($proto) || $proto;
    my $self =  $class->SUPER::new(@_);
    $self->{METRIC_COUNT} = 0;
    $self;
}

# Add methods

sub addParent {
    my $self = shift;
    my $host = shift or return;
    my $ip = shift;
    
    if (!$ip) {
        my ($hostReal, $aliases, $addrtype, $length, @addrs);

        unless ( ($hostReal, $aliases, $addrtype, $length, @addrs) = gethostbyname($host)) {
            return;
        }

        $ip = join ('.', unpack('C4', $addrs[0]));
    }

    $self->verbose ("Found site parent: $host, $ip.");
    $self->{PARENT} = {HOSTNAME=>$host, ADDRESS=>$ip};
    1;
}

sub addHost
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $id = shift;
    my $fullname;

    if ($id) {
        $fullname = "${host}_${id}";
    } else {
        $fullname = $host;
    }
    
    if (! exists $self->{HOSTS}->{$fullname}) {
        my ($hostReal, $aliases, $addrtype, $length, @addrs);

        ($hostReal, $aliases, $addrtype, $length, @addrs) = gethostbyname($host);
        if ($#addrs) {
            $self->{HOSTS}->{$fullname}->{ADDRESS} = $host;
        } else {
            $self->{HOSTS}->{$fullname}->{ADDRESS} = join ('.', unpack('C4', $addrs[0]));
        }
        $self->{HOSTS}->{$fullname}->{ID} = $id if ($id);
        $self->{HOSTS}->{$fullname}->{HOSTNAME} = $host;
    }

    1;
}

sub addService
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $service = shift || return;

    # host is in HOSTS
    if (exists $self->{HOSTS}->{$host}) {
        if (! exists $self->{HOSTS}->{$host}->{SERVICES}->{$service}) {
            $self->{HOSTS}->{$host}->{SERVICES}->{$service} = {};
        }
    }
    # host doesn't exist, this is not allowed
    else {
        $self->warning ("Host $host is not in the list of hosts on site!");
        return;
    }

    1;
}

sub addVO
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $service = shift || return;
    my $vo = shift;
    
    # host is in HOSTS, add service/VO
    if (exists $self->{HOSTS}->{$host}) {
        # if service is not on the host return error
        if (! exists $self->{HOSTS}->{$host}->{SERVICES}->{$service} ) {
            $self->warning ("Service $service is not present on host $host!");
            return;
        }
        
        $self->{HOSTS}->{$host}->{SERVICES}->{$service}->{VOS}->{$vo} = 0;
    }
    # host doesn't exist, this is not allowed
    else {
        $self->warning ("Host $host is not in the list of hosts on site!");
        return;
    }    

    1;
}

# add remote metric (TODO: this should be removed)
sub addRemoteMetric
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift;
    my $metric = shift;
    my $remoteService = shift;
    my $url = shift;
    my $docUrl = shift;
    my $vo = shift;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning ("Host $host is not in the list of hosts on site!");
        return;
    }

    $self->{HOSTS}->{$host}->{METRICS}->{$metric} = {};
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{TYPE} = "remote";
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{REMOTESERVICE} = $remoteService;
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{URL} = $url;
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{DOCURL} = $docUrl;
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{VO} = $vo;

    $self->{METRIC_COUNT}++;
    
    1;
}

# add remote metric (TODO: this should be removed)
sub addRemoteMetricLong {
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift;
    my $metric = shift;
    my $remoteService = shift;
    my $config = shift;
    my $url = shift;
    my $docUrl = shift;
    my $vo = shift;
    my $dependencies = shift;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning ("Host $host is not in the list of hosts on site!");
        return;
    }

    $self->{HOSTS}->{$host}->{METRICS}->{$metric} = {};
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{TYPE} = "remote";
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{REMOTESERVICE} = $remoteService;
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{CONFIG} = $config;
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{URL} = $url;
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{DOCURL} = $docUrl;
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{VO} = $vo;
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{DEPENDENCIES} = $dependencies;
    
    $self->{METRIC_COUNT}++;
    
    1;
}


# add local metric
sub addLocalMetric
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift;
    my $metric = shift;
    my $service = shift || "Undefined";
    my $probe = shift;
    my $config = shift;
    my $attributes = shift;
    my $parameters = shift;
    my $dependencies = shift;
    my $flags = shift;
    my $parent = shift;
    my $docUrl = shift;
    my $vo = shift;
    my $voFqan = shift || '_ALL_';

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning ("Host $host is not in the list of hosts on site!");
        return;
    }

    if (exists $self->{HOSTS}->{$host}->{METRICS}->{$metric}) {
        $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{SERVICES}->{$service} = 1;
        $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{VOS}->{$vo}->{$voFqan} = 1 if ($vo);
        return 1;
    }

    $self->{HOSTS}->{$host}->{METRICS}->{$metric} = {};
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{TYPE} = "local";

    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{SERVICES}->{$service} = 1;
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{PROBE} = $probe;
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{DEPENDENCIES} = $dependencies;
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{FLAGS} = $flags;
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{DOCURL} = $docUrl;
    $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{VOS}->{$vo}->{$voFqan} = 1 if ($vo);

    if ($self->{HOSTS}->{$host}->{METRICS}->{$metric}->{FLAGS}->{PASSIVE}) {
        if ($parent) {
            $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{PARENT} = $parent;
        }
    } else {
        $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{CONFIG} = $config;
        $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{ATTRIBUTES} = $attributes;
        $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{PARAMETERS} = $parameters;
    }
    
    $self->{METRIC_COUNT}++;

    1;
}

sub addContact
{
    my $self = shift;

    $self->debugSub(@_);

    my $value = shift || return;
    my $enabled = shift || 0;

    $self->{CONTACTS}->{$value} = $enabled;

    1;
}

sub addVoFqan
{
    my $self = shift;

    $self->debugSub(@_);

    my $vo = shift || return;
    my $voFqan = shift || return;

    $self->{VO_FQANS}->{$vo}->{$voFqan} = 1;

    1;
}

sub addUser
{
    my $self = shift;

    $self->debugSub(@_);

    my $dn = shift || return;
    my $name = shift || return;
    my $email = shift || return;

    $self->{USERS}->{$dn} = {EMAIL => $email, NAME => $name};

    1;
}

# Add host contact
sub addHostContact
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $value = shift || return;
    my $enabled = shift || 0;

    if (exists $self->{CONTACTS}->{$value})
    {
        $self->warning ("Contact is already in site contacts.");
        return;
    }

    if (exists $self->{HOSTS}->{$host} ) {
        $self->{HOSTS}->{$host}->{CONTACTS}->{$value} = $enabled;
    } else {
        $self->warning ("Host $host is not in the list of hosts on site!");
        return;
    }

    1;
}

sub addServiceContact
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $service = shift || return;
    my $value = shift || return;

    if (exists $self->{CONTACTS}->{$value})
    {
        $self->warning ("Contact is already in site contacts.");
        return;
    }

    if (exists $self->{HOSTS}->{$host} ) {
        if (exists $self->{HOSTS}->{$host}->{CONTACTS}->{$value}) {
            $self->warning ("Contact is already in host contacts.");
            return;
        }
        $self->{HOSTS}->{$host}->{SERVICE_CONTACTS}->{$service}->{$value} = 1;
    } else {
        $self->warning ("Host $host is not in the list of hosts on site!");
        return;
    }

    1;
}

sub addServiceFlavourContact
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $service = shift || return;
    my $value = shift || return;
    my $enabled = shift || 0;

    if (exists $self->{CONTACTS}->{$value})
    {
        $self->warning ("Contact is already in site contacts.");
        return;
    }

    if (exists $self->{HOSTS}->{$host} ) {
        if (exists $self->{HOSTS}->{$host}->{CONTACTS}->{$value}) {
            $self->warning ("Contact is already in host contacts.");
            return;
        }
        $self->{HOSTS}->{$host}->{SERVICE_FLAVOUR_CONTACTS}->{$service}->{$value} = $enabled;
    } else {
        $self->warning ("Host $host is not in the list of hosts on site!");
        return;
    }

    1;
}

sub addRemoteService
{
    my $self = shift;

    $self->debugSub(@_);

    my $value = shift || return;

    $self->{REMOTESERVICES}->{$value} = 1;

    1;
}

# Remove methods
sub removeHost
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning ("Host $host is not in the list of hosts on site!");
        return;
    }

    delete $self->{HOSTS}->{$host};

    1;
}

sub removeService
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift;
    my $service = shift  || return;

    if (!$host) {
        foreach my $hostname (keys %{$self->{HOSTS}}) {
            delete $self->{HOSTS}->{$hostname}->{SERVICES}->{$service};
        }
    } else {
        if (exists $self->{HOSTS}->{$host} ) {
            delete $self->{HOSTS}->{$host}->{SERVICES}->{$service};
        } else {
            $self->warning ("Host $host is not in the list of hosts on site!");
            return;
        }
    }

    1;
}

sub removeMetric
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift;
    my $service = shift;
    my $metric = shift || return;

    # if host is undefined, remove metric from all hosts
    if (!$host) {
        foreach my $hostname (keys %{$self->{HOSTS}}) {
            # if service is defined check if host has the service first
            if (!$service || (exists $self->{HOSTS}->{$hostname}->{METRICS}->{$metric} && exists $self->{HOSTS}->{$hostname}->{METRICS}->{$metric}->{SERVICES}->{$service})) {
                delete $self->{HOSTS}->{$hostname}->{METRICS}->{$metric};
            }
        }
    } else {
        # host is defined, check if it exists
        if (exists $self->{HOSTS}->{$host} ) {
            if (!$service || (exists $self->{HOSTS}->{$host}->{METRICS}->{$metric} && exists $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{SERVICES}->{$service})) {
                delete $self->{HOSTS}->{$host}->{METRICS}->{$metric};
            }
        } else {
            $self->warning ("Host $host is not in the list of hosts on site!");
            return;
        }
    }

    1;
}

sub removeContact
{
    my $self = shift;

    $self->debugSub(@_);

    my $value = shift || return;

    delete $self->{CONTACTS}->{$value};

    1;
}

# Accessor methods

sub siteName
{
    my $self = shift;

    $self->debugSub(@_);

    my $value = shift;

    $self->{SITENAME} = $value if (defined $value);
    $self->{SITENAME};
}

sub siteROC
{
    my $self = shift;

    $self->debugSub(@_);

    my $value = shift;

    $self->{ROC} = $value if (defined $value);
    $self->{ROC};
}

sub siteLDAP
{
    my $self = shift;
    
    $self->debugSub(@_);

    my $value = shift;

    $self->{LDAP_ADDRESS} = $value if (defined $value);
    $self->{LDAP_ADDRESS};
}

sub siteCountry
{
    my $self = shift;

    $self->debugSub(@_);

    my $value = shift;

    $self->{COUNTRY} = $value if (defined $value);
    $self->{COUNTRY};
}

sub addSiteGrid
{
    my $self = shift;

    $self->debugSub(@_);

    my $value = shift || return;

    $self->{GRIDS}->{$value} = 1;
    $self->{GRIDS};
}

# global attributes
sub globalAttribute
{
    my $self = shift;

    $self->debugSub(@_);

    my $attribute = shift || return;
    my $value = shift;

    $self->{ATTRIBUTES}->{$attribute}->{VALUE} = $value if (defined $value);
    $self->{ATTRIBUTES}->{$attribute}->{VALUE};
}


sub hostAttribute
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $attribute = shift || return;
    my $value = shift;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return;
    }

    $self->{HOSTS}->{$host}->{ATTRIBUTES}->{$attribute}->{VALUE} = $value if (defined $value);
    # if attribute doesn't exist check if global attribute exists
    if (!exists $self->{HOSTS}->{$host}->{ATTRIBUTES}->{$attribute}->{VALUE}) {
        return $self->globalAttribute($attribute);
    } else {
        return $self->{HOSTS}->{$host}->{ATTRIBUTES}->{$attribute}->{VALUE};
    }
}

# set attribute for all hosts with a given hostname
sub setHostAttributeByHostName
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $attribute = shift || return;
    my $value = shift || return;

    if (exists $self->{HOSTS}->{$host} ) {
        $self->{HOSTS}->{$host}->{ATTRIBUTES}->{$attribute}->{VALUE} = $value;
    }
    foreach my $hostname (keys %{$self->{HOSTS}}) {
        if ($self->{HOSTS}->{$hostname}->{HOSTNAME} eq $host) {
            $self->{HOSTS}->{$hostname}->{ATTRIBUTES}->{$attribute}->{VALUE} = $value;
        }
    }
}

sub globalAttributeVO
{
    my $self = shift;

    $self->debugSub(@_);

    my $attribute = shift || return;
    my $vo = shift || return;
    my $value = shift;

    $self->{ATTRIBUTES}->{$attribute}->{VOS}->{$vo} = $value if (defined $value);
    $self->{ATTRIBUTES}->{$attribute}->{VOS}->{$vo};
}

sub hostAttributeVO
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift;
    my $attribute = shift;
    my $vo = shift;
    my $value = shift;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return;
    }

    $self->{HOSTS}->{$host}->{ATTRIBUTES}->{$attribute}->{VOS}->{$vo} = $value if (defined $value);

    if (!exists $self->{HOSTS}->{$host}->{ATTRIBUTES}->{$attribute}->{VOS}->{$vo}) {
        return $self->globalAttributeVO($attribute,$vo);
    } else {
        return $self->{HOSTS}->{$host}->{ATTRIBUTES}->{$attribute}->{VOS}->{$vo};
    }
}

# set VO attribute for all hosts with a given hostname
sub setHostAttributeVOByHostName
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $attribute = shift || return;
    my $vo = shift;
    my $value = shift || return;

    if (exists $self->{HOSTS}->{$host} ) {
        $self->{HOSTS}->{$host}->{ATTRIBUTES}->{$attribute}->{VOS}->{$vo} = $value;
    }
    foreach my $hostname (keys %{$self->{HOSTS}}) {
        if ($self->{HOSTS}->{$hostname}->{HOSTNAME} eq $host) {
            $self->{HOSTS}->{$hostname}->{ATTRIBUTES}->{$attribute}->{VOS}->{$vo} = $value;
        }
    }
}

sub addHostAttributeArray
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $attribute = shift || return;
    my $value = shift || return;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return;
    }

    $self->{HOSTS}->{$host}->{ATTRIBUTES_ARRAY}->{$attribute}->{VALUE}->{$value} = 1;
}

sub addHostAttributeArrayVO
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $attribute = shift || return;
    my $vo = shift || return;
    my $value = shift || return;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return;
    }

    $self->{HOSTS}->{$host}->{ATTRIBUTES_ARRAY}->{$attribute}->{VOS}->{$vo}->{$value} = 1 if (defined $value);
}

# Metric methods

sub _metricField
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift;
    my $metric = shift;
    my $attr = shift;
    my $value = shift;

    # host is in HOSTS
    if (exists $self->{HOSTS}->{$host}) {
        if (exists $self->{HOSTS}->{$host}->{METRICS}->{$metric}) {
            return $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{$attr};
        } else {
            $self->warning ("Metric $metric is not present on host $host!");
            return;
        }
    }
    # host doesn't exist, this is not allowed
    else {
        $self->warning ("Host $host is not in the list of hosts on site!");
        return;
    }
}

sub _metricHashField
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $attr = shift || return;
    my $flag = shift || return;
    my $value = shift;

    my $flags = $self->_metricField ($host, $metric, $attr);

    return unless ($flags);
    if (defined $value) {
        $flags->{$flag} = $value;
        return $flags->{$flag};
    }
    return $flags->{$flag} if (exists $flags->{$flag});
}

sub metricType
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $value = shift;

    $self->_metricField ($host, $metric, "TYPE", $value);
}

sub metricDocUrl
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $value = shift;

    $self->_metricField ($host, $metric, "DOCURL", $value);
}

sub metricProbe
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $value = shift;
    
    $self->_metricField ($host, $metric, "PROBE", $value);
}

sub metricRemoteService
{
    my $self = shift;
    
    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $value = shift;

    $self->_metricField ($host, $metric, "REMOTESERVICE", $value);
}

sub metricUrl
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $value = shift;

    $self->_metricField ($host, $metric, "URL", $value);
}

sub metricParent
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $value = shift;

    $self->_metricField ($host, $metric, "PARENT", $value);
}

sub metricVo
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $value = shift;

    $self->_metricField ($host, $metric, "VO", $value);
}

# hash fields
# if value is set it will reset the whole hash
# returns keys of hash

#these return keys:
# metricServices
# metricVoFqans
#
#return hash:
# metricConfig
# metricAttributes
# metricParameters
# metricDependencies

sub metricServices
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $value = shift;

    my $res = $self->_metricField ($host, $metric, "SERVICES", $value);

    if (ref $res eq "HASH") {
        return keys %$res;
    } else {
        return ();
    }
}

sub metricVoFqans
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;

    my $res = $self->_metricField ($host, $metric, "VOS");

    if (ref $res eq "HASH") {
        return $res;
    } else {
        return {};
    }
}

sub addMetricVoFqans
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $vo = shift || return;    
    my $voFqan = shift || '_ALL_';
    
    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning ("Host $host is not in the list of hosts on site!");
        return;
    }

    if (exists $self->{HOSTS}->{$host}->{METRICS}->{$metric}) {
        $self->{HOSTS}->{$host}->{METRICS}->{$metric}->{VOS}->{$vo}->{$voFqan} = 1;
        return 1;
    }  else {
        $self->warning ("Metric $metric doesn't exist on host $host!");
        return;
    }
}


sub metricConfig
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $value = shift;

    $self->_metricField ($host, $metric, "CONFIG", $value);
}

sub defaultConfig
{
    my $self = shift;

    $self->debugSub(@_);

    my $config = {
        path => '/usr/lib64/nagios/plugins',
        interval => 60,
        timeout => 60,
        retryInterval => 5,
        maxCheckAttempts => 3
    };
    
    return $config;
}

sub metricConfigValue
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift;
    my $metric = shift || return;
    my $conf = shift || return;
    my $value = shift;

    if (!$host) {
        foreach my $hostname (keys %{$self->{HOSTS}}) {
            if (exists $self->{HOSTS}->{$hostname}->{METRICS}->{$metric}) {
                $self->_metricHashField ($hostname, $metric, "CONFIG", $conf, $value);
            }
        }
        if (exists $self->{METRICS}->{$metric}) {
            $self->{METRICS}->{$metric}->{CONFIG}->{$conf} = $value;
        }
    } else {
        $self->_metricHashField ($host, $metric, "CONFIG", $conf, $value);
    }
}

sub metricAttributes
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $value = shift;

    $self->_metricField ($host, $metric, "ATTRIBUTES", $value);
}

sub metricAttribute
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift;
    my $metric = shift || return;
    my $attr = shift || return;    
    my $value = shift;

    if (!$host) {
        foreach my $hostname (keys %{$self->{HOSTS}}) {
            if (exists $self->{HOSTS}->{$hostname}->{METRICS}->{$metric}) {
                $self->_metricHashField ($hostname, $metric, "ATTRIBUTES", $attr, $value);
            }
        }
        if (exists $self->{METRICS}->{$metric}) {
            $self->{METRICS}->{$metric}->{ATTRIBUTES}->{$attr} = $value;
        }
    } else {
        $self->_metricHashField ($host, $metric, "ATTRIBUTES", $attr, $value);
    }
}

sub metricParameters
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $value = shift;

    $self->_metricField ($host, $metric, "PARAMETERS", $value);
}

sub metricParameter
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift;
    my $metric = shift || return;
    my $param = shift || return;    
    my $value = shift;

    if (!$host) {
        foreach my $hostname (keys %{$self->{HOSTS}}) {
            if (exists $self->{HOSTS}->{$hostname}->{METRICS}->{$metric}) {
                $self->_metricHashField ($hostname, $metric, "PARAMETERS", $param, $value);
            }
        }
        if (exists $self->{METRICS}->{$metric}) {
            $self->{METRICS}->{$metric}->{PARAMETERS}->{$param} = $value;
        }
    } else {
        $self->_metricHashField ($host, $metric, "PARAMETERS", $param, $value);
    }
}

sub metricDependencies
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $value = shift;

    $self->_metricField ($host, $metric, "DEPENDENCIES", $value);
}

sub metricDependency
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift;
    my $metric = shift || return;
    my $dep = shift || return;
    my $value = shift;

    if (!$host) {
        foreach my $hostname (keys %{$self->{HOSTS}}) {
            if (exists $self->{HOSTS}->{$hostname}->{METRICS}->{$metric}) {
                $self->_metricHashField ($hostname, $metric, "DEPENDENCIES", $dep, $value);
            }
        }
        if (exists $self->{METRICS}->{$metric}) {
            $self->{METRICS}->{$metric}->{DEPENDENCIES}->{$dep} = $value;
        }
    } else {
        $self->_metricHashField ($host, $metric, "DEPENDENCIES", $dep, $value);
    }
}

sub metricFlag
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift;
    my $metric = shift || return;
    my $flag = shift || return;
    my $value = shift;

    if (!$host) {
        foreach my $hostname (keys %{$self->{HOSTS}}) {
            if (exists $self->{HOSTS}->{$hostname}->{METRICS}->{$metric}) {
                $self->_metricHashField ($hostname, $metric, "FLAGS", $flag, $value);
            }
        }
        if (exists $self->{METRICS}->{$metric}) {
            $self->{METRICS}->{$metric}->{FLAG}->{$flag} = $value;
        }
    } else {
        $self->_metricHashField ($host, $metric, "FLAGS", $flag, $value);
    }
}

sub parent
{
    my $self = shift;

    $self->debugSub(@_);

    if (!exists $self->{PARENT}) {
        return;
    }

    $self->{PARENT};
}

# read-only
sub hostAddress
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    
    if (!exists $self->{HOSTS}->{$host} ) {
        $self->error ("Host $host is not in the list of hosts on site!");
        return;
    }

    $self->{HOSTS}->{$host}->{ADDRESS};    
}

# read-only
sub hostName 
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->error ("Host $host is not in the list of hosts on site!");
        return;
    }

    $self->{HOSTS}->{$host}->{HOSTNAME};
}

sub userName
{
    my $self = shift;

    $self->debugSub(@_);

    my $user = shift || return;

    if (!exists $self->{USERS}->{$user} ) {
        $self->error ("User $user is not in the list of users on site!");
        return;
    }

    $self->{USERS}->{$user}->{NAME};
}

sub userEmail
{
    my $self = shift;

    $self->debugSub(@_);

    my $user = shift || return;

    if (!exists $self->{USERS}->{$user} ) {
        $self->error ("User $user is not in the list of users on site!");
        return;
    }

    $self->{USERS}->{$user}->{EMAIL};
}

# iterator methods

sub getHosts
{
    my $self = shift;

    $self->debugSub(@_);

    if (exists $self->{HOSTS}) {
        return keys %{$self->{HOSTS}};
    } else {
        return ();
    }
}

sub getServices
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;

    if (exists $self->{HOSTS}->{$host}) {
        return keys %{$self->{HOSTS}->{$host}->{SERVICES}};
    } else {
        return ();
    }
}

sub getVOsByHostService
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return ();
    my $service = shift || return ();

    if (exists $self->{HOSTS}->{$host}) {
        if (exists $self->{HOSTS}->{$host}->{SERVICES}->{$service}) {
            return keys %{$self->{HOSTS}->{$host}->{SERVICES}->{$service}->{VOS}};
        } else {
            return ();
        }
    } else {
        return ();
    }
}

sub getMetrics
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return ();

    if (exists $self->{HOSTS}->{$host}) {
        return keys %{$self->{HOSTS}->{$host}->{METRICS}};
    } else {
        return ();
    }
}

sub getLocalMetrics
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return ();

    if (exists $self->{HOSTS}->{$host}) {
        my @metrics;
        foreach my $metric ( keys %{$self->{HOSTS}->{$host}->{METRICS}}) {
            if ($self->{HOSTS}->{$host}->{METRICS}->{$metric}->{TYPE} eq 'local') {
                push @metrics, $metric;
            }
        }
        return @metrics;
    } else {
        return;
    }
}

sub getNativeMetrics
{
    my $self = shift;

    $self->getLocalMetrics(@_);
}

sub getRemoteMetrics
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return ();

    if (exists $self->{HOSTS}->{$host}) {
        my @metrics;
        foreach my $metric ( keys %{$self->{HOSTS}->{$host}->{METRICS}}) {
            if ($self->{HOSTS}->{$host}->{METRICS}->{$metric}->{TYPE} eq 'remote') {
                push @metrics, $metric;
            }
        }
        return @metrics;
    } else {
        return ();
    }
}

sub getContacts
{
    my $self = shift;

    $self->debugSub(@_);

    if (exists $self->{CONTACTS}) {
        return keys %{$self->{CONTACTS}};
    } else {
        return ();
    }
}

sub isContactEnabled
{
    my $self = shift;

    $self->debugSub(@_);

    my $contact = shift || return 0;

    if (exists $self->{CONTACTS}) {
        if (exists $self->{CONTACTS}->{$contact}) {
            return $self->{CONTACTS}->{$contact};
        } else {
            return 0;
        }
    } else {
        return 0;
    }
}

sub getHostProfiles {
    my $self = shift;

    $self->debugSub(@_);
    
    my $host = shift || return;

    return $self->{HOSTS}->{$host}->{PROFILES};
}

sub getProfiles
{
    my $self = shift;

    $self->debugSub(@_);

    if (exists $self->{PROFILES}) {
        return keys %{$self->{PROFILES}};
    } else {
        return ();
    }
}

sub getVoFqans
{
    my $self = shift;
    my $vo = shift or return ();

    $self->debugSub(@_);

    if (exists $self->{VO_FQANS}->{$vo}) {
        return keys %{$self->{VO_FQANS}->{$vo}};
    } else {
        return ();
    }
}

sub getUsers
{
    my $self = shift;

    $self->debugSub(@_);

    if (exists $self->{USERS}) {
        return keys %{$self->{USERS}};
    } else {
        return ();
    }
}

sub getHostContacts
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return ();

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return ();
    }

    if (exists $self->{HOSTS}->{$host}->{CONTACTS}) {
        return keys %{$self->{HOSTS}->{$host}->{CONTACTS}};
    } else {
        return ();
    }
}

sub isHostContactEnabled
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return 0;
    my $contact = shift || return 0;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return 0;
    }

    if (exists $self->{HOSTS}->{$host}->{CONTACTS}) {
        if (exists $self->{HOSTS}->{$host}->{CONTACTS}->{$contact}) {
            return $self->{HOSTS}->{$host}->{CONTACTS}->{$contact};
        } else {
            return 0;
        }
    } else {
        return 0;
    }
}

sub getServiceContactsServices
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return ();

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return ();
    }

    if (exists $self->{HOSTS}->{$host}->{SERVICE_CONTACTS}) {
        return keys %{$self->{HOSTS}->{$host}->{SERVICE_CONTACTS}};
    } else {
        return ();
    }
}

sub getServiceContacts
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return ();
    my $service = shift || return ();

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return ();
    }

    if (exists $self->{HOSTS}->{$host}->{SERVICE_CONTACTS} && exists $self->{HOSTS}->{$host}->{SERVICE_CONTACTS}->{$service}) {
        return keys %{$self->{HOSTS}->{$host}->{SERVICE_CONTACTS}->{$service}};
    } else {
        return ();
    }
}

sub getServiceFlavourContactsServiceFlavours
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return ();

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return ();
    }

    if (exists $self->{HOSTS}->{$host}->{SERVICE_FLAVOUR_CONTACTS}) {
        return keys %{$self->{HOSTS}->{$host}->{SERVICE_FLAVOUR_CONTACTS}};
    } else {
        return ();
    }
}

sub getServiceFlavourContacts
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return ();
    my $service = shift || return ();

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return ();
    }

    if (exists $self->{HOSTS}->{$host}->{SERVICE_FLAVOUR_CONTACTS} && exists $self->{HOSTS}->{$host}->{SERVICE_FLAVOUR_CONTACTS}->{$service}) {
        return keys %{$self->{HOSTS}->{$host}->{SERVICE_FLAVOUR_CONTACTS}->{$service}};
    } else {
        return ();
    }    
}

sub isServiceFlavourContactEnabled
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return ();
    my $service = shift || return ();
    my $contact = shift || return 0;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return ();
    }
    
    if (exists $self->{HOSTS}->{$host}->{SERVICE_FLAVOUR_CONTACTS} && exists $self->{HOSTS}->{$host}->{SERVICE_FLAVOUR_CONTACTS}->{$service}) {
        if (exists $self->{HOSTS}->{$host}->{SERVICE_FLAVOUR_CONTACTS}->{$service}->{$contact}) {
            return $self->{HOSTS}->{$host}->{SERVICE_FLAVOUR_CONTACTS}->{$service}->{$contact};
        } else {
            return 0;
        }
    } else {
        return 0;
    }    
}

sub getRemoteServices
{
    my $self = shift;

    $self->debugSub(@_);

    if (exists $self->{REMOTESERVICES}) {
        return keys %{$self->{REMOTESERVICES}};
    } else {
        return ();    
    }
}

sub getGrids
{
    my $self = shift;

    $self->debugSub(@_);

    if (exists $self->{GRIDS}) {
        return keys %{$self->{GRIDS}};
    } else {
        return ();
    }
}

# check methods

sub hasHost
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $hosts;

    return exists $self->{HOSTS}->{$host};
}

sub hasService
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $service = shift || return;

    if (exists $self->{HOSTS}->{$host} ) {
        return exists $self->{HOSTS}->{$host}->{SERVICES}->{$service};
    }
}

sub hasAttribute {
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $attr = shift || return;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->error("Host $host is not in the list of hosts on site!");
        return;
    }

    return (exists $self->{HOSTS}->{$host}->{ATTRIBUTES}->{$attr}->{VALUE} || exists $self->{ATTRIBUTES}->{$attr}->{VALUE});
}

sub hasContacts
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return;
    }

    return (exists $self->{HOSTS}->{$host}->{CONTACTS});
}

sub hasProfile
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $profile = shift || return;

    return (exists $self->{HOSTS}->{$host}->{PROFILES}->{$profile} ||  $self->{PROFILES}->{$profile});
}

sub hasServiceContacts
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $service = shift || return;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return;
    }

    return (exists $self->{HOSTS}->{$host}->{SERVICE_CONTACTS} && exists $self->{HOSTS}->{$host}->{SERVICE_CONTACTS}->{$service});
}

sub hasServiceFlavourContacts
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $service = shift || return;

    if (!exists $self->{HOSTS}->{$host} ) {
        $self->warning("Host $host is not in the list of hosts on site!");
        return;
    }

    return (exists $self->{HOSTS}->{$host}->{SERVICE_FLAVOUR_CONTACTS} && exists $self->{HOSTS}->{$host}->{SERVICE_FLAVOUR_CONTACTS}->{$service});
}

sub hasMetrics {
    my $self = shift;
    my $retVal;
    $self->debugSub(@_);

    $retVal = 1 if ($self->{METRIC_COUNT} > 0);

    $retVal;
}

sub hasMetricVoFqan {
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $vo = shift || return;
    my $voFqan = shift || return;
    # if voFqan is not default one, return false on empty list
    my $isDefault = shift;
    my $result;
    my $hostRef;
    
    unless (defined $isDefault) {
        $isDefault = 1;
    }

    if (exists $self->{HOSTS}->{$host}) {
        $hostRef = $self->{HOSTS}->{$host};
    }

    return undef unless (defined $hostRef);

    return $isDefault unless exists $hostRef->{METRICS}->{$metric}->{VOS};

    return 1 if exists $hostRef->{METRICS}->{$metric}->{VOS}->{$vo}->{$voFqan};

    return $isDefault if exists $hostRef->{METRICS}->{$metric}->{VOS}->{$vo}->{'_ALL_'};
}

sub hasMetricVo {
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $vo = shift || return;
    $vo = lc($vo);
    my $result;
    my $hostRef;
    
    if (exists $self->{HOSTS}->{$host}) {
        $hostRef = $self->{HOSTS}->{$host};
    }

    return 0 unless (defined $hostRef);

    return 1 unless ( exists $hostRef->{METRICS}->{$metric}->{VOS} );

    return exists $hostRef->{METRICS}->{$metric}->{VOS}->{$vo};
}

sub hasVO
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $vo = shift || return;
    my $metric = shift;
    my $result;
    my $hostRef;
    $vo = lc($vo);

    if (exists $self->{HOSTS}->{$host}) {
        $hostRef = $self->{HOSTS}->{$host};
    }

    if (defined $hostRef) {
        my @searchArr;
        # if services have no VO assigned we assume that VO is supported
        # examples are: MON, BDII, Site-BDII

        if ($metric) {
            return 0 unless ($self->hasMetricVo($host, $metric, $vo));
        
            @searchArr = $self->metricServices($host, $metric);
        } else {
            @searchArr = keys %{$hostRef->{SERVICES}};
        }

        my $foundNoVO = 0;
        foreach my $service (@searchArr) {
            if (exists $hostRef->{SERVICES}->{$service}->{VOS}) {
                if (exists $hostRef->{SERVICES}->{$service}->{VOS}->{$vo}) {
                    $result = 1;
                    last;
                } else {
                    $foundNoVO = 1;
                }
            }
        }
        
        return ($result || !$foundNoVO);
    }
}

sub hasMetric
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metric = shift || return;
    my $types = shift;
    my $metrics;

    # check if host exists
    if (exists $self->{HOSTS}->{$host}) {
        $metrics = $self->{HOSTS}->{$host}->{METRICS};
    } else {
        $self->warning("Host $host is not in the list of hosts on site!");
        return;
    }

    if ($types && ref $types eq "HASH") {
        return exists $metrics->{$metric} && exists $types->{$metrics->{$metric}->{TYPE}};
    } else {
        return exists $metrics->{$metric};
    }
}

sub hasMetricNRPEService
{
    my $self = shift;

    $self->debugSub(@_);

    my $host = shift || return;
    my $metrics;

    # check if host exists
    if (exists $self->{HOSTS}->{$host}) {
        $metrics = $self->{HOSTS}->{$host}->{METRICS};
    } else {
        $self->warning("Host $host is not in the list of hosts on site!");
        return;
    }

    foreach my $metricRef (values %{$metrics}) {
        if (exists $metricRef->{FLAGS}->{NRPE_SERVICE}) {
            return 1;
        }
    }
}

=head1 NAME

NCG::SiteDB

=head1 DESCRIPTION

The NCG::SiteDB module encapsulates the structure containing information
about grid site, services & local/remote probes used for monitoring.

Main component of NCG::SiteDB module is list of hosts which belong to site.
- List HOSTS contains all hosts which are found by NCG::SiteInfo module
and for these hosts configuration is generated by NCG::ConfigGen. 

Structure is based on topology and probe description database.
Structure of HOSTS is following:
  $self->{HOSTS}
    - contains list of hosts on site
    - attributes:
      - ADDRESS: host address used for host check

  $self->{HOSTS}->{$hostName}->{SERVICES}
    - contains list of services on host
    - services are interpreted as grid services in GOCDB (nodetypes)
    - examples: SRM, SE, CE, BDII

  $self->{HOSTS}->{$hostName}->{SERVICES}->{$serviceName}->{VOS}
    - contains list of VOs supported on service
    - this list is not mandatory (e.g. grids without VOs)

  $self->{HOSTS}->{$hostName}->{METRICS}
    - contains list of metrics on host
    - metrics are atomic checks
    - single service contains several metrics
    - examples: hr.srce.GridFTP-Transfer, ch.cern.LFC-Readdir
    - attributes:
      - TYPE: local|remote
      - DOCURL: URL with metric documentation
      - URL: URL with detailed output (remote only)
      - REMOTESERVICE: name of the remote service which performed
      remote check (remote only)
      - PROBE: executable (local only)
      - SERVICES: list of services to which metric belongs
      - CONFIG: configuration paramteres hash (local only)
      - ATTRIBUTES: attributes hash (local only)
                    value=parametername
      - PARAMETERS: parameters hash (local only)
                    parametername=[value]
      - DEPENDENCIES: array of metrics which metric depends on (local only)
      - PASSIVE: metric is part of a complex check, e.g. SAM tests (local only)
      - PARENT: name of the metric which is executing complex check (local only)
      - VO_FQANS: list of VOs of VO_FQANs for which metric should be executed

  $self->{HOSTS}->{$hostName}->{ATTRIBUTES}
    - contains list of attributes needed for metrics

  $self->{HOSTS}->{$hostName}->{ATTRIBUTES}->{$attribute}->{VOS}
    - contains list of attribute values for each supported

  $self->{HOSTS}->{$hostName}->{CONTACTS}
    - contains list of contact persons for host

Global attributes which can be used for any host are stored in:
  $self->{ATTRIBUTES}
When fetching attributes via hostAttribute method first hosts attributes
are checked and then global ones.

=head1 SYNOPSIS

  use NCG::SiteDB;

=cut

=head1 METHODS

=over

=item C<new>

  $site = NCG::SiteDB->new( $attr );

Creates new NCG::SiteDB instance.

=item C<addHost>

  $res = $site->addHost( $host );

Adds new host.

Result is 1 if operation is successful, 0 otherwise.

=item C<addService>

  $res = $ncg->addService( $host, $service );

Adds new service to host. If host doesn't exist, method returns error.

Result is 1 if operation is successful, 0 otherwise.

=item C<addVO>

  $res = $ncg->addVO( $host, $service, $vo );

Adds new supported VO to service on host. If service on host doesn't exist,
method returns error.

Result is 1 if operation is successful, 0 otherwise.

=item C<addLocalMetric>

  $res = $ncg->addLocalMetric( $host, $metric, $probe,
                               $config, $attributes, $parameters,
                               $dependencies, $flags, $parent, $docUrl);

Adds new local metric to host. If host doesn't exist, method returns error.

Parameters are:
    - $host: add metric to defined host
    - $metric: metric name
    - $probe: executable used for gathering metric
    - $config: configuration paramteres hash (name=>value)
    - $attributes: attributes hash (name=>value)
    - $parameters: parameters hash (name=>value)
    - $dependencies: dependencies hash (parentMetric=>value); value is
    1 for host internal dependencies and 0 for external (e.g.
    GridProxy-Valid)
    - $flags: various metric flags hash (name=>value),
      currently supported flags:
      - PASSIVE: if defined, metric is part of a complex check
      - VO: defines if metric is VO dependent
      - NRPE: defines if metric should be executed on NRPE
      - PNP: generate action_url pointing to PNP data
      - SUDO: command is executed via sudo
      - NOHOSTNAME: command is not passed -H parameter
      - OBSESS: metric results should be published via obsess command
      - NRPE_SERVICE: metric should be executed via NRPE on service node
      - REQUIREMENT: metric should be generated if req. metric is present on 
        some site 
        (used only for metrics associated with Nagios host)
      - LOCALDEP: metric should be removed if local flag is not on
        (used only for metrics associated with Nagios host)      
    - $parent: name of the metric which runs complex check
      (only if flag PASSIVE is set)
    - $docUrl: URL with metric documentation

Result is 1 if operation is successful, 0 otherwise.

=item C<addRemoteMetric>

  $res = $ncg->addRemoteMetric( $host, $metric, $remoteService, $url, $docUrl );

Adds new remote metric to host. If host doesn't exist, method issues warning.

Parameters are:
    - $host: add metric to defined host
    - $metric: metric name
    - $remoteService: name of the remote service which performed
      remote metric
    - $url: URL with detailed output
    - $docUrl: URL with metric documentation

Result is 1 if operation is successful, 0 otherwise.

=item C<addContact>

  $res = $ncg->addContact( $contact, $enabled );

Adds contact to all entities on site. Variable $enabled defines
if the contact should receive alarms when ENABLE_NOTIFICATIONS
is set to 0 (see SAM-1424).

Site level contacts are kept independently from hosts.

=item C<addHostContact>

  $res = $ncg->addHostContact( $host, $contact, $enabled );

Adds contact to host.

Variable $enabled defines if the contact should receive alarms 
when ENABLE_NOTIFICATIONS is set to 0 (see SAM-1424).

=item C<addRemoteService>

  $res = $ncg->addRemoteService( $serviceName );

Adds remote services which executed remote metrics which
are imported.

=item C<addUser>

  $res = $ncg->addUser( $dn, $name, $email );

Adds user to a list of users authorized on site.

Parameters are:
    - $dn: certificate DN of user
    - $name: user's full name
    - $email: user's email

Result is 1 if operation is successful, 0 otherwise.

=item C<removeContact>

  $res = $ncg->removeContact( $contact );

Remove contact from all entities on site.

=item C<removeHost>

  $res = $ncg->removeHost( $host );

Removes host from list HOSTS. 

=item C<removeService>

  $res = $ncg->removeService( $host );

Removes service from host in list HOSTS. 

=item C<siteName>

  print $ncg->siteName;
  $ncg->siteName('egee.srce.hr');

Accessor method for property SITENAME.

=item C<siteROC>

  print $ncg->siteROC;
  $ncg->siteROC('CentralEurope');

Accessor method for property ROC.

=item C<siteLDAP>

  print $ncg->siteLDAP;
  $ncg->siteLDAP('bdii-egee.srce.hr');

Accessor method for property LDAP_ADDRESS.

=item C<hostAttribute>

  print $ncg->hostAttribute( $host, $attr );
  $ncg->hostAttribute( $host, $attr, $value );

Accessor method for attribute $attr on host $host.

=item C<hostAttributeVO>

  print $ncg->hostAttributeVO( $host, $attr, $vo );
  $ncg->hostAttributeVO( $host, $attr, $vo, $value );

Accessor method for attribute $attr for VO $vo on host
$host.

=item C<metric*>

  print $ncg->metric* ( $host, $metric );

Read-only accessors for metric attributes on host $host.

Methods are following: metricType, metricDocUrl, metricProbe
metricNative, metricRemoteService, metricUrl, 
metricConfig, metricAttributes, metricDependencies, metricParent.

See DESCRIPTION, C<addLocalMetric> and C<addRemoteMetric> for
detailed description of metric attributes.

=item C<hostAddress>

  print $ncg->hostAddress ( $host );

Read-only accessor for address of host $host.

=item C<userName>

  print $ncg->userName ( $user );

Read-only accessor for full name of user $user.

=item C<userEmail>

  print $ncg->userEmail ( $user );

Read-only accessor for email of user $user.

=item C<getHosts>

  @res = $ncg->getHosts( $host );

Retrieves array of hosts in list HOSTS.

This method is useful for generating configuration for
registered hosts.

=item C<getServices>

  @res = $ncg->getServices( $host );

Retrieves array of services associated with $host from
list HOSTS.

=item C<getRemoteServices>

  @res = $ncg->getRemoteServices( );

Retrieves array of remote services from which remote
metrics will be imported.

=item C<getMetrics>

  @res = $ncg->getMetrics( $host );

Retrieves array of metrics associated with $host from
list HOSTS.

=item C<getLocalMetrics>

  @res = $ncg->getLocalMetrics( $host );

Retrieves array of local metrics associated with $host from
list HOSTS.

=item C<getRemoteMetrics>

  @res = $ncg->getRemoteMetrics( $host );

Retrieves array of remote metrics associated with $host from
list HOSTS.

=item C<getContacts>

  @res = $ncg->getContacts;

Retrieves array of global contacts associated with
all hosts.

=item C<getHostContacts>

  @res = $ncg->getHostContacts ( $host );

Retrieves array of contacts associated host $host

=item C<getUsers>

  @res = $ncg->getUsers;

Retrieves array of users associated with site.

=item C<hasHost>

  $res = $ncg->hasHost ( $host );

Method checks if $host exists in list HOSTS.

=item C<hasService>

  $res = $ncg->hasService ( $host, $service );

Method checks if $host in list HOSTS has $service.

=item C<hasAttribute>

  $res = $ncg->hasAttribute ( $host, $attribute );

Method checks if $host has $attribute defined.

=item C<hasServiceURI>

  $res = $ncg->hasAttribute ( $host, $metricSet );

Method checks if $host has service uri defined
for metric set $metricSet.

=item C<hasContacts>

  $res = $ncg->hasContacts ( $host );

Method checks if $host has contacts defined.

=item C<hasVO>

  $res = $ncg->hasVO ( $host, $vo );

Method checks if there is any service on $host which supports 
$vo.

In case when all services don't have VOs defined, method
returns true. Example is BDII service.

=item C<hasMetric>

  $res = $ncg->hasMetric ( $host, $metric );

  $res = $ncg->hasMetric ( $host, $metric, $types );

Method checks if $host has metric $metric.

Argument $types is optional. Argument $types should contain hah reference
with supported metric types. For example, for following value:
  $types = {local=>1, remote=>1}
function will check if the metric exists and if the metric's type is in 
the list of supported types.

=item C<hasMetricNRPEService>

  $res = $ncg->hasMetricNRPEService ( $host );

Method checks if host $host has metric with flag NRPE_SERVICE.
This check is used to see if host needs NRPE config.

=item C<isContactEnabled>

  $res = $ncg->isContactEnabled ( $contact );

Method checks if contact $contact should receive alarms even
if ENABLE_NOTIFICATIONS is switched off (see SAM-1424).

=item C<isHostContactEnabled>

  $res = $ncg->isHostContactEnabled ( $host, $contact );

Method checks if hostcontact $contact should receive alarms even
if ENABLE_NOTIFICATIONS is switched off (see SAM-1424).


=back

=head1 SEE ALSO

  NCG

=cut


1;
