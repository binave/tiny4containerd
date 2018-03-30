#!/bin/busybox ash
# /etc/init.d/rc.shutdown - used by /etc/inittab to shutdown the system.
#
. /etc/init.d/tc-functions
useBusybox

clear
Ymd=`date +%Y%m%d`;
LOG_DIR=/log/tiny/${Ymd:0:6};
mkdir -p $LOG_DIR;

{
    printf "\n\n[`date`]\n";

    # stop container daemon
    /usr/local/sbin/containerd stop;

    # shutdown script
    find /opt/tiny/etc/init.d -type f -perm /u+x -name "K*.sh" -exec /bin/sh -c {} \;

    /usr/local/sbin/wtmp;

    # PID USER COMMAND
    ps -ef | grep "crond\|monitor\|ntpd\|sshd\|udevd" | awk '{print "kill "$1}' | sh 2>/dev/null

} 2>&1 | tee -a $LOG_DIR/shut_$Ymd.log;

unset LOG_DIR Ymd;

# Sync all filesystems.
sync; sleep 1; sync; sleep 1;

# Unload disk
/usr/local/sbin/mdisk destroy;

echo -n "${NORMAL}";

# Unmount all tcz extensions that were mounted into /tmp/tcloop via loopback
for loop in $(mount | awk '/\/tmp\/tcloop/{print substr($1,10,3)}'|sort -nr);
do
    umount -d /dev/loop"$loop" 2>/dev/null;
done

# Unmount all scm extensions that were mounted into /opt via loopback
for loop in $(mount | awk '/\/opt/{print substr($1,10,3)}'|sort -nr);
do
    umount -d /dev/loop"$loop" 2>/dev/null;
done

if [ -s /tmp/audit_marked.lst ]; then
    echo "${BLUE}Removing requested extensions:";
    ONBOOTNAME="$(getbootparam lst 2>/dev/null)";
    [ -n "$ONBOOTNAME" ] || ONBOOTNAME="onboot.lst";
    for F in `cat /tmp/audit_marked.lst`;
    do
        echo "${YELLOW}$F";
        rm -f "$F"*;
        FROMDIR=`dirname "$F"` && TCEDIR=${FROMDIR%/*};
        EXTN=`basename "$F"`;
        APP=${EXTN%.tcz};
        LIST="$TCEDIR"/copy2fs.lst;
        ONBOOT="${TCEDIR}/${ONBOOTNAME}";
        XWBAR="$TCEDIR"/xwbar.lst;
        if grep -w "$EXTN" "$LIST" >/dev/null 2>&1; then
            sed -i '/'"$EXTN"'/d' "$LIST";
        fi
        if grep -w "$EXTN" "$ONBOOT" >/dev/null 2>&1; then
            sed -i '/'"$EXTN"'/d' "$ONBOOT";
        fi
        if grep -w "$EXTN" "$XWBAR" >/dev/null 2>&1; then
            sed -i '/'"$EXTN"'/d' "$XWBAR";
        fi
        [ -s "$FROMDIR"/tce.db ] && rm -f "$FROMDIR"/tce.db;
        [ -s "$FROMDIR"/tce.lst ] && rm -f "$FROMDIR"/tce.lst;
        rm -f "$TCEDIR"/ondemand/$APP* 2>/dev/null
    done

    rm -f /tmp/audit_marked.lst;
    sync; sleep 1; sync; sleep 1;
    echo "${NORMAL}"
fi

# Umount filesystems.
echo "${BLUE}Unmounting all filesystems. ";
echo -n "${NORMAL}";

TCE=$(readlink /etc/sysconfig/tcedir)
if [ -d "$TCE" ]; then
    TCEMOUNT=${TCE%/*};
    [ -z "$TCEMOUNT" ] || umount "$TCEMOUNT" 2>/dev/null
fi

if [ -s /etc/sysconfig/backup_device ]; then
    BACKUP=`cat /etc/sysconfig/backup_device`;
    BACKUPDEVICE=/mnt/${BACKUP%/*};
    umount "$BACKUPDEVICE" 2>/dev/null
fi

umount -arf >/dev/null 2>&1;

echo "Shutdown in progress.";
sync;

echo
