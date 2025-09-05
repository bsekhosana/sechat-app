# SeChat App Encryption Documentation

**App Name:** SeChat  
**Package ID:** com.strapblaque.sechat  
**Version:** 2.0.0+2  
**Date:** January 2025  

## Encryption Declaration

**Does this app use encryption?** YES

**App Uses Non-Exempt Encryption:** YES

## Encryption Implementation Details

### 1. Standard Encryption Algorithms Used

SeChat uses the following **standard, internationally recognized encryption algorithms**:

#### Primary Encryption Algorithm
- **Algorithm:** AES-256-CBC (Advanced Encryption Standard)
- **Key Length:** 256 bits (32 bytes)
- **Mode:** Cipher Block Chaining (CBC)
- **Padding:** PKCS7
- **IV Length:** 128 bits (16 bytes)
- **Standard Body:** NIST (National Institute of Standards and Technology)

#### Cryptographic Hash Functions
- **Algorithm:** SHA-256 (Secure Hash Algorithm)
- **Purpose:** Data integrity verification and checksum generation
- **Standard Body:** NIST FIPS 180-4

#### Key Exchange and Management
- **Algorithm:** Ed25519 (Edwards Curve Digital Signature Algorithm)
- **Purpose:** Public key cryptography for key exchange
- **Standard Body:** RFC 8032 (Internet Engineering Task Force)

### 2. Encryption Usage in SeChat

#### What Gets Encrypted
SeChat encrypts the following data types:

1. **Message Content**
   - All text messages sent between users
   - Message metadata (timestamps, sender/recipient IDs)
   - Message status information (delivered, read indicators)

2. **User Communication Data**
   - Typing indicators
   - Online/offline status updates
   - Invitation and response data
   - Conversation metadata

3. **Local Storage**
   - All user data stored locally on device
   - Encryption keys and key pairs
   - User preferences and settings

#### Encryption Flow
1. **Key Generation:** Ed25519 key pairs generated for each user
2. **Key Exchange:** Public keys exchanged via QR code scanning
3. **Message Encryption:** AES-256-CBC encryption of all message content
4. **Data Integrity:** SHA-256 checksums for tamper detection
5. **Local Storage:** All data encrypted before local storage

### 3. Technical Implementation

#### Encryption Service Architecture
```
SeChat Encryption Stack:
├── EnhancedChatEncryptionService (Primary encryption service)
├── EncryptionService (Core AES-256-CBC implementation)
├── SeSessionService (Session management and key storage)
└── KeyExchangeService (Public key exchange)
```

#### Encryption Process
1. **Data Preparation:** JSON serialization of message data
2. **Key Retrieval:** Get recipient-specific encryption key
3. **IV Generation:** Generate random 128-bit initialization vector
4. **Encryption:** AES-256-CBC encryption with PKCS7 padding
5. **Envelope Creation:** Package encrypted data with metadata
6. **Checksum Generation:** SHA-256 hash for integrity verification

#### Decryption Process
1. **Envelope Parsing:** Extract encrypted data and metadata
2. **Key Retrieval:** Get appropriate decryption key
3. **Integrity Check:** Verify SHA-256 checksum
4. **Decryption:** AES-256-CBC decryption with PKCS7 unpadding
5. **Data Reconstruction:** JSON deserialization of message data

### 4. Security Features

#### End-to-End Encryption
- **Local Encryption:** All data encrypted on sender's device
- **Transit Security:** Encrypted data transmitted via secure channels
- **Local Decryption:** All data decrypted on recipient's device
- **Server Blindness:** Servers cannot read encrypted message content

#### Key Management
- **Unique Keys:** Each user pair has unique encryption keys
- **Secure Storage:** Keys stored using Flutter Secure Storage
- **Key Rotation:** Support for key regeneration and rotation
- **Key Exchange:** Secure public key exchange via QR codes

#### Data Integrity
- **Checksums:** SHA-256 checksums for all encrypted data
- **Tamper Detection:** Automatic verification of data integrity
- **Error Handling:** Comprehensive error handling for encryption failures

### 5. Compliance and Standards

#### International Standards Compliance
- **AES-256-CBC:** NIST FIPS 197 (Advanced Encryption Standard)
- **SHA-256:** NIST FIPS 180-4 (Secure Hash Standard)
- **Ed25519:** RFC 8032 (Edwards-Curve Digital Signature Algorithm)
- **PKCS7:** RFC 2315 (Public-Key Cryptography Standards)

#### No Proprietary Algorithms
SeChat does **NOT** use any proprietary or non-standard encryption algorithms. All encryption is performed using internationally recognized, standard algorithms.

#### No Custom Encryption
SeChat does **NOT** implement custom encryption algorithms. All encryption functionality uses well-established, peer-reviewed cryptographic libraries and standards.

### 6. Third-Party Libraries

#### Cryptographic Libraries Used
- **PointyCastle:** Dart implementation of cryptographic algorithms
- **Crypto:** Dart cryptographic hash functions
- **Encrypt:** Flutter encryption package (AES implementation)
- **Sodium Libs:** Cross-platform cryptographic library

#### Library Standards Compliance
All third-party libraries used implement standard cryptographic algorithms and are regularly updated for security compliance.

### 7. Export Compliance

#### Encryption Export Classification
- **Category:** Mass Market Software
- **Classification:** EAR99 (Export Administration Regulations)
- **Restrictions:** None - uses only standard encryption algorithms

#### No Restricted Algorithms
SeChat does not use any encryption algorithms that require export licenses or special permissions.

### 8. Privacy and Data Protection

#### Zero-Knowledge Architecture
- **No Data Collection:** SeChat does not collect user data
- **No Server Storage:** Messages are not stored on servers
- **Local Processing:** All encryption/decryption happens locally
- **Minimal Metadata:** Only routing information is unencrypted

#### Compliance Statements
- **GDPR Compliant:** No personal data collection or processing
- **CCPA Compliant:** No data collection or sharing
- **COPPA Compliant:** No data collection from children
- **Privacy by Design:** Encryption built into core architecture

### 9. Testing and Validation

#### Encryption Testing
- **Round-trip Testing:** Automated encryption/decryption validation
- **Key Generation Testing:** Verification of key generation processes
- **Integrity Testing:** Checksum generation and validation testing
- **Performance Testing:** Encryption performance benchmarking

#### Security Auditing
- **Code Review:** Regular security code reviews
- **Dependency Scanning:** Regular scanning of cryptographic dependencies
- **Vulnerability Assessment:** Regular security vulnerability assessments

### 10. Contact Information

**Developer:** StrapBlaque  
**Contact:** bruno@strapblaque.com  
**Website:** strapblaque.com  
**Support:** +27 65 347 9779  

---

## Declaration

I hereby declare that:

1. SeChat uses only standard, internationally recognized encryption algorithms
2. No proprietary or custom encryption algorithms are implemented
3. All encryption is performed using established cryptographic standards
4. The app complies with all applicable export regulations
5. This documentation accurately represents the encryption implementation



