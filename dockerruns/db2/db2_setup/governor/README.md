## Reference to Compose/governor
Compose runs a a [Postgresql as a service platform](https://www.compose.io/postgresql), which is highly-available from creation.  This is a coded example from our prior blog post: [High Availability for PostgreSQL, Batteries Not Included](https://blog.compose.io/high-availability-for-postgresql-batteries-not-included/).
Note this code is based on compose/governor for postgres

## Getting Started
check the config in db2.yml, governor loads it on standby
To get started, do the following from primary/standby:

```
> python governor.py
```

From there, you will see db2 monitoring enabled

## How Governor works

For a diagram of the high availability decision loop, see the included a PDF: [db2-ha.pdf](https://github.ibm.com/db2oncloud/governor/blob/master/db2-ha.pdf)

## YAML Configuration

For an example file, see `db2.yml`.  Below is an explanation of settings:

* *loop_wait*: the number of seconds the loop will sleep
* *env*: test

* *etcd*
  * *scope*: the relative path used on etcd's http api for this deployment, thus you can run multiple HA deployments from a single etcd
  * *ttl*: the TTL to acquire the leader lock.  Think of it as the length of time before automatic failover process is initiated.
  * *endpoint*: the scheme://host:port for the etcd endpoint where scheme is https or http, in array
  * *authentication*: optional if etcd is protected by HTTP basic auth
    * *username*: username for accessing etcd
    * *password*: password for accessing etcd
  * *cert*: full_path_certificate
  * *timeout*: etcd timeout

* *db2*
  * *ip*: ip
  * *ip_other*: ip_other
  * *db*: db name
  * *authentication*:
    * *username*: bluadmin
    * *password*: Yzk3MzdlNzMwYmRh
* *net_interface*
  * *public_interface*: interface enable floating ip
* *op_timeout*:
  * *connect*: 120
  * *start*: 180
  * *start_as_standby*: 180
  * *start_as_primary*: 180

## Applications should not use superusers

When connecting from an application, always use a non-superuser. Governor requires access to the database to function properly.  By using a superuser from application, you can potentially use the entire connection pool, including the connections reserved for superusers with the `superuser_reserved_connections` setting. If Governor cannot access the Primary, because the connection pool is full, behavior will be undesireable.

## CentOS Packages
- ksh
- python 2.7.11
- pip Enum34 subprocess32 mock nose-parameterized pyyaml

## etcd Architecture
For dashDB Transactional HADR (2 node cluster) we will reuse one etcd cluster and have separate key domains to manage each hadr cluster.

For example key: ```/service/dashdb-txn-yp-dal01-01/leader```

The credentials to access the etcd server will be *shared* with all dashDB Transactional instances for all customers. etcd will contain the partial hostname and the private IP of the primary.
