//
//  SessionProtocol.h
//  Runner
//
//  Created by Session Protocol Implementation
//

#import <Foundation/Foundation.h>
#import "SessionApi.h"

NS_ASSUME_NONNULL_BEGIN

@interface SessionProtocol : NSObject

- (instancetype)init;

// Key generation
- (NSDictionary<NSString *, NSString *> *)generateEd25519KeyPairWithError:(NSError **)error;

// Session management
- (void)initializeWithIdentity:(SessionIdentity *)identity error:(NSError **)error;
- (void)connectWithError:(NSError **)error;
- (void)disconnectWithError:(NSError **)error;

// Messaging
- (void)sendMessage:(SessionMessage *)message error:(NSError **)error;
- (void)sendTypingIndicatorWithSessionId:(NSString *)sessionId isTyping:(BOOL)isTyping error:(NSError **)error;

// Contact management
- (void)addContact:(SessionContact *)contact error:(NSError **)error;
- (void)removeContactWithSessionId:(NSString *)sessionId error:(NSError **)error;
- (void)updateContact:(SessionContact *)contact error:(NSError **)error;

// Group management
- (NSString *)createGroup:(SessionGroup *)group error:(NSError **)error;
- (void)addMemberToGroupWithGroupId:(NSString *)groupId memberId:(NSString *)memberId error:(NSError **)error;
- (void)removeMemberFromGroupWithGroupId:(NSString *)groupId memberId:(NSString *)memberId error:(NSError **)error;
- (void)leaveGroupWithGroupId:(NSString *)groupId error:(NSError **)error;

// File management
- (NSString *)uploadAttachment:(SessionAttachment *)attachment error:(NSError **)error;
- (SessionAttachment *)downloadAttachmentWithAttachmentId:(NSString *)attachmentId error:(NSError **)error;

// Encryption
- (NSString *)encryptMessage:(NSString *)message recipientId:(NSString *)recipientId error:(NSError **)error;
- (NSString *)decryptMessage:(NSString *)encryptedMessage senderId:(NSString *)senderId error:(NSError **)error;

// Network configuration
- (void)configureOnionRoutingWithEnabled:(BOOL)enabled proxyUrl:(NSString * _Nullable)proxyUrl error:(NSError **)error;

// Storage
- (void)saveToStorageWithKey:(NSString *)key value:(NSString *)value error:(NSError **)error;
- (NSString *)loadFromStorageWithKey:(NSString *)key error:(NSError **)error;

// Utilities
- (NSString *)generateSessionIdWithPublicKey:(NSString *)publicKey error:(NSError **)error;
- (BOOL)validateSessionId:(NSString *)sessionId;

@end

NS_ASSUME_NONNULL_END 