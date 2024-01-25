#!/var/jb/bin/sh

/var/jb/usr/libexec/firmware
/var/jb/usr/sbin/pwd_mkdb -p /var/jb/etc/master.passwd >/dev/null 2>&1
/var/jb/Library/dpkg/info/debianutils.postinst configure 99999
/var/jb/Library/dpkg/info/apt.postinst configure 999999
/var/jb/Library/dpkg/info/dash.postinst configure 999999
/var/jb/Library/dpkg/info/zsh.postinst configure 999999
/var/jb/Library/dpkg/info/bash.postinst configure 999999
/var/jb/Library/dpkg/info/vi.postinst configure 999999

/var/jb/usr/sbin/pwd_mkdb -p /var/jb/etc/master.passwd

/var/jb/usr/bin/chsh -s /var/jb/usr/bin/zsh mobile
/var/jb/usr/bin/chsh -s /var/jb/usr/bin/zsh root

if [ -z "$NO_PASSWORD_PROMPT" ]; then
    PASSWORDS=""
    PASSWORD1=""
    PASSWORD2=""
    while [ -z "$PASSWORD1" ] || [ ! "$PASSWORD1" = "$PASSWORD2" ]; do
            PASSWORDS="$(/var/jb/usr/bin/uialert -b "In order to use command line tools like \"sudo\" after jailbreaking, you will need to set a terminal passcode. (This cannot be empty)" --secure "Password" --secure "Repeat Password" -p "Set" "Set Password")"
            PASSWORD1="$(printf "%s\n" "$PASSWORDS" | /var/jb/usr/bin/sed -n '1 p')"
            PASSWORD2="$(printf "%s\n" "$PASSWORDS" | /var/jb/usr/bin/sed -n '2 p')"
    done
    printf "%s\n" "$PASSWORD1" | /var/jb/usr/sbin/pw usermod 501 -h 0
fi

rm -f /var/jb/prep_bootstrap.sh
