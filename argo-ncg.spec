%define lperllib modules/NCG
%define templatedir %{_datadir}/argo-ncg/templates
%define configdir /etc/argo-ncg
%define perllib %{perl_vendorlib}

Summary: ARGO Nagios config generator
Name: argo-ncg
Version: 0.1.0
Release: 2%{?dist}
License: ASL 2.0
Group: Network/Monitoring
Source0: %{name}-%{version}.tar.gz
Obsoletes: grid-monitoring-config-gen-nagios grid-monitoring-config-gen ncg-metric-config
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
BuildArch: noarch

%description
(NULL)

%prep
%setup -q

%build

%install
rm -rf $RPM_BUILD_ROOT

#
# App
#
install --directory $RPM_BUILD_ROOT%{_sbindir}
install --directory $RPM_BUILD_ROOT/usr/libexec
install --mode=755 ncg.pl $RPM_BUILD_ROOT%{_sbindir}
install --mode=755 ncg.reload.sh $RPM_BUILD_ROOT%{_sbindir}
#
# Config
#
install --directory $RPM_BUILD_ROOT%{configdir}/ncg.conf.d/
install --directory $RPM_BUILD_ROOT%{configdir}/
install ncg.conf $RPM_BUILD_ROOT%{configdir}
install ncg.conf.example $RPM_BUILD_ROOT%{configdir}
install ncg.localdb $RPM_BUILD_ROOT%{configdir}
install ncg.localdb.example $RPM_BUILD_ROOT%{configdir}
install check_logfiles_ncg.conf $RPM_BUILD_ROOT%{configdir}
install --directory $RPM_BUILD_ROOT/etc/nagios/argo-ncg.d
cp -r unicore $RPM_BUILD_ROOT/etc/nagios
install --mode=644 ncg-metric-config.conf $RPM_BUILD_ROOT/etc
cp -r ncg-metric-config.d $RPM_BUILD_ROOT/etc
#
# modules
#
install --directory $RPM_BUILD_ROOT%{perllib}
cp -r modules/NCG $RPM_BUILD_ROOT%{perllib}
install --mode=644 modules/NCG.pm $RPM_BUILD_ROOT%{perllib}
#
# templates
#
install --directory $RPM_BUILD_ROOT%{templatedir}
cp -r templates/* $RPM_BUILD_ROOT%{templatedir}
#
# config dirqueue
install --directory $RPM_BUILD_ROOT/var/run/argo-ncg

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
/etc/ncg-metric-config.conf
/etc/ncg-metric-config.d
%config(noreplace) %{configdir}/ncg.conf.d
%config(noreplace) %{configdir}/ncg.conf
%config(noreplace) %{configdir}/ncg.localdb
%config(noreplace) %{configdir}/ncg.conf.example
%config(noreplace) %{configdir}/ncg.localdb.example
%config(noreplace) /etc/nagios/argo-ncg.d
%config(noreplace) /etc/nagios/unicore/log4j-ucc.properties
%config(noreplace) /etc/nagios/unicore/log4j-ucc-debug.properties
%config(noreplace) /etc/nagios/unicore/log4j-uvosclc.properties
%config(noreplace) /etc/nagios/unicore/log4j-uvosclc-debug.properties
/etc/nagios/unicore/UNICORE_Job.u
%{configdir}/check_logfiles_ncg.conf
%{_sbindir}/ncg.pl
%{_sbindir}/ncg.reload.sh
%{perllib}/NCG.pm
%{perllib}/NCG/
%{templatedir}/
%dir %attr(0770,nagios,nagios) /var/run/argo-ncg

%pre
if [ -f /etc/init.d/ncg ] ; then
   /sbin/service ncg stop || echo "ncg service was already stopped"
   /sbin/chkconfig --del ncg
fi

%changelog
* Tue Mar 15 2016 Emir Imamagic <eimamagi@srce.hr> - 0.1.0-2
- Removed hashlocal-to-json.pl from RPM
* Tue Mar 8 2016 Emir Imamagic <eimamagi@srce.hr> - 0.1.0-1
- Initial build for ARGO Monitoring Engine
