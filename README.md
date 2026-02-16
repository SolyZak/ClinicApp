# Dr. Medhat - Patient Management System

<p align="center">
  <strong>A desktop patient records system for pulmonary and critical care medicine</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python"/>
  <img src="https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white" alt="FastAPI"/>
  <img src="https://img.shields.io/badge/SQLite-003B57?style=for-the-badge&logo=sqlite&logoColor=white" alt="SQLite"/>
  <img src="https://img.shields.io/badge/React-61DAFB?style=for-the-badge&logo=react&logoColor=black" alt="React"/>
</p>

---

## Overview

A full-stack patient management system built for a pulmonary and critical care medicine practice. Runs locally on macOS with one-click start/stop scripts, SQLite for portable storage, and built-in backup/restore functionality.

## Features

### Patient Management
- Create and search patient records (name, DOB, phone, medical history)
- Track allergies, chronic conditions, and current medications
- Soft-delete with data preservation

### Visit Documentation
- Record comprehensive visit details: chief complaint, present illness history, vital signs (BP, temp, O2 sat, pulse), examination notes, diagnoses, medications, treatment plan, and follow-up instructions
- Create first visits or add follow-ups to existing patients

### Data Safety
- One-click database backup with timestamped files
- Restore from any previous backup
- Export patient data to CSV

### Authentication
- Password-protected login with JWT session tokens
- Default password: `clinic123`

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Python 3 + FastAPI |
| Database | SQLite (portable, no server needed) |
| ORM | SQLAlchemy |
| Auth | JWT (python-jose) + bcrypt |
| Frontend | React SPA (pre-built) |
| Server | Uvicorn (ASGI) |

## Quick Start (macOS)

### One-Time Setup
1. Install Python from [python.org](https://www.python.org/downloads/) — check "Add Python to PATH"
2. Right-click each `.command` file, select Open, and click "Open" when prompted (only needed once)

### Daily Use

| Action | Script |
|--------|--------|
| Start the system | Double-click `Start.command` |
| Stop the system | Double-click `Stop.command` |
| Backup data | Double-click `Backup.command` |

The browser opens automatically at http://localhost:8000

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/login` | Authenticate |
| GET/POST | `/api/patients` | List or create patients |
| GET/PUT/DELETE | `/api/patients/{id}` | Patient CRUD |
| POST | `/api/patients/with-visit` | Create patient with first visit |
| GET/POST | `/api/patients/{id}/visits` | List or add visits |
| GET/PUT | `/api/visits/{id}` | Visit CRUD |
| GET | `/api/exports/patients.csv` | Export to CSV |
| GET | `/api/backup` | Download backup |
| POST | `/api/restore` | Restore from backup |

## Project Structure

```
ClinicApp/
├── app/
│   └── main.py             # FastAPI application (routes, models, auth)
├── static/                  # Pre-built React frontend
├── assets/                  # Images and resources
├── Start.command            # macOS start script
├── Stop.command             # macOS stop script
├── Backup.command           # macOS backup script
├── requirements.txt         # Python dependencies
└── README.md
```

## Troubleshooting

**"Python not found" error?**
Install Python from [python.org](https://www.python.org/downloads/) (check "Add to PATH")

**Browser doesn't open?**
Navigate to http://localhost:8000 manually

**System won't start?**
Run `Stop.command` first, then `Start.command` — another process may be using port 8000

---

Built for Dr. Medhat - Pulmonary & Critical Care Medicine
