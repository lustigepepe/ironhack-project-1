## ansible-galaxy collection install -r requirements.yml

## Why Use Multiple keyed_groups?keyed_groups Entry

What Group It Creates
When It's Useful
tags.Role
role_vote-result, role_redis-worker, role_postgres-primary
Most Important — Main grouping for playbooks
tags.Name
name_vote-app-vote-us-east-1a
Debugging, targeting one specific instance
placement.availability_zone
az_us-east-1a, az_us-east-1b
AZ-specific tasks, maintenance, or disaster recovery
