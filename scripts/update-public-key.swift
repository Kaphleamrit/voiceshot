import CryptoKit
import Foundation

guard let line = readLine(), let seed = Data(base64Encoded: line), seed.count == 32,
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
    fputs("Set SPARKLE_PRIVATE_KEY to the exported Sparkle Ed25519 signing key.\n", stderr)
    exit(1)
}

print(key.publicKey.rawRepresentation.base64EncodedString())
