# Security TODOs

## VM Network Isolation - HTTP Proxy
**Priority:** High  
**Current:** VM uses NAT for full internet access  
**Target:** Swift-based HTTP proxy on vsock with domain whitelist (openai.com, anthropic.com, google.com)  
**Benefit:** Fine-grained control over VM internet access, audit all API calls, prevent unauthorized connections
