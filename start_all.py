
import subprocess
import os
import time

env = os.environ.copy()
env["DATABASE_URL"] = "mysql+pymysql://systemuser:StrongPass123!@127.0.0.1/message_system"
env["REDIS_HOST"] = "127.0.0.1"
env["MAIN_SERVER_URL"] = "http://127.0.0.1:8000"
env["MAIN_SERVER_VERIFY_SSL"] = "false"
env["ENCRYPTION_KEY_PATH"] = "secrets/encryption.key"
env["JWT_SECRET"] = "secret"
env["LOG_LEVEL"] = "INFO"

venv_python = r"E:\projects\from-old-pc\message_broker\venv\Scripts\python.exe"

print("Starting Main Server...")
main_server = subprocess.Popen([venv_python, "-m", "uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8000"], 
                               cwd=r"E:\projects\from-old-pc\message_broker\main_server", env=env)

time.sleep(5)

print("Starting Proxy...")
proxy = subprocess.Popen([venv_python, "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8001"], 
                         cwd=r"E:\projects\from-old-pc\message_broker\proxy", env=env)

print("Starting Worker...")
worker = subprocess.Popen([venv_python, "worker.py"], 
                          cwd=r"E:\projects\from-old-pc\message_broker\worker", env=env)

print("Starting Portal...")
portal = subprocess.Popen([venv_python, "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "5000"], 
                          cwd=r"E:\projects\from-old-pc\message_broker\portal", env=env)

print("All services started.")
