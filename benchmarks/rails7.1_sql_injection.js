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
  test_post_page_with_json_body: buildTestTrends("test_post_page_with_json_body"),
  test_get_page_without_attack: buildTestTrends("test_get_page_without_attack"),
  test_get_page_with_sql_injection: buildTestTrends("test_get_page_with_sql_injection")
}
export const options = {
  vus: 1, // Number of virtual users
  iterations: 200,
  thresholds: {
    http_req_failed: ['rate==0'], // we are marking the attacks as expected, so we should have no errors
    test_post_page_with_json_body_delta: ["med<10"],
    test_get_page_without_attack_delta: ["med<10"],
    test_get_page_with_sql_injection_delta: ["med<10"],
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
