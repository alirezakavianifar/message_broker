"""
Email utility for sending system notifications.

Handles SMTP communication and provides templates for common 
notifications such as password resets.
"""

import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Optional

logger = logging.getLogger(__name__)

class EmailManager:
    """Manager for sending emails via SMTP."""
    
    def __init__(self, host: str, port: int, user: str, password: str, from_addr: str):
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.from_addr = from_addr

    def _send_email(self, recipient: str, subject: str, body_html: str, body_text: str = "") -> bool:
        """Sends an HTML email with optional plain text fallback."""
        try:
            msg = MIMEMultipart('alternative')
            msg['Subject'] = subject
            msg['From'] = self.from_addr
            msg['To'] = recipient

            if body_text:
                msg.attach(MIMEText(body_text, 'plain'))
            msg.attach(MIMEText(body_html, 'html'))

            with smtplib.SMTP(self.host, self.port) as server:
                if self.password:
                    server.starttls()
                    server.login(self.user, self.password)
                server.send_message(msg)
            
            logger.info(f"Email sent to {recipient}: {subject}")
            return True
        except Exception as e:
            logger.error(f"Failed to send email to {recipient}: {e}")
            return False

    def send_password_reset(self, recipient: str, reset_url: str) -> bool:
        """Sends a password reset email."""
        subject = "Password Reset Request - Message Broker"
        
        # Simple HTML template (could be moved to a file if needed)
        body_html = f"""
        <html>
            <body style="font-family: sans-serif; line-height: 1.6; color: #333;">
                <div style="max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #ddd; border-radius: 8px;">
                    <h2 style="color: #007bff; border-bottom: 2px solid #007bff; padding-bottom: 10px;">
                        Password Reset Request
                    </h2>
                    <p>Hello,</p>
                    <p>We received a request to reset your password for the Message Broker Portal.</p>
                    <p>Please click the button below to choose a new password. This link will expire in 1 hour.</p>
                    <div style="text-align: center; margin: 30px 0;">
                        <a href="{reset_url}" 
                           style="background-color: #007bff; color: white; padding: 12px 25px; 
                                  text-decoration: none; border-radius: 5px; font-weight: bold;">
                            Reset Password
                        </a>
                    </div>
                    <p>If the button above doesn't work, copy and paste this URL into your browser:</p>
                    <p style="word-break: break-all; color: #666;">{reset_url}</p>
                    <hr style="border: 0; border-top: 1px solid #eee; margin: 20px 0;">
                    <p style="font-size: 0.9em; color: #999;">
                        If you did not request a password reset, please ignore this email. 
                        Your password will remain unchanged.
                    </p>
                </div>
            </body>
        </html>
        """
        
        body_text = f"Password Reset Request\n\nPlease reset your password using the following link (expires in 1 hour): {reset_url}"
        
        return self._send_email(recipient, subject, body_html, body_text)
