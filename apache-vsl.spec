Name:           apache-vsl
Version:        3.0
Release:        1%{?dist}
Summary:        VirtualHost-splitting log daemon for Apache

Group:          Applications/System
License:        GPLv2+
URL:            http://www.finnie.org/software/apache-vsl/
Source0:        http://www.finnie.org/software/apache-vsl/apache-vsl-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch


%description
apache-vsl is a logging program, intended to be run from Apache.  It is 
designed to be configurable, versatile, efficient and scalable.


%prep
%setup -q


%build
make %{?_smp_mflags}


%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT


%clean
make clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
/usr/local/bin/apache-vsl
/usr/local/share/man/man8/apache-vsl.8
%doc README
%doc COPYING


%changelog
