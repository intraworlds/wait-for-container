# wait-for-container

When starting docker containers, even if one service is marked as depending on the second one,
the first service is started before the initial process of the second container is complete - and
it is then unable to connect to the 'still in initialization' service.

This script is based on running etcd server used as discovery/synchronization engine.


## Examples

* wait for service

```bash
> ./doctainer.sh wait foo # wait for service 'foo' forever (no timeout)
or
> ./doctainer.sh wait foo 5 # wait for service 'foo' for 5 seconds
```

* fire event about service

```bash
> ./doctainer.sh notify foo # service 'foo' is in default status 'running' now
or
> ./doctainer.sh notify foo preparing # service 'foo' is in status 'preparing'
```