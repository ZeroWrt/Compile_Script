#!/bin/bash

# 彩色输出函数
color_output() {
    echo -e "$1"
}

# 打印协议条款
agreement() {
    clear
    color_output "\e[36m======================================\e[0m"
    color_output "\e[36m  本脚本用于 OpenWrt 固件编译环境配置\e[0m"
    color_output "\e[36m  请仔细阅读以下条款:\e[0m"
    color_output "\e[36m======================================\e[0m"
    color_output ""
    color_output "\e[33m  1. 本脚本可能涉及修改系统配置，请谨慎运行。\e[0m"
    color_output "\e[33m  2. 运行本脚本即表示您已知晓风险，并自行承担责任。\e[0m"
    color_output "\e[36m======================================\e[0m"
    echo ""
    
    # 用户确认是否同意
    read -p "是否同意并继续？(y/n): " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        color_output "\e[31m您未同意条款，脚本退出。\e[0m"
        exit 1
    fi

    color_output "\e[32m已同意条款，开始执行脚本...\e[0m"
}

# 设备选择
select_device() {
    clear
    color_output "\e[36m请选择要编译的设备:\e[0m"
    color_output "\e[36m======================================\e[0m"
    color_output "\e[33m  1. x86\e[0m"
    color_output "\e[33m  2. rockchip\e[0m"
    color_output "\e[36m======================================\e[0m"

    read -p "请输入编号 (1 或 2): " device_choice
    case "$device_choice" in
        1)
            color_output "\e[32m选择了 x86，正在下载配置...\e[0m"
            curl -skL https://raw.githubusercontent.com/ZeroWrt/ZeroWrt-Action/refs/heads/master/configs/x86_64.config -o .config
            ;;
        2)
            color_output "\e[32m选择了 rockchip，正在下载配置...\e[0m"
            curl -skL https://raw.githubusercontent.com/ZeroWrt/ZeroWrt-Action/refs/heads/master/configs/rockchip.config -o .config
            ;;
        *)
            color_output "\e[31m输入无效，请输入 1 或 2。\e[0m"
            exit 1
            ;;
    esac
}

# 调用协议函数
agreement

# 更新feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 修改默认IP
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# TTYD
sed -i 's/services/system/g' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
sed -i '3 a\\t\t"order": 50,' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/g' feeds/packages/utils/ttyd/files/ttyd.init
sed -i 's/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/utils/ttyd/files/ttyd.init

# zsh
sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# banner
rm -rf package/base-files/files/etc/banner
wget -O ./package/base-files/files/etc/banner https://raw.githubusercontent.com/ZeroWrt/ZeroWrt-Action/refs/heads/master/diy/banner

# luci
pushd feeds/luci
    curl -s https://git.kejizero.online/zhao/files/raw/branch/main/patch/luci/0001-luci-mod-status-firewall-disable-legacy-firewall-rul.patch | patch -p1
popd

# 移除 SNAPSHOT 标签
sed -i 's,-SNAPSHOT,,g' include/version.mk
sed -i 's,-SNAPSHOT,,g' package/base-files/image-config.in
sed -i '/CONFIG_BUILDBOT/d' include/feeds.mk
sed -i 's/;)\s*\\/; \\/' include/feeds.mk

# make olddefconfig
wget -qO - https://github.com/openwrt/openwrt/commit/c21a3570.patch | patch -p1

# 更换为 ImmortalWrt Uboot 以及 Target
git clone --depth=1 -b openwrt-24.10 https://github.com/immortalwrt/immortalwrt immortalwrt_24
rm -rf ./target/linux/rockchip
cp -rf immortalwrt_24/target/linux/rockchip ./target/linux/rockchip
wget -O ./target/linux/rockchip/patches-6.6/014-rockchip-add-pwm-fan-controller-for-nanopi-r2s-r4s.patch https://git.kejizero.online/zhao/files/raw/branch/main/patch/kernel/rockchip/014-rockchip-add-pwm-fan-controller-for-nanopi-r2s-r4s.patch
wget -O ./target/linux/rockchip/patches-6.6/702-general-rk3328-dtsi-trb-ent-quirk.patch https://git.kejizero.online/zhao/files/raw/branch/main/patch/kernel/rockchip/702-general-rk3328-dtsi-trb-ent-quirk.patch
wget -O ./target/linux/rockchip/patches-6.6/703-rk3399-enable-dwc3-xhci-usb-trb-quirk.patch https://git.kejizero.online/zhao/files/raw/branch/main/patch/kernel/rockchip/703-rk3399-enable-dwc3-xhci-usb-trb-quirk.patch
#wget https://github.com/immortalwrt/immortalwrt/raw/refs/tags/v23.05.4/target/linux/rockchip/patches-5.15/991-arm64-dts-rockchip-add-more-cpu-operating-points-for.patch -O target/linux/rockchip/patches-6.6/991-arm64-dts-rockchip-add-more-cpu-operating-points-for.patch
rm -rf package/boot/{rkbin,uboot-rockchip,arm-trusted-firmware-rockchip}
cp -rf immortalwrt_24/package/boot/uboot-rockchip ./package/boot/uboot-rockchip
cp -rf immortalwrt_24/package/boot/arm-trusted-firmware-rockchip ./package/boot/arm-trusted-firmware-rockchip
sed -i '/REQUIRE_IMAGE_METADATA/d' target/linux/rockchip/armv8/base-files/lib/upgrade/platform.sh

# 移除immortalwrt
rm -rf immortalwrt_24

# Disable Mitigations
sed -i 's,rootwait,rootwait mitigations=off,g' target/linux/rockchip/image/default.bootscript
sed -i 's,@CMDLINE@ noinitrd,noinitrd mitigations=off,g' target/linux/x86/image/grub-efi.cfg
sed -i 's,@CMDLINE@ noinitrd,noinitrd mitigations=off,g' target/linux/x86/image/grub-iso.cfg
sed -i 's,@CMDLINE@ noinitrd,noinitrd mitigations=off,g' target/linux/x86/image/grub-pc.cfg

# fstool
wget -qO - https://github.com/coolsnowwolf/lede/commit/8a4db76.patch | patch -p1

# 移除要替换的包
rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box,adguardhome,socat,zerotier}
rm -rf feeds/packages/net/alist feeds/luci/applications/luci-app-alist
rm -rf feeds/packages/utils/v2dat
rm -rf feeds/packages/lang/golang

# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# golong1.24依赖
git clone https://github.com/sbwml/packages_lang_golang -b 24.x feeds/packages/lang/golang

# SSRP & Passwall
git clone https://git.kejizero.online/zhao/openwrt_helloworld.git package/helloworld -b v5

# 加载软件源
git clone https://github.com/oppen321/openwrt-package package/openwrt-package

# Realtek 网卡 - R8168 & R8125 & R8126 & R8152 & R8101
rm -rf package/kernel/r8168 package/kernel/r8101 package/kernel/r8125 package/kernel/r8126
git clone https://git.kejizero.online/zhao/package_kernel_r8168 package/kernel/r8168
git clone https://git.kejizero.online/zhao/package_kernel_r8152 package/kernel/r8152
git clone https://git.kejizero.online/zhao/package_kernel_r8101 package/kernel/r8101
git clone https://git.kejizero.online/zhao/package_kernel_r8125 package/kernel/r8125
git clone https://git.kejizero.online/zhao/package_kernel_r8126 package/kernel/r8126

# 修改名称
sed -i 's/OpenWrt/ZeroWrt/' package/base-files/files/bin/config_generate

# default-settings
git clone --depth=1 -b openwrt-24.10 https://github.com/oppen321/default-settings package/default-settings
sed -i 's/OpenWrt/ZeroWrt/' package/base-files/files/bin/config_generate

# default-settings
git clone --depth=1 -b openwrt-24.10 https://github.com/oppen321/default-settings package/default-settings

# 生成默认配置
echo -e "${GREEN}生成默认配置...${NC}"
make defconfig

# 编译 ZeroWrt
echo -e "${BLUE}开始编译 ZeroWrt...${NC}"
echo -e "${YELLOW}使用所有可用的 CPU 核心进行并行编译...${NC}"
make -j$(nproc) || make -j1 || make -j1 V=s
  
# 输出编译完成的固件路径
echo -e "${GREEN}编译完成！固件已生成至：${NC} bin/targets"

