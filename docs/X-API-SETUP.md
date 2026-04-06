# X (Twitter) API Setup

## 1. Create Developer Account

1. Go to [developer.twitter.com](https://developer.twitter.com/)
2. Sign in with your X account
3. Create a Project → Create an App
4. Name it (e.g., "Bookmark Pipeline")

## 2. Configure OAuth 2.0

1. Open your app → **User authentication settings** → **Set up**
2. Enable **OAuth 2.0**
3. Set **Callback URL**: `http://localhost:3000/auth/callback`
4. App type: **Confidential client** / **Web App**
5. Permissions: Read (tweets and bookmarks)
6. Save

## 3. Get Credentials

1. Open **Keys and tokens**
2. Copy **OAuth 2.0 Client ID**
3. Copy **OAuth 2.0 Client Secret**
4. Store securely (never commit to git)

## 4. Get Refresh Token (One-Time)

```bash
export TWITTER_CLIENT_ID='your_client_id'
export TWITTER_CLIENT_SECRET='your_client_secret'

# Start OAuth flow
./scripts/get-twitter-oauth-refresh-token.sh start

# Authorize in browser, then:
./scripts/get-twitter-oauth-refresh-token.sh exchange
# Paste the callback URL when prompted
```

## 5. Get Your User ID

1. Go to [tweeterid.com](https://tweeterid.com/)
2. Enter your @handle
3. Copy the numeric ID

## 6. Set Environment Variables

```bash
# Add to ~/.openclaw/.env or export
TWITTER_CLIENT_ID="..."
TWITTER_CLIENT_SECRET="..."
TWITTER_REFRESH_TOKEN="..."
TWITTER_USER_ID="..."
```

## Cost

X API uses **Pay-Per-Use** pricing:
- ~$0.005 per bookmark read
- Daily fetch of 5 bookmarks ≈ $0.025/day
- Monthly cost: ~$0.75-1.50

Top up credits at [developer.twitter.com](https://developer.twitter.com/) → Dashboard.
