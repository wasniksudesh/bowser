from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"]

flow = InstalledAppFlow.from_client_secrets_file(
    "client_secret.json",
    SCOPES
)

# 👇 Opens browser once
creds = flow.run_local_server(port=0)

print("\nACCESS TOKEN:\n", creds.token)
print("\nREFRESH TOKEN:\n", creds.refresh_token)
