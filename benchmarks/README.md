# Benchmarking Zen for Ruby


We use [WRK](https://github.com/wg/wrk) & [Grafana K6](https://k6.io) for these.

WRK benchmarks are only requesting a URL (`/benchmark`). In case you want to add more 
of those test, you have to code them in the file `tasklib/bench.rake`.

K6 tests are defined in `benchmarks` folder. They are a javascript file, with calls 
to different endpoints.

In order to run a benchmarks against a single application, run the following
from the root of the project:

```
$ BUNDLE_GEMFILE=./sample_apps/{app}/Gemfile bundle exec rake bench:{app}:(k6|wrk)_run
```

For example, for the WRK of `rails7.1_benchmark` application:

```
$ BUNDLE_GEMFILE=./sample_apps/rails7.1_benchmark/Gemfile bundle exec rake bench:rails7.1_benchmark:wrk_run
```
