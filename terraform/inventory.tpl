[all:vars]
ansible_user=root
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
domain_suffix=${domain_suffix}
public_ip=${public_ip}

[managers]
%{ for manager in managers ~}
${manager.name} ansible_host=${public_ip} ansible_port=${manager.port} private_ip=${manager.private_ip}
%{ endfor ~}

[workers]
%{ for worker in workers ~}
${worker.name} ansible_host=${public_ip} ansible_port=${worker.port} private_ip=${worker.private_ip} worker_role=${worker.role}
%{ endfor ~}

[swarm:children]
managers
workers

[docker_swarm_manager]
%{ for manager in managers ~}
${manager.name}
%{ endfor ~}

[docker_swarm_worker]
%{ for worker in workers ~}
${worker.name}
%{ endfor ~} 