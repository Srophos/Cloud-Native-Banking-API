import os
from fastapi import FastAPI, HTTPException, Depends, Header
from typing import Annotated

# --- Database Imports ---
from sqlalchemy import create_engine, Column, String, Float, text
from sqlalchemy.orm import sessionmaker, declarative_base
from sqlalchemy.exc import OperationalError
import time

# --- Azure SDK Imports ---
from azure.identity.aio import DefaultAzureCredential
from azure.keyvault.secrets.aio import SecretClient
import asyncio

# --- CONFIGURATION ---
INTERNAL_SECRET = "a-super-long-and-random-secret-key-that-no-one-can-guess-123!@#"
KEY_VAULT_URL = os.environ.get("KEY_VAULT_URL")

# --- DATABASE SETUP (SQLAlchemy) ---
Base = declarative_base()

class Account(Base):
    # This class defines the structure of our 'accounts' table in the database.
    __tablename__ = 'accounts'
    id = Column(String(50), primary_key=True)
    owner = Column(String(255), nullable=False)
    balance = Column(Float, nullable=False)

# We will initialize the database engine and session later during the app's startup event.
engine = None
SessionLocal = None

# --- AZURE KEY VAULT FUNCTION ---
async def get_db_connection_string():
    """Securely fetches the database connection string from Azure Key Vault."""
    if not KEY_VAULT_URL:
        raise RuntimeError("FATAL ERROR: KEY_VAULT_URL environment variable is not set.")
    
    # Use the app's Managed Identity to authenticate to Key Vault.
    credential = DefaultAzureCredential()
    secret_client = SecretClient(vault_url=str(KEY_VAULT_URL), credential=credential)
    
    print("Attempting to fetch secret 'sql-connection-string' from Key Vault...")
    secret = await secret_client.get_secret("sql-connection-string")
    await credential.close()
    await secret_client.close()
    
    if not secret or not secret.value:
        raise RuntimeError("FATAL ERROR: 'sql-connection-string' not found in Key Vault.")
        
    print("Successfully fetched secret from Key Vault.")
    return secret.value

# --- FASTAPI APP ---
app = FastAPI(title="Account Service")

@app.on_event("startup")
async def startup_event():
    """
    This function runs once when the application starts up.
    It connects to the database and prepares it for use.
    """
    global engine, SessionLocal
    
    connection_string = await get_db_connection_string()
    
    print("Attempting to connect to the database...")
    engine = create_engine(connection_string, echo=False) # Set echo=True for detailed SQL logs
    
    # Create the 'accounts' table if it doesn't already exist.
    Base.metadata.create_all(bind=engine)
    
    # Create a session factory to interact with the database.
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    print("Successfully connected to the database and configured session.")

    # --- Data Seeding (for demonstration purposes) ---
    # This block adds our sample data to the database if the table is empty.
    db = SessionLocal()
    try:
        if db.query(Account).count() == 0:
            print("Database is empty. Seeding initial data...")
            db.add_all([
                Account(id='acc-1001', owner='Chandler Bing', balance=1500.75),
                Account(id='acc-1002', owner='Monica Geller', balance=9850.00)
            ])
            db.commit()
            print("Initial data seeded successfully.")
    finally:
        db.close()


# --- SECURITY DEPENDENCY ---
async def verify_secret_header(x_internal_secret: Annotated[str | None, Header()] = None):
    """Checks for the secret header from the APIM gateway."""
    if x_internal_secret is None or x_internal_secret != INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Forbidden: Access Denied")
    return True

# --- API ENDPOINT ---
@app.get("/accounts/{account_id}/balance", dependencies=[Depends(verify_secret_header)])
def get_account_balance(account_id: str):
    """
    Retrieves the balance for a specific account ID from the Azure SQL database.
    """
    if not SessionLocal:
        raise HTTPException(status_code=503, detail="Database service is not available.")
        
    db = SessionLocal()
    try:
        # Query the real database for the account.
        account = db.query(Account).filter(Account.id == account_id).first()
        if account is None:
            raise HTTPException(status_code=404, detail="Account not found in the database.")
        return {"account_id": account.id, "balance": account.balance}
    finally:
        db.close()

@app.get("/", include_in_schema=False)
def read_root():
    """Health check endpoint."""
    return {"service": "Account Service", "status": "online"}

