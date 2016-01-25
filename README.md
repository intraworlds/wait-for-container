# wait-for-container

When starting docker containers, even if one service is marked as depending on the second one,
the first service is started before the initial process of the second container is complete - and
it is then unable to connect to the 'still in initialization' service.

This script is based on running etcd server used as discovery/synchronization engine.

## Examples