#!/bin/bash

# Set up Kubernetes Version
kubernetes-version() {
    DEFAULT_KUBERNETES_VERSION=1.35
    echo "Enter Kubernetes version that you want to use. Press Enter if you want to use the default version: $DEFAULT_KUBERNETES_VERSION "
    echo "The default version is always the newest one that has passed all tests on the author’s side."
    printf "Enter the Kubernetes version (press Enter for default: %s): " "$DEFAULT_KUBERNETES_VERSION"
    read -r KUBERNETES_VERSION

    if [ -z "$KUBERNETES_VERSION" ]; then
        printf "Using default version: %s\n" "$DEFAULT_KUBERNETES_VERSION"
        KUBERNETES_VERSION="$DEFAULT_KUBERNETES_VERSION"
    fi

    #Check if the repo is valid
    if curl -sS https://pkgs.k8s.io/core:/stable:/"v${KUBERNETES_VERSION}"/rpm/; then
    echo "Specified repo version is valid."
    else
        echo "Specified repo version in invalid, exiting script execution..."
        exit 1
    fi
    echo
    }

# Disables SELinux
disable-selinux() {
    if [[ $(getenforce) == "Enforcing" ]]; then
        echo "SELinux is active."
        printf "To continue with the installation SELinux has to be shutdown and disabled. Type 'confirm' if you want the script to disable SELinux: "
        read -r confirm
        if [ "$confirm" = "confirm" ]; then
            echo "Disabling SELinux..."
            if sudo sudo setenforce 0 && sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config; then
                echo "SELinux disabled."
                echo
            else
                echo "An issue occured when trying to disable SELinux!"
                exit 1
            fi
        fi
        else
            echo "SELinux is disabled."
            echo
    fi
}

# Disables swap
disable-swap() {
    disable-swap-fstab() {
        echo "Disabling swap..."
        sleep 1 
        sudo swapoff -a
        if sudo sed -i '/\bswap\b/s/^/#/' /etc/fstab; then
            echo "Swap disabled!"
        else
            echo "There was an issue when disabling swap! Exiting script execution..."
            exit 1
        fi
    }
    echo "Checking for active swap partitions..."
    if sudo systemctl list-units --type=swap | grep 'loaded active'; then
        echo "### Warning ###"
        echo "There is already at least 1 active and loaded swap unit."
        while true; do
            printf "Type 'confirm' if you would like to stop and mask active swap units and continue Kubernetes setup: "
            read -r confirm
            if [ "$confirm" = "confirm" ]; then
                echo "Shutting down active swap units..."
                sudo systemctl mask "$(systemctl list-unit-files --type=swap --no-legend | awk '{print $1}')"
                sudo swapoff -a
                if sudo sed -i '/\bswap\b/s/^/#/' /etc/fstab; then
                    echo
                else
                    echo "There was an issue when disabling swap! Exiting script execution..."
                    exit 1
                fi
            echo "Swap disabled!"
            break
            else
                echo "Invalid input. Type exactly: confirm"
            fi
        done
    else
        disable-swap-fstab
    fi
    echo
}

# Enables IPv4 packet forwarding
ipv4-forwarding()   {
echo "Enabling IPv4 forwarding..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    if sudo sysctl -w net.ipv4.ip_forward=1; then
        echo "IPv4 packet forwarding enabled!"
    else
        echo "There was an issue enabling IPv4 packet forwarding! Exiting script execution..."
        exit 1
    fi
    echo
}

# Installs and configures containerd
containerd-install() {
    echo "Installing containerd..."
    sleep 1
    # sudo apt install -y containerd
    sudo dnf install -y dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo dnf install -y containerd.io
    echo
    echo "Setting containerd configuration..."
    sudo mkdir -p /etc/containerd containerd config default | sudo tee /etc/containerd/config.toml
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    sudo systemctl enable --now containerd
    sleep 5
    echo
    cdactive=$(sudo systemctl is-active containerd)
    if [[ ${cdactive} == active ]]; then
            echo "Containerd installed and configured!"
    else
            echo "There was an issue when configuring containerd! Exiting script execution..."
    exit 1
    fi
    echo
}

# Installs kubelet, kubeadm and kubectl
kube-install() {
    echo "Installing Kube tools..."
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/rpm/repodata/repomd.xml.key
EOF
    if sudo dnf install -y kubelet kubeadm kubectl; then
        echo
        sudo systemctl enable kubelet
        echo "Kube tools installed!"
    else
        echo "There was an issue when installing kube tools! Exiting script execution..."
        exit 1
    fi
    echo
}

control-plane() {

    # Run kubernetes-version function
    kubernetes-version

    # Sets up control plane IP
    echo "We will now choose the IP for your control plane node. You can use an internal IP address, but that address must be reachable from all expected worker nodes."
    echo "The following is your IP interface: "
    echo
    ip -br a
    echo
    while true; do
        printf "Enter the control plane IP address: "
        read -r CONTROL_PLANE_IP_ADDRESS
        echo "You entered: $CONTROL_PLANE_IP_ADDRESS"

        printf "Type 'confirm' to continue installation or 'retry' to re-enter the IP address: "
        read -r confirm

        if [ "$confirm" = "confirm" ]; then
            echo "Continuing installation..."
            sleep 1
            break
        elif [ "$confirm" = "retry" ]; then
            echo "Starting over..."
            continue
        else
            echo "Invalid input. Exiting script execution..."
            exit 1
        fi
    done
    echo

    #Opens necessary ports on Control Plane if the default firewall service is active
    if [ "$(sudo systemctl is-active firewalld)" = active ]; then
        echo "Allowing necessary ports on Control Plane server..."
        for port in 6443 2379 2380 10250 10259 10257 179; do
            sudo firewall-cmd --permanent --add-port=${port}/tcp >> /dev/null
            echo "Port ${port} allowed."
        done
        sudo firewall-cmd --reload >> /dev/null
        echo
    else
        echo "Firewalld is not enabled, skipping allowing ports..."
        echo
    fi

    # Disables SELinux
    disable-selinux

    # Disables swap
    disable-swap

    # Enables IPv4 packet forwarding
    ipv4-forwarding

    # Installs containerd
    containerd-install

    # Installs kubelet, kubeadm and kubectl
    kube-install

    # Initializes kubeadm
    sudo kubeadm init --apiserver-advertise-address "$CONTROL_PLANE_IP_ADDRESS" --pod-network-cidr "192.168.0.0/16" --upload-certs | tee >(tail -n 2 > kubeadm-join-command.output)
    echo
    echo "### IMPORTANT ###"
    echo "kubeadm join command was written to the kubeadm-join-command.ouput file. You'll need to run the command with 'sudo' to join the worker nodes to the cluster!"
    echo "Please keep in mind that the kubeadm init bootstrap token is valid for the next 24 hours."
    echo "After the token expires you can create a new one with the following command: 'sudo kubeadm token create --print-join-command'."
    echo
    while true; do
        printf "Type 'confirm' to continue installation: "
        read -r confirm

        if [ "$confirm" = "confirm" ]; then
            echo "Continuing installation..."
            sleep 1
            break
        else
            echo "Invalid input. Type exactly: confirm"
        fi
    done
    echo
    mkdir -p "$HOME"/.kube
    sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
    sudo chown "$(id -u)":"$(id -g)" "$HOME/.kube/config"

    #Enabling overlay and br_netfilter modules
    echo "Enabling overlay and br_netfilter modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    if sudo modprobe overlay; then
        echo "'overlay' module enabled."
    else
        echo "There was an issue with enabling 'overlay' module. Exiting script..."
        exit 1
    fi

    if sudo modprobe br_netfilter; then
        echo "'br_netfilter' module enabled."
    else
        echo "There was an issue with enabling 'br_netfilter' module. Exiting script..."
        exit 1
    fi

    # Setting up Calico CNI
    echo
    echo "Applying Calico CNI manifest..."  
    kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
    sleep 5
    calicorun=$(kubectl get pods -n kube-system | grep -i calico-kube-controllers | grep Running | awk '{print $3}')
    echo "Waiting for Calico to start..."

    attempts=0
    max_attempts=60

    while true; do
        calicorun=$(kubectl get pods -n kube-system | grep -i calico-kube-controllers | grep Running | awk '{print $3}')
        if [[ "${calicorun}" == "Running" ]]; then
            echo "Calico CNI is running."
            echo
            echo "### Control plane setup completed! ###"
            echo "You can now run './kubernetes-setup.sh worker-node' on worker nodes to add them to the cluster."
            break
        fi

        if (( attempts >= max_attempts )); then
            echo "There was an issue when installing Calico! Exiting script execution..."
            exit 1
        fi

        attempts=$((attempts + 1))
        sleep 5
    done
    }

worker-node() {

    #kubernetes version
    kubernetes-version

    if [ "$(sudo systemctl is-active firewalld)" = active ]; then
        if sudo firewall-cmd --permanent --add-port=10250/tcp >>/dev/null && sudo firewall-cmd --permanent --add-port=10256/tcp >>/dev/null && sudo firewall-cmd --permanent --add-port=30000-32767/tcp >>/dev/null; then
            echo "Ports 10250, 10256, and 30000-32777 allowed."
            sudo firewall-cmd --reload >> /dev/null
        else
            echo "There was an issue when allowing ports. Exiting script execution..."
            exit 1      
        fi
    else
        echo "Default firewall service is not enabled. Skipping allowing ports..."
        echo
    fi   

    # Disables SELinux
    disable-selinux

    # Disables swap
    disable-swap

    # Enables IPv4 packet forwarding
    ipv4-forwarding

    # Installs containerd
    containerd-install

    # Installs kubelet, kubeadm and kubectl
    kube-install

    # Join the node to the cluster
    echo "### Worker node setup completed! ###"
    echo "Worker node packages installed and configuration applied. You can now run the kubeadm join command to add this worker node to the cluster. "
    }

help()  {
    cat <<'EOF'

### HELP ###

Please be aware that even though Kubernetes is very modular in this script we're setting several defaults that are considered best practice.
If you would like to change these defaults feel free to modify the script to your liking.

The script uses the following technologies as default:
- kubeadm as a cluster creator
- containerd as a container runtime
- kubelet as a pod node agent
- kubectl as Kubernetes CLI
- Calico as CNI

Make sure that you have 'sudo' access on all of the machines you run this script on, and that the planned control-plane and worker node machines can talk over TCP on ports 6443 and 10250.


### SETUP ###

0. Make sure that this script is available on the control plane server and all worker nodes you intend to join the cluster.
1. To start setting up the Kubernetes cluster run:
   ./kubernetes-setup.sh control-plane

2. Provide the desired Kubernetes version.
3. Provide the control plane IP address.
4. The script will then install required packages and configure the cluster.
5. The script will output the kubeadm join command and save it to the kubeadm-join-command.output file on the control plane server.
6. After kubeadm join confirmation the Calico CNI will be installed.
7. Move to a worker node and run:
   ./kubernetes-setup.sh worker-node

8. The script installs required packages and configures the worker node.
9. Run the join command.
10. Repeat steps 7, 8 and 9 for all worker nodes you want to join.
11. Done!

EOF
}


if [ $# -eq 0 ]; then
    cat <<'EOF'

### Script info ###

Hello! :). This script sets up a Kubernetes cluster on a Alma and Rocky systems. It imports keys, installs packages, and applies kernel changes as required.

This script is provided as‑is. Use it at your own risk. It makes system‑level changes and assumes you understand Linux and Kubernetes fundamentals. No warranties are given, and the authors are not responsible for data loss, downtime, or misconfiguration. Always review and test in a non‑production environment first.

You are free to use, modify, and redistribute this script in any form, as long as this notice is included.

For help, run: ./kubernetes-setup.sh help


Thank you for using the script! Any feedback on GitHub is appreciated.

Options: help, control-plane, worker-node

EOF
fi

OPTION=$1
$OPTION