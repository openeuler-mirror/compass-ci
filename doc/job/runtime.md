# runtime

Meaning:
- Run time for test: seconds(s), hours(h) or days(d).
- Limit the test's run time in $runtime.

Usage example:

```bash
#!/bin/sh
# - runtime

## delay for a specified amount of time
echo sleep started
exec sleep ${1:-$runtime}
echo sleep finished
```

`runtime` is a parameter of test script.
For any test case needing parameter(s),
need such comment line and follow exactly the
same format `# - parameter`.

```yaml
suite: borrow
testcase: borrow

runtime: 1d

sleep:
```

