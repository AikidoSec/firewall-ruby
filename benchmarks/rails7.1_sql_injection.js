import http from 'k6/http';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';
import { check, sleep, fail } from 'k6';
import exec from 'k6/execution';
import { Trend } from 'k6/metrics';

const BASE_URL_3001 = 'http://localhost:3001';
const BASE_URL_3002 = 'http://localhost:3002';

const defaultHeaders = {
  "User-Agent":
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36",
};

function measureRequest(url, method, payload, statusCode = 200, headers = defaultHeaders) {
  const response = (method === "GET") ?
    http.get(url, { headers }) :
    http.post(url, payload, { headers });
  check(response, {
    'status is correct': (r) => r.status === statusCode,
  });
  return response.timings.duration; // Return the duration of the request
}

function test(trend, amount, method, route, data={}, status=200) {
  for (let i = 0; i < amount; i++) {
    let withZen = measureRequest(BASE_URL_3001 + route, method, data, status)
    let withoutZen = measureRequest(BASE_URL_3002 + route, method, data, status)
    trend.add(withZen - withoutZen)
  }
}

export const options = {
  vus: 1, // Number of virtual users
  thresholds: {
    get_page: [{
      threshold: "p(95)<10",
      abortOnFail: true
    }],
    get_page_with_sql_injection: [{
      threshold: "p(95)<30",
      abortOnFail: true
    }]
  }
};
const getPage = new Trend("get_page");
const getPageWithSQLi = new Trend("get_page_with_sql_injection");

export default function () {
  test(getPage, 500, "GET", "/cats")
  test(getPageWithSQLi, 500, "GET", "/cats/1'%20OR%20''='", {}, 500)
}
