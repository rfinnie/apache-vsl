Name:           apache-vsl
Version:        3.1.1
Release:        0%{?dist}
Summary:        VirtualHost-splitting log daemon for Apache
License:        GPLv2+
URL:            http://www.finnie.org/software/apache-vsl
Source0:        http://www.finnie.org/software/%{name}/%{name}-%{version}.tar.gz
BuildArch:      noarch

BuildRequires:  perl
BuildRequires:  perl(Config)
BuildRequires:  perl(ExtUtils::MakeMaker)
BuildRequires:  perl(strict)
# Run-time
BuildRequires:  perl(Pod::Usage)
BuildRequires:  perl(POSIX)
BuildRequires:  perl(Config::General)
BuildRequires:  perl(File::Path)
BuildRequires:  perl(File::Basename)
BuildRequires:  perl(File::Spec)
BuildRequires:  perl(Cwd)
BuildRequires:  perl(Getopt::Long)

Requires:       perl(:MODULE_COMPAT_%(eval "`perl -V:version`"; echo $version))

%description
apache-vsl is a logging program, intended to be run from Apache.  It is 
designed to be configurable, versatile, efficient and scalable.

%prep
%setup -q

%build
%{__perl} Makefile.PL INSTALLDIRS=vendor
make EXTRAVERSION=-%{release} %{?_smp_mflags}

%install
rm -rf $RPM_BUILD_ROOT
make pure_install PERL_INSTALL_ROOT=$RPM_BUILD_ROOT
find $RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} ';'
find $RPM_BUILD_ROOT -depth -type d -exec rmdir {} 2>/dev/null ';'
%{_fixperms} $RPM_BUILD_ROOT/*

%check
make test

%clean
rm -rf $RPM_BUILD_ROOT

%files
%doc ChangeLog COPYING README apache-vsl.conf.example
%{_bindir}/apache-vsl
%{_mandir}/man1/apache-vsl.1p*

%changelog
