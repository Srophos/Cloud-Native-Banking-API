from fastapi import FastAPI, HTTPException, Depends, Header
from typing import Annotated

# This is our "secret handshake" password.
INTERNAL_SECRET = "a-super-long-and-random-secret-key-that-no-one-can-guess-123!@#"

app = FastAPI(title="Account Service")

# Use a simple Python dictionary as our in-memory "database"
mock_db = {
    "acc-1001": {"owner": "Chandler Bing", "balance": 1500.75},
    "acc-1002": {"owner": "Monica Geller", "balance": 9850.00},
}

# --- Security Dependency ---
# This function checks for the secret header from APIM.
async def verify_secret_header(x_internal_secret: Annotated[str | None, Header()] = None):
    if x_internal_secret is None or x_internal_secret != INTERNAL_SECRET:
        # If the header is missing or wrong, deny access.
        raise HTTPException(status_code=403, detail="Forbidden")
    return True

@app.get("/")
def read_root():
    return {"service": "Account Service", "status": "online"}

# This endpoint is protected by our security dependency.
@app.get("/accounts/{account_id}/balance", dependencies=[Depends(verify_secret_header)])
def get_account_balance(account_id: str):
    """
    Retrieves the balance for a specific account ID from mock data.
    """
    if account_id not in mock_db:
        raise HTTPException(status_code=404, detail="Account not found")
    
    return {"account_id": account_id, "balance": mock_db[account_id]["balance"]}