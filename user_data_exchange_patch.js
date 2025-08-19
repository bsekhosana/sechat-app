// Patch to add user_data_exchange event handler to socketService.js

// Add this event handler after the key_exchange_response handler (around line 94)
socket.on('user_data_exchange', (data) => {
  this.emitLogEvent(io, 'key-exchange', 'debug', `Received user_data_exchange event from socket ${socket.id}`, {
    socketId: socket.id,
    sessionId: socket.sessionId || 'unregistered',
    data,
    timestamp: new Date().toISOString()
  });
  this.handleUserDataExchange(socket, data, io);
});

// Add this method after the handleKeyExchangeResponse method (around line 347)
handleUserDataExchange(socket, data, io) {
  try {
    const { recipientId, encryptedData, timestamp } = data;
    const senderId = socket.sessionId;
    
    if (!senderId || !recipientId || !encryptedData) {
      this.emitLogEvent(io, 'error', 'error', `User data exchange failed: Missing required fields from ${senderId} to ${recipientId}`, {
        senderId,
        recipientId,
        socketId: socket.id
      });
      socket.emit('error', { message: 'Missing required fields for user data exchange' });
      return;
    }
    
    this.emitLogEvent(io, 'key-exchange', 'info', `User data exchange from ${senderId} to ${recipientId}`, {
      senderId,
      recipientId,
      socketId: socket.id
    });
    
    const recipientSocketId = this.userSockets.get(recipientId);
    
    if (recipientSocketId) {
      // Recipient is online - deliver immediately
      this.emitLogEvent(io, 'key-exchange', 'info', `Recipient ${recipientId} is online, delivering user data exchange immediately`, {
        senderId,
        recipientId,
        socketId: socket.id
      });
      
      io.to(recipientSocketId).emit('user_data_exchange', {
        recipientId: senderId,
        encryptedData,
        timestamp,
        conversationId: data.conversationId
      });
      
      this.emitLogEvent(io, 'key-exchange', 'success', `User data exchange delivered to ${recipientId}`, {
        senderId,
        recipientId,
        socketId: socket.id
      });
    } else {
      // Recipient is offline - queue the message
      this.emitLogEvent(io, 'queue', 'info', `Recipient ${recipientId} is offline, queuing user data exchange`, {
        senderId,
        recipientId,
        socketId: socket.id
      });
      
      const queued = this.messageQueue.queueMessage(recipientId, {
        type: 'user_data_exchange',
        senderId,
        recipientId,
        encryptedData,
        timestamp,
        conversationId: data.conversationId
      });
      
      if (queued) {
        this.emitLogEvent(io, 'queue', 'success', `User data exchange queued successfully for ${recipientId}`, {
          senderId,
          recipientId,
          socketId: socket.id
        });
      } else {
        this.emitLogEvent(io, 'error', 'error', `Failed to queue user data exchange for ${recipientId}`, {
          senderId,
          recipientId,
          socketId: socket.id
        });
        socket.emit('error', {
          message: 'Failed to queue user data exchange'
        });
      }
    }
  } catch (error) {
    console.error('Error handling user_data_exchange:', error);
    this.emitLogEvent(io, 'error', 'error', `User data exchange error: ${error.message}`, {
      socketId: socket.id
    });
  }
}
