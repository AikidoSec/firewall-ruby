import http from 'k6/http';
import {Trend} from 'k6/metrics';

const HTTP = {
  withZen: {
    get: (path, ...args) => http.get("http://localhost:3001" + path, ...args),
    post: (path, ...args) => http.post("http://localhost:3001" + path, ...args)
  },
  withoutZen: {
    get: (path, ...args) => http.get("http://localhost:3002" + path, ...args),
    post: (path, ...args) => http.post("http://localhost:3002" + path, ...args)
  }
}

function test(name, fn) {
  const withZen = fn(HTTP.withZen);
  const withoutZen = fn(HTTP.withoutZen);
  const timeWithZen = withZen.timings.duration;
  const timeWithoutZen = withoutZen.timings.duration;

  tests[name].delta.add(timeWithZen - timeWithoutZen);
  tests[name].overhead.add(100 * (timeWithZen - timeWithoutZen) / timeWithoutZen)

  tests[name].with_zen.add(timeWithZen);
  tests[name].without_zen.add(timeWithoutZen);
}

function buildTestTrends(prefix) {
  return {
    delta: new Trend(`${prefix}_delta`),
    with_zen: new Trend(`${prefix}_with_zen`),
    without_zen: new Trend(`${prefix}_without_zen`),
    overhead: new Trend(`${prefix}_overhead`)
  };
}

const tests = {
  benchmark_page: buildTestTrends("benchmark_page"),
}
export const options = {
  vus: 10, // Number of virtual users
  iterations: 2000,
  thresholds: {
    http_req_failed: ['rate==0'], // we are marking the attacks as expected, so we should have no errors
    benchmark_page_delta: ["med<10"],
  }
};

export default function () {
  test("benchmark_page", (http) => http.get("/benchmark"))
}
