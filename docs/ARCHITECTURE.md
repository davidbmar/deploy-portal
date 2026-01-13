# Architecture Diagram - Complete System

This document provides comprehensive visual diagrams of the entire authentication and deployment system architecture.

## Table of Contents

- [High-Level Overview](#high-level-overview)
- [Detailed Authentication Flow](#detailed-authentication-flow)
- [Component Interaction Diagram](#component-interaction-diagram)
- [Network Flow](#network-flow)
- [Deployment Architecture](#deployment-architecture)
- [Security Layers](#security-layers)

---

## High-Level Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              USER BROWSER                               │
│                         (https://52.43.35.1)                   │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 │ HTTPS Request
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         EC2 INSTANCE (Ubuntu)                           │
│                        Security Group: sg-0d6bba...                     │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                    NGINX (Port 443/80)                            │ │
│  │                   Reverse Proxy + TLS                             │ │
│  │                                                                   │ │
│  │  • Handles HTTPS/TLS termination                                 │ │
│  │  • Routes requests based on path                                 │ │
│  │  • Enforces authentication via auth_request                      │ │
│  │  • Injects user headers (X-User-Email, X-Auth-Request-User)      │ │
│  └─────────────┬─────────────────────────────────────────────────────┘ │
│                │                                                         │
│                │ auth_request /oauth2/auth                               │
│                ▼                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │              OAUTH2-PROXY (Port 4180)                             │ │
│  │            OIDC Authentication Service                            │ │
│  │                                                                   │ │
│  │  • Validates session cookies                                     │ │
│  │  • Redirects to AWS Cognito if not authenticated                 │ │
│  │  • Validates JWT tokens from Cognito                             │ │
│  │  • Sets secure session cookies                                   │ │
│  └─────────────┬─────────────────────────────────────────────────────┘ │
│                │                                                         │
│                │ OAuth2/OIDC Flow                                        │
│                ▼                                                         │
│       ┌────────────────────────────────────────────────┐                │
│       │    Proxy to Applications (based on path)      │                │
│       └────────────────────────────────────────────────┘                │
│                │                                                         │
│    ┌───────────┼───────────┬─────────────┬─────────────┬──────────┐    │
│    │           │           │             │             │          │    │
│    ▼           ▼           ▼             ▼             ▼          ▼    │
│  ┌────┐    ┌────────┐  ┌─────────┐  ┌─────────┐  ┌────────┐  ┌─────┐ │
│  │ /  │    │/deploy/│  │/cloner/ │  │/app-1/  │  │/app-2/ │  │ ... │ │
│  │    │    │        │  │         │  │         │  │        │  │     │ │
│  └─┬──┘    └───┬────┘  └────┬────┘  └────┬────┘  └───┬────┘  └──┬──┘ │
│    │           │            │            │            │           │    │
│    ▼           ▼            ▼            ▼            ▼           ▼    │
│  ┌────────┐ ┌─────────┐ ┌──────────┐ ┌────────┐ ┌────────┐  ┌──────┐ │
│  │SSH     │ │Deploy   │ │Website   │ │User    │ │User    │  │User  │ │
│  │Helper  │ │Portal   │ │Cloner    │ │App 1   │ │App 2   │  │App N │ │
│  │        │ │         │ │          │ │        │ │        │  │      │ │
│  │:8080   │ │:5000    │ │:3000     │ │:8001   │ │:8002   │  │:NNNN │ │
│  │        │ │         │ │          │ │        │ │        │  │      │ │
│  │Node.js │ │Flask/   │ │Node.js   │ │Any     │ │Any     │  │Any   │ │
│  │        │ │Python   │ │          │ │Stack   │ │Stack   │  │Stack │ │
│  └────────┘ └─────────┘ └──────────┘ └────────┘ └────────┘  └──────┘ │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ OAuth2/OIDC Flow
                                 ▼
                   ┌──────────────────────────────┐
                   │      AWS COGNITO             │
                   │   (User Pool + Hosted UI)    │
                   │                              │
                   │  • User authentication       │
                   │  • JWT token issuance        │
                   │  • User management           │
                   │  • MFA (optional)            │
                   └──────────────────────────────┘
```

---

## Detailed Authentication Flow

```
┌─────────┐
│  USER   │
│ BROWSER │
└────┬────┘
     │
     │ 1. GET https://52.43.35.1/
     │
     ▼
┌─────────────────────────────────────────────────────────────────┐
│                         NGINX (:443)                            │
│                                                                 │
│  location / {                                                   │
│      auth_request /oauth2/auth;  ◄─────┐                       │
│      ...                                │                       │
│  }                                      │                       │
└─────────────────────────────────────────┼───────────────────────┘
     │                                    │
     │ 2. Subrequest                      │
     │    (internal)                      │
     │                                    │
     ▼                                    │
┌─────────────────────────────────────────┼───────────────────────┐
│                    OAUTH2-PROXY (:4180) │                       │
│                                         │                       │
│  3. Check for valid session cookie      │                       │
│     • Cookie name: _oauth2_proxy        │                       │
│     • Validate expiry and signature     │                       │
│                                         │                       │
│  ┌──────────────────────────────────┐   │                       │
│  │ Session Valid?                   │   │                       │
│  └──────────────────────────────────┘   │                       │
│           │              │               │                       │
│     YES   │              │  NO           │                       │
│           ▼              ▼               │                       │
│  ┌─────────────┐  ┌──────────────────┐  │                       │
│  │Return 202   │  │Return 401        │  │                       │
│  │+ User Info  │  │Unauthorized      │  │                       │
│  │Headers      │  │                  │  │                       │
│  └──────┬──────┘  └────────┬─────────┘  │                       │
└─────────┼──────────────────┼─────────────┼───────────────────────┘
          │                  │             │
          │ 4a. Valid        │ 4b. Invalid │
          │                  │             │
     ┌────▼──────┐      ┌────▼─────────────▼────────────────────┐
     │           │      │                                        │
     │  Go to    │      │  5. Redirect to Cognito               │
     │  Step 11  │      │     /oauth2/start?rd=...              │
     │           │      │                                        │
     └───────────┘      └─────────────┬──────────────────────────┘
                                      │
                                      │ 6. 302 Redirect
                                      │
                                      ▼
                        ┌──────────────────────────────────────┐
                        │       AWS COGNITO HOSTED UI          │
                        │                                      │
                        │  7. Show login form                  │
                        │     • Username/Email                 │
                        │     • Password                       │
                        │     • Optional: MFA                  │
                        │     • Social providers (optional)    │
                        │                                      │
                        └──────────────┬───────────────────────┘
                                      │
                                      │ 8. User submits credentials
                                      │
                                      ▼
                        ┌──────────────────────────────────────┐
                        │       AWS COGNITO VALIDATES          │
                        │                                      │
                        │  • Check username/password           │
                        │  • Verify MFA (if enabled)           │
                        │  • Generate authorization code       │
                        │                                      │
                        └──────────────┬───────────────────────┘
                                      │
                                      │ 9. Redirect with auth code
                                      │    https://52.43.35.1/oauth2/callback?code=XXX
                                      │
                                      ▼
                        ┌──────────────────────────────────────┐
                        │    OAUTH2-PROXY (:4180)              │
                        │    /oauth2/callback endpoint         │
                        │                                      │
                        │  10. Exchange code for tokens:       │
                        │      • POST to Cognito token endpoint│
                        │      • Receive ID token (JWT)        │
                        │      • Receive access token          │
                        │      • Receive refresh token         │
                        │                                      │
                        │  11. Validate ID token:              │
                        │      • Verify JWT signature          │
                        │      • Check issuer (Cognito)        │
                        │      • Check audience (client ID)    │
                        │      • Check expiry                  │
                        │                                      │
                        │  12. Create session:                 │
                        │      • Generate session ID           │
                        │      • Store user info (email, sub)  │
                        │      • Set secure cookie:            │
                        │        _oauth2_proxy=SESSION_ID      │
                        │        HttpOnly, Secure, SameSite    │
                        │                                      │
                        │  13. Redirect to original URL        │
                        │      https://52.43.35.1/    │
                        │                                      │
                        └──────────────┬───────────────────────┘
                                      │
                                      │ 14. New request with cookie
                                      │
                                      ▼
                        ┌──────────────────────────────────────┐
                        │          NGINX (:443)                │
                        │                                      │
                        │  15. auth_request /oauth2/auth       │
                        │      → oauth2-proxy validates cookie │
                        │      → Returns 202 + user headers    │
                        │                                      │
                        │  16. Set headers from auth response: │
                        │      X-User-Email: user@example.com  │
                        │      X-Auth-Request-User: username   │
                        │                                      │
                        │  17. Proxy request to backend:       │
                        │      proxy_pass http://localhost:PORT│
                        │                                      │
                        └──────────────┬───────────────────────┘
                                      │
                                      │ 18. Proxied request with headers
                                      │
                                      ▼
                        ┌──────────────────────────────────────┐
                        │      BACKEND APPLICATION             │
                        │      (Port 8080, 5000, 3000, etc.)   │
                        │                                      │
                        │  19. Read headers:                   │
                        │      user_email = req.headers['X-User-Email']│
                        │                                      │
                        │  20. Process request                 │
                        │      • NO authentication code        │
                        │      • Trust nginx headers           │
                        │      • Application logic only        │
                        │                                      │
                        │  21. Return response                 │
                        │                                      │
                        └──────────────┬───────────────────────┘
                                      │
                                      │ 22. Response
                                      ▼
                        ┌──────────────────────────────────────┐
                        │          NGINX (:443)                │
                        │                                      │
                        │  23. Return to client                │
                        │                                      │
                        └──────────────┬───────────────────────┘
                                      │
                                      │ 24. HTTPS Response
                                      ▼
                                 ┌─────────┐
                                 │  USER   │
                                 │ BROWSER │
                                 └─────────┘
```

---

## Component Interaction Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          COMPONENT LAYERS                                │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│ LAYER 1: TLS/SSL TERMINATION                                            │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │                    NGINX (Port 443)                            │     │
│  │  ┌──────────────────────────────────────────────────────────┐  │     │
│  │  │  SSL Certificate: /etc/nginx/ssl/                       │  │     │
│  │  │  • Self-signed (dev) or Let's Encrypt (prod)            │  │     │
│  │  │  • TLS 1.2/1.3                                          │  │     │
│  │  │  • RSA 4096-bit or ECDSA                                │  │     │
│  │  └──────────────────────────────────────────────────────────┘  │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│ LAYER 2: AUTHENTICATION & AUTHORIZATION                                 │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │              OAUTH2-PROXY (Port 4180)                          │     │
│  │  ┌──────────────────────────────────────────────────────────┐  │     │
│  │  │  Configuration: /etc/oauth2-proxy/config.cfg            │  │     │
│  │  │                                                          │  │     │
│  │  │  provider = "oidc"                                       │  │     │
│  │  │  oidc_issuer_url = "https://cognito-idp.us-east-1...."  │  │     │
│  │  │  client_id = "..."                                       │  │     │
│  │  │  client_secret = "..."                                   │  │     │
│  │  │  cookie_secret = "..."                                   │  │     │
│  │  │  cookie_secure = true                                    │  │     │
│  │  │  cookie_httponly = true                                  │  │     │
│  │  │  cookie_samesite = "lax"                                 │  │     │
│  │  │  cookie_expire = "24h"                                   │  │     │
│  │  │  email_domains = ["*"]                                   │  │     │
│  │  └──────────────────────────────────────────────────────────┘  │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                              │                                           │
│                              │ OAuth2/OIDC Protocol                      │
│                              ▼                                           │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │                    AWS COGNITO                                 │     │
│  │  ┌──────────────────────────────────────────────────────────┐  │     │
│  │  │  User Pool: us-east-1_XXXXXXXXX                          │  │     │
│  │  │  Region: us-east-1                                       │  │     │
│  │  │                                                          │  │     │
│  │  │  Features:                                               │  │     │
│  │  │  • User registration & login                             │  │     │
│  │  │  • Password policies                                     │  │     │
│  │  │  • MFA (optional)                                        │  │     │
│  │  │  • Social identity providers (optional)                  │  │     │
│  │  │  • Hosted UI                                             │  │     │
│  │  │  • JWT token issuance                                    │  │     │
│  │  │  • Token refresh                                         │  │     │
│  │  │                                                          │  │     │
│  │  │  App Client Configuration:                               │  │     │
│  │  │  • Callback URLs: https://gateway.../oauth2/callback    │  │     │
│  │  │  • Logout URLs: https://gateway.../                     │  │     │
│  │  │  • OAuth 2.0 flows: Authorization code + PKCE           │  │     │
│  │  │  • OAuth scopes: openid, email, profile                 │  │     │
│  │  └──────────────────────────────────────────────────────────┘  │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│ LAYER 3: REVERSE PROXY & ROUTING                                        │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │                    NGINX ROUTING RULES                         │     │
│  │                                                                │     │
│  │  ┌──────────────────────────────────────────────────────────┐ │     │
│  │  │ location /oauth2/ {                                      │ │     │
│  │  │     proxy_pass http://127.0.0.1:4180;                    │ │     │
│  │  │     # Auth endpoints (no auth required)                  │ │     │
│  │  │ }                                                        │ │     │
│  │  └──────────────────────────────────────────────────────────┘ │     │
│  │                                                                │     │
│  │  ┌──────────────────────────────────────────────────────────┐ │     │
│  │  │ location / {                                             │ │     │
│  │  │     auth_request /oauth2/auth;                           │ │     │
│  │  │     proxy_pass http://127.0.0.1:8080;  # SSH Helper     │ │     │
│  │  │     proxy_set_header X-User-Email $email;                │ │     │
│  │  │ }                                                        │ │     │
│  │  └──────────────────────────────────────────────────────────┘ │     │
│  │                                                                │     │
│  │  ┌──────────────────────────────────────────────────────────┐ │     │
│  │  │ location /deploy/ {                                      │ │     │
│  │  │     auth_request /oauth2/auth;                           │ │     │
│  │  │     rewrite ^/deploy/(.*)$ /$1 break;                    │ │     │
│  │  │     proxy_pass http://127.0.0.1:5000;  # Deploy Portal  │ │     │
│  │  │     proxy_set_header X-User-Email $email;                │ │     │
│  │  │ }                                                        │ │     │
│  │  └──────────────────────────────────────────────────────────┘ │     │
│  │                                                                │     │
│  │  ┌──────────────────────────────────────────────────────────┐ │     │
│  │  │ location /cloner/ {                                      │ │     │
│  │  │     auth_request /oauth2/auth;                           │ │     │
│  │  │     rewrite ^/cloner/(.*)$ /$1 break;                    │ │     │
│  │  │     proxy_pass http://127.0.0.1:3000;  # Website Cloner │ │     │
│  │  │     proxy_set_header X-User-Email $email;                │ │     │
│  │  │ }                                                        │ │     │
│  │  └──────────────────────────────────────────────────────────┘ │     │
│  │                                                                │     │
│  │  ┌──────────────────────────────────────────────────────────┐ │     │
│  │  │ location /app-name/ {                                    │ │     │
│  │  │     auth_request /oauth2/auth;                           │ │     │
│  │  │     rewrite ^/app-name/(.*)$ /$1 break;                  │ │     │
│  │  │     proxy_pass http://127.0.0.1:DYNAMIC_PORT;  # User App│ │     │
│  │  │     proxy_set_header X-User-Email $email;                │ │     │
│  │  │ }                                                        │ │     │
│  │  └──────────────────────────────────────────────────────────┘ │     │
│  │                                                                │     │
│  │  ┌──────────────────────────────────────────────────────────┐ │     │
│  │  │ location /health {                                       │ │     │
│  │  │     return 200 "OK";                                     │ │     │
│  │  │     # Public endpoint (no auth)                          │ │     │
│  │  │ }                                                        │ │     │
│  │  └──────────────────────────────────────────────────────────┘ │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│ LAYER 4: APPLICATION SERVICES                                           │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  │
│  │ SSH Helper  │  │Deploy Portal │  │Website Cloner│  │  User Apps  │  │
│  │             │  │              │  │              │  │             │  │
│  │ Port: 8080  │  │ Port: 5000   │  │ Port: 3000   │  │ Port: 8000+ │  │
│  │ Tech: Node  │  │ Tech: Flask  │  │ Tech: Node   │  │ Tech: Any   │  │
│  │             │  │              │  │              │  │             │  │
│  │ Features:   │  │ Features:    │  │ Features:    │  │ Features:   │  │
│  │ • Terminal  │  │ • IP Whitelist│ │ • URL Clone │  │ • Custom    │  │
│  │ • WebSocket │  │ • SSH Keys   │  │ • S3 Deploy  │  │   Logic     │  │
│  │ • PTY       │  │ • Auto Deploy│  │ • Link Rewrite│ │            │  │
│  │             │  │ • Port Mgmt  │  │ • Dynamic Det│  │             │  │
│  │             │  │              │  │              │  │             │  │
│  │ Auth: None  │  │ Auth: None   │  │ Auth: None   │  │ Auth: None  │  │
│  │ (reads      │  │ (reads       │  │ (reads       │  │ (reads      │  │
│  │  headers)   │  │  headers)    │  │  headers)    │  │  headers)   │  │
│  └─────────────┘  └──────────────┘  └──────────────┘  └─────────────┘  │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│ LAYER 5: INFRASTRUCTURE & AWS SERVICES                                  │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │                    EC2 INSTANCE                                │     │
│  │  ┌──────────────────────────────────────────────────────────┐  │     │
│  │  │  IAM Role: ssh-whitelist-role                            │  │     │
│  │  │                                                          │  │     │
│  │  │  Permissions:                                            │  │     │
│  │  │  • ec2:DescribeSecurityGroups                           │  │     │
│  │  │  • ec2:AuthorizeSecurityGroupIngress                    │  │     │
│  │  │  • ec2:RevokeSecurityGroupIngress                       │  │     │
│  │  │  • s3:* (for website-cloner)                            │  │     │
│  │  └──────────────────────────────────────────────────────────┘  │     │
│  │                                                                │     │
│  │  ┌──────────────────────────────────────────────────────────┐  │     │
│  │  │  Security Group: sg-0d6bbadbbd290b320                    │  │     │
│  │  │                                                          │  │     │
│  │  │  Inbound Rules:                                          │  │     │
│  │  │  • Port 443 (HTTPS): 0.0.0.0/0                          │  │     │
│  │  │  • Port 80 (HTTP): 0.0.0.0/0 (for Let's Encrypt)        │  │     │
│  │  │  • Port 22 (SSH): Dynamic IPs only (via deploy-portal)  │  │     │
│  │  │                                                          │  │     │
│  │  │  Outbound Rules:                                         │  │     │
│  │  │  • All traffic: 0.0.0.0/0                               │  │     │
│  │  └──────────────────────────────────────────────────────────┘  │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │                    AWS S3 (Optional)                           │     │
│  │  ┌──────────────────────────────────────────────────────────┐  │     │
│  │  │  Used by: website-cloner                                 │  │     │
│  │  │                                                          │  │     │
│  │  │  Features:                                               │  │     │
│  │  │  • Static website hosting                                │  │     │
│  │  │  • Public read access                                    │  │     │
│  │  │  • CORS configuration                                    │  │     │
│  │  │  • Cache-Control headers                                 │  │     │
│  │  └──────────────────────────────────────────────────────────┘  │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Network Flow

```
INBOUND TRAFFIC FLOW:

Internet
    │
    │ HTTPS Request
    │ Port 443
    ▼
┌─────────────────────────────────────┐
│  AWS Security Group                 │
│  sg-0d6bbadbbd290b320               │
│                                     │
│  Rule: Allow 443 from 0.0.0.0/0    │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  EC2 Network Interface              │
│  Public IP: 52.43.35.1              │
│  Private IP: 10.x.x.x               │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  nginx (listening on 0.0.0.0:443)  │
│  Process: PID 89797                 │
└──────────────┬──────────────────────┘
               │
               ├─→ Internal subrequest to 127.0.0.1:4180 (oauth2-proxy)
               │   Returns: 202 (authenticated) or 401 (not authenticated)
               │
               ├─→ If authenticated, proxy to backend:
               │   • 127.0.0.1:8080 (ssh-helper)
               │   • 127.0.0.1:5000 (deploy-portal)
               │   • 127.0.0.1:3000 (website-cloner)
               │   • 127.0.0.1:8000-8999 (user apps)
               │
               └─→ If not authenticated, redirect to Cognito


OUTBOUND TRAFFIC FLOW:

┌─────────────────────────────────────┐
│  oauth2-proxy (127.0.0.1:4180)      │
└──────────────┬──────────────────────┘
               │
               │ HTTPS (443)
               │ OAuth2/OIDC Protocol
               ▼
┌─────────────────────────────────────┐
│  AWS Cognito                        │
│  cognito-idp.us-east-1.amazonaws.com│
│                                     │
│  Endpoints:                         │
│  • /oauth2/authorize                │
│  • /oauth2/token                    │
│  • /oauth2/userInfo                 │
│  • /.well-known/jwks.json           │
└─────────────────────────────────────┘


INTERNAL TRAFFIC (Loopback):

┌─────────────────────────────────────┐
│  nginx (Port 443)                   │
└──────────────┬──────────────────────┘
               │
               │ 127.0.0.1 (localhost)
               │
               ├─→ 127.0.0.1:4180 (oauth2-proxy)
               ├─→ 127.0.0.1:8080 (ssh-helper)
               ├─→ 127.0.0.1:5000 (deploy-portal)
               ├─→ 127.0.0.1:3000 (website-cloner)
               └─→ 127.0.0.1:8000-8999 (user apps)

Note: All backend applications listen ONLY on 127.0.0.1
      Never exposed directly to the internet
      Always protected by nginx + auth


SSH ACCESS FLOW:

Internet
    │
    │ SSH Request
    │ Port 22
    ▼
┌─────────────────────────────────────┐
│  AWS Security Group                 │
│  sg-0d6bbadbbd290b320               │
│                                     │
│  Dynamic Rules:                     │
│  • Allow 22 from 1.2.3.4/32        │
│  • Allow 22 from 5.6.7.8/32        │
│  • (Added via deploy-portal)        │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  EC2 SSH Service (Port 22)          │
│  User: ubuntu                       │
│  Auth: SSH key pair                 │
└─────────────────────────────────────┘
```

---

## Deployment Architecture

```
DEPLOYMENT WORKFLOW:

┌─────────────────────────────────────────────────────────────────────────┐
│                         DEVELOPER WORKSTATION                           │
│                                                                         │
│  1. Developer authenticates via browser:                                │
│     https://52.43.35.1/deploy/                                 │
│                                                                         │
│  2. Deploy Portal provisions access:                                    │
│     • Detects developer's public IP                                    │
│     • Adds IP to Security Group                                        │
│     • Generates deployment kit:                                        │
│       - SSH private key (deploy-key.pem)                               │
│       - Claude Code prompt with connection details                     │
│       - Instructions and scripts                                       │
│                                                                         │
│  3. Developer downloads deployment kit (ZIP)                            │
│                                                                         │
│  4. Developer extracts and uses:                                        │
│     chmod 600 deploy-key.pem                                           │
│     ssh -i deploy-key.pem ubuntu@52.43.35.1                            │
│                                                                         │
│  5. Or use with Claude Code:                                           │
│     - Paste the provided prompt into Claude                            │
│     - Claude connects via SSH                                          │
│     - Claude deploys application                                       │
└─────────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ SSH Connection
                                 │ (Port 22, whitelisted IP)
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        EC2 INSTANCE (GATEWAY)                           │
│                                                                         │
│  Application Deployment Process:                                        │
│                                                                         │
│  A. Developer/Claude creates application code                           │
│     /home/ubuntu/apps/my-app/                                          │
│                                                                         │
│  B. Deploy Portal automation scripts handle:                            │
│     1. Port allocation (from pool 8000-8999)                           │
│        automation/port-allocator.sh                                    │
│                                                                         │
│     2. nginx configuration                                             │
│        automation/nginx-register.sh                                    │
│        Creates: /etc/nginx/sites-available/my-app                      │
│        Symlinks: /etc/nginx/sites-enabled/my-app                       │
│        Reloads: nginx                                                  │
│                                                                         │
│     3. Systemd service creation                                        │
│        automation/systemd-register.sh                                  │
│        Creates: /etc/systemd/system/my-app.service                     │
│        Enables and starts service                                      │
│                                                                         │
│     4. Registry update                                                 │
│        automation/registry-manager.sh                                  │
│        Updates: data/app-registry.json                                 │
│                 data/port-registry.json                                │
│                                                                         │
│  C. Application is now live at:                                         │
│     https://52.43.35.1/my-app/                                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘


APPLICATION LIFECYCLE:

┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌─────────┐
│   DEVELOP   │────▶│    DEPLOY    │────▶│     RUN      │────▶│ MONITOR │
└─────────────┘     └──────────────┘     └──────────────┘     └─────────┘
      │                    │                     │                   │
      │                    │                     │                   │
      ▼                    ▼                     ▼                   ▼
  • Code on          • Port alloc         • systemd svc        • journalctl
    local            • nginx config       • Restart on fail    • nginx logs
  • Test local       • systemd svc        • Protected by       • Health check
  • Git commit       • Register app         Cognito            • Metrics
  • SSH to EC2       • Reload nginx       • User access
                     • Start service        via browser


INFRASTRUCTURE AS CODE:

┌─────────────────────────────────────────────────────────────────────────┐
│                    TERRAFORM (Optional)                                 │
│                                                                         │
│  Location: easy-cognito-nginx-gateway-auth/terraform/                   │
│                                                                         │
│  Modules:                                                               │
│  ├── networking/         VPC, subnets, security groups                 │
│  ├── compute/            EC2 instance with user_data                   │
│  ├── ssl/                ACM certificates (future)                     │
│  └── cognito/            Cognito User Pool (future)                    │
│                                                                         │
│  Example: single-instance                                               │
│  • Creates EC2 instance                                                │
│  • Attaches IAM role                                                   │
│  • Configures Security Group                                           │
│  • Runs installation script via user_data                              │
│  • Outputs: public IP, security group ID                               │
│                                                                         │
│  Usage:                                                                 │
│    cd terraform/examples/single-instance                               │
│    terraform init                                                      │
│    terraform apply                                                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Security Layers

```
SECURITY ONION MODEL:

┌─────────────────────────────────────────────────────────────────────────┐
│ LAYER 1: NETWORK PERIMETER                                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │  AWS Security Group: sg-0d6bbadbbd290b320                     │     │
│  │                                                               │     │
│  │  Inbound:                                                     │     │
│  │  • Port 443 (HTTPS): Open to world (0.0.0.0/0)              │     │
│  │  • Port 80 (HTTP): Open for Let's Encrypt (0.0.0.0/0)       │     │
│  │  • Port 22 (SSH): RESTRICTED - Dynamic whitelist only       │     │
│  │    - Added/removed via deploy-portal                         │     │
│  │    - Time-limited access                                     │     │
│  │    - Logged and audited                                      │     │
│  │                                                               │     │
│  │  Internal Ports: BLOCKED from internet                        │     │
│  │  • Port 4180 (oauth2-proxy): localhost only                  │     │
│  │  • Port 8080, 5000, 3000 (apps): localhost only             │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ LAYER 2: TRANSPORT SECURITY                                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │  TLS/SSL Encryption                                           │     │
│  │                                                               │     │
│  │  Certificate:                                                 │     │
│  │  • Self-signed (dev): /etc/nginx/ssl/selfsigned.crt         │     │
│  │  • Let's Encrypt (prod): /etc/letsencrypt/live/...          │     │
│  │                                                               │     │
│  │  Configuration:                                               │     │
│  │  • TLS 1.2 minimum                                           │     │
│  │  • TLS 1.3 preferred                                         │     │
│  │  • Strong cipher suites only                                 │     │
│  │  • HSTS header (31536000 seconds)                            │     │
│  │  • Forward secrecy                                           │     │
│  │                                                               │     │
│  │  All HTTP traffic redirected to HTTPS                         │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ LAYER 3: AUTHENTICATION                                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │  AWS Cognito User Pool                                        │     │
│  │                                                               │     │
│  │  Features:                                                     │     │
│  │  • Password policy enforcement                                │     │
│  │    - Minimum length                                          │     │
│  │    - Complexity requirements                                 │     │
│  │    - Expiration policies                                     │     │
│  │  • MFA support (optional)                                     │     │
│  │    - SMS-based                                               │     │
│  │    - TOTP (time-based)                                       │     │
│  │  • Account recovery                                           │     │
│  │  • Email verification                                         │     │
│  │  • Brute force protection                                     │     │
│  │  • Compromised credentials check                              │     │
│  │                                                               │     │
│  │  Tokens:                                                       │     │
│  │  • JWT-based (RS256 signature)                               │     │
│  │  • Short-lived (1 hour default)                              │     │
│  │  • Refresh tokens available                                   │     │
│  │  • Validated on every request                                │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │  oauth2-proxy Session Management                              │     │
│  │                                                               │     │
│  │  Cookies:                                                      │     │
│  │  • Name: _oauth2_proxy                                       │     │
│  │  • HttpOnly: true (no JavaScript access)                     │     │
│  │  • Secure: true (HTTPS only)                                 │     │
│  │  • SameSite: lax (CSRF protection)                           │     │
│  │  • Expiry: 24 hours                                          │     │
│  │  • Cryptographically signed                                   │     │
│  │                                                               │     │
│  │  Session validation on every request                          │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ LAYER 4: AUTHORIZATION                                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │  nginx auth_request Directive                                 │     │
│  │                                                               │     │
│  │  Every protected request:                                      │     │
│  │  1. Subrequest to oauth2-proxy                               │     │
│  │  2. Validates session cookie                                  │     │
│  │  3. Returns 202 (allow) or 401 (deny)                        │     │
│  │  4. Passes user info via headers                              │     │
│  │                                                               │     │
│  │  If denied:                                                    │     │
│  │  • Redirect to /oauth2/start                                 │     │
│  │  • Preserve original URL (rd parameter)                       │     │
│  │  • Start OAuth2 flow                                         │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │  Application-Level Security                                   │     │
│  │                                                               │     │
│  │  All applications:                                             │     │
│  │  • Read X-User-Email header (trusted from nginx)             │     │
│  │  • Listen only on 127.0.0.1 (localhost)                      │     │
│  │  • Never exposed to internet directly                         │     │
│  │  • No authentication code required                            │     │
│  │                                                               │     │
│  │  Additional app-specific security as needed                    │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ LAYER 5: AWS IAM (Infrastructure Security)                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │  EC2 IAM Role: ssh-whitelist-role                            │     │
│  │                                                               │     │
│  │  Principle of Least Privilege:                                │     │
│  │  • Only necessary EC2 permissions                            │     │
│  │  • Only necessary S3 permissions                             │     │
│  │  • No wildcard permissions (where possible)                   │     │
│  │  • Resource-level restrictions                               │     │
│  │                                                               │     │
│  │  No hardcoded credentials:                                     │     │
│  │  • All apps use IAM role automatically                        │     │
│  │  • Credentials rotated by AWS                                │     │
│  │  • No keys in code or config files                           │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ LAYER 6: AUDIT & MONITORING                                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │  Logging                                                      │     │
│  │                                                               │     │
│  │  • nginx access logs: /var/log/nginx/access.log             │     │
│  │  • nginx error logs: /var/log/nginx/error.log               │     │
│  │  • oauth2-proxy: journalctl -u oauth2-proxy                 │     │
│  │  • Applications: journalctl -u <service-name>               │     │
│  │                                                               │     │
│  │  Each log entry includes:                                     │     │
│  │  • Timestamp                                                  │     │
│  │  • User email (for authenticated requests)                   │     │
│  │  • IP address                                                │     │
│  │  • Request path                                              │     │
│  │  • Status code                                               │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │  Security Group Change Tracking                               │     │
│  │                                                               │     │
│  │  • All IP whitelist changes logged                            │     │
│  │  • Includes: user email, timestamp, IP, duration             │     │
│  │  • Stored in: deploy-portal/data/access-log.json            │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘


THREAT MODEL:

┌─────────────────────────────────────────────────────────────────────────┐
│ Mitigated Threats:                                                      │
│                                                                         │
│ ✓ Unauthorized access         → AWS Cognito authentication             │
│ ✓ Man-in-the-middle           → TLS/SSL encryption                     │
│ ✓ Session hijacking           → HttpOnly, Secure cookies                │
│ ✓ CSRF attacks                → SameSite cookies                        │
│ ✓ Direct app access           → Apps listen on localhost only           │
│ ✓ Brute force login           → Cognito rate limiting                   │
│ ✓ Credential stuffing         → Cognito compromised credentials check   │
│ ✓ Token tampering             → JWT signature verification              │
│ ✓ Privilege escalation        → IAM least privilege                     │
│ ✓ SSH brute force             → Dynamic IP whitelist only               │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│ Residual Risks:                                                         │
│                                                                         │
│ ⚠ Compromised user account    → Enable MFA in Cognito                  │
│ ⚠ DDoS attacks                → Use CloudFront + WAF (future)          │
│ ⚠ Zero-day in nginx/proxy     → Keep software updated                  │
│ ⚠ Insider threat              → Audit logs + access reviews             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Summary

This architecture implements a **defense-in-depth** security model with:

1. **Centralized Authentication**: AWS Cognito + oauth2-proxy handle all auth
2. **Zero-Trust Applications**: Backend apps trust nginx headers, no auth code
3. **Network Isolation**: Apps listen on localhost only, never exposed directly
4. **Transport Security**: TLS/SSL for all external traffic
5. **Session Management**: Secure, HttpOnly cookies with proper expiration
6. **Dynamic Access Control**: Time-limited SSH access via Security Group rules
7. **Audit Trail**: Comprehensive logging at every layer

**Key Benefits**:
- Easy to add new applications (no auth code required)
- Consistent security policy across all apps
- Centralized user management
- Simple troubleshooting (clear separation of concerns)
- Cost-effective (one gateway protects many apps)

**Production Readiness**:
- ✅ TLS/SSL (upgrade to Let's Encrypt for production)
- ✅ OAuth2 + PKCE flow
- ✅ Secure session management
- ✅ IAM role-based credentials
- ✅ Comprehensive logging
- 🔄 MFA (optional, enable in Cognito)
- 🔄 CloudWatch monitoring (future enhancement)
- 🔄 Automated backups (future enhancement)

For questions or issues, consult the individual project documentation or the main CLAUDE.md file in the repository root.
