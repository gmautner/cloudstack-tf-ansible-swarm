all:
  vars:
    ansible_user: root
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
    public_ip: ${public_ip}
    domain_suffix: ${domain_suffix}
    automatic_reboot: ${automatic_reboot}
    automatic_reboot_time_utc: "${automatic_reboot_time_utc}"
  children:
    managers:
      hosts:
%{ for manager in managers ~}
        ${manager.name}:
          ansible_host: ${public_ip}
          ansible_port: ${manager.port}
          private_ip: ${manager.private_ip}
%{ endfor ~}
    workers:
      hosts:
%{ for worker in workers ~}
        ${worker.name}:
          ansible_host: ${public_ip}
          ansible_port: ${worker.port}
          private_ip: ${worker.private_ip}
%{ if length(worker.labels) > 0 ~}
          labels:
%{ for key, value in worker.labels ~}
            ${key}: "${value}"
%{ endfor ~}
%{ endif ~}
%{ endfor ~}
    swarm:
      children:
        managers:
        workers: