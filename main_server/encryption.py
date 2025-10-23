"""
Encryption and hashing utilities for message security.

This module provides:
- AES-256 encryption/decryption for message bodies
- SHA-256 hashing for phone numbers
- Key management and rotation support
"""

import base64
import hashlib
import logging
import os
from pathlib import Path
from typing import Optional

from cryptography.fernet import Fernet, InvalidToken
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

logger = logging.getLogger(__name__)


class EncryptionManager:
    """
    Manages encryption/decryption operations with key rotation support.
    
    Uses Fernet (AES-256 in CBC mode with HMAC authentication) for
    message encryption and SHA-256 for phone number hashing.
    """
    
    def __init__(
        self,
        key_path: Optional[str] = None,
        salt: Optional[str] = None,
        key_version: int = 1,
    ):
        """
        Initialize encryption manager.
        
        Args:
            key_path: Path to encryption key file
            salt: Salt for phone number hashing
            key_version: Current key version (for rotation)
        """
        self.key_path = key_path
        self.salt = salt or os.environ.get("HASH_SALT", "message_broker_default_salt")
        self.key_version = key_version
        self.cipher: Optional[Fernet] = None
        
        # Key storage for rotation support
        self.keys = {}  # version -> Fernet instance
        
        if key_path:
            self._load_key(key_path, key_version)
    
    def _load_key(self, key_path: str, version: int = 1):
        """
        Load encryption key from file.
        
        Args:
            key_path: Path to key file
            version: Key version number
        """
        try:
            key_file = Path(key_path)
            if not key_file.exists():
                raise FileNotFoundError(f"Encryption key not found: {key_path}")
            
            # Read key from file
            with open(key_file, "rb") as f:
                key_data = f.read().strip()
            
            # Create Fernet instance
            cipher = Fernet(key_data)
            self.keys[version] = cipher
            self.cipher = cipher  # Set as current cipher
            
            logger.info(f"Loaded encryption key version {version} from {key_path}")
            
        except Exception as e:
            logger.error(f"Failed to load encryption key: {e}")
            raise
    
    def encrypt_message(
        self,
        plaintext: str,
        key_version: Optional[int] = None,
    ) -> tuple[str, int]:
        """
        Encrypt a message body.
        
        Args:
            plaintext: Message content to encrypt
            key_version: Key version to use (default: current)
        
        Returns:
            Tuple of (base64-encoded encrypted data, key version)
        """
        if not self.cipher:
            raise RuntimeError("Encryption key not loaded")
        
        try:
            # Use specified key version or current
            version = key_version or self.key_version
            cipher = self.keys.get(version, self.cipher)
            
            # Encrypt message
            encrypted_data = cipher.encrypt(plaintext.encode("utf-8"))
            
            # Base64 encode for storage
            encrypted_b64 = base64.b64encode(encrypted_data).decode("utf-8")
            
            logger.debug(f"Message encrypted with key version {version}")
            return encrypted_b64, version
            
        except Exception as e:
            logger.error(f"Encryption failed: {e}")
            raise
    
    def decrypt_message(
        self,
        encrypted_b64: str,
        key_version: int = 1,
    ) -> str:
        """
        Decrypt a message body.
        
        Args:
            encrypted_b64: Base64-encoded encrypted data
            key_version: Key version used for encryption
        
        Returns:
            Decrypted message content
        """
        if not self.cipher:
            raise RuntimeError("Encryption key not loaded")
        
        try:
            # Get cipher for specified version
            cipher = self.keys.get(key_version, self.cipher)
            
            # Decode from base64
            encrypted_data = base64.b64decode(encrypted_b64.encode("utf-8"))
            
            # Decrypt message
            plaintext = cipher.decrypt(encrypted_data).decode("utf-8")
            
            logger.debug(f"Message decrypted with key version {key_version}")
            return plaintext
            
        except InvalidToken:
            logger.error("Decryption failed: Invalid token or wrong key")
            raise ValueError("Failed to decrypt message: invalid key or corrupted data")
        except Exception as e:
            logger.error(f"Decryption failed: {e}")
            raise
    
    def hash_phone_number(self, phone_number: str) -> str:
        """
        Hash a phone number with SHA-256.
        
        Args:
            phone_number: Phone number in E.164 format
        
        Returns:
            Hexadecimal hash string
        """
        try:
            # Combine phone number with salt
            data = f"{self.salt}{phone_number}".encode("utf-8")
            
            # Calculate SHA-256 hash
            hash_digest = hashlib.sha256(data).hexdigest()
            
            logger.debug(f"Phone number hashed: {phone_number[:4]}...")
            return hash_digest
            
        except Exception as e:
            logger.error(f"Phone number hashing failed: {e}")
            raise
    
    def verify_phone_hash(self, phone_number: str, hash_value: str) -> bool:
        """
        Verify a phone number against its hash.
        
        Args:
            phone_number: Phone number to verify
            hash_value: Expected hash value
        
        Returns:
            True if hash matches, False otherwise
        """
        try:
            computed_hash = self.hash_phone_number(phone_number)
            return computed_hash == hash_value
        except Exception:
            return False
    
    def add_key_version(self, key_path: str, version: int):
        """
        Add a new key version for rotation.
        
        Args:
            key_path: Path to new key file
            version: Version number for new key
        """
        self._load_key(key_path, version)
        logger.info(f"Added encryption key version {version}")
    
    def set_current_version(self, version: int):
        """
        Set the current key version for new encryptions.
        
        Args:
            version: Version number to set as current
        """
        if version not in self.keys:
            raise ValueError(f"Key version {version} not loaded")
        
        self.key_version = version
        self.cipher = self.keys[version]
        logger.info(f"Set current encryption key version to {version}")
    
    @staticmethod
    def generate_key() -> bytes:
        """
        Generate a new Fernet encryption key.
        
        Returns:
            Random encryption key
        """
        return Fernet.generate_key()
    
    @staticmethod
    def save_key_to_file(key: bytes, file_path: str):
        """
        Save encryption key to file with restricted permissions.
        
        Args:
            key: Encryption key to save
            file_path: Path to save key file
        """
        try:
            key_file = Path(file_path)
            key_file.parent.mkdir(parents=True, exist_ok=True)
            
            # Write key to file
            with open(key_file, "wb") as f:
                f.write(key)
            
            # Set restricted permissions (owner read-only)
            os.chmod(key_file, 0o400)
            
            logger.info(f"Encryption key saved to {file_path}")
            
        except Exception as e:
            logger.error(f"Failed to save encryption key: {e}")
            raise


# ============================================================================
# Helper Functions
# ============================================================================

def mask_phone_number(phone_number: str) -> str:
    """
    Mask a phone number for display.
    
    Args:
        phone_number: Phone number to mask (e.g., +1234567890)
    
    Returns:
        Masked number (e.g., +123****7890)
    """
    if len(phone_number) <= 8:
        # Short number: show first 3 and last 2
        return phone_number[:3] + "****" + phone_number[-2:]
    else:
        # Normal number: show first 4 and last 4
        return phone_number[:4] + "****" + phone_number[-4:]


def derive_key_from_password(password: str, salt: bytes) -> bytes:
    """
    Derive encryption key from password using PBKDF2.
    
    Args:
        password: Password to derive key from
        salt: Salt for key derivation
    
    Returns:
        Derived encryption key
    """
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=100000,
    )
    key = base64.urlsafe_b64encode(kdf.derive(password.encode()))
    return key


def generate_and_save_key(file_path: str) -> bytes:
    """
    Generate new encryption key and save to file.
    
    Args:
        file_path: Path to save key file
    
    Returns:
        Generated encryption key
    """
    key = EncryptionManager.generate_key()
    EncryptionManager.save_key_to_file(key, file_path)
    return key


# ============================================================================
# Module-level instance (optional singleton pattern)
# ============================================================================

_encryption_manager: Optional[EncryptionManager] = None


def init_encryption(
    key_path: Optional[str] = None,
    salt: Optional[str] = None,
) -> EncryptionManager:
    """
    Initialize global encryption manager.
    
    Args:
        key_path: Path to encryption key file
        salt: Salt for hashing
    
    Returns:
        Initialized encryption manager
    """
    global _encryption_manager
    _encryption_manager = EncryptionManager(key_path=key_path, salt=salt)
    return _encryption_manager


def get_encryption_manager() -> EncryptionManager:
    """
    Get global encryption manager instance.
    
    Returns:
        Encryption manager
    """
    if _encryption_manager is None:
        raise RuntimeError("Encryption manager not initialized. Call init_encryption() first.")
    return _encryption_manager

