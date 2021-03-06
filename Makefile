VERSION = 5.85
PN = anything-sync-daemon

PREFIX ?= /usr
CONFDIR = /etc
CRONDIR = /etc/cron.hourly
INITDIR_SYSTEMD = /usr/lib/systemd/system
INITDIR_UPSTART = /etc/init.d
INITDIR_RUNIT = /etc/sv/asd
BINDIR = $(PREFIX)/bin
DOCDIR = $(PREFIX)/share/doc/$(PN)
MANDIR = $(PREFIX)/share/man/man1
ZSHDIR = $(PREFIX)/share/zsh/site-functions
BSHDIR = $(PREFIX)/share/bash-completion/completions
LOGDIR = /var/log/asd

# set to anything except 0 to enable manpage compression
COMPRESS_MAN = 1

RM = rm -f
CP = cp --preserve=all
SED = sed
INSTALL = install -p
INSTALL_PROGRAM = $(INSTALL) -m755
INSTALL_SCRIPT = $(INSTALL) -m755
INSTALL_DATA = $(INSTALL) -m644
INSTALL_DIR = $(INSTALL) -d

Q = @

common/$(PN): common/$(PN).in
	$(Q)echo -e '\033[1;32mSetting version\033[0m'
	$(Q)$(SED) 's/@VERSION@/'$(VERSION)'/' common/$(PN).in > common/$(PN)

help: install

install-bin: common/$(PN)
	$(Q)echo -e '\033[1;32mInstalling main script...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(BINDIR)"
	$(INSTALL_PROGRAM) common/$(PN) "$(DESTDIR)$(BINDIR)/$(PN)"
	ln -sf $(PN) "$(DESTDIR)$(BINDIR)/asd"
	$(INSTALL_DIR) "$(DESTDIR)$(ZSHDIR)"
	$(INSTALL_DATA) common/zsh-completion "$(DESTDIR)/$(ZSHDIR)/_asd"
	$(INSTALL_DIR) "$(DESTDIR)$(BSHDIR)"
	$(INSTALL_DATA) common/bash-completion "$(DESTDIR)/$(BSHDIR)/asd"

install-man:
	$(Q)echo -e '\033[1;32mInstalling manpage...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(MANDIR)"
	$(INSTALL_DATA) doc/asd.1 "$(DESTDIR)$(MANDIR)/asd.1"
ifneq ($(COMPRESS_MAN),0)
	gzip -9 "$(DESTDIR)$(MANDIR)/asd.1"
	ln -sf asd.1.gz "$(DESTDIR)$(MANDIR)/$(PN).1.gz"
else
	ln -sf asd.1 "$(DESTDIR)$(MANDIR)/$(PN).1"
endif

install-cron:
	$(Q)echo -e '\033[1;32mInstalling cronjob...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(CRONDIR)"
	$(INSTALL_SCRIPT) common/asd.cron.hourly "$(DESTDIR)$(CRONDIR)/asd-update"

install-systemd:
	$(Q)echo -e '\033[1;32mInstalling systemd files...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(CONFDIR)"
	$(INSTALL_DIR) "$(DESTDIR)$(INITDIR_SYSTEMD)"
	$(INSTALL_DATA) common/asd.conf "$(DESTDIR)$(CONFDIR)/asd.conf"
	$(INSTALL_DATA) init/asd.service "$(DESTDIR)$(INITDIR_SYSTEMD)/asd.service"
	$(INSTALL_DATA) init/asd-resync.service "$(DESTDIR)$(INITDIR_SYSTEMD)/asd-resync.service"
	$(INSTALL_DATA) init/asd-resync.timer "$(DESTDIR)$(INITDIR_SYSTEMD)/asd-resync.timer"

install-upstart:
	$(Q)echo -e '\033[1;32mInstalling upstart files...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(CONFDIR)"
	$(INSTALL_DIR) "$(DESTDIR)$(INITDIR_UPSTART)"
	$(INSTALL_DATA) common/asd.conf "$(DESTDIR)$(CONFDIR)/asd.conf"
	$(INSTALL_SCRIPT) init/asd.upstart "$(DESTDIR)$(INITDIR_UPSTART)/asd"

clean-runit-rc:
	sed -e '/^# ASD$$/ d' -e '/^\[ -x \/usr\/bin\/anything-sync-daemon \] && ( sync/ d' < /etc/rc.shutdown >> /etc/rc.shutdown.tmp && cp --attributes-only /etc/rc.shutdown /etc/rc.shutdown.tmp && mv -f /etc/rc.shutdown.tmp /etc/rc.shutdown

clean-runit-sv:
	-sv force-stop asd
	$(RM) "/var/service/asd"


# this should help avoid data loss issues, from the unsync failing due to runit timeout
setup-runit-rc: clean-runit-rc
	cat init/runit/etc/rc.shutdown >> /etc/rc.shutdown

setup-runit:
	$(INSTALL_DIR) "$(DESTDIR)$(INITDIR_RUNIT)"
	$(INSTALL_DIR) "$(DESTDIR)$(INITDIR_RUNIT)/log"
	$(INSTALL_DIR) -m600 "$(DESTDIR)$(LOGDIR)"
	$(INSTALL_DATA) init/runit/conf "$(DESTDIR)$(INITDIR_RUNIT)/conf"
	$(INSTALL_SCRIPT) init/runit/resync "$(DESTDIR)$(INITDIR_RUNIT)/resync"
	$(INSTALL_SCRIPT) init/runit/run "$(DESTDIR)$(INITDIR_RUNIT)/run"
	$(INSTALL_SCRIPT) init/runit/finish "$(DESTDIR)$(INITDIR_RUNIT)/finish"
	$(INSTALL_SCRIPT) init/runit/log/run "$(DESTDIR)$(INITDIR_RUNIT)/log/run"

install-runit: setup-runit setup-runit-rc
	$(Q)echo -e '\033[1;32mInstalling runit files...\033[0m'
	$(INSTALL_DATA) common/asd.conf "$(DESTDIR)$(CONFDIR)/asd.conf"
	$(Q)echo "Update /etc/asd.conf for initial configuration, and then enable runit service asd"
	$(Q)echo "Restart the service on subsequent changes"
	$(Q)echo "Update /etc/sv/asd/conf to change default resync interval, no restart needed"
	$(Q)echo "If syncing directories times out, consider increasing SVWAIT from 7 in your /etc/rc.conf"

# allows runit updates without existing asd.conf being affected.
update-runit:
	$(Q)echo -e '\033[1;32mUpdating runit files...\033[0m'
	$(MAKE) clean-runit-sv
	$(MAKE) setup-runit
	-ln -s /etc/sv/asd /var/service
	-sv start asd

install-systemd-all: install-bin install-man install-systemd

install-upstart-all: install-bin install-man install-cron install-upstart

install-runit-all: install-bin install-man install-runit

install:
	$(Q)echo "run one of the following:"
	$(Q)echo "  make install-systemd-all (systemd based systems)"
	$(Q)echo "  make install-upstart-all (upstart based systems)"
	$(Q)echo "  make install-runit-all (runit based systems)"
	$(Q)echo
	$(Q)echo "or check out the Makefile for specific rules"

uninstall-bin:
	$(RM) "$(DESTDIR)$(BINDIR)/$(PN)"
	$(RM) "$(DESTDIR)$(BINDIR)/asd"
	$(RM) "$(DESTDIR)/$(ZSHDIR)/_asd"
	$(RM) "$(DESTDIR)/$(BSHDIR)/asd"

uninstall-man:
	$(RM) "$(DESTDIR)$(MANDIR)/$(PN).1.gz"
	$(RM) "$(DESTDIR)$(MANDIR)/asd.1.gz"
	$(RM) "$(DESTDIR)$(MANDIR)/$(PN).1"
	$(RM) "$(DESTDIR)$(MANDIR)/asd.1"

uninstall-cron:
	$(RM) "$(DESTDIR)$(CRONDIR)/asd-update"

uninstall-systemd:
	$(RM) "$(DESTDIR)$(CONFDIR)/asd.conf"
	$(RM) "$(DESTDIR)$(INITDIR_SYSTEMD)/asd.service"
	$(RM) "$(DESTDIR)$(INITDIR_SYSTEMD)/asd-resync.service"
	$(RM) "$(DESTDIR)$(INITDIR_SYSTEMD)/asd-resync.timer"

uninstall-upstart:
	$(RM) "$(DESTDIR)$(CONFDIR)/asd.conf"
	$(RM) "$(DESTDIR)$(INITDIR_UPSTART)/asd"

uninstall-runit: clean-runit-rc
	$(RM) "$(DESTDIR)$(CONFDIR)/asd.conf"
	$(MAKE) clean-runit-sv
	$(RM) "$(DESTDIR)$(INITDIR_RUNIT)/run"
	$(RM) "$(DESTDIR)$(INITDIR_RUNIT)/resync"
	$(RM) "$(DESTDIR)$(INITDIR_RUNIT)/finish"
	$(RM) "$(DESTDIR)$(INITDIR_RUNIT)/conf"
	$(RM) -r "$(DESTDIR)$(INITDIR_RUNIT)/supervise"
	-$(RM) -d "$(DESTDIR)$(INITDIR_RUNIT)"

uninstall-all: uninstall-bin uninstall-man backup-conf

uninstall-systemd-all: uninstall-all uninstall-systemd

uninstall-upstart-all: uninstall-all uninstall-cron uninstall-upstart

uninstall-runit-all: uninstall-all uninstall-runit

uninstall:
	$(Q)echo "run one of the following:"
	$(Q)echo "  make uninstall-systemd-all (systemd based systems)"
	$(Q)echo "  make uninstall-upstart-all (upstart based systems)"
	$(Q)echo "  make uninstall-runit-all (runit based systems)"
	$(Q)echo
	$(Q)echo "or check out the Makefile for specific rules"

clean:
	$(RM) common/$(PN)

backup-conf:
	$(CP) "$(DESTDIR)$(CONFDIR)/asd.conf" "$(DESTDIR)$(CONFDIR)/.asd.conf.bak"

restore-conf:
	mv -f "$(DESTDIR)$(CONFDIR)/.asd.conf.bak" "$(DESTDIR)$(CONFDIR)/asd.conf"

.PHONY: help install-bin install-man install-cron install-systemd install-upstart setup-runit install-runit install-systemd-all install-upstart-all install-runit-all install uninstall-bin uninstall-man uninstall-cron uninstall-systemd uninstall-upstart uninstall-runit uninstall-systemd-all uninstall-runit-all uninstall clean clean-runit-rc setup-runit-rc backup-conf restore-conf uninstall-all
