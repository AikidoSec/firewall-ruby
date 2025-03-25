# Benchmarking Zen for Ruby


We use [WRK](https://github.com/wg/wrk) for these. 

In order to run a benchmarks against a single application, run the following
from the root of the project:

```
$ bundle exec rake bench:{app}:run
```

For example, for the `rails7.1_benchmark` application:

```
$ bundle exec rake bench:rails7.1_benchmark:run
```
