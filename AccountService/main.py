from fastapi import FastAPI, HTTPException, Depends, Header
from typing import Annotated

# This is our "secret handshake" password.
INTERNAL_SECRET = "a-super-long-and-random-secret-key-that-no-one-can-guess-123!@#"

app = FastAPI(title="Account Service")

mock_db = {
    "acc-1001": {"owner": "Chandler Bing", "balance": 1500.75},
    "acc-1002": {"owner": "Monica Geller", "balance": 9850.00},
}

# Security Dependency to check for the secret header
async def verify_secret_header(x_internal_secret: Annotated[str | None, Header()] = None):
    if x_internal_secret is None or x_internal_secret != INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Forbidden")
    return True

@app.get("/accounts/{account_id}/balance", dependencies=[Depends(verify_secret_header)])
def get_account_balance(account_id: str):
    if account_id not in mock_db:
        raise HTTPException(status_code=404, detail="Account not found")
    return {"account_id": account_id, "balance": mock_db[account_id]["balance"]}