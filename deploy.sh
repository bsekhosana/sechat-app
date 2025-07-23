#!/bin/bash

# Session Messenger Server Deployment Script
# Deploys to: 41.76.111.100:1337 (SSH) -> /var/www/askless
# Socket Port: 5000
# Domain: askless.strapblaque.com

set -e

# Configuration
SERVER_USER=laravel
SERVER_IP=41.76.111.100
SERVER_PORT=1337
SOCKET_PORT=5000
SERVER_PATH=/var/www/askless
GIT_REPO=git@github.com:bsekhosana/askless.git
PM2_PROCESS_NAME=askless-session-messenger

echo "🚀 Session Messenger Server Deployment"
echo "======================================"
echo "Server: $SERVER_USER@$SERVER_IP:$SERVER_PORT"
echo "Path: $SERVER_PATH"
echo "Socket Port: $SOCKET_PORT"
echo "PM2 Process: $PM2_PROCESS_NAME"
echo ""

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    echo "❌ package.json not found. Please run this script from the session-messenger-server directory."
    exit 1
fi

# Check if git is initialized
if [ ! -d ".git" ]; then
    echo "📦 Initializing git repository..."
    git init
    git add .
    git commit -m "Initial commit: Session Messenger Server"
fi

# Check if remote exists, if not add it
if ! git remote get-url origin &> /dev/null; then
    echo "🔗 Adding git remote..."
    git remote add origin $GIT_REPO
fi

# Push to git
echo "📤 Pushing to git repository..."
git add .
if git diff --staged --quiet; then
    echo "No changes to commit, pushing existing commits..."
else
    git commit -m "Deploy: Session Messenger Server $(date)"
fi
git push -u origin main || git push origin main

echo ""
echo "🔌 Deploying to server..."

# Deploy to server
ssh -p $SERVER_PORT $SERVER_USER@$SERVER_IP << EOF
    set -e
    
    echo "📁 Creating server directory..."
    mkdir -p $SERVER_PATH
    
    echo "📂 Cloning/updating repository..."
    if [ ! -d "$SERVER_PATH/.git" ]; then
        cd $SERVER_PATH
        git clone $GIT_REPO .
    else
        cd $SERVER_PATH
        git fetch origin
        git reset --hard origin/main
    fi
    
    echo "📦 Installing dependencies..."
    npm install --production
    
    echo "🔧 Setting up environment..."
    if [ ! -f ".env" ]; then
        cat > .env << ENVEOF
# Session Messenger Server Environment
NODE_ENV=production
PORT=$SOCKET_PORT
SOCKET_PORT=$SOCKET_PORT

# Database Configuration (if needed)
DB_HOST=localhost
DB_USERNAME=root
DB_PASSWORD=
DB_DATABASE=sechat
DB_PORT=3306

# SSL Configuration
SSL_KEY_PATH=/etc/letsencrypt/live/askless.strapblaque.com/privkey.pem
SSL_CERT_PATH=/etc/letsencrypt/live/askless.strapblaque.com/fullchain.pem

# Logging
LOG_LEVEL=info
LOG_FILE=logs/session-messenger.log
ENVEOF
    fi
    
    echo "📁 Creating logs directory..."
    mkdir -p logs
    
    echo "🔄 Restarting PM2 process..."
    # Stop existing process if running
    pm2 stop $PM2_PROCESS_NAME 2>/dev/null || true
    pm2 delete $PM2_PROCESS_NAME 2>/dev/null || true
    
    # Start new process
    pm2 start server.js --name $PM2_PROCESS_NAME --env production
    
    echo "💾 Saving PM2 configuration..."
    pm2 save
    
    echo "🔄 Setting up PM2 startup script..."
    echo "Note: PM2 startup script requires manual setup with sudo access"
    echo "Run 'pm2 startup' manually on the server if needed"
    
    echo "✅ Deployment completed!"
    echo ""
    echo "📊 PM2 Status:"
    pm2 show $PM2_PROCESS_NAME
    
    echo ""
    echo "🔍 Checking server health..."
    sleep 3
    
    # Check local health
    LOCAL_HEALTH=\$(curl -s -w "%{http_code}" http://localhost:$SOCKET_PORT/health)
    LOCAL_HTTP_CODE=\${LOCAL_HEALTH: -3}
    LOCAL_RESPONSE=\${LOCAL_HEALTH%???}
    
    if [ "\$LOCAL_HTTP_CODE" = "200" ]; then
        echo "✅ Local server is healthy (HTTP \$LOCAL_HTTP_CODE)"
        echo "Response: \$LOCAL_RESPONSE"
    else
        echo "⚠️ Local health check failed (HTTP \$LOCAL_HTTP_CODE)"
        echo "Response: \$LOCAL_RESPONSE"
    fi
    
    # Check external health
    echo ""
    echo "🌐 Testing external access..."
    EXTERNAL_HEALTH=\$(curl -s -w "%{http_code}" https://askless.strapblaque.com/health)
    EXTERNAL_HTTP_CODE=\${EXTERNAL_HEALTH: -3}
    
    if [ "\$EXTERNAL_HTTP_CODE" = "200" ]; then
        echo "✅ External access working (HTTP \$EXTERNAL_HTTP_CODE)"
    else
        echo "⚠️ External access failed (HTTP \$EXTERNAL_HTTP_CODE)"
        echo "Note: Server might still be starting"
    fi
    
    echo ""
    echo "📋 Recent logs:"
    pm2 logs $PM2_PROCESS_NAME --lines 5 --nostream
EOF

echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "📱 Server Information:"
echo "   - Health Check: https://askless.strapblaque.com/health"
echo "   - Statistics: https://askless.strapblaque.com/stats"
echo "   - Socket Logs: https://askless.strapblaque.com/logs"
echo "   - Test Client: https://askless.strapblaque.com/test-client.html"
echo "   - Live Monitor: https://askless.strapblaque.com/live-monitor"
echo ""
echo "🔧 Management Commands:"
echo "   - View logs: ssh -p $SERVER_PORT $SERVER_USER@$SERVER_IP 'pm2 logs $PM2_PROCESS_NAME'"
echo "   - Restart: ssh -p $SERVER_PORT $SERVER_USER@$SERVER_IP 'pm2 restart $PM2_PROCESS_NAME'"
echo "   - Status: ssh -p $SERVER_PORT $SERVER_USER@$SERVER_IP 'pm2 show $PM2_PROCESS_NAME'"
echo ""
echo "🌐 Update Flutter app WebSocket URL to: wss://askless.strapblaque.com/ws" 