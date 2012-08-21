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
make EXTRAVERSION=-$RPM_PACKAGE_RELEASE


%install
rm -rf $RPM_BUILD_ROOT
make install PREFIX=/usr DESTDIR=$RPM_BUILD_ROOT
install -d -m 0755 $RPM_BUILD_ROOT/usr/share/man/man8
install -m 0755 apache-vsl.8 $RPM_BUILD_ROOT/usr/share/man/man8


%clean
make clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
/usr/bin/apache-vsl
/usr/share/man/man8/apache-vsl.8.gz
%doc README
%doc COPYING


%changelog
