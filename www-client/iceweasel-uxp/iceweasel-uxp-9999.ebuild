# Copyright 1999-2022 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=8
WANT_AUTOCONF="2.1"
MOZ_ESR=""

#MOZCONFIG_OPTIONAL_GTK2ONLY=1
MOZCONFIG_OPTIONAL_WIFI=0

inherit check-reqs flag-o-matic toolchain-funcs gnome2-utils mozconfig-v6.52 xdg-utils autotools

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://repo.palemoon.org/MoonchildProductions/UXP"
	IW_REPO_URI="https://git.hyperbola.info:50100/software/iceweasel-uxp.git"
	EGIT_CHECKOUT_DIR="${WORKDIR}/${P}"
	EGIT_BRANCH="master"
	SRC_URI=""
	KEYWORDS="amd64 x86"
	S="${WORKDIR}/${P}"
else
	UXP_VER="2019.03.08"
	IW_VER="2.4"
	SRC_URI="https://github.com/MoonchildProductions/UXP/archive/v$UXP_VER.tar.gz"
	IW_URI="https://repo.hyperbola.info:50000/other/iceweasel-uxp/iceweasel-uxp-$IW_VER.tar.gz"
	KEYWORDS="~amd64 ~x86"
	S="${WORKDIR}/UXP-$UXP_VER"
fi

DESCRIPTION="A new generation of Iceweasel, an XUL-based standalone web browser on the Unified XUL Platform (UXP)."
HOMEPAGE="https://wiki.hyperbola.info/doku.php?id=en:project:iceweasel-uxp"

KEYWORDS="amd64"

SLOT="0"
LICENSE="MPL-2.0 GPL-2 LGPL-2.1"
IUSE="hardened +privacy hwaccel jack pulseaudio selinux test"
RESTRICT="mirror"

ASM_DEPEND=">=dev-lang/yasm-1.1"

RDEPEND="
	dev-lang/tauthon
	dev-util/pkgconf
	jack? ( virtual/jack )
	sys-libs/zlib
	app-arch/bzip2
	app-text/hunspell
	dev-libs/libffi
	x11-libs/pixman
	media-libs/libjpeg-turbo
	selinux? ( sec-policy/selinux-mozilla )"
#	No longer working overrides, kept here for reference
#        system-icu? ( dev-libs/icu )
#        system-libvpx? ( >=media-libs/libvpx-1.7:0=[postproc] )
#        system-png? ( >=media-libs/libpng-1.6.35:0=[apng] )
#        system-libevent? ( >=dev-libs/libevent-2.0:0=[threads] )
#        system-sqlite? ( >=dev-db/sqlite-3.30.1:3[secure-delete,debug=] )


DEPEND="${RDEPEND}
	amd64? ( ${ASM_DEPEND} virtual/opengl )
	x86? ( ${ASM_DEPEND} virtual/opengl )"

QA_PRESTRIPPED="usr/lib*/${PN}/iceweasel-uxp"

BUILD_OBJ_DIR="${S}/o"

src_unpack() {
	if [[ ${PV} == "9999" ]]; then
		git-r3_fetch
		git-r3_checkout
		mkdir "${S}/application"
		cd "${S}/application" && git clone $IW_REPO_URI || die "Failed to download application source (git)"
		git reset --hard master
	else
		unpack UXP-$UXP_VER.tar.gz
		cd "${S}/application" && /usr/bin/wget $IW_URI || die "Failed to download application source (wget)"
		tar -xzf iceweasel-uxp-$IW_VER.tar.gz || die "Failed to unpack application source"
		mv "iceweasel-uxp-$IW_VER" "iceweasel-uxp" || die "Failed to remove version from application name (broken branding)"
		ln -s "${S}/iceweasel-uxp-$IW_VER" "${S}/UXP-$UXP_VER/application/iceweasel-uxp"
		cd "${S}"
	fi
}

pkg_setup() {
	moz_pkgsetup

	unset DBUS_SESSION_BUS_ADDRESS \
		DISPLAY \
		ORBIT_SOCKETDIR \
		SESSION_MANAGER \
		XDG_SESSION_COOKIE \
		XAUTHORITY
}

pkg_pretend() {
	# Ensure we have enough disk space to compile
	if use debug || use test ; then
		CHECKREQS_DISK_BUILD="8G"
	else
		CHECKREQS_DISK_BUILD="4G"
	fi
	check-reqs_pkg_setup
}

src_prepare() {
	# Apply our application specific patches to UXP source tree
	eapply "${FILESDIR}"/0001-Tauthon-Patch.patch
	eapply "${FILESDIR}"/0002-musl.patch
	eapply "${FILESDIR}"/0003-Hardcode-AppName-in-nsAppRunner.patch
	eapply "${FILESDIR}"/0004-Add-iceweasel-uxp-application-specfic-override.patch

	if use privacy; then
		eapply "${FILESDIR}"/0005-Disable-SSLKEYLOGFILE-in-NSS.patch
		eapply "${FILESDIR}"/0006-Uplift-enable-proxy-bypass-protection-flag.patch
	fi

        # Fix for Gento GCC overflow error
        eapply "${FILESDIR}"/0007-Bypass-UXP-1324-for-Gentoo-GCC.patch

	# Drop -Wl,--as-needed related manipulation for ia64 as it causes ld sefgaults, bug #582432
	if use ia64 ; then
		sed -i \
		-e '/^OS_LIBS += no_as_needed/d' \
		-e '/^OS_LIBS += as_needed/d' \
		"${S}"/widget/gtk/mozgtk/gtk2/moz.build \
		"${S}"/widget/gtk/mozgtk/gtk3/moz.build \
		|| die "sed failed to drop --as-needed for ia64"
	fi

	# Allow user to apply any additional patches without modifing ebuild
	eapply_user
}

src_configure() {
	MEXTENSIONS="default"

	####################################
	#
	# mozconfig, CFLAGS and CXXFLAGS setup
	#
	####################################

	# It doesn't compile on alpha without this LDFLAGS
	use alpha && append-ldflags "-Wl,--no-relax"

	# Add full relro support for hardened
	use hardened && append-ldflags "-Wl,-z,relro,-z,now"

	mozconfig_annotate '' --enable-extensions="${MEXTENSIONS}"

	echo "mk_add_options MOZ_OBJDIR=${BUILD_OBJ_DIR}" >> "${S}"/.mozconfig
	echo "mk_add_options XARGS=/usr/bin/xargs" >> "${S}"/.mozconfig

	if use jack ; then
		echo "ac_add_options --enable-jack" >> "${S}"/.mozconfig
	fi

	if use pulseaudio ; then
		echo "ac_add_options --enable-pulseaudio" >> "${S}"/.mozconfig
	else
		echo "ac_add_options --disable-pulseaudio" >> "${S}"/.mozconfig
	fi

	echo "ac_add_options --with-system-zlib" >> "${S}"/.mozconfig

	echo "ac_add_options --with-system-bz2" >> "${S}"/.mozconfig

	echo "ac_add_options --enable-system-hunspell" >> "${S}"/.mozconfig

	echo "ac_add_options --enable-system-ffi" >> "${S}"/.mozconfig

	echo "ac_add_options --enable-system-pixman" >> "${S}"/.mozconfig

	echo "ac_add_options --with-system-jpeg" >> "${S}"/.mozconfig

	if ! use dbus ; then
		echo "ac_add_options --disable-dbus" >> "${S}"/.mozconfig
	fi

	# Criticial libs with in-tree patches (system versions not recommended and not working properly anymore)
#
#	if use system-icu ; then
#		echo "ac_add_options --with-system-icu" >> "${S}"/.mozconfig
#	fi
#
#	if use system-libvpx ; then
#		echo "ac_add_options --with-system-libvpx" >> "${S}"/.mozconfig
#	fi
#
#	if use system-libevent ; then
#		echo "ac_add_options --with-system-libevent" >> "${S}"/.mozconfig
#	fi
#
#	if use system-png ; then
#		echo "ac_add_options --with-system-png" >> "${S}"/.mozconfig
#	fi
#
#	if use system-sqlite ; then
#		echo "ac_add_options --with-system-sqlite" >> "${S}"/.mozconfig
#	fi

	echo "ac_add_options --enable-noncomm-build" >> "${S}"/.mozconfig
	# Favor Privacy over features at compile time
	echo "ac_add_options --disable-userinfo" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-safe-browsing" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-sync" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-url-classifier" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-updater" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-crashreporter" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-synth-pico" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-b2g-camera" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-b2g-ril" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-b2g-bt" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-gamepad" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-tests" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-maintenance-service" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-parental-controls" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-accessibility" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-necko-wifi" >> "${S}"/.mozconfig
	echo "ac_add_options --disable-updater" >> "${S}"/.mozconfig
        echo "ac_add_options --disable-startupcache" >> "${S}"/.mozconfig
        echo "ac_add_options --disable-gconf" >> "${S}"/.mozconfig

	# Build paths
	echo "ac_add_options --prefix=/usr" >> "${S}"/.mozconfig
	echo "ac_add_options --libdir=/usr/lib" >> "${S}"/.mozconfig
	echo "ac_add_options --x-libraries=/usr/lib" >> "${S}"/.mozconfig
	# Optimizations
	echo "ac_add_options --enable-jemalloc" >> "${S}"/.mozconfig
	echo "ac_add_options --enable-strip" >> "${S}"/.mozconfig
	echo "ac_add_options --with-pthreads" >> "${S}"/.mozconfig

	# Use gtk3
	echo "ac_add_options --enable-default-toolkit=cairo-gtk3" >> "${S}"/.mozconfig

	if use privacy ; then
		echo "ac_add_options --disable-webrtc" >> "${S}"/.mozconfig
		echo "ac_add_options --disable-webspeech" >> "${S}"/.mozconfig
		echo "ac_add_options --disable-mozril-geoloc" >> "${S}"/.mozconfig
		echo "ac_add_options --disable-nfc" >> "${S}"/.mozconfig
	fi

	#Build the iceweasel-uxp application with iceweasel branding
	echo "ac_add_options --disable-official-branding" >> "${S}"/.mozconfig
	echo "ac_add_options --enable-application=application/iceweasel-uxp" >> "${S}"/.mozconfig
	echo "ac_add_options --with-branding=application/iceweasel-uxp/branding/iceweasel" >> "${S}"/.mozconfig
	echo "export MOZILLA_OFFICIAL=1"
	echo "export MOZ_TELEMETRY_REPORTING="
	echo "export MOZ_ADDON_SIGNING="
	echo "export MOZ_REQUIRE_SIGNING="

	# Allow for a proper pgo build
	if use pgo; then
		echo "mk_add_options PROFILE_GEN_SCRIPT='EXTRA_TEST_ARGS=10 \$(MAKE) -C \$(MOZ_OBJDIR) pgo-profile-run'" >> "${S}"/.mozconfig
	fi

	if [[ $(gcc-major-version) -lt 4 ]]; then
		append-cxxflags -fno-stack-protector
	fi

	# workaround for funky/broken upstream configure...
	SHELL="${SHELL:-${EPREFIX%/}/bin/bash}" \
	emake -f client.mk configure
}

src_compile() {
	MOZ_MAKE_FLAGS="${MAKEOPTS}" SHELL="${SHELL:-${EPREFIX%/}/bin/bash}" \
	#./mach build
	emake -f client.mk realbuild
}

src_install() {
	cd "${BUILD_OBJ_DIR}" || die

	MOZ_MAKE_FLAGS="${MAKEOPTS}" SHELL="${SHELL:-${EPREFIX%/}/bin/bash}" \
	emake DESTDIR="${D}" INSTALL_SDK= install

	# Install language packs
	# mozlinguas_src_install

	local size sizes icon_path icon name
		sizes="16 32 48"
		icon_path="${S}/application/iceweasel-uxp/branding/iceweasel"
		icon="iceweasel"
		name="Iceweasel-UXP"

	# Install icons and .desktop for menu entry
	for size in ${sizes}; do
		insinto "/usr/share/icons/hicolor/${size}x${size}/apps"
		newins "${icon_path}/default${size}.png" "${icon}.png"
	done
	# The 128x128 icon has a different name
	insinto "/usr/share/icons/hicolor/128x128/apps"
	newins "${icon_path}/mozicon128.png" "${icon}.png"
	# Install a 48x48 icon into /usr/share/pixmaps for legacy DEs
	newicon "${icon_path}/content/icon48.png" "${icon}.png"
	newmenu "${FILESDIR}/icon/${PN}.desktop" "${PN}.desktop"
	# TODO: FIXME
#	sed -i -e "s:@NAME@:${name}:" -e "s:@ICON@:${icon}:" \
#		"${ED}/usr/share/applications/${PN}.desktop" || die

	# TODO: FIXME
	# Add StartupNotify=true bug 237317
#	if use startup-notification ; then
#		echo "StartupNotify=true"\
#			 >> "${ED}/usr/share/applications/${PN}.desktop" \
#			|| die
#	fi

	# Apply privacy user.js
	if use privacy ; then
		insinto "/usr/lib/${PN}/browser/defaults/preferences"
		newins "${FILESDIR}/privacy.js-1" "iceweasel-branding.js"
	fi

}

pkg_preinst() {
	gnome2_icon_savelist

	# if the apulse libs are available in MOZILLA_FIVE_HOME then apulse
	# doesn't need to be forced into the LD_LIBRARY_PATH
	if use pulseaudio && has_version ">=media-sound/apulse-0.1.9" ; then
		einfo "APULSE found - Generating library symlinks for sound support"
		local lib
		pushd "${ED}"${MOZILLA_FIVE_HOME} &>/dev/null || die
		for lib in ../apulse/libpulse{.so{,.0},-simple.so{,.0}} ; do
			# a quickpkg rolled by hand will grab symlinks as part of the package,
			# so we need to avoid creating them if they already exist.
			if ! [ -L ${lib##*/} ]; then
				ln -s "${lib}" ${lib##*/} || die
			fi
		done
		popd &>/dev/null || die
	fi
}

pkg_postinst() {
	# Update mimedb for the new .desktop file
	xdg_desktop_database_update
	gnome2_icon_cache_update

	if use pulseaudio && has_version ">=media-sound/apulse-0.1.9" ; then
		elog "Apulse was detected at merge time on this system and so it will always be"
		elog "used for sound.  If you wish to use pulseaudio instead please unmerge"
		elog "media-sound/apulse."
	fi

	if use system-libevent || system-sqlite || system-libvpx ; then
		elog "Using out of tree critical system libraries is not supported and not recommended."
		elog "Refer to UXP #1342 / https://forum.palemoon.org/viewtopic.php?f=5&t=23706"
		elog "Usage of these means you are on your own and may face profile corruption."
		elog "Do no bother reporting said bugs upstream. You were warned."
	fi
}

pkg_postrm() {
	gnome2_icon_cache_update
}
