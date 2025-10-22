import http from "k6/http";
import {Trend} from "k6/metrics";

const HTTP = {
  withZen: {
    get: (path, ...args) => http.get("http://localhost:3001" + path, ...args),
    post: (path, ...args) => http.post("http://localhost:3001" + path, ...args)
  },
  withoutZen: {
    get: (path, ...args) => http.get("http://localhost:3002" + path, ...args),
    post: (path, ...args) => http.post("http://localhost:3002" + path, ...args)
  }
};

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
  test_get_page_without_attack: buildTestTrends("test_get_page_without_attack")
};

export const options = {
  vus: 1, // Number of virtual users
  duration: "60s",
  thresholds: {
    http_req_failed: ["rate==0"], // We are marking the attacks as expected, so we should have no errors.
    test_post_page_with_json_body_delta: ["med<10"],
    test_get_page_without_attack_delta: ["med<10"]
  }
};

const headers = {
  Authorization:
    "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.Bw8sSk3kdnT9d803kqqE_LZJzY1PzMl5cbmuanQKxrI",
  Accept:
    "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
  "Accept-Language": "en-US,en;q=0.9",
  Dnt: "1",
  Priority: "u=0, i",
  "Sec-Ch-Ua":
    '"Not)A;Brand";v="99", "Google Chrome";v="127", "Chromium";v="127"',
  "Sec-Ch-Ua-Arch": '"arm"',
  "Sec-Ch-Ua-Bitness": '"64"',
  "Sec-Ch-Ua-Full-Version-List":
    '"Not)A;Brand";v="99.0.0.0", "Google Chrome";v="127.0.6533.72", "Chromium";v="127.0.6533.72"',
  "Sec-Ch-Ua-Mobile": "?0",
  "Sec-Ch-Ua-Model": '""',
  "Sec-Ch-Ua-Platform": '"macOS"',
  "Sec-Ch-Ua-Platform-Version": '"14.5.0"',
  "Sec-Ch-Ua-Wow64": "?0",
  "Sec-Fetch-Dest": "document",
  "Sec-Fetch-Mode": "navigate",
  "Sec-Fetch-Site": "cross-site",
  "Sec-Fetch-User": "?1",
  "Sec-Gpc": "1",
  "Upgrade-Insecure-Requests": "1",
  "User-Agent":
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36",
};

const expectAttack = http.expectedStatuses(200, 500);

export default function () {
  test("test_post_page_with_json_body",
    (http) => http.post("/cats",
      JSON.stringify({cat: {name: "Féline Dion"}}),
      {
        headers: {
          ...headers,
          "Content-Type": "application/json",
          "Accept": "application/json"
        }
      })
  )

  test("test_get_page_without_attack",
    (http) => http.get("/cats",
    {
        headers: headers
    })
  )
}
