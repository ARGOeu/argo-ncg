%define lperllib modules/NCG
%define templatedir %{_datadir}/argo-ncg/templates
%define configdir /etc/argo-ncg
%define perllib %{perl_vendorlib}

Summary: ARGO Nagios config generator
Name: argo-ncg
Version: 0.4.12
Release: 1%{?dist}
License: ASL 2.0
Group: Network/Monitoring
Source0: %{name}-%{version}.tar.gz
Obsoletes: grid-monitoring-config-gen-nagios grid-monitoring-config-gen ncg-metric-config
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
BuildArch: noarch
Requires: perl-libwww-perl > 5.833-2
Requires: psmisc
%if 0%{?el7:1}
Requires: perl(LWP::Protocol::https)
%endif

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
install --directory $RPM_BUILD_ROOT/usr/libexec/%{name}
install --mode=755 ncg.pl $RPM_BUILD_ROOT%{_sbindir}
install --mode=755 ncg.reload.sh $RPM_BUILD_ROOT%{_sbindir}
install --mode=755 argo-java-keystore.sh $RPM_BUILD_ROOT/usr/libexec/%{name}
install --mode=755 argo-java-truststore.sh $RPM_BUILD_ROOT/usr/libexec/%{name}

#
# Config
#
install --directory $RPM_BUILD_ROOT%{configdir}/ncg.conf.d/
install --directory $RPM_BUILD_ROOT%{configdir}/ncg-localdb.d/
install ncg.conf $RPM_BUILD_ROOT%{configdir}
install ncg-vars.conf $RPM_BUILD_ROOT%{configdir}
install ncg.localdb $RPM_BUILD_ROOT%{configdir}
install ncg.localdb.example $RPM_BUILD_ROOT%{configdir}
install check_logfiles_ncg.conf $RPM_BUILD_ROOT%{configdir}
install --directory $RPM_BUILD_ROOT/etc/nagios/argo-ncg.d
install --directory $RPM_BUILD_ROOT/etc/nagios/globus

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

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%config(noreplace) %{configdir}/ncg.conf.d
%config(noreplace) %{configdir}/ncg.conf
%config(noreplace) %{configdir}/ncg-vars.conf
%config(noreplace) %{configdir}/ncg.localdb
%config(noreplace) %{configdir}/ncg.localdb.example
%config(noreplace) %{configdir}/ncg-localdb.d
%config(noreplace) /etc/nagios/argo-ncg.d
%{configdir}/check_logfiles_ncg.conf
%{_sbindir}/ncg.pl
%{_sbindir}/ncg.reload.sh
/usr/libexec/%{name}/argo-java-keystore.sh
/usr/libexec/%{name}/argo-java-truststore.sh

%{perllib}/NCG.pm
%{perllib}/NCG/
%{templatedir}/
%config(noreplace) %attr(0770,nagios,nagios) /etc/nagios/globus

%pre
if [ -f /etc/init.d/ncg ] ; then
   /sbin/service ncg stop || echo "ncg service was already stopped"
   /sbin/chkconfig --del ncg
fi

%changelog
* Mon Feb 1 2021 Emir Imamagic <eimamagi@srce.hr - 0.4.12-1
- Version bump
* Fri May 8 2020 Emir Imamagic <eimamagi@srce.hr - 0.4.11-1
- Version bump
* Fri Apr 10 2020 Emir Imamagic <eimamagi@srce.hr> - 0.4.10-1
- Version bump
* Thu Mar 26 2020 Emir Imamagic <eimamagi@srce.hr> - 0.4.9-1
- Version bump
* Thu Dec 21 2017 Emir Imamagic <eimamagi@srce.hr> - 0.4.2-1
- Version bump
* Thu May 25 2017 Emir Imamagic <eimamagi@srce.hr> - 0.3.4-1
- Version bump
* Thu May 4 2017 Emir Imamagic <eimamagi@srce.hr> - 0.3.3-1
- Version bump
* Thu Apr 6 2017 Emir Imamagic <eimamagi@srce.hr> - 0.3.2-1
- Version bump
* Fri Mar 3 2017 Emir Imamagic <eimamagi@srce.hr> - 0.3.1-1
- Configuration changes in Nagios 4.3.1
- Increase org.egee.ImportGocdbDowntimes timeout
- eu.egi.OCCI-IGTF and eu.egi.Keystone-IGTF broken
* Wed Feb 15 2017 Emir Imamagic <eimamagi@srce.hr> - 0.3.0-1
- Add probe for monitoring decommission of dCache 2.10
- Fix configuration of test dg.FinishedJobs
- Add support for extracting gsisshd port
- Integrate onedata probes to monitoring instances
- Add scripts for handling UNICORE configuration
- Various metric configuration changes
* Thu Dec 8 2016 Emir Imamagic <eimamagi@srce.hr> - 0.2.2-1
- Changes from ARGO central instances
* Fri Jul 29 2016 Emir Imamagic <eimamagi@srce.hr> - 0.2.1-1
- Added UNICORE scripts for credential management
* Thu Mar 24 2016 Emir Imamagic <eimamagi@srce.hr> - 0.2.0-1
- Added config directories globus and ncg-localdb.d to package
- Removed obsolete failure_prediction_enabled
- Added TENANT option
- CREAM-CE test configurations
- Modified argo tests probe locations
- Added NCG_TIMEOUT to ncg.reload.sh
- Removed LOCAL_METRIC_STORE option
* Tue Mar 15 2016 Emir Imamagic <eimamagi@srce.hr> - 0.1.0-2
- Removed hashlocal-to-json.pl from RPM
* Tue Mar 8 2016 Emir Imamagic <eimamagi@srce.hr> - 0.1.0-1
- Initial build for ARGO Monitoring Engine
