terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

variable "use_kubeconfig" {
  type        = bool
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
  default     = false
}

data "coder_parameter" "os" {
  name         = "os"
  display_name = "Operating system"
  description  = "The operating system to use for your workspace."
  default      = "ubuntu"
  option {
    name  = "Ubuntu"
    value = "ubuntu"
    icon  = "/icon/ubuntu.svg"
  }
  option {
    name  = "Fedora"
    value = "fedora"
    icon  = "/icon/fedora.svg"
  }
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "The number of CPU cores"
  default      = "2"
  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "6 Cores"
    value = "6"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "The amount of memory (in GB)"
  default      = "2"
  option {
    name  = "2 GB"
    value = "2"
  }
  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "6 GB"
    value = "6"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
}

data "coder_parameter" "workspaces_volume_size" {
  name         = "workspaces_volume_size"
  display_name = "Workspaces volume size"
  description  = "Size of the `/workspaces` volume (GiB)."
  default      = "10"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = false
  validation {
    min = 1
    max = 99999
  }
  order = 3
}

data "coder_parameter" "repo" {
  description  = "Select a repository to automatically clone and start working with a devcontainer."
  display_name = "Repository (auto)"
  mutable      = true
  name         = "repo"
  order        = 4
  type         = "string"
  default      = "https://github.com/MichaelKueller/devcontainers_spring_boot"
}

module "devcontainers-cli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/devcontainers-cli/coder"
  agent_id = coder_agent.dev.id
}


module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.1"
  agent_id = coder_agent.dev.id
  url      = data.coder_parameter.repo.value 
}

resource "coder_devcontainer" "devcontainer" {
  count            = data.coder_workspace.me.start_count
  agent_id         = coder_agent.dev.id
  workspace_folder = "/home/podman/devcontainers_spring_boot"
}

resource "coder_agent" "dev" {
  os             = "linux"
  arch           = "amd64"
  # dir            = "/home/podman"
  startup_script_behavior = "blocking"
  startup_script = <<EOF
    #!/bin/sh

    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.11.0
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &

    # Run once to avoid unnecessary warning: "/" is not a shared mount
    podman ps
  EOF

}

# code-server
resource "coder_app" "code-server" {
  agent_id     = coder_agent.dev.id
  display_name = "code-server"
  slug         = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337"
}


resource "kubernetes_pod_v1" "main" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_persistent_volume_claim_v1.home-directory
  ]
  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = "coder"
    #annotations = {
      # Disables apparmor, required for Debian- and Ubuntu-derived systems
    #  "container.apparmor.security.beta.kubernetes.io/dev" = "unconfined"
    #}
  }
  timeouts {
    create = "30m"
  }
  spec {
    security_context {
      # Runs as the "podman" user
      run_as_user = 1000
      fs_group    = 1000
    }
    container {
      name = "dev"
      # We recommend building your own from our reference: see ./images directory
      image             = "ghcr.io/coder/podman:${data.coder_parameter.os.value}"
      # image             = "codercom/enterprise-base:ubuntu"
      # image             = "mcr.microsoft.com/devcontainers/universal"
      image_pull_policy = "Always"
      command           =  [
        "/bin/bash", 
        "-c", 
        <<-EOT
          
          sudo apt purge -y moby-cli

          echo 'export COMPOSE_CMD=podman-compose' >> ~/.bashrc
           
          sudo apt update
          sudo apt install -y \
            git
          
          curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
          sudo apt install -y nodejs

          mkdir -p ~/.npm-global
          npm config set prefix "$HOME/.npm-global"

          echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bashrc
          source ~/.bashrc
            
          sudo apt install -y python3-pip
          pip3 install --user podman-compose

          mkdir -p ~/.local/bin

          cat > ~/.local/bin/docker-compose <<'EOF'
          #!/bin/sh
          exec ~/.local/bin/podman-compose "$@"
          EOF

          chmod +x ~/.local/bin/docker-compose

          export PATH="$HOME/.local/bin:$PATH"
          

          
          ln -s /usr/bin/podman-compose /usr/local/bin/docker-compose

          echo 'export COMPOSE_DOCKER_CLI_BUILD=0' >> ~/.bashrc
          echo 'export DOCKER_BUILDKIT=0' >> ~/.bashrc

          #echo 'export DOCKER_HOST=tcp://127.0.0.1:2375' >> ~/.bashrc
          #podman system service --time=0 tcp:127.0.0.1:2375 &
          
          exec ${coder_agent.dev.init_script}
        EOT
      ]
      security_context {
        # Runs as the "podman" user
        run_as_user = "1000"
        privileged = true          # required for Bidirectional propagation
      }
      resources {
        requests = {
          "cpu"    = "250m"
          "memory" = "500Mi"
        }
        limits = {
          # Acquire a FUSE device, powered by smarter-device-manager
          "github.com/fuse" : 1
          cpu    = "${data.coder_parameter.cpu.value}"
          memory = "${data.coder_parameter.memory.value}Gi"
        }

      }
      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.dev.token
      }
      volume_mount {
        mount_path = "/home/podman"
        name       = "home-directory"
        mount_propagation = "Bidirectional"  # or "HostToContainer"
      }
    }
    volume {
      name = "home-directory"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim_v1.home-directory.metadata.0.name
      }
    }
  }
}

# resource "kubernetes_persistent_volume_claim_v1" "home-directory" {
#   metadata {
#     name      = "coder-pvc-${data.coder_workspace.me.id}"
#     namespace = "default"
#   }
#   spec {
#     access_modes = ["ReadWriteOnce"]
#     resources {
#       requests = {
#         storage = "10Gi"
#       }
#     }
#   }
# }


resource "kubernetes_persistent_volume_claim_v1" "home-directory" {
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.id)}-workspaces"
    namespace = "coder" # var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-${lower(data.coder_workspace.me.id)}-workspaces"
      "app.kubernetes.io/instance" = "coder-${lower(data.coder_workspace.me.id)}-workspaces"
      "app.kubernetes.io/part-of"  = "coder"
      //Coder-specific labels.
      "com.coder.resource"       = "true"
      "com.coder.workspace.id"   = data.coder_workspace.me.id
      "com.coder.workspace.name" = data.coder_workspace.me.name
      "com.coder.user.id"        = data.coder_workspace_owner.me.id
      "com.coder.user.username"  = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${data.coder_parameter.workspaces_volume_size.value}Gi"
      }
    }
    # storage_class_name = "local-path" # Configure the StorageClass to use here, if required.
  }
}
