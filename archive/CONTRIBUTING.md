# Contributing to Message Broker System

Thank you for your interest in contributing to the Message Broker System! This document provides guidelines and instructions for contributing.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)
- [Testing](#testing)

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers and help them get started
- Focus on constructive feedback
- Maintain professional communication

## Getting Started

### Prerequisites

1. Read the [README.md](README.md) for setup instructions
2. Ensure you have all required dependencies installed
3. Set up your development environment

### Fork and Clone

```powershell
# Fork the repository on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/message_broker.git
cd message_broker

# Add upstream remote
git remote add upstream https://github.com/ORIGINAL_OWNER/message_broker.git
```

## Development Workflow

### Branch Strategy

- `main` - Production-ready code (protected)
- `develop` - Integration branch for features
- `feature/*` - New features
- `bugfix/*` - Bug fixes
- `hotfix/*` - Emergency production fixes
- `release/*` - Release preparation

### Creating a Feature Branch

```powershell
# Update your local develop branch
git checkout develop
git pull upstream develop

# Create a new feature branch
git checkout -b feature/your-feature-name
```

## Coding Standards

### Python Style Guide

- Follow [PEP 8](https://www.python.org/dev/peps/pep-0008/)
- Use type hints for all function signatures
- Maximum line length: 100 characters
- Use descriptive variable names

### Code Quality

```python
# Good Example
def process_message(message: str, sender_id: int) -> dict:
    """
    Process incoming message and return result.
    
    Args:
        message: The message content
        sender_id: Unique identifier for sender
        
    Returns:
        Dictionary containing processing result
    """
    result = {
        "status": "success",
        "message_id": generate_id(),
        "processed_at": datetime.utcnow()
    }
    return result

# Bad Example
def proc(m, s):
    r = {"status": "ok"}
    return r
```

### Documentation

- Add docstrings to all classes and functions
- Include type hints
- Comment complex logic
- Update README.md for new features

### File Structure

```python
# Standard import order:
# 1. Standard library imports
# 2. Third-party imports
# 3. Local application imports

import os
import sys
from typing import Optional, Dict

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from .models import Message
from .utils import validate_phone
```

## Commit Guidelines

### Commit Message Format

```
type(scope): brief description

[optional body]

[optional footer]
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks
- `perf`: Performance improvements

### Examples

```
feat(proxy): add rate limiting middleware

Implements token bucket algorithm for rate limiting.
Max 100 requests per minute per client.

Closes #123
```

```
fix(worker): correct retry interval calculation

Previous calculation was using seconds instead of milliseconds.
Updated to use proper time units.
```

```
docs(readme): update installation instructions for Windows

Added detailed steps for OpenSSL installation on Windows 10/11.
```

## Pull Request Process

### Before Submitting

1. **Update your branch**
   ```powershell
   git fetch upstream
   git rebase upstream/develop
   ```

2. **Run tests** (when available)
   ```powershell
   pytest
   ```

3. **Check code style**
   ```powershell
   flake8 .
   black --check .
   mypy .
   ```

4. **Update documentation**
   - Update README.md if needed
   - Add/update docstrings
   - Update CHANGELOG.md

### Submitting Pull Request

1. Push your branch to your fork
   ```powershell
   git push origin feature/your-feature-name
   ```

2. Create Pull Request on GitHub
   - Use a clear, descriptive title
   - Reference related issues
   - Describe changes in detail
   - Add screenshots for UI changes

3. PR Template
   ```markdown
   ## Description
   Brief description of changes
   
   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Breaking change
   - [ ] Documentation update
   
   ## Related Issues
   Fixes #123
   
   ## Testing
   Describe testing performed
   
   ## Checklist
   - [ ] Code follows project style guidelines
   - [ ] Self-review completed
   - [ ] Documentation updated
   - [ ] No new warnings
   ```

### Review Process

- At least one approval required
- Address review comments
- Keep PR focused and small
- Respond to feedback promptly

## Testing

### Manual Testing Checklist

1. **Proxy Server**
   - [ ] Message submission succeeds
   - [ ] Invalid phone numbers rejected
   - [ ] Rate limiting works
   - [ ] TLS authentication enforced

2. **Worker**
   - [ ] Messages consumed from queue
   - [ ] Retry logic works correctly
   - [ ] Failed messages re-queued
   - [ ] Concurrent workers operate correctly

3. **Main Server**
   - [ ] Messages stored encrypted
   - [ ] Certificate generation works
   - [ ] Database operations succeed
   - [ ] API authentication enforced

4. **Portal**
   - [ ] User login works
   - [ ] Messages displayed correctly
   - [ ] Search/filter functions work
   - [ ] Admin features accessible

### Testing Guidelines

- Test happy path and error cases
- Verify security features
- Check performance under load
- Test certificate validation
- Verify logging output

## Questions?

- Open an issue for bugs or feature requests
- Contact maintainers for questions
- Check existing issues and PRs

Thank you for contributing! 🎉

