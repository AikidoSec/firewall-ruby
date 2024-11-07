import http from 'k6/http';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';
import { check, sleep, fail } from 'k6';
import exec from 'k6/execution';
import { Trend } from 'k6/metrics';

function checkResponse(response, expectedStatus) {
  check(response, {"status is correct": (r) => r.status === expectedStatus});
  return response;
}

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

const defaultTestOptions = {
  amount: 500,
  expectedStatus: 200,
}
function test(name, fn, options = {}) {
  options = { ...defaultTestOptions, ...options };
  const duration = tests[name].duration;
  const overhead = tests[name].overhead;

  for (let i = 0; i < options.amount; i++) {
    const withZen = checkResponse(fn(HTTP.withZen), options.expectedStatus);
    const withoutZen = checkResponse(fn(HTTP.withoutZen), options.expectedStatus);
    duration.add(withZen.timings.duration - withoutZen.timings.duration);
  }
}

const defaultHeaders = {
  "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36",
};

const tests = {
  get_page_without_attack: {
    duration: new Trend("get_page_without_attack"),
    overhead: new Trend("overhead_without_attack")
  },
  get_page_with_sql_injection: {
    duration: new Trend("get_page_with_sql_injection"),
    overhead: new Trend("overhead_with_sql_injection"),
  }
}
export const options = {
  vus: 1, // Number of virtual users
  thresholds: {
    get_page_without_attack: [{
      threshold: "p(95)<10",
      abortOnFail: true
    }],
    get_page_with_sql_injection: [{
      threshold: "p(95)<50",
      abortOnFail: true
    }]
  }
};

export default function () {
  test("get_page_without_attack", (http) => http.get("/cats"))
  test("get_page_with_sql_injection",
    (http) => http.get("/cats/1'%20OR%20''='"),
    {expectedStatus: 500}
  )
}
