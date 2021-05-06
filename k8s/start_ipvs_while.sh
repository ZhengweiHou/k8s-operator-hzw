#!/bin/bash
# ipvs内核模块地址
ipvs_mods_dir="/usr/lib/modules/$(uname -r)/kernel/net/netfilter/ipvs"
# 遍历所有ipvs组件，并启动
for i in $(ls $ipvs_mods_dir | grep -o "^[^.]*")
do
    /sbin/modinfo -F filename $i &>/dev/null
    if [ $? -eq 0 ]; then
        echo "/sbin/modprobe $i"
        /sbin/modprobe $i
    fi
done
