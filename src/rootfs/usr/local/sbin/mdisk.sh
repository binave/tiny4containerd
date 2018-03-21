#!/bin/sh
#   Copyright 2018 bin jin
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin;

[ $(id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# skip this script. edit: isolinux.cfg -> append
grep -q 'nodisk' /proc/cmdline 2>/dev/null && {
    printf "[WARN] skip load disk.\n" >&2;
    exit 0
};

# import settings from profile
for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

# stop rebuild when assemble
grep -q 'noautorebuild' /proc/cmdline 2>/dev/null && NOAUTOREBUILD=1 || unset NOAUTOREBUILD;

# mkfs
: ${DISK_PREFIX:=sd};
: ${BYTES_PER_INODE:=8192};
: ${LOG_EXTENTS_PERCENT:=15};

# RAID
: ${BLOCK_SIZE:=4};
: ${CHUNK:=128};

Ymd=`date +%Y%m%d`;

# test disk
ls /dev/$DISK_PREFIX? >/dev/null 2>&1 || {
    printf "[ERROR] no disk found.\n" >&2;
    exit 1
};

# stride calculation
# https://busybox.net/~aldot/mkfs_stride.html
# [ raid_level ] [ disk_count ]
_stride_calculation() {
    # test integer. if the result is a negative number, will return an error
    expr $1 + $2 + 1 >/dev/null 2>&1 || {
        printf "[ERROR] args: '$1', '$2'.\n" >&2;
        return 1
    };

    local stride=$(expr $CHUNK / $BLOCK_SIZE) \
        stripe_width=0 lvl="$1" effective_disks="$2";

    # has to be multiple of 2
    [ $stride -gt 0 -a $(expr $stride % 2) == 0 ] && {
        if [ $lvl == 6 ]; then
            effective_disks=$(expr $effective_disks - 2);
        elif [ $lvl == 5 ]; then
            effective_disks=$(expr $effective_disks - 1);
        elif [ $lvl == 1 -o $lvl == 10 ]; then
            effective_disks=$(expr $effective_disks / 2);
        fi
        stripe_width=$(expr $stride \* $effective_disks)
    };

    printf %s " -b $(expr $BLOCK_SIZE \* 1024)";
    [ $stride -gt 0 -o $stripe_width -gt 0 ] && printf %s " -E ";
    [ $stride -gt 0 ] && printf "stride=$stride";
    [ $stride -gt 0 -a $stripe_width -gt 0 ] && printf %s ",";
    [ $stripe_width -gt 0 ] && printf %s "stripe-width=$stripe_width";

    return 0

}

# return a new RAID device path
_md_dev_path() {
    local md_dev_num=0;
    while [ -e /dev/md$md_dev_num ];
    do
        md_dev_num=$(expr $md_dev_num + 1);
        [ $md_dev_num -ge 512 ] && {
            printf "[ERROR] out of range\n" >&2;
            return 1
        }
    done
    printf $md_dev_num
}

# format: Disk [/dev/sd?]: [[0-9]+ [MGT]B], [0-9]+ bytes, [0-9]+ sectors
_disk_bytes_table() {
    fdisk -l $@ 2>/dev/null | grep -B 4 "doesn't contain a valid partition table" | grep bytes,
}

# create raid by empty disk, args: [/dev/*] ...
_create_raid() {
    [ $# == 0 ] && {
        printf "[ERROR] args is empty.\n" >&2;
        return 1
    };

    local level args device dev_count bytes_table;

    # test use by other raid
    mdadm --query $@ 2>/dev/null | grep -q raid && {
        printf "[ERROR] some of the disk are occupied by other RAID.\n" >&2;
        return 1
    };

    # bytes info list
    bytes_table=$(_disk_bytes_table $@);

    if [ $# -gt 1 ]; then
        # test disk size same
        printf "$bytes_table" | awk '{print $5}' | uniq -u | grep -q '[0-9]' && {
            printf "[ERROR] disk size is not exactly the same.\n" >&2;
            return 1
        }
    fi

    # test disk count
    dev_count=$(printf "$bytes_table" | grep -c bytes,);
    [ $dev_count == $# ] || {
        printf "[ERROR] $(expr $# - $dev_count) disk already in use.\n" >&2;
        return 1
    };

    # reset count
    dev_count=$#;

    case $# in
        1|2)
            # raid 1
            level=1
        ;;
        3|4)
            # raid 5
            level=5
        ;;
        *)
            # raid 5 with spare
            level=5;
            dev_count=4;
            args="--spare-devices=1"
        ;;
    esac

    # get new raid path
    device=/dev/md$(_md_dev_path);

    {
        printf "\nmdadm: create array $device, raid$level: $1 $2 $3 $4 $5\n";

        # create raid
        echo y | mdadm --create $device --level=$level --chunk=$CHUNK \
            --raid-devices=$dev_count $args --force $1 $2 $3 $4 $5;

        # if raid 1, source count must greater than 1, change the number of active devices in an array
        [ $# == 1 ] && {
            mdadm --grow $device --force --raid-devices=2 >&2;
            dev_count=2
        };

    } >&2; # stderr

    printf "$device $level $dev_count";
    return 0 # if not continue
}

_full_swap_size() {
    # mem and min disk bytes
    local mem=$(free -b | grep Mem | awk '{print $2}') mdisk=$(
        _disk_bytes_table /dev/$DISK_PREFIX? | awk '{print $5}' | sort -n | head -1
    );

    [ ${#mdisk} -gt ${#mem} ] && return 0;
    [ ${#mem} -gt ${#mdisk} ] && return 1;
    [ $(expr ${mdisk:0:2} / 2) -ge ${mem:0:2} ] && return 0;
    return 1
}

# [ /dev/(md?|sd?) ] [[ $raid_level $disk_count ]]
_create_lvm() {
    [ "/dev/" == "${1:0:5}" ] || {
        printf "[ERROR] path: '$1'\n" >&2;
        return 1
    };

    local vg_name device=$1 mkfs_stride;

    if [ "$3" ]; then
        mkfs_stride=`_stride_calculation $2 $3` || return 1
    fi

    # init pv
    pvcreate $device --dataalignment ${CHUNK}k;

    # init vg
    vg_name=vg_$(mdadm --detail $device | grep UUID | awk -F: '{print $5}');
    vgcreate $vg_name $device;

    # create swap partition
    if _full_swap_size; then
        lvcreate --size $(free -m | grep Mem | awk '{print $2}')M --name lv_swap $vg_name || return 1;
    else
        lvcreate --extents 30%VG --name lv_swap $vg_name || return 1;
    fi

    mkswap /dev/$vg_name/lv_swap;

    # print mkfs args
    printf "\nmkfs.ext4 -i $BYTES_PER_INODE $mkfs_stride /dev/$vg_name/...\n\n";

    # log partition
    lvcreate --extents $LOG_EXTENTS_PERCENT%FREE --name lv_log $vg_name;
    mkfs.ext4 -i $BYTES_PER_INODE $mkfs_stride /dev/$vg_name/lv_log || return 1;

    # data partition
    lvcreate --extents 100%FREE --name lv_data $vg_name;
    mkfs.ext4 -i $BYTES_PER_INODE $mkfs_stride /dev/$vg_name/lv_data;

    # unactive vg
    vgchange --activate n $vg_name;

    return 0
}

_extend_lvm() {
    local vg_name device=$1;

    for vg_name in $(__vg_list);
    do

        [ -e /dev/$vg_name/lv_data ] || continue;

        # init pv
        pvcreate $device --dataalignment ${CHUNK}k;
        vgextend $vg_name $device;

        # lvextend --extents $LOG_EXTENTS_PERCENT%VG --resizefs /dev/$vg_name/lv_log;
        lvextend --extents $LOG_EXTENTS_PERCENT%VG /dev/$vg_name/lv_log;
        resize2fs -F -p /dev/$vg_name/lv_log;

        # lvextend --extents +100%FREE --resizefs /dev/$vg_name/lv_data;
        lvextend --extents +100%FREE /dev/$vg_name/lv_data;
        resize2fs -F -p /dev/$vg_name/lv_data;
        return 0
    done

    printf "[ERROR] no vg extend.\n" >&2;
    return 1

}

# list of unused disk, format: [device_path]\n
_idle_disk_list() {
    {
        fdisk -l /dev/$DISK_PREFIX? 2>/dev/null | grep "doesn't contain a valid partition table" | awk '{print $2}';
        mdadm --query /dev/$DISK_PREFIX? 2>/dev/null | grep raid | awk '{gsub(/:/,"");print $1}'
    } 2>/dev/null | sort | uniq -u
}

# format: [raid_level] [uuid] [id] [count] [device_path]\n
_raid_dev_info_table() {
    mdadm --examine /dev/$DISK_PREFIX? 2>/dev/null | grep '\/dev\|Array UUID\|Level\|Devices\|Role' | \
        sed 's/\w\+ \w\+ ://g;s/Active device//g;s/spare/-1/g' | awk -F: '{gsub(/\/d/,"\n\/d");printf $1}' | \
        grep '[0-9a-f]\+' | awk '$5 != "" {print $3" "$2" "$5" "$4" "$1}' | sort
}

# format: [raid_path] [uuid]\n
_md_uuid_table() {
    mdadm --detail /dev/md* | grep '^\/dev\|UUID' | sed 's/^\//:&/g' | \
        awk -F: '{gsub(/\/d/,"\n\/d");printf $2}' | grep '[0-9a-f]\+'
}

# Model, SerialNo
_disk_model_serial_no() {
    set $(hdparm -i $1 | grep = | sed 's/[=,]/ /g') >/dev/null;
    printf ":";
    while [ "$2" ];
    do
        [ "${1/odel/}" != "$1" -o "${1/erial/}" != "$1" ] && printf " $1=$2";
        shift
    done
    printf "\n"
}

# load all raid
_assemble_raid() {
    local count_diff work_raid_list raid_dev raid_dev_info_table uuid re_path;

    raid_dev_info_table=$(_raid_dev_info_table);

    # get raid uuid exclude list
    work_raid_list=$(mdadm --detail /dev/md* 2>/dev/null | grep UUID | awk -F: '{printf $2}');

    # uuid list
    for uuid in $(printf "$raid_dev_info_table" | awk '{print $2}' | uniq);
    do
        # if already load, skip it
        [ "${work_raid_list/$uuid/}" == "$work_raid_list" ] || continue;

        # if raid disk count error, skip it
        re_path=$(_rebuild_and_array_disk_path $uuid 2>/dev/null) || return 1;
        set $re_path; # will drop error status
        re_path=$1; # reset re_path
        shift;

        # new raid path
        raid_dev=/dev/md$(_md_dev_path);

        # assemble raid
        mdadm --assemble --run $raid_dev $* || return 1;

        # rebuild raid
        [ ! "$NOAUTOREBUILD" -a "$re_path" != "NULL" ] && \
            mdadm --manage $raid_dev --add $re_path;

        # variable extend
        work_raid_list="$work_raid_list $uuid"
    done

    # TODO stop unwork raid path
}

# get min disk path, args: [uuid], env: [raid_dev_info_table]
# if raid disk count error, return 1
# return [/dev/sd?|NULL] /dev/sd? ...
_rebuild_and_array_disk_path() {
    [ "$raid_dev_info_table" ] || return 0;

    local uuid=$1 count_diff each_uuid_raid_info idle_disk_list min_size dev_path;

    # global variable
    each_uuid_raid_info=$(printf "$raid_dev_info_table" | grep "$uuid");

    # tag disk count - real disk count
    count_diff=$(
        expr $(printf "$each_uuid_raid_info" | tail -1 | awk '{print $4}') - \
            $(printf "$each_uuid_raid_info" | grep -c 'dev')
    );

    # if disk count diff greater than 1, error
    [ $count_diff -gt 1 ] && {
        printf "[ERROR] $count_diff RAID broken, UUID:'$uuid'.\n" >&2;
        return 1
    };

    idle_disk_list=$(_idle_disk_list);

    # TODO $count_diff == 0: add

    if [ $count_diff == 1 -a "$idle_disk_list" ]; then
        # get min size in this raid
        min_size=$(
            _disk_bytes_table $(printf "$each_uuid_raid_info" | awk '{printf " "$5}') | awk '{print $5}' | sort -n | head -1
        );

        # get same size empty disk
        dev_path=$(
            _disk_bytes_table $idle_disk_list | grep "$min_size" | head -1 | awk '{gsub(/:/,"");print $2}'
        )
    else
        [ "$idle_disk_list" ] || printf "[WARN] no unused disk found.\n" >&2
    fi

    [ "$dev_path" ] && printf "$dev_path" || printf %s 'NULL';

    # show raid disk list
    printf "$each_uuid_raid_info" | awk '{printf " "$5}';

    return 0
}

__vg_list() {
    vgdisplay | grep Name | awk '{print $3}'
}

_lv_online() {
    local lv vg lv_swap lv_data lv_log;

    for vg in $(__vg_list);
    do
        # active vg
        vgchange --activate y $vg;

        for lv in $(lvdisplay | grep Path | grep "$vg" | awk '{print $3}');
        do
            if [ "${lv##*/}" == "lv_swap" ]; then
                lv_swap="$lv"
            elif [ "${lv##*/}" == "lv_data" ]; then
                lv_data="$lv"
            elif [ "${lv##*/}" == "lv_log" ]; then
                lv_log="$lv"
            fi
        done
    done

    if [ ! "$vg" ]; then
        printf "[ERROR] no LVM found.\n" >&2;
        return 1
    fi

    [ -e "$lv_swap" -a -e "$lv_data" -a -e "$lv_log" ] || {
        printf "[ERROR]";
        [ -e "$lv_swap" ] || printf " 'lv_swap'";
        [ -e "$lv_data" ] || printf " 'lv_data'";
        [ -e "$lv_log" ] || printf " 'lv_log'";
        printf " load failed.\n";
        return 1
    } >&2;

    # off old swap
    swapoff -a 2>/dev/null;
    swapon $lv_swap;

    # data
    mkdir -p $PERSISTENT_DATA;
    mount $lv_data $PERSISTENT_DATA;

    # log
    mkdir -p $PERSISTENT_DATA/log;
    mount $lv_log $PERSISTENT_DATA/log;

    _dir_online $PERSISTENT_DATA;
    return 0
}

_dir_online() {
    # clean $PERSISTENT_DATA/*
    mkdir -p \
        $1/run \
        $1/home \
        $1/tmp;

    # create work, opt path
    printf "\nmount:";
    mount --bind $1/run /run && printf ", '/run'";

    # change home path
    if [ -d $1/home/*map ]; then
        rm -fr /home/*;
    else
        mv -f /home/* $1/home
    fi
    mount --bind $1/home /home && printf ", '/home'";

    # Make sure /tmp is on the disk too too
    rm -fr /tmp/*;
    mount --bind $1/tmp /tmp && printf ", '/tmp'";

    printf "\n";

    return 0
}

# unload device
_lv_offline() {
    umount -f /log;
    umount -f /mnt/data;

    # umount -afr >/dev/null 2>&1;

    local vg vg_list=$(__vg_list);
    # lv offline
    for vg in $vg_list;
    do
        # unload swap
        swapoff /dev/$vg/lv_swap 2>/dev/null;
        # unload vg
        vgchange --activate n $vg
    done

    # all
    swapoff -a 2>/dev/null;

    # raid offline
    for vg in $vg_list;
    do
        mdadm --stop $(
            pvdisplay | grep 'Name' | grep -B 1 "$vg" | grep 'PV' | awk '{print $3}'
        ) 2>/dev/null
    done
}

_logger() {
    local mdisk_log="$PERSISTENT_DATA/log/tiny/${Ymd:0:6}/${0##*/}_$Ymd.log";
    mkdir -p "${mdisk_log%/*}";
    awk '{print strftime("%F %T, '"$@"'") $0}' >> $mdisk_log
}

_log_out() {
    local mdisk_log="$PERSISTENT_DATA/log/tiny/${Ymd:0:6}/${0##*/}_$Ymd.log";
    mkdir -p "${mdisk_log%/*}";
    tee -a $mdisk_log
}

# main
_init() {
    [ -d $PERSISTENT_DATA/log ] && {
        printf "[WARN] disk is already initialized.\n" >&2;
        return 0
    };

    if $NORAID; then
        _lv_online || \
            _create_lvm $(_disk_bytes_table | head -1 | awk '{gsub(/:/,"");print $2}') && \
                _lv_online
    else
        # test have raid
        if mdadm --query /dev/$DISK_PREFIX? | grep -q raid; then
            # support assemble all raid
            _assemble_raid
        else
            # get unused disk column, convert to row
            local row=`_idle_disk_list`;
            _create_lvm `_create_raid $row` || return 1

        fi
        _lv_online
    fi

    printf "disk loading complete.\n"
}

_destroy() {
    umount -f /home;
    umount -f $PERSISTENT_DATA;
    umount -f /run;
    umount -f /tmp;
    _lv_offline;
    printf "disk offline complete.\n"
}

# lvm extend
_expand() {
    if $NORAID; then
        ls /dev/md* 2>/dev/null && {
            printf "[ERROR] not support 'NORAID' mod.\n" >&2;
            return 1
        };

        _extend_lvm $(_idle_disk_list | head -1)

    else
        #----- create raid at same level -----#
        local md_dev_count new_load_dev_count md_uuid_table raid_dev_info_table status;

        raid_dev_info_table=$(_raid_dev_info_table);

        md_uuid_table=$(_md_uuid_table)

        # get disk count from use raid
        md_dev_count=$(
            printf "$raid_dev_info_table" | grep $(
                # get uuid
                printf "$md_uuid_table" | grep "$(
                    # use pv dev path
                    pvdisplay | grep 'PV Name' | head -1 | awk '{print $3}'
                )" | awk '{print $2}'
            ) | tail -1 | awk '{print $4}'
        );

        # counting disk list
        disk_list=$(_idle_disk_list | head -$md_dev_count);

        new_load_dev_count=$(printf "$disk_list" | grep -c 'dev');

        status=true;
        [ $new_load_dev_count == $md_dev_count ] || {
            status=false;
            [ $md_dev_count == 2 ] && [ $new_load_dev_count == 1 ] && status=true
        };

        # TODO 5 disk;

        $status || {
            printf "[ERROR] insufficient number of disk: $new_load_dev_count/$md_dev_count\n" >&2;
            return 1
        };

        _extend_lvm `_create_raid $disk_list`;

        $0 monitor
    fi
}

# add spare disk
_add() {
    [ "/dev/md" == "${1:0:7}" -a "/dev/" == "${2:0:5}" ] || {
        printf "[ERROR] not a disk path.\n" >&2;
        return 1
    };
    [ -e $1 -a -e $2 ] || {
        printf "[ERROR] path not found.\n" >&2;
        return 1
    };

    # assuming the same capacity
    local src_dev=$(mdadm --detail $1 | grep dev | sed 's/[ ]\+/\n/g' | grep dev | tail -1);
    [ -e $src_dev ] || {
        printf "[ERROR] '$src_dev' not found.\n" >&2;
        return 1
    };

    # test size same
    fdisk -l $src_dev $2 | grep bytes, | awk '{print $5}' | uniq -u | grep -q '[0-9]' && {
        printf "[ERROR] disk capacity mismatch.\n" >&2;
        return 1
    };

    mdadm --manage $1 --add $2
}

# make disk scrap
_fail() {
    # get disk SerialNo and Model
    {
        printf "[Fail] $2";
        [ -e $2 ] || {
            printf ", drive lost.\n";
            return 0
        };
        _disk_model_serial_no $2;
    } | tee -a /etc/motd;

    mdadm --manage $1 --fail $2 --remove $2;

    local md_info;
    md_info=$(mdadm --examine $2 2>/dev/null | grep 'Array UUID\|Level\|Devices\|Role');

    # cut info
    [ ${#md_info} -gt 446 ] && md_info=${md_info:0:446};

    #
    printf "$md_info" | dd of=$2 seek=$(expr 446 - ${#md_info}); sync;

    # https://en.wikipedia.org/wiki/Master_boot_record

    # # clear disk info
    # dd if=/dev/zero of=$2 bs=1 count=512; sync;

    # # clear mbr
    # dd if=/dev/zero of=$2 bs=1 count=446; sync;

    # # clear partition info
    # dd if=/dev/zero of=$2 bs=1 seek=446 count=66; sync;

    # # backup partition info
    # dd if=$2 of=/tmp/pbr.bak bs=1 skip=446 count=66; sync;

    # erase the MD superblock
    mdadm --misc --zero-superblock $2;

    # create a new empty DOS partition table, skip 'doesn't contain a valid partition table'
    printf "o\nw\n" | fdisk $2
}

# rebuild raid
_rebuild() {
    $NORAID && {
        printf "[ERROR] not raid mod.\n" >&2
        return 1
    };

    local raid_dev_info_table md_uuid_table devs_path raid_dev;

    #----- manage add -----#
    raid_dev_info_table=$(_raid_dev_info_table);

    # no raid found
    [ "$raid_dev_info_table" ] || return 0;

    md_uuid_table=$(_md_uuid_table);

    for uuid in $(printf "$raid_dev_info_table" | awk '{print $2}' | uniq);
    do
        devs_path=$(_rebuild_and_array_disk_path $uuid) || return 1;
        set $devs_path; # will drop error status
        [ "$1" == "NULL" ] && continue;

        raid_dev=$(printf "$md_uuid_table" | grep "$uuid" | awk '{print $1}');
        mdadm --manage $raid_dev --add $1
    done
}

# find 'noraid' tag
grep -q 'noraid' /proc/cmdline 2>/dev/null && NORAID=true || NORAID=false;

# main
# TODO change hostname
case $1 in
    init) _init;;
    status)
        cat /proc/mdstat | grep -v '<none';
        printf "unused devices:";
        _idle_disk_list | awk '{printf " "$1}';
        printf "\n"
    ;;
    Fail) _fail $2 $3 2>&1 | _logger;;
    monitor)
        ls /dev/md* >/dev/null 2>&1 || exit 1;

        # kill monitor
        cat $PERSISTENT_DATA/run/md.pid 2>/dev/null | xargs kill 2>/dev/null;

        # mdadm --monitor --oneshot /dev/md*
        mdadm --monitor --program=$0 --daemonise --pid-file=$PERSISTENT_DATA/run/md.pid /dev/md*
        # mdadm --monitor --mail=root@localhost --program=$0 --daemonise --pid-file=$PERSISTENT_DATA/run/md.pid /dev/md*
    ;;
    add) _add $2 $3 2>&1 | _log_out;;
    rebuild) _rebuild 2>&1 | _log_out;;
    expand) _expand 2>&1 | _log_out;;
    destroy) _destroy;;
    *)
        echo "$@" | _logger "ARGS: ";
        echo "Usage ${0##*/} {init|status|add|rebuild|expand|destroy}" >&2;
        exit 1
    ;;
esac
# TODO reset hostname
