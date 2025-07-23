# Nginx Configuration for Live Monitor

## 🔧 **Manual Nginx Configuration Update Required**

The live monitor endpoint needs to be added to your nginx configuration. Please run these commands on your server:

### **1. Connect to your server:**
```bash
ssh -p 1337 laravel@41.76.111.100
```

### **2. Update nginx configuration:**
```bash
sudo tee /etc/nginx/sites-available/askless.strapblaque.com > /dev/null << 'EOF'
server {
    server_name askless.strapblaque.com;
    
    root /var/www/askless;
    index index.php index.html index.htm;
    
    # Session Messenger WebSocket proxy
    location /ws {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
    
    # Session Messenger Health check
    location /health {
        proxy_pass http://localhost:5000/health;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Session Messenger Statistics
    location /stats {
        proxy_pass http://localhost:5000/stats;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Session Messenger Socket logs
    location /logs {
        proxy_pass http://localhost:5000/logs;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Session Messenger Test client
    location /test-client.html {
        proxy_pass http://localhost:5000/test-client.html;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Session Messenger Live Monitor
    location /live-monitor {
        proxy_pass http://localhost:5000/live-monitor;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Original PHP handling
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/askless.strapblaque.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/askless.strapblaque.com/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}

server {
    if ($host = askless.strapblaque.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    listen 80;
    server_name askless.strapblaque.com;
    return 404; # managed by Certbot
}
EOF
```

### **3. Test and reload nginx:**
```bash
sudo nginx -t
sudo systemctl reload nginx
```

### **4. Test the live monitor:**
```bash
curl -s https://askless.strapblaque.com/live-monitor | head -10
```

## 🎯 **Live Monitor Features**

Once configured, your live monitor will be available at:
**https://askless.strapblaque.com/live-monitor**

### **📊 Dashboard Sections:**
- **Server Statistics:** Total connections, messages, invitations, uptime, memory usage
- **Active Connections:** Real-time list of connected users
- **Recent Messages:** Latest messages with sender/recipient info
- **Recent Invitations:** Latest invitations with status
- **Server Logs:** Real-time server logs with color coding
- **System Health:** CPU usage, response time, error rate

### **🔄 Real-time Updates:**
- Auto-refresh every 5 seconds
- WebSocket connection for instant updates
- Toggle auto-refresh on/off
- Mobile responsive design

### **🎨 Features:**
- Beautiful gradient background
- Glass morphism design
- Color-coded status indicators
- Hover effects and animations
- Professional monitoring interface

## ✅ **After Configuration**

Your Session Messenger server will have these endpoints:
- **Health:** `https://askless.strapblaque.com/health`
- **Stats:** `https://askless.strapblaque.com/stats`
- **Logs:** `https://askless.strapblaque.com/logs`
- **Test Client:** `https://askless.strapblaque.com/test-client.html`
- **Live Monitor:** `https://askless.strapblaque.com/live-monitor` 🆕
- **WebSocket:** `wss://askless.strapblaque.com/ws` 