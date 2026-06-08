packer {
  required_version = ">=1.8.4"

  required_plugins {
    alicloud = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/alicloud"
    }
  }
}

# ----------------------------------------------------------------------------
# Build a custom image on AlibabaCloud via the alicloud-ecs builder.
#
# Image naming convention: ${prefix}orch-<timestamp>, consistent with provider-aws / provider-gcp;
# the top-level main.tf matches the latest image by prefix via image_family_prefix during ECS scheduling.
# ----------------------------------------------------------------------------
source "alicloud-ecs" "ubuntu" {
  region        = var.alicloud_region
  profile       = var.alicloud_profile
  instance_type = var.base_instance_type

  image_name             = "${var.prefix}orch-${formatdate("YYYY-MM-DD-hh-mm-ss", timestamp())}"
  image_description      = "E2B Nomad cluster disk image (AlibabaCloud)"
  image_force_delete     = true
  image_force_delete_snapshots = true

  source_image           = ""              # Empty -> use source_image_name_regex filter
  source_image_owners    = var.source_image_owners
  source_image_name_regex = var.source_image_name_regex

  ssh_username           = "root"
  io_optimized           = true
  internet_charge_type   = "PayByTraffic"
  internet_max_bandwidth_out = 50

  vswitch_id = var.vswitch_id

  system_disk_mapping {
    disk_size     = 40
    disk_category = "cloud_essd"
  }

  run_tags = {
    Name = "${var.prefix}orch-${formatdate("YYYY-MM-DD-hh-mm-ss", timestamp())}"
  }
}

locals {
  shared_setup_dir = "${path.root}/../../nomad-cluster-disk-image/setup"
}

build {
  sources = ["source.alicloud-ecs.ubuntu"]

  # Installation chain 100% consistent with provider-aws / provider-gcp: except for cloud CLI/credential helper
  provisioner "file" {
    source      = "${local.shared_setup_dir}/supervisord.conf"
    destination = "/tmp/supervisord.conf"
  }

  provisioner "file" {
    source      = "${local.shared_setup_dir}"
    destination = "/tmp"
  }

  provisioner "file" {
    source      = "${local.shared_setup_dir}/daemon.json"
    destination = "/tmp/daemon.json"
  }

  provisioner "file" {
    source      = "${local.shared_setup_dir}/limits.conf"
    destination = "/tmp/limits.conf"
  }

  # Docker
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /etc/docker",
      "sudo mv /tmp/daemon.json /etc/docker/daemon.json",
      "sudo curl -fsSL https://get.docker.com -o get-docker.sh",
      "sudo sh get-docker.sh",
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y nvme-cli unzip jq net-tools qemu-utils make build-essential openssh-client openssh-server nfs-common",
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo systemctl start docker",
      "sudo usermod -aG docker $USER",
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/gruntwork",
      "git clone --branch v0.1.3 https://github.com/gruntwork-io/bash-commons.git /tmp/bash-commons",
      "sudo cp -r /tmp/bash-commons/modules/bash-commons/src /opt/gruntwork/bash-commons",
    ]
  }

  provisioner "shell" {
    script          = "${local.shared_setup_dir}/install-consul.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} {{ .Path }} --version ${var.consul_version}"
  }

  provisioner "shell" {
    script          = "${local.shared_setup_dir}/install-nomad.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} {{ .Path }} --version ${var.nomad_version}"
  }

  provisioner "shell" {
    script          = "${local.shared_setup_dir}/install-clickhouse-client.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} {{ .Path }} --version ${var.clickhouse_client_version}"
  }

  provisioner "shell" {
    script          = "${local.shared_setup_dir}/install-cni-plugins.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} {{ .Path }} --version ${var.cni_plugin_version}"
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/nomad/plugins",
    ]
  }

  # ----- AlibabaCloud-specific -----
  # aliyun-cli (replace AWS CLI)
  provisioner "shell" {
    inline = [
      "curl -L https://aliyuncli.alicdn.com/aliyun-cli-linux-latest-amd64.tgz -o aliyun-cli.tgz",
      "tar -xzf aliyun-cli.tgz",
      "sudo mv aliyun /usr/local/bin/aliyun",
    ]
  }

  # ossutil (replace AWS S3 CLI / s3fs)
  provisioner "shell" {
    inline = [
      "curl -L https://gosspublic.alicdn.com/ossutil/1.7.18/ossutil64 -o /tmp/ossutil",
      "sudo install -m 0755 /tmp/ossutil /usr/local/bin/ossutil",
    ]
  }

  # ossfs (replaces AWS s3fs; mounts OSS bucket as a local filesystem)
  provisioner "shell" {
    inline = [
      "curl -L https://gosspublic.alicdn.com/ossfs/ossfs_1.91.4_ubuntu24.04_amd64.deb -o /tmp/ossfs.deb",
      "sudo dpkg -i /tmp/ossfs.deb || sudo apt-get install -f -y",
    ]
  }

  # ACR docker credential helper (equivalent to AWS amazon-ecr-credential-helper).
  # Installs a shell wrapper at /usr/local/bin/docker-credential-acr-credential-helper;
  # docker daemon calls it during pull based on credHelpers in /root/docker/config.json,
  # which in turn auto-fetches ACR EE temporary tokens via ECS RAM Role without any static AK/SK.
  provisioner "shell" {
    script          = "${local.shared_setup_dir}/install-acr-credential-helper.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} {{ .Path }}"
  }

  provisioner "shell" {
    inline = [
      # Increase the maximum number of open files
      "sudo mv /tmp/limits.conf /etc/security/limits.conf",
      # Increase the maximum number of connections by 4x
      "echo 'net.netfilter.nf_conntrack_max = 2097152' | sudo tee -a /etc/sysctl.conf",
    ]
  }
}
