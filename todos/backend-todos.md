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
2. Chat Bubbles: scrape/fetch real webpage content and send to LLM instead of just the URL

### TEST  
2. ITs to add 

### Features 
1. Snapshot, Downladed Files -> Not implemented
2. "Files" button should show all Notes, Snapshots, DownloadedFiles. 
3. Implement fly-cut.
4. Agent <-> Widget integration (Skill should write Carousel and widget should display it) (plan => scheduled_agents_and_widgets)

