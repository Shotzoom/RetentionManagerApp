//
//  JWTGenerator.swift
//  RetentionManager
//
//  Created by John Hawley on 3/11/26.
//

import Foundation
import CryptoKit

/// Generates JWT tokens for API authentication using ES256 (P-256 ECDSA with SHA-256)
class JWTGenerator {
    private let keyID: String
    private let issuerID: String
    private let bundleID: String
    private let privateKey: P256.Signing.PrivateKey
    
    init(keyID: String, issuerID: String, bundleID: String, privateKeyPEM: String) throws {
        self.keyID = keyID
        self.issuerID = issuerID
        self.bundleID = bundleID
        self.privateKey = try Self.parseP8PrivateKey(pem: privateKeyPEM)
    }
    
    /// Parse a P8 (PEM format) PKCS#8 private key into a CryptoKit P256.Signing.PrivateKey.
    /// CryptoKit handles the PKCS#8 DER structure directly via `pemRepresentation`.
    private static func parseP8PrivateKey(pem: String) throws -> P256.Signing.PrivateKey {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let privateKey = try P256.Signing.PrivateKey(pemRepresentation: trimmed)
            print("🔐 Private key loaded successfully via PEM (PKCS#8)")
            return privateKey
        } catch {
            print("❌ Failed to parse PEM private key: \(error)")
            throw JWTError.invalidPrivateKey
        }
    }
    
    /// Generate a JWT token
    /// - Parameters:
    ///   - expirationTime: Time in seconds until the token expires (default: 3600 = 1 hour)
    /// - Returns: A signed JWT token string
    func generateToken(expirationTime: TimeInterval = 3600) throws -> String {
        let now = Date()
        let exp = now.addingTimeInterval(expirationTime)
        
        // Create JWT header
        let header: [String: Any] = [
            "alg": "ES256",
            "kid": keyID,
            "typ": "JWT"
        ]
        
        // Create JWT claims
        let claims: [String: Any] = [
            "iss": issuerID,
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(exp.timeIntervalSince1970),
            "aud": "appstoreconnect-v1",
            "bid": bundleID
        ]
        
        print("🔐 JWT Header: \(header)")
        print("🔐 JWT Claims: \(claims)")
        
        // Encode header and claims as base64url
        let headerData = try JSONSerialization.data(withJSONObject: header)
        let claimsData = try JSONSerialization.data(withJSONObject: claims)
        
        let headerString = base64URLEncode(headerData)
        let claimsString = base64URLEncode(claimsData)
        
        print("🔐 JWT Header (base64url): \(headerString)")
        print("🔐 JWT Claims (base64url): \(claimsString)")
        
        // Create the signing input
        let signingInput = "\(headerString).\(claimsString)"
        let signingInputData = Data(signingInput.utf8)
        
        // Sign with ES256 (P-256 ECDSA with SHA-256)
        let signature = try privateKey.signature(for: signingInputData)
        
        // Convert signature to raw format (r and s components)
        // The signature.rawRepresentation gives us the r and s values concatenated
        let signatureString = base64URLEncode(signature.rawRepresentation)
        
        // Return the complete JWT
        let fullToken = "\(signingInput).\(signatureString)"
        print("🔐 Full JWT token: \(fullToken)")
        return fullToken
    }
    
    /// Base64URL encode data (different from standard Base64)
    private func base64URLEncode(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        let base64url = base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return base64url
    }
}

// MARK: - Error Types

enum JWTError: LocalizedError {
    case invalidPrivateKey
    case signingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            return "Failed to parse the private key from P8 format"
        case .signingFailed:
            return "Failed to sign the JWT token"
        }
    }
}
