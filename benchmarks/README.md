# Benchmarking Zen for Ruby

This directory contains the benchmarking scripts that we use to ensure adding
Zen to your application does not impact performance significantly.

We use [Grafana K6](https://k6.io) for these. For each sample application we
include in this repo under [sample_apps](../sample_apps), you should find
a script here that runs certain benchmarks against that app.

To run all the benchmarks, run the following from the root of the project:

```
$ bundle exec rake bench
```

In order to run a benchmarks against a single application, run the following
from the root of the project:

```
$ bundle exec rake bench:{app}:run
```

For example, for the `rails7.1_sql_injection` application:

```
$ bundle exec rake bench:rails7.1_sql_injection:run
```
