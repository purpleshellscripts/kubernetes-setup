# Kubernetes Setup Script

A Bash script for fast, repeatable Kubernetes cluster setup on Ubuntu, Rocky, and Alma servers.

## Features

* Installs container runtime, kubeadm, kubelet, and kubectl and Calico CNI
* Initializes control plane
* Automatically configures networking (CNI)
* Initializes worker nodes and provided a join command

## Requirements

* Ubuntu or RHEL based hosts
* Root or passwordless sudo
* At least two server hosts

## Tested on following OSes

- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS
- Alma Linux 9
- Alma Linux 10
- Rocky Linux 9
- Rocky Linux 10

## Tested with following Kubernetes versions
- 1.32
- 1.33
- 1.34
- 1.35 (script's Default version)

## Usage

```bash
chmod +x kubernetes-setup.sh
./kubernetes-setup.sh help

# On control plane
./kubernetes-setup.sh control-plane

# On worker node
./kubernetes-setup.sh worker-node
```

## What It Does

1. Lets you pick the Kubernetes version you want to install
2. Defines control plane IP
3. Disables swap, enables IPv4 packet forwarding
4. Disables SELinux on RHEL based systems
5. Opens necessary ports in the firewalld if the default OS firewall is enabled
6. Installs containerd as a container runtime
7. Install kubelet, kubeadm, and kubectl
8. Initializes control plane
9. Sets up Calico CNI
10. Sets up worker nodes and provides the join command

## Future plans

- Additonal server prerequisite checks
- Support for single node setup (Minikube)
- OpenSuse Support
- Flannel CNI support (possibly other CNIs)
- Docker support
- Kubernetes dashboard optional setup
- Misc script improvements and bug fixes
- Testing and providing changes for upcoming Ubuntu, Alma and Rocky Linux, and Kubernetes versions

## Distribution

Per MIT license you can freely use, modify, and distribute software, as long as the original copyright notice and license terms are included.
Please keep in mind that I intend to maintain this project by myself, as this project, and others that will come, are personal projects of mine, which means I, unfortunately, won't allow direct changes from other willing contributors, but will appreciate any feedback, suggestion from the community, bug reports, and similar non-direct contributions, and will do my best to use that feedback to better this project.
Thank you for understanding! :)

## Disclaimer

This script is provided as‑is. Use it at your own risk. It makes system‑level changes and assumes you understand Linux and Kubernetes fundamentals. No warranties are given, and the authors are not responsible for data loss, downtime, or misconfiguration. Always review and test in a non‑production environment first.

## License

MIT
