#!/bin/bash

echo "🔍 Comprehensive Local Storage Operations Audit"
echo "==============================================="

# Check LocalStorageService deletion functions
echo "📋 Checking LocalStorageService deletion functions..."

if grep -q "deleteChat.*chatId" lib/core/services/local_storage_service.dart; then
    echo "✅ deleteChat function exists"
else
    echo "❌ deleteChat function missing"
fi

if grep -q "deleteMessage.*chatId.*messageId" lib/core/services/local_storage_service.dart; then
    echo "✅ deleteMessage function exists"
else
    echo "❌ deleteMessage function missing"
fi

if grep -q "deleteMessagesForChat.*chatId" lib/core/services/local_storage_service.dart; then
    echo "✅ deleteMessagesForChat function exists"
else
    echo "❌ deleteMessagesForChat function missing"
fi

if grep -q "deleteInvitation.*invitationId" lib/core/services/local_storage_service.dart; then
    echo "✅ deleteInvitation function exists"
else
    echo "❌ deleteInvitation function missing"
fi

if grep -q "deleteNotification.*notificationId" lib/core/services/local_storage_service.dart; then
    echo "✅ deleteNotification function exists"
else
    echo "❌ deleteNotification function missing"
fi

if grep -q "clearAllData" lib/core/services/local_storage_service.dart; then
    echo "✅ clearAllData function exists"
else
    echo "❌ clearAllData function missing"
fi

# Check provider deletion functions
echo "📋 Checking provider deletion functions..."

if grep -q "deleteInvitation.*invitationId" lib/features/invitations/providers/invitation_provider.dart; then
    echo "✅ InvitationProvider.deleteInvitation exists"
else
    echo "❌ InvitationProvider.deleteInvitation missing"
fi

if grep -q "removeNotification.*notificationId" lib/features/notifications/providers/notification_provider.dart; then
    echo "✅ NotificationProvider.removeNotification exists"
else
    echo "❌ NotificationProvider.removeNotification missing"
fi

if grep -q "deleteMessage.*chatId.*messageId" lib/features/chat/providers/chat_provider.dart; then
    echo "✅ ChatProvider.deleteMessage exists"
else
    echo "❌ ChatProvider.deleteMessage missing"
fi

# Check UI deletion functions
echo "📋 Checking UI deletion functions..."

if grep -q "_deleteInvitation" lib/features/invitations/screens/invitations_screen.dart; then
    echo "✅ InvitationsScreen._deleteInvitation exists"
else
    echo "❌ InvitationsScreen._deleteInvitation missing"
fi

if grep -q "_removeUserChats" lib/features/chat/screens/chat_screen.dart; then
    echo "✅ ChatScreen._removeUserChats exists"
else
    echo "❌ ChatScreen._removeUserChats missing"
fi

if grep -q "_clearAllChats" lib/shared/widgets/profile_icon_widget.dart; then
    echo "✅ ProfileIconWidget._clearAllChats exists"
else
    echo "❌ ProfileIconWidget._clearAllChats missing"
fi

# Check persistence and sync functions
echo "📋 Checking persistence and sync functions..."

if grep -q "notifyListeners" lib/core/services/local_storage_service.dart; then
    echo "✅ LocalStorageService uses notifyListeners for UI updates"
else
    echo "❌ LocalStorageService missing notifyListeners"
fi

if grep -q "saveInvitations.*toJson" lib/features/invitations/providers/invitation_provider.dart; then
    echo "✅ InvitationProvider saves to local storage"
else
    echo "❌ InvitationProvider missing local storage saving"
fi

if grep -q "saveNotifications" lib/features/notifications/providers/notification_provider.dart; then
    echo "✅ NotificationProvider saves to local storage"
else
    echo "❌ NotificationProvider missing local storage saving"
fi

echo ""
echo "🔧 Issues Found and Fixes Needed:"
echo "1. Ensure all deletion functions save to local storage"
echo "2. Ensure all providers sync with local storage"
echo "3. Ensure all UI updates trigger local storage saves"
echo "4. Ensure all data persists until manual deletion"
echo "5. Ensure proper error handling for all operations"
echo ""
echo "📝 Next Steps:"
echo "1. Fix invitation persistence (already done)"
echo "2. Fix notification persistence"
echo "3. Fix chat/message persistence"
echo "4. Fix user data persistence"
echo "5. Test all deletion functions"
echo ""
echo "✅ Local Storage Operations Audit Complete!" 