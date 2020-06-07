grep-friendly ID
================

Convert all magic numbers to some constant with grep-friendly name.
For example, all ip/host shall be replaced like this


      JOB_REDIS_IP = "172.17.0.1"
      JOB_REDIS_PORT = 6379

      ...

      resources.redis_client(JOB_REDIS_IP, JOB_REDIS_PORT)

If it's not convenient defined as constant, should add a comment like
this

	# some.yaml

        port: 6379   # JOB_REDIS_PORT

So that in future whenever we want to find all related files,
we can grep such named ID easily.

The same principle applies to more places that have IMPLICIT DEPENDENCIES:
give some named ID to all places, so that in future refactors, when
changing one place, one will be confident and know some other places
shall also be checked. It's a very important rule to follow in the
beginning of a large project.
