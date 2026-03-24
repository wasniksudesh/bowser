### Backend VM Integration TODOs
1. Macos App requires backend-image for VM creation. Fix this for development. 
2. Upload built system.img to CDN
3. Add UI for download progress
4. Test actual VM boot (requires CDN image)
5. Add VM monitoring/metrics
6. Implement actual vsock key exchange protocol

### Backend VM backlogs
1. On crashes -> auto restart VM
2. UDF Validator 
3. Encryption on diskwrites in VM
4. Log+Audit every ai-action on VM 
5. AI-Action Anamoly detector

### AI Backend
1. if AI key is not configured, backend loops making call over and over to LLM with 5xx/4xx errors

### TEST 
1. UTs present. 
2. ITs to add 