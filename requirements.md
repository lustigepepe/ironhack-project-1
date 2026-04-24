# Key Points About the Dockerfiles:

- Vote
- Worker
- Result
- Redis
- PostgreSQL

Application Distribution

Instance A (Application Tier - Frontend): An EC2 instance launched in any AZ that runs the Vote (Python/Flask) and Result (Node.js/Express) services.

Instance B (Data/Backend Services): Runs Redis and the Worker (.NET) in a private subnet (single AZ or multi-AZ for high availability).

Instance C (Database Tier): Runs PostgreSQL in its own private subnet, optionally with a read-replica in a second AZ.

## Create your EC2 instances:

$${\color{green} \Large \textbf{2 AZ with:}}$$ \\
**A** in a )1( public subnet from Vote + Result, this instance will be used as a _Bastion Host_
**B** in a )2( private subnet for (Redis + Worker)
**C** own )3( private subnet for PostgreSQL, read replica ##standby server##

# _Dependencies_

## Load balancer for :

- Vote
- Result

## 2 Availability Zones in pu Subnets

## Target Groups for vote and result

redis private

Vote → redis
Worker → redis
Worker → postgresql
Result → postgresql

## Setting up the Infrastructure

Infrastructure Setup:

Create a VPC with one public subnet in any AZ and one private subnet in any AZ.
Create your EC2 instances:
A in a public subnet from Vote + Result, this instance will be used as a Bastion Host
B in a private subnet for Redis + Worker
C in a private subnet for PostgreSQL
Create Security Groups for each tier, locking down inbound/outbound traffic as outlined below.
Public Subnets: Place the instance A here so it’s internet-accessible.
Private Subnets: Place instances B and C in private subnets. They should not be directly exposed to the internet.
Desired Layout:

Security Groups:

Vote/Result SG: Allows incoming HTTP/HTTPS from the internet.
Redis/Worker SG: Allows inbound traffic from Vote/Result EC2 to Redis port (6379), and allows outbound to Postgres.
Postgres SG: Allows inbound traffic on port 5432 only from the Worker SG (and possibly from Vote/Result if needed directly).
Remote State and Locking:

Store your terraform.tfstate file in a remote backend and enable state locking with DynamoDB or a similar mechanism.

# two

Application Distribution

Instance A (Application Tier - Frontend): An EC2 instance launched in any AZ that runs the Vote (Python/Flask) and Result (Node.js/Express) services.

Instance B (Data/Backend Services): Runs Redis and the Worker (.NET) in a private subnet (single AZ or multi-AZ for high availability).

Instance C (Database Tier): Runs PostgreSQL in its own private subnet, optionally with a read-replica in a second AZ.

## Pull your images from DockerHub on the EC2 instances.

## What services can use load balancing? With this project, only the vote and result

# PostgreSQL:

PostgreSQL detects it is a standby in two main ways:Presence of standby.signal file in the data directory (PGDATA).This file tells PostgreSQL: “Start in recovery / standby mode.”

Connection details to the primary — stored in:postgresql.auto.conf (created by pg_basebackup -R)
Or manually in postgresql.conf
