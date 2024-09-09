# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Request::HeuristicRouterTest < ActiveSupport::TestCase
  setup do
    @router = Aikido::Zen::Request::HeuristicRouter.new
  end

  def assert_parameterizes(path, into:)
    request = Rack::Request.new("PATH_INFO" => path, "REQUEST_METHOD" => "GET")
    expected = Aikido::Zen::Route.new(verb: "GET", path: into)
    assert_equal expected, @router.recognize(request)
  end

  test "empty path is treated as a forward slash" do
    assert_parameterizes "", into: "/"
  end

  test "lone forward slash is kept unmodified" do
    assert_parameterizes "/", into: "/"
  end

  test "ignores strings" do
    assert_parameterizes "/posts/abc", into: "/posts/abc"
  end

  test "replaces numbers" do
    assert_parameterizes "/posts/3", into: "/posts/:number"
    assert_parameterizes "/posts/3/", into: "/posts/:number"
    assert_parameterizes "/posts/3/comments/10", into: "/posts/:number/comments/:number"
    assert_parameterizes "/blog/2023/05/great-article", into: "/blog/:number/:number/great-article"
  end

  test "ignores numbers with a comma or period" do
    assert_parameterizes "/posts/3,000", into: "/posts/3,000"
    assert_parameterizes "/posts/3.000", into: "/posts/3.000"
  end

  test "ignores numbers with a prefix" do
    assert_parameterizes "/v1/posts/3", into: "/v1/posts/:number"
  end

  test "replaces dates" do
    assert_parameterizes "/posts/2023-05-01", into: "/posts/:date"
    assert_parameterizes "/posts/2023-05-01/", into: "/posts/:date"
    assert_parameterizes "/posts/2023-05-01/comments/2023-05-01", into: "/posts/:date/comments/:date"

    assert_parameterizes "/posts/05-01-2023", into: "/posts/:date"
    assert_parameterizes "/posts/05-01-2023/", into: "/posts/:date"
    assert_parameterizes "/posts/05-01-2023/comments/05-01-2023", into: "/posts/:date/comments/:date"
  end

  test "replaces UUIDs" do
    # UUIDv1
    assert_parameterizes "/posts/d9428888-122b-11e1-b85c-61cd3cbb3210", into: "/posts/:uuid"
    assert_parameterizes "/posts/D9428888-122B-11E1-B85C-61CD3CBB3210", into: "/posts/:uuid"

    # UUIDv2
    assert_parameterizes "/posts/000003e8-2363-21ef-b200-325096b39f47", into: "/posts/:uuid"
    assert_parameterizes "/posts/000003E8-2363-21EF-B200-325096B39F47", into: "/posts/:uuid"

    # UUIDv3
    assert_parameterizes "/posts/a981a0c2-68b1-35dc-bcfc-296e52ab01ec", into: "/posts/:uuid"
    assert_parameterizes "/posts/A981A0C2-68B1-35DC-BCFC-296E52AB01EC", into: "/posts/:uuid"

    # UUIDv4
    assert_parameterizes "/posts/109156be-c4fb-41ea-b1b4-efe1671c5836", into: "/posts/:uuid"
    assert_parameterizes "/posts/109156BE-C4FB-41EA-B1B4-EFE1671C5836", into: "/posts/:uuid"

    # UUIDv5
    assert_parameterizes "/posts/90123e1c-7512-523e-bb28-76fab9f2f73d", into: "/posts/:uuid"
    assert_parameterizes "/posts/90123E1C-7512-523E-BB28-76FAB9F2F73D", into: "/posts/:uuid"

    # UUIDv6
    assert_parameterizes "/posts/1ef21d2f-1207-6660-8c4f-419efbd44d48", into: "/posts/:uuid"
    assert_parameterizes "/posts/1EF21D2F-1207-6660-8C4F-419EFBD44D48", into: "/posts/:uuid"

    # UUIDv7
    assert_parameterizes "/posts/017f22e2-79b0-7cc3-98c4-dc0c0c07398f", into: "/posts/:uuid"
    assert_parameterizes "/posts/017F22E2-79B0-7CC3-98C4-DC0C0C07398F", into: "/posts/:uuid"

    # UUIDv8
    assert_parameterizes "/posts/0d8f23a0-697f-83ae-802e-48f3756dd581", into: "/posts/:uuid"
    assert_parameterizes "/posts/0D8F23A0-697F-83AE-802E-48F3756DD581", into: "/posts/:uuid"

    # special cases
    assert_parameterizes "/posts/00000000-0000-0000-0000-000000000000", into: "/posts/:uuid"
    assert_parameterizes "/posts/ffffffff-ffff-ffff-ffff-ffffffffffff", into: "/posts/:uuid"
    assert_parameterizes "/posts/FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF", into: "/posts/:uuid"
  end

  test "ignores invalid UUIDs" do
    assert_parameterizes "/posts/00000000-0000-1000-6000-000000000000",
      into: "/posts/00000000-0000-1000-6000-000000000000"
  end

  test "replaces emails" do
    assert_parameterizes "/login/john.doe@acme.com", into: "/login/:email"
    assert_parameterizes "/login/john.doe+alias@acme.com", into: "/login/:email"
  end

  test "replaces IP addresses" do
    assert_parameterizes "/block/1.2.3.4", into: "/block/:ip"
    assert_parameterizes "/block/2001:2:ffff:ffff:ffff:ffff:ffff:ffff", into: "/block/:ip"
    assert_parameterizes "/block/64:ff9a::255.255.255.255", into: "/block/:ip"
    assert_parameterizes "/block/100::", into: "/block/:ip"
    assert_parameterizes "/block/fec0::", into: "/block/:ip"
    assert_parameterizes "/block/227.202.96.196", into: "/block/:ip"
  end

  test "replaces hash-looking strings" do
    assert_parameterizes \
      "/files/9359f5a8ec6f99fc59fae030c4e3e4fa",
      into: "/files/:hash"
    assert_parameterizes \
      "/files/25c752d6369515a2695ee28710924b3d4b16c5a4",
      into: "/files/:hash"
    assert_parameterizes \
      "/files/bccbd9dabe9e0fef2a0d606d86542299672ae94f1a839b94ac55bdc7e3d25235",
      into: "/files/:hash"
    assert_parameterizes \
      "/files/5a719ac1c32d5682da39b825ac30eff2de39c4ab03e940c2ed37ebf2bea6f2faf46ca704fd5fb6f995bf1ff87010ff3dd28adf11519739e22de66273349ffadd",
      into: "/files/:hash"
  end

  test "ignores hex strings of the wrong length" do
    assert_parameterizes "/files/9f5d0c32", into: "/files/9f5d0c32" # 8 chars
  end

  test "replaces secret-looking strings" do
    assert_parameterizes "/confirm/CnJ4DunhYfv2db6T1FRfciRBHtlNKOYrjoz",
      into: "/confirm/:secret"
  end

  class SecretMatcherTest < ActiveSupport::TestCase
    SecretMatcher = Aikido::Zen::Request::HeuristicRouter::SecretMatcher

    def assert_secret(string)
      assert SecretMatcher === string, "#{string.inspect} expected to be considered a secret"
    end

    def refute_secret(string)
      refute SecretMatcher === string, "#{string.inspect} expected to not be considered a secret"
    end

    test "ignores short strings" do
      refute_secret "c"
      refute_secret "NR"
      refute_secret "7t3"
      refute_secret "4qEK"
      refute_secret "KJr6s"
      refute_secret "KXiW4a"
      refute_secret "Fupm2Vi"
      refute_secret "jiGmyGfg"
      refute_secret "SJPLzVQ8t"
      refute_secret "OmNf04j6mU"
    end

    test "ignores plain numbers" do
      refute_secret "012345678901"
      refute_secret "101010101010101010"
    end

    test "matches longer strings" do
      assert_secret "rsVEExrR2sVDONyeWwND"
      assert_secret ":2fbg;:qf$BRBc<2AG8&"
      assert_secret "efDJHhzvkytpXoMkFUgag6shWJktYZ5QUrUCTfecFELpdvaoAT3tekI4ZhpzbqLt"
      assert_secret "XqSwF6ySwMdTomIdmgFWcMVXWf5L0oVvO5sIjaCPI7EjiPvRZhZGWx3A6mLl1HXPOHdUeabsjhngW06JiLhAchFwgtUaAYXLolZn75WsJVKHxEM1mEXhlmZepLCGwRAM"
    end

    test "ignores strings with whitespace or known word separators" do
      refute_secret "rsVEExrR2sVDONyeWwND "
      refute_secret " rsVEExrR2sVDONyeWwND"
      refute_secret "rsVEExrR2sV DONyeWwND"
      refute_secret "this-is-a-secret-1"
    end

    def random_string_from(dict, size = SecretMatcher::MIN_LENGTH + 1)
      dict = dict.to_a
      Array.new(size).map { dict.sample }.join("")
    end

    test "ignores strings with less than two charsets" do
      refute_secret random_string_from("a".."z")
      refute_secret random_string_from("A".."Z")
      refute_secret random_string_from("0".."9")
      refute_secret random_string_from(%w[! # $ % ^ & * | ; : < >])
    end

    test "matches known secrets" do
      secrets = [
        "yqHYTS<agpi^aa1",
        "hIofuWBifkJI5iVsSNKKKDpBfmMqJJwuXMxau6AS8WZaHVLDAMeJXo3BwsFyrIIm",
        "AG7DrGi3pDDIUU1PrEsj",
        "CnJ4DunhYfv2db6T1FRfciRBHtlNKOYrjoz",
        "Gic*EfMq:^MQ|ZcmX:yW1",
        "AG7DrGi3pDDIUU1PrEsj"
      ]

      secrets.each { |word| assert_secret word }
    end

    test "ignores words and terms common in URLs" do
      safe_words = [
        "development",
        "programming",
        "applications",
        "implementation",
        "environment",
        "technologies",
        "documentation",
        "demonstration",
        "configuration",
        "administrator",
        "visualization",
        "international",
        "collaboration",
        "opportunities",
        "functionality",
        "customization",
        "specifications",
        "optimization",
        "contributions",
        "accessibility",
        "subscription",
        "subscriptions",
        "infrastructure",
        "architecture",
        "authentication",
        "sustainability",
        "notifications",
        "announcements",
        "recommendations",
        "communication",
        "compatibility",
        "enhancement",
        "integration",
        "performance",
        "improvements",
        "introduction",
        "capabilities",
        "communities",
        "credentials",
        "integration",
        "permissions",
        "validation",
        "serialization",
        "deserialization",
        "rate-limiting",
        "throttling",
        "load-balancer",
        "microservices",
        "endpoints",
        "data-transfer",
        "encryption",
        "authorization",
        "bearer-token",
        "multipart",
        "urlencoded",
        "api-docs",
        "postman",
        "json-schema",
        "serialization",
        "deserialization",
        "rate-limiting",
        "throttling",
        "load-balancer",
        "api-gateway",
        "microservices",
        "endpoints",
        "data-transfer",
        "encryption",
        "signature",
        "poppins-bold-webfont.woff2",
        "karla-bold-webfont.woff2",
        "startEmailBasedLogin",
        "jenkinsFile",
        "ConnectionStrings.config",
        "coach",
        "login",
        "payment_methods",
        "activity_logs",
        "feedback_responses",
        "balance_transactions",
        "customer_sessions",
        "payment_intents",
        "billing_portal",
        "subscription_items",
        "namedLayouts",
        "PlatformAction",
        "quickActions",
        "queryLocator",
        "relevantItems",
        "parameterizedSearch"
      ]

      safe_words.each { |word| refute_secret(word) }
    end
  end
end
