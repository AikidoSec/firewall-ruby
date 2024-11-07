import http from 'k6/http';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';
import { check, sleep, fail } from 'k6';
import exec from 'k6/execution';
import { Trend } from 'k6/metrics';

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
  const duration = tests[name].duration;
  const overhead = tests[name].overhead;

  const withZen = fn(HTTP.withZen);
  const withoutZen = fn(HTTP.withoutZen);
  duration.add(withZen.timings.duration - withoutZen.timings.duration);

  const ratio = withZen.timings.duration / withoutZen.timings.duration;
  overhead.add((ratio - 1) * 100)
}

const defaultHeaders = {
  "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36",
};

const tests = {
  test_get_page_without_attack: {
    duration: new Trend("test_get_page_without_attack"),
    overhead: new Trend("test_overhead_without_attack")
  },
  test_get_page_with_sql_injection: {
    duration: new Trend("test_get_page_with_sql_injection"),
    overhead: new Trend("test_overhead_with_sql_injection"),
  }
}

const strict = (threshold) => ({ threshold, abortOnFail: true });
export const options = {
  vus: 1, // Number of virtual users
  iterations: 200,
  thresholds: {
    test_get_page_without_attack: [strict("med<10"), "p(95)<50"],
    test_get_page_with_sql_injection: [strict("med<10"), "p(95)<30"],
  }
};

const expectAttack = http.expectedStatuses(500);

export default function () {
  test("test_get_page_without_attack", (http) => http.get("/cats"))
  test("test_get_page_with_sql_injection", (http) =>
    http.get("/cats/1'%20OR%20''='", {responseCallback: expectAttack})
  )
}
