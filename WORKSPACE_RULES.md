# Workspace Rules

## SessionMessenger Server Changes

When making changes, updates, or edits to the SessionMessenger server, **ALWAYS** SSH into the VPS server and make changes directly on the server rather than editing local files.

### VPS Connection Details
- **Username**: root
- **IP Address**: 41.76.111.100
- **Port**: 1337
- **Directory**: /var/www/askless

### SSH Command Format
```bash
ssh -p 1337 root@41.76.111.100
cd /var/www/askless
```

### Change Management Process

1. **Connect to VPS**: Use the SSH command above
2. **Navigate to Directory**: `cd /var/www/askless`
3. **Make Changes**: Edit files directly on the server
4. **Restart Service**: `pm2 restart askless-session-messenger`
5. **Check Logs**: `pm2 logs askless-session-messenger --lines 20`
6. **Verify Status**: `pm2 status`

### Common Commands

```bash
# Connect and navigate
ssh -p 1337 root@41.76.111.100 "cd /var/www/askless && pwd"

# Check server status
ssh -p 1337 root@41.76.111.100 "cd /var/www/askless && pm2 status"

# View server logs
ssh -p 1337 root@41.76.111.100 "cd /var/www/askless && pm2 logs askless-session-messenger --lines 20"

# Restart server
ssh -p 1337 root@41.76.111.100 "cd /var/www/askless && pm2 restart askless-session-messenger"

# Edit server files
ssh -p 1337 root@41.76.111.100 "cd /var/www/askless && nano server.js"

# Check file contents
ssh -p 1337 root@41.76.111.100 "cd /var/www/askless && cat server.js | grep -n 'keyword'"
```

### Important Notes

- **Never edit local server files** - all server changes must be made on the VPS
- **Always restart the service** after making changes
- **Check logs** to verify changes are working
- **Use proper SSH command format** with port 1337
- **Navigate to /var/www/askless** directory before making changes

### Flutter App Changes

Flutter app changes (client-side) can still be made locally in the `sechat_app` directory, but any server-side changes must go through the VPS.

### Exception Handling

If SSH connection fails or hangs:
1. Try with timeout: `ssh -p 1337 -o ConnectTimeout=10 root@41.76.111.100`
2. Use direct command execution: `ssh -p 1337 root@41.76.111.100 "command"`
3. Check if the server is accessible and the port is open 