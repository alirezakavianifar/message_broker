# Agent Instructions

## Git Remote

Changes must be pushed to: **https://github.com/alirezakavianifar/message_broker.git**

Ensure the remote `origin` points to this URL. If not configured, use: `git remote add origin https://github.com/alirezakavianifar/message_broker.git` (or `git remote set-url origin <url>` to update).

## .gitignore

If `.gitignore` does not exist, create one based on the codebase structure and language. Adapt entries to match the project's technologies and build output locations.

## Python Virtual Environment

**Always ensure a virtual environment exists and run Python code inside it.** Before executing any Python commands or scripts:

1. **Check for virtual environment**: Look for `venv/`, `.venv/`, or similar directories in the project root.
2. **Create if missing**: If no virtual environment exists, create one using `python -m venv venv` (or `python3 -m venv venv` on systems where `python` points to Python 2).
3. **Activate before use**: Always activate the virtual environment before running Python commands:
   - **Windows (PowerShell)**: `venv\Scripts\Activate.ps1` or `.\venv\Scripts\Activate.ps1`
   - **Windows (CMD)**: `venv\Scripts\activate.bat`
   - **Unix/MacOS**: `source venv/bin/activate`
4. **Install dependencies**: If a `requirements.txt` exists, ensure dependencies are installed with `pip install -r requirements.txt` after activation.

**Note:** All Python operations (running scripts, installing packages, etc.) must be performed within the activated virtual environment.

## Git Push Workflow

When the user uses the keyword "push" in a request (e.g., "please push these changes", "push", or similar), you MUST follow this specific workflow:

1. **Stage all changes**: standard `git add .`
2. **Infer Commit Message**: Generate a concise, descriptive, and professional commit message based on the recent file changes and conversation context. Do not ask the user for a commit message unless they explicitly provide one.
3. **Commit**: `git commit -m "<inferred_message>"`
4. **Push**: `git push` (or `git push -u origin <branch>` if the upstream is not set).

**Note:** You should proactively execute these commands without asking for extra confirmation if the user explicitly said "push".
