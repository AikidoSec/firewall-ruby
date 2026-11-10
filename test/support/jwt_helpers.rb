# frozen_string_literal: true

module JWTHelpers
  # Encodes an object as one part of a JWT: base64url-encoded JSON.
  def encode_jwt_part(object, padding: false)
    encoded = [JSON.generate(object)].pack("m0").tr("+/", "-_")
    padding ? encoded : encoded.delete("=")
  end

  # Builds a JWT string from a payload. The header and the signature default to
  # placeholders, since most tests only care about the payload.
  def encode_jwt(payload, header: {"alg" => "none"}, signature: "signature", padding: false)
    [encode_jwt_part(header, padding: padding), encode_jwt_part(payload, padding: padding), signature].join(".")
  end
end
