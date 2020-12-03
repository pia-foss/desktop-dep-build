rem Copyright (c) 2020 Private Internet Access, Inc.
rem
rem This file is part of the Private Internet Access Desktop Client.
rem
rem The Private Internet Access Desktop Client is free software: you can
rem redistribute it and/or modify it under the terms of the GNU General Public
rem License as published by the Free Software Foundation, either version 3 of
rem the License, or (at your option) any later version.
rem
rem The Private Internet Access Desktop Client is distributed in the hope that
rem it will be useful, but WITHOUT ANY WARRANTY; without even the implied
rem warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
rem GNU General Public License for more details.
rem
rem You should have received a copy of the GNU General Public License
rem along with the Private Internet Access Desktop Client.  If not, see
rem <https://www.gnu.org/licenses/>.

@echo off
rem Clone from the patched copy created by build-pia.bat
set OPENVPN_GIT=..\..\openvpn
set OPENVPN_BRANCH=pia-openvpn-build

rem Usually these archives are preloaded instead of downloaded at build time,
rem but use HTTPS instead of HTTP if a dev is downloading them this way, etc.
set OPENSSL_URL=https://www.openssl.org/source/openssl-%OPENSSL_VERSION%.tar.gz
set LZO_URL=https://www.oberhumer.com/opensource/lzo/download/lzo-%LZO_VERSION%.tar.gz
