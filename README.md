# Tiny4Containerd

Tiny4Containerd is a lightweight Linux distribution made specifically to run containers on bare metal.
<br/>It runs completely from RAM.

Tiny4Containerd 是一个轻量级，运行于内存中的 linux，用于在裸机上快速部署容器环境。

---------
# Licensing
tiny4containerd is licensed under the Apache License, Version 2.0. See
[LICENSE](https://github.com/binave/tiny4containerd/blob/master/LICENSE) for the full
license text.

import:
* [kernel](https://www.kernel.org)
* [Docker](https://www.docker.com/)
* [cgroupfs-mount](https://github.com/tianon/cgroupfs-mount)

---------

If you want to SSH into the machine, the credentials are:
<br/>如果你需要通过 SSH 登陆设备，初始账号密码如下。

```
user: tc
pass: tcuser
```

---------

#### Install on any device

To 'install' the ISO onto an SD card, USB-Stick or even empty hard disk, you can
use `dd if=tiny4containerd.iso of=/dev/sdX`.  This will create the small boot
partition, and install an MBR.
<br/>如果想要将 ISO 文件安装到 SD 卡或其他 USB 接口的空存储介质，可以
使用 `dd if=tiny4containerd.iso of=/dev/sdX` 命令。

If make sure the disk is empty for real, initialise to md array, create a logical volume, format it.
<br/>如果启动中检测到一个空硬盘，会自动初始化成 RAID，并在上面建立 LVM2 分区。
<br/>If there is a logical volume name `lv_data` and `lv_log`, mount it.
<br/>如果启动中检测到一个逻辑卷名为 `lv_data` 和 `lv_log`，会对其进行自动挂载。
<br/>
<br/>卷标为 `lv_log` 的逻辑卷会挂载到 `/log` 目录上。
<br/>逻辑卷 `lv_data` 中的以下目录会被挂载到根目录上：

```
/home
/var
/tmp
/run
```

如果没有相应目录，会自动建立并挂载。
<br/>注意：没有对 SSD （固态硬盘）进行特别处理。
<br/>相同型号 SSD 组成的 RAID ，可能出现寿命同时用尽的情况，会增加数据永久丢失的风险。

---------

# FAQ

### Q: 如何进行自定义配置
A:
> 卷标为 `lv_data` 的逻辑卷，存在多个配置文件
> 依执行顺序：

> |路径|说明|样例|备注
> |---|---|---|---
> |/var/etc/pw.cfg|密码配置|`root::$1$AgCGptrX$hL7QB536iJ9KKjO1KtfVA.`|使用 `openssl passwd -1 [password]` 生成加密密码
> |/var/etc/if.cfg|静态 ip 配置|`eth0 192.168.1.123 192.168.1.255 255.255.255.0`|
> |/var/etc/init.d/[SK]*.sh|启动、关机脚本|S01_ftpd.sh K20_ftpd.sh|`S*.sh` 在服务启动前执行<br/>`K*.sh` 设备关机前执行
> |/var/etc/env.cfg|环境变量配置|`EXTRA_ARGS="--registry-mirror=https://xxx.mirror.aliyuncs.com"`|
> |/var/etc/rc.local|启动最后阶段执行||需要赋予可执行权限
> |isolinux.cfg|启动参数和环境变量配置||需要编辑源代码中的配置文件
<p><br/></p>

### Q: 如果磁盘空间不足怎么办？
A:
> 使用 `mdisk` 命令的 `expand` 子命令进行分区扩容。需要在执行前安装好新的存储设备。
> 不同场景：
> <br/>在 `isolinux.cfg` 文件的 `APPEND` 字符后插入 `noraid` 字符，会忽略所有的磁盘阵列，仅将一个新硬盘加入现有的 LVM 中。
> <br/>不使用 `noraid` 的情况下：为了保证分区对齐，`expand` 命令要求空闲硬盘能够组成的新阵列，必须与原有磁盘 RAID 等级相同，否则会失败。
> <br/>`noraid` 是为了支持 `硬件 RAID 卡` 而设计的。通常情况下建议使用磁盘阵列以降低数据丢失的风险。
<p><br/></p>

### Q: 使用 RAID 模式时必须使用多块硬盘吗？
A:
> 可以使用单块硬盘，单块硬盘会初始化成 `RAID 1`，阵列里会留有一个空位。
> <br/>你可以在使用一段时间之后，加入一块相同容量的空硬盘。它会在系统启动（或使用 `mdisk rebuild` 命令）时自动修补之前的 RAID。
> <br/>Tiny4Containerd 将只支持 `RAID 1` 和 `RAID 5`，且不支持阵列嵌套。
<p><br/></p>

### Q: 如何让新加入的硬盘用于扩容，而不是在重启操作系统时进行 RAID 修补。
A:
> 安装的新硬盘只有在使用的 RAID 不完整，并且经过装载步骤的情况下才会用于 RAID 修补。
> <br/>在 `isolinux.cfg` 文件的 `APPEND` 字符后插入 `noautorebuild` 字符，会在装载时跳过修补，然后登陆后使用 `mdisk expand` 命令来手动进行扩容。
> <br/>如果使用热插拔硬盘，只要避免重启操作系统，执行 `mdisk expand` 命令即可。
<p><br/></p>

### Q: 新增命令有哪些环境变量？
A:
> `Dockerfile` 的 `ENV` 配置：

> |环境变量名称|默认值|说明
> |---|---|---
> |OUTPUT_PATH|/|默认输出路径（容器中）
> |TIMEOUT_SEC|600|超时时间（秒）
> |TIMELAG_SEC|5|循环间隔（秒）
> |TMP|/tmp|临时目录
> |KERNEL_MAJOR_VERSION|4.9|内核版本
<br/>

> 在 `isolinux.cfg` 文件的 `APPEND` 字符后加入：（键值对使用 `=` 连接）

> |名称|默认值|说明|所属命令|备注
> |---|---|---|---|---
> |nodisk||忽略所有硬盘|mdisk init|
> |noraid||忽略所有 RAID 设备和相关逻辑|mdisk init|
> |noautorebuild||跳过 RAID 修补|mdisk init|
> |BYTES_PER_INODE|8192|修改文件系统存储文件数量上限|mdisk|不建议修改
> |DISK_PREFIX|sd|磁盘前缀名称|mdisk|需要根据硬件进行调整
> |LOG_EXTENTS_PERCENT|15|`lv_log` 分区占用百分比|mdisk|
> |BLOCK_SIZE|4|区块大小|mdisk|不建议修改
> |CHUNK|128|RAID 块大小|mdisk|不建议修改
<br/>

> 公用配置 `/var/etc/env.cfg`：

> |环境变量名称|默认值|说明|所属命令|备注
> |---|---|---|---|---
> |CROND_LOGLEVEL|8|crond 日志等级，0 为最详细|crond|
> |PW_CONFIG|/var/etc/pw.cfg|密码配置|pwset
> |IF_CONFIG|/var/etc/if.cfg|静态 ip 配置|ifset|
> |IF_PREFIX|eth|网卡前缀名称|ifset, containerd|需要根据硬件进行调整
> |CONTAINERD_ULIMITS|1048576|进程数上限|containerd|
> |CONTAINERD_HOST|`-H tcp://0.0.0.0:2375`|监听 hosts|containerd|
> |CONTAINERD_USER|tc|默认用户名|containerd|如果修改需要自己建立用户
> |ORG|tinycorelinux|证书组织名称|containerd|
> |SERVER_ORG|tinycorelinux|服务端证书组织名称|containerd|
> |CA_ORG|tinycorelinuxCA|根证书名称|containerd|
> |CERT_DAYS|365|证书有效期|containerd|
> |WAIT_LIMIT|20|重试次数极限|containerd|
> |SSHD_PORT|22|监听端口|sshd|
<p><br/></p>

### Q: 可以自定义容器启动顺序吗？
A:
> 可以建立 `~/.container_start` 配置文件。
> <br/> 同一行的多个 `container id` 会被同时启动。
> <br/> 不同行之间可以插入 `sleep [sec]` 用以延迟启动时机。
> <br/> 用 `!` 标记的行，后方的 `container id` 将不会被启动（每行仅可以使用一个 `!`）。
> <br/> 不在配置文件中的 `container id` 会在最后被同时启动。
> <br/><br/> e.g.
```
!0123456789ab cdef01234567  # 不启动
89abcdef0123
sleep 2                     # 间隔 2 秒
456789abcdef ba9876543210
```

### Q: 如何加快操作日志记录频率。
A:

> 在 `root` 用户下，使用 `crontab -e` 编辑定时任务，加入以下命令：

```sh
*/5 * * * * /usr/local/sbin/wtmp
```

> 在登陆触发日志记录操作以外，增加每 5 分钟记录一次的操作。
