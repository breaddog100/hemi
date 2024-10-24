#!/bin/bash

# 设置版本号
current_version=20241024003

update_script() {
    # 指定URL
    update_url="https://raw.githubusercontent.com/breaddog100/hemi/main/hemi.sh"
    file_name=$(basename "$update_url")

    # 下载脚本文件
    tmp=$(date +%s)
    timeout 10s curl -s -o "$HOME/$tmp" -H "Cache-Control: no-cache" "$update_url?$tmp"
    exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
        echo "命令超时"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        echo "下载失败"
        return 1
    fi

    # 检查是否有新版本可用
    latest_version=$(grep -oP 'current_version=([0-9]+)' $HOME/$tmp | sed -n 's/.*=//p')

    if [[ "$latest_version" -gt "$current_version" ]]; then
        clear
        echo ""
        # 提示需要更新脚本
        printf "\033[31m脚本有新版本可用！当前版本：%s，最新版本：%s\033[0m\n" "$current_version" "$latest_version"
        echo "正在更新..."
        sleep 3
        mv $HOME/$tmp $HOME/$file_name
        chmod +x $HOME/$file_name
        exec "$HOME/$file_name"
    else
        # 脚本是最新的
        rm -f $tmp
    fi

}

# 节点安装功能
function install_node() {

	cd $HOME

    FEE=$(curl -s https://mempool.space/testnet/api/v1/fees/recommended | sed -n 's/.*"fastestFee":\([0-9.]*\).*/\1/p')
    read -p "设置gas(参考值：$FEE)：" POPM_STATIC_FEE

    sudo apt update
    sudo apt install -y jq git make

    # 安装GO
    sudo rm -rf /usr/local/go
    wget https://go.dev/dl/go1.23.2.linux-amd64.tar.gz -P /tmp/
    sudo tar -C /usr/local -xzf /tmp/go1.23.2.linux-amd64.tar.gz
    echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bashrc
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    go version

	# 下载代码
	# wget https://github.com/hemilabs/heminetwork/releases/download/v0.4.5/heminetwork_v0.4.5_linux_amd64.tar.gz
	# tar -xvf heminetwork_v0.4.5_linux_amd64.tar.gz
	# mv heminetwork_v0.4.5_linux_amd64 heminetwork
    git clone https://github.com/hemilabs/heminetwork.git
    cd heminetwork
    make deps
    make install

	./bin/keygen -secp256k1 -json -net="testnet" > popm-address.json
	POPM_BTC_PRIVKEY=$(jq -r '.private_key' popm-address.json)
    POPM_BTC_PUBKEY=$(jq -r '.pubkey_hash' popm-address.json)

	POPM_BFG_URL="wss://testnet.rpc.hemi.network/v1/ws/public"
	
    sudo tee /lib/systemd/system/hemi.service > /dev/null <<EOF
[Unit]
Description=Hemi Network App Service
[Service]
Type=simple
Restart=always
RestartSec=30s
WorkingDirectory=$HOME/heminetwork
Environment=POPM_BTC_PRIVKEY=$POPM_BTC_PRIVKEY
Environment=POPM_STATIC_FEE=$POPM_STATIC_FEE
Environment=POPM_BFG_URL=$POPM_BFG_URL
ExecStart=$HOME/heminetwork/bin/popmd
[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable hemi
    sudo systemctl start hemi

    printf "\033[31m部署完成，请给：%s，领水\033[0m\n" "$POPM_BTC_PUBKEY"
}

# 查看日志
function view_logs(){
	sudo journalctl -u hemi.service -f --no-hostname -o cat
}

# 查看节点状态
function view_status(){
	sudo systemctl status hemi
}

# 停止节点
function stop_node(){
	sudo systemctl stop hemi
	echo "节点已停止..."
}

# 启动节点
function start_node(){
	sudo systemctl start hemi
	echo "节点已启动..."
}

# 更改gas
function update_gas(){
    cd $HOME
	FEE=$(curl -s https://mempool.space/testnet/api/v1/fees/recommended | sed -n 's/.*"fastestFee":\([0-9.]*\).*/\1/p')
    ORE_FEE=$(grep -oP 'POPM_STATIC_FEE=\K[^ ]+' /lib/systemd/system/hemi.service)

	read -p "设置gas(当前值：$ORE_FEE,参考值：$FEE)：" POPM_STATIC_FEE
    sudo sed -i "s/Environment=POPM_STATIC_FEE=[0-9.]\+/Environment=POPM_STATIC_FEE=$POPM_STATIC_FEE/" /lib/systemd/system/hemi.service
    sudo systemctl daemon-reload
    echo "修改完成，正在重启节点..."
    stop_node
    start_node
}

# 卸载节点功能
function uninstall_node() {
    echo "确定要卸载节点程序吗？这将会删除所有相关的数据。[Y/N]"
    read -r -p "请确认: " response

    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载节点程序..."
            sudo systemctl stop hemi
	        rm -rf $HOME/heminetwork
            echo "节点程序卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}

# 代码更新
update_code () {
    local repo_path="$HOME/heminetwork"
    
    # 进入项目目录
    cd "$repo_path" || { echo "Failed to enter directory: $repo_path"; return 1; }

    # 获取远程更新
    git fetch origin

    # 检查远程是否有更新
    local updates=$(git log HEAD..origin/main --oneline)

    if [ -n "$updates" ]; then
        echo "发现新代码:"
        echo "$updates"
        echo "正在更新..."
        git pull origin main
    else
        echo "完成更新..."
    fi
}

# 主菜单
function main_menu() {
	while true; do
	    clear
	    echo "===================Hemi Network一键部署脚本==================="
		echo "当前版本：$current_version"
		echo "沟通电报群：https://t.me/lumaogogogo"
		echo "推荐配置：2C4G100G"
	    echo "请选择要执行的操作:"
	    echo "1. 部署节点 install_node"
	    echo "2. 节点状态 view_status"
        echo "3. 节点日志 view_logs"
	    echo "4. 停止节点 stop_node"
	    echo "5. 启动节点 start_node"
        echo "6. 修改gas update_gas"
        echo "7. 更新代码 update_code"
	    echo "1618. 卸载节点 uninstall_node"
	    echo "0. 退出脚本 exit"
	    read -p "请输入选项: " OPTION
	
	    case $OPTION in
	    1) install_node ;;
	    2) view_status ;;
        3) view_logs ;;
	    4) stop_node ;;
	    5) start_node ;;
        6) update_gas ;;
        7) update_code ;;
	    1618) uninstall_node ;;
	    0) echo "退出脚本。"; exit 0 ;;
	    *) echo "无效选项，请重新输入。"; sleep 3 ;;
	    esac
	    echo "按任意键返回主菜单..."
        read -n 1
    done
}

# 检查更新
update_script

# 显示主菜单
main_menu