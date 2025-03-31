import http from 'k6/http';
import {Trend, Counter} from 'k6/metrics';

const HTTP = {
  withZen: {
    get: (path, ...args) => http.get("http://localhost:3001" + path, {tags: {zen_enabled: true}, ...args}),
    post: (path, ...args) => http.post("http://localhost:3001" + path, {tags: {zen_enabled: true}, ...args}),
  },

  withoutZen: {
    get: (path, ...args) => http.get("http://localhost:3002" + path, {tags: {zen_enabled: false}, ...args}),
    post: (path, ...args) => http.post("http://localhost:3002" + path, {tags: {zen_enabled: false}, ...args}),
  }
}

function test(name, fn) {
  const withZen = fn(HTTP.withZen);
  const withoutZen = fn(HTTP.withoutZen);
  const timeWithZen = withZen.timings.waiting;
  const timeWithoutZen = withoutZen.timings.waiting;

  if (timeWithZen - timeWithoutZen > 0) {
    tests[name].delta.add(timeWithZen - timeWithoutZen);
    tests[name].overhead.add(100 * (timeWithZen - timeWithoutZen) / timeWithoutZen)
  } else {
    tests[name].zen_fastest.add(1)
    tests[name].zen_fastest_trend.add(timeWithoutZen - timeWithZen);
  }
}

function buildTestTrends(prefix) {
  return {
    delta: new Trend(`${prefix}_delta`, true),
    overhead: new Trend(`${prefix}_overhead`),
    zen_fastest: new Counter(`${prefix}_zen_fastest`),
    zen_fastest_trend: new Trend(`${prefix}_zen_fastest_trend`, true),
  };
}

const tests = {
  benchmark_page: buildTestTrends("benchmark_page"),
}
export const options = {
  vus: 4, // Number of virtual users
  duration: '15s',
  thresholds: {
    http_req_failed: ['rate==0'], // we are marking the attacks as expected, so we should have no errors
    "http_req_duration{zen_enabled:true}": ["p(95)<10"],
    "http_req_duration{zen_enabled:false}": ["p(95)<10"],

    // Our endpoint is sleep by 1ms, ensuring
    "http_req_waiting{zen_enabled:false}": ["p(95)<3", "med<2"],
    "http_req_waiting{zen_enabled:true}": ["p(95)<4", "med<3"],
  }
};

export default function () {
  test("benchmark_page", (http) => http.get("/benchmark"))
}
