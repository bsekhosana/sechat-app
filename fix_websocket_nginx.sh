#!/bin/bash

# Fix WebSocket nginx configuration for Session Messenger
echo "🔧 Fixing WebSocket nginx configuration..."

# Backup current nginx config
echo "📋 Backing up current nginx configuration..."
cp /etc/nginx/sites-available/askless.strapblaque.com /etc/nginx/sites-available/askless.strapblaque.com.backup.$(date +%Y%m%d_%H%M%S)

# Update nginx configuration to include WebSocket proxy
echo "🔧 Updating nginx configuration..."
cat > /etc/nginx/sites-available/askless.strapblaque.com << 'EOF'
server {
    listen 80;
    server_name askless.strapblaque.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name askless.strapblaque.com;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/askless.strapblaque.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/askless.strapblaque.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Laravel API
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }

    # WebSocket proxy for Session Messenger
    location /ws {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
    }

    # Live monitor
    location /live-monitor {
        proxy_pass http://localhost:3001/live-monitor;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Deny access to sensitive files
    location ~ /\. {
        deny all;
    }
}
EOF

# Test nginx configuration
echo "🧪 Testing nginx configuration..."
nginx -t

if [ $? -eq 0 ]; then
    echo "✅ Nginx configuration is valid"
    
    # Reload nginx
    echo "🔄 Reloading nginx..."
    systemctl reload nginx
    
    # Restart Session Messenger server
    echo "🔄 Restarting Session Messenger server..."
    cd /root/session-messenger-server
    pm2 restart session-messenger || pm2 start server.js --name session-messenger
    
    echo "✅ WebSocket configuration fixed!"
    echo "🌐 WebSocket endpoint: wss://askless.strapblaque.com/ws"
    echo "📊 Live monitor: https://askless.strapblaque.com/live-monitor"
else
    echo "❌ Nginx configuration test failed"
    echo "🔄 Restoring backup..."
    cp /etc/nginx/sites-available/askless.strapblaque.com.backup.* /etc/nginx/sites-available/askless.strapblaque.com
    exit 1
fi 