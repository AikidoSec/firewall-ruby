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
  const duration = tests[name].duration;
  const overhead = tests[name].overhead;

  const withZen = fn(HTTP.withZen);
  const withoutZen = fn(HTTP.withoutZen);

  const timeWithZen = withZen.timings.duration,
    timeWithoutZen = withoutZen.timings.duration;

  duration.add(timeWithZen - timeWithoutZen);

  const ratio = withZen.timings.duration / withoutZen.timings.duration;
  overhead.add(100 * (timeWithZen - timeWithoutZen) / timeWithoutZen)
}

const defaultHeaders = {
  "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36",
};

const tests = {
  test_post_page_with_json_body: {
    duration: new Trend("test_post_page_with_json_body"),
    overhead: new Trend("test_overhead_with_json_body")
  },
  test_get_page_without_attack: {
    duration: new Trend("test_get_page_without_attack"),
    overhead: new Trend("test_overhead_without_attack")
  },
  test_get_page_with_sql_injection: {
    duration: new Trend("test_get_page_with_sql_injection"),
    overhead: new Trend("test_overhead_with_sql_injection"),
  }
}
export const options = {
  vus: 1, // Number of virtual users
  iterations: 200,
  thresholds: {
    http_req_failed: ['rate==0'], // we are marking the attacks as expected, so we should have no errors
    test_post_page_with_json_body: ["med<10"],
    test_get_page_without_attack: ["med<10"],
    test_get_page_with_sql_injection: ["med<10"],
  }
};

const expectAttack = http.expectedStatuses(200, 500);

export default function () {
  test("test_post_page_with_json_body",
    (http) => http.post("/cats", JSON.stringify({cat: {name: "Féline Dion"}}), {
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json"
      }
    })
  )

  test("test_get_page_without_attack", (http) => http.get("/cats"))

  test("test_get_page_with_sql_injection", (http) =>
    http.get("/cats/1'%20OR%20''='", { responseCallback: expectAttack })
  )
}
